# Multi-match: every match in a process of its own (D44)

**Written 2026-09-25 and reviewed the same day.** This is a PLAN, not a record. When a phase lands,
move what it built into `multiplayer.md` and strike it here. Delete the file when the last phase
has landed.

The measurements behind every claim here are in
`Findings/2026-09-25-one-server-many-matches.md`, including what the review measured. This file
repeats none of its numbers, because a plan outlives the day they were taken.

**The review.** Independent reviews from six angles (the server half of the handoff, the client
half, failures and races, security, hosting and capacity, consistency and phasing) checked this
plan against the code, the Godot and systemd sources and small experiments. A second pass tried to
refute every finding. None of them changed the shape: one process per match, a handoff by token,
stage (a) before stage (b). What they changed is folded in below:
- rules for the spawn window;
- the lifetime of a token;
- a seat table in place of MatchStart's head count;
- the client's move as a state of its own;
- where the match's address comes from;
- what a RESULT can hold;
- the deploy order;
- what `OOMPolicy` really does;
- stage (b)'s systemd traps;
- a switch that keeps all of it off on `main` until it ships.

The review also found one bug that is live today (P0).

---

## Where it stands: the handoff

**Keep this section current.** A session on another machine starts here, and nothing else carries
over: Claude's memory and scratch files stay on the machine that wrote them.

**Last updated 2026-09-25, at the push made so the owner could continue on another PC.**

**Done:**
- The decisions (§0), including the rejoin rule taken after the review.
- P0: the server fixes, the client fixes and the deploy script's new controls.
- P1: the authentication spike, and the Windows half of the spawn spike.
- The review, and this rewrite of the plan around it.
- The test harness moved into the repo (below).

**On the server:** none of this work is deployed. The next deploy ships all of it, and it has two
consequences:
- `Lobby.request_seat_state` moved the D31 rpc hash, so **a deploy without a new client build
  hands every tester "the server is running different code"**;
- `-InstallShutdown` must run right after that deploy, and never before it (§7, P0).

So do not deploy before P5's window (§7), unless the owner asks for it.

**Next, in order:**
1. **The live bug in P0** (the loading gate counts heads). It is small, and independent of D44.
   Its proof needs new probe flags and a count of join clients in the runner; P0 lists them.
2. **Fold `multi-match-todo.md` into this plan, then delete that file.**
   - It is the check pass made on this rewrite: three readers (completeness, correctness, the
     implementer), each issue with the exact replacement text. Its header says which items are
     already applied.
   - What is left there is mostly the precise shape of P2:
     - a pending token holds its seat;
     - the seat states renamed so that "held" means one thing;
     - no TOO_LATE after go while `refuse_new_connections` is set;
     - an ordered exit;
     - the match file, auth bytes, RESULT and exit codes fixed as contracts;
     - the switch named;
     - clients keyed on the announce rather than on the switch.
   - Do it before any P2 code.
3. **P2**, behind the switch that keeps the handoff off on `main` (§7). It starts with that switch.
4. P3, then P4 (gated on the owner's port test), then P5 (gated on the Linux spawn half), which is
   the release.

**The owner still owes:**
- the port test from testers' networks (§7, P1). It gates P4;
- the Linux half of the spawn spike, on the box. It gates P5;
- a click-test of the lobby's seat dropdown (host clicks an empty seat, Open/Closed);
- whether to move the editor from Godot 4.7.1 to 4.7.2, which the server runs.

**How to test.** The harness is in `Tools/`, and it runs the same on any machine:
- `.\Tools\new_probe_copy.ps1 -Name <copy> [-Files <changed files>]` builds an isolated copy of
  HEAD, with only the named working-tree files laid over it and LockstepProbe switched on through
  an `override.cfg`. It lands under `%TEMP%\ltw_probe`.
- `.\Tools\run_lockstep_probe.ps1 -Copy <copy> -Name <scenario> [flags]` plays one scenario on
  loopback: a relay, a host and a join. The flags are in the script's header: kill a player, shut
  the relay down, a third peer, a second match, an old build on one side.
- `python Tools\probe_table.py %TEMP%\ltw_probe\runs` tabulates every run.
- A run with no `PROBE RESULT` line did not run. The positive-control rule in CLAUDE.md applies to
  every result.
- The scenarios worth re-running, and their numbers, are in CLAUDE.md (LockstepProbe) and in the
  Findings.

**How the owner wants this worked:**
- **Commit as phases land.** Push and deploy only when the whole piece is finished, or when the
  owner asks, as they did for this machine switch. A deploy earlier than that, for a test, is asked
  for first. Before any push, name what is about to land.
- **Netcode is the owner's least experienced area.**
  - Bring each choice in plain terms, with a recommendation.
  - Anything on the box or the network is handed over as exact copy-paste commands, in order,
    each with what it is for, what success and failure look like, and when to stop and send the
    output back.
- **Claude cannot reach the box.** ssh from a tool call is denied, so the owner runs every box
  command, deploy included.
- **Another Claude session may share the working tree.** Commit only explicit paths. That session
  may also push `main`, which is one reason the switch exists.

**Not in the repo:** the review's raw findings, which carry file-and-line evidence, stayed on the
machine the review ran on. Everything they established is in this plan, and the engine and
systemd facts are in the Findings.

---

## 0. Orientation

The dedicated server is one process. It holds the lobby list and relays one lockstep match at a
time; a second Start is refused with a sentence. Under lockstep (D2, D40) the server simulates
nothing: it stamps each order with the slot of the player who sent it, seals one turn per tick,
compares checksums, and speaks for a player who has left.

**What the owner decided on 2026-09-25**, all in `multiplayer.md` §1:

- **D44. Each match runs in its own server process**, handed off from the lobby process. The
  reason is independence between matches. The shape also suits a future where the server
  simulates again.
  - It is built in two stages:
    - **(a)** match processes as children of the lobby's service;
    - **(b)** one systemd unit per match, so that a lobby crash leaves running matches alone.
  - A new client build with a protocol bump is accepted.
  - A started match's lobby **disappears** from the browser.
  - A player whose move to the match process fails **may retry until the load timeout** (D15).
  - **A player whose connection to the match process breaks during loading may claim their seat
    again within D26's hold.** After the hold they are out. Once the match has begun, D13 holds
    unchanged. (Decided after the review.)
  - The match cap is set **from a load test**, not guessed.
- **D45. A deploy cancels running matches and tells the players**; it never refuses.

Read before touching anything:
- `../CLAUDE.md`, for the hard rules and the engine traps;
- `multiplayer.md` §1, §2 and §11;
- `server.md`.

**What is already done** (2026-09-25, server-side, `@rpc` surface unchanged):
- The relay opens no match scene. The roster comes from `MatchStart.running_setup()`.
- The godot_ai helper is kept off the server.
- `server_relay` is off.
- The replication-era order endpoint is refused under lockstep.
- Orders have a byte budget.
- The lobby list goes only to peers not in a match.
- Match ids carry the boot's clock.
- There is a clean shutdown by file (`Net.begin_shutdown`).

---

## 1. The shape

```
                  lobby process (ltw-server)                match process, one per match
 client ──join──▶ lobby list, countdown, the handoff ──spawn──▶ one relay, today's code
   │              tokens, ports, supervision, the cap           accepts only its own players
   │                                                            exits when the match ends
   └───────────── moves its one connection to the match process at the start of loading
```

**The relay code does not change.** `LockstepService` and `CommandService` find a sender's slot by
`network_id`. They read the roster through `MatchStart.running_setup()`, which is null until the
go signal. So a match process runs them as they are, once the roster carries the ids of the
connections it actually has.

**MatchStart's loading gate does change.** Today it counts peer ids. In a match process it becomes
a seat table (§2, step 6).

What else changes:
- who starts the process;
- how a client gets from the lobby to it;
- how the lobby learns what happened.

**It is not the "address change" the old docs called it.** A peer id is chosen by the CLIENT,
afresh on every connection, and every id is public. So the lobby's ids mean nothing to the match
process. The move is an identity transfer:
- a secret per seat;
- a claim on arrival;
- a roster re-keyed BEFORE the go signal, because the relay stamps every order's slot and
  addresses every seal by `network_id`;
- and never changed AFTER it, because `network_id` is hashed into every checksum.

---

## 2. The handoff, step by step

### Step 1. The countdown begins (D24), and the lobby spawns

D24 already freezes the roster, seats, colours and settings when the countdown starts. So the
setup is final then, and the match process boots while the countdown runs rather than after it.

The lobby:
- refuses a rename during the countdown as well. Today `register_player` is not refused then, and
  `display_name` is hashed into the checksum;
- builds the `MatchSetup` as today;
- makes one token per HUMAN seat: at least 16 bytes from `Crypto.generate_random_bytes`.
  - Tokens live in a slot-to-token map beside the setup. **They are never a field of
    `MatchPlayer`, `MatchSetup` or `LobbyInfo`**, because each of those is serialised whole to
    every player or to every browser.
  - An AI seat (later) gets no token, and is never waited for;
- takes a port from the match range, the least recently freed first;
- writes the MATCH FILE into its run directory. It holds:
  - the setup;
  - the token map;
  - when the countdown ends, which is when D15's clock starts;
  - the lobby's pid.

  Every per-match file (match, READY, RESULT, heartbeat, shutdown, log) is named by the match id,
  so no file can be taken for another spawn's.
- spawns the child with the whole line:

  ```
  <godot> --headless --path <checkout> --log-file <run dir>/<match id>.log --
          --match-server --match-id <id> --match-file <f> --port <p> --shutdown-file <s>
  ```

  The binary path is refused when it ends in ` (deleted)`: that means a Godot upgrade replaced it
  under a running lobby;
- logs one spawn line with the match id, the pid and the port.

*Why a file, not arguments:* Boot logs its arguments, `/proc/<pid>/cmdline` is readable by every
local user, and journald records each writer's command line. A token must reach none of them.

**Limits on spawning:**
- A lobby has at most one child in flight.
- The cap counts a child from spawn to reap.
- Spawns are serialised, one child booting at a time, until P5 measures whether the box's cores
  can take more. A boot costs whole CPU-seconds, and every running relay needs its tick on time.

### Step 2. The match process boots

In this order:
1. **Boot treats `--match-server` as a dedicated server**, so the godot_ai helper is dropped. The
   log line "Editor helper removed" is the positive control. Today `is_dedicated_server` matches
   `--server` exactly, so without this change a match process would boot as a CLIENT.
2. **It refuses to boot with `lockstep_enabled` off.** The replication comparison runs in a single
   process, as it does today.
3. **It raises its own `/proc/self/oom_score_adj`** (Linux only) and reads the value back (§4).
4. **It reads the match file, then deletes it, and clears every seat's `network_id`.** Until a
   seat is claimed, it is identified by its token.
5. **It installs `auth_callback` and `auth_timeout`** (a named `NetworkConfig` value) before
   `Net.host()` assigns the peer, next to `server_relay`.
6. **It keeps every rpc autoload, `Lobby` included**, because the D31 hash walks all of them. In
   this role, `Lobby`'s endpoints return at once and log nothing.
7. **It binds its port. A bind that fails exits at once with its own exit code.** It does not log
   NOT LISTENING and wait.
8. **A shutdown file already present when it hosts is HONOURED.** It is not deleted as stale: its
   name is minted per match, so it cannot be stale. Today's `_arm_shutdown_file` deletes it, which
   would swallow a D45 request aimed at a child that is still booting.
9. **Only then does it write READY**, with its pid.

**The lobby polls in a fixed order:** READY first, then liveness (`is_process_running`), then the
ceiling.
- A READY seen in the same poll as the ceiling wins.
- A child that has already exited is handled at once. A taken port is respawned once on the next
  free port; any other exit cancels the start.
- The ceiling is set from P5's boot measurement on the box. It is only the backstop for a hang.

### Step 3. The spawn window

Between the spawn and the announce, the countdown is running and the child is booting. **The whole
window counts as the countdown for D24:**
- A member leaving, the host leaving (D23), the host's Cancel, or a D45 shutdown cancels the start
  as a countdown cancel does today, with the same sentence.
- The child is KILLED. It is never asked to stop through its shutdown file, because it may not be
  listening yet. Its port is freed and its files are deleted.
- If the countdown reaches zero before READY, the room keeps reading "Starting the match..." with
  Start disabled: `is_starting` stays true until the announce. The same rules hold until then.
  Today the room would offer the host an enabled Start in that gap.
- The announce goes out only if the lobby still exists and its members still match the match file.
  Otherwise the child is killed.

### Step 4. The announce

- **The lobby sends `receive_match_starting` through a send-only helper that holds no match
  state.** Today `begin()` both sends the announce and arms the loading gate. Arming the gate in
  the lobby would make the lobby busy again, which means one match at a time.
- **The payload gains two keys:** the match PORT and that player's own token. The token is added
  to the dictionary after it is built, for that peer only.
- **It has no host key.** The lobby cannot know which of its addresses a client used (loopback,
  LAN, public or Tailscale), so any host it named would be wrong for some client. The client dials
  the address that reached the lobby. A host key would only be added if a match ever ran on
  another machine.
- **At the same moment the lobby closes itself silently.** It is erased from the list and from
  every member's lobby entry, and no `receive_closed` is sent.
- **Each handed-off connection is marked.** Its requests are refused, and the lobby closes it
  itself if it is still connected when the load window ends. The client hangs up to move; this is
  for a client that does not.
- **In the lobby code:**
  - the cap check replaces the `is_busy` branch of `_start_refusal`;
  - the reopen in `_on_match_abandoned` becomes the reopen after a failed spawn;
  - `submit_alive` and `submit_order` check membership before they write any per-sender table,
    because a lobby process never runs the match that would clear them.

### Step 5. The client moves

§6 has the client side in full.
- It moves at once, while its load starts. `Net.move_to(port, token)` dials
  `Net.current_address()` at the announced port and authenticates with the token.
- **The version handshake (D29/D31) runs on the new connection exactly as today, after
  admission.** It is not folded into the auth message (§8).
- A dial that gets no answer, and a SEAT_HELD refusal, are retried until the load timeout.

### Step 6. The match process claims seats

The match process keeps a SEAT TABLE. Each seat holds:
- its token;
- its current peer id, or 0;
- a state: unclaimed, claimed, ready, held (inside D26's hold) or left.

MatchStart's `begin()` is not reused. With every id cleared, it would start at once, because 0 is
at least 0. With the lobby's ids, it would wait for connections that will never come.

- **Checking.** `auth_callback`:
  - refuses a payload over a small fixed size;
  - parses a fixed layout, never with `bytes_to_var`;
  - for a valid token whose seat is unclaimed or held, records `pending[peer] = seat` and
    completes auth;
  - ends the connection on the first wrong token, and on any auth message after a claim. One
    connection claims at most one seat.
- **Claiming.** The seat is re-keyed only on `peer_connected`, which fires on admission, and its
  link is stretched (D41) at that moment rather than at go. `peer_authentication_failed` discards
  the pending entry. A peer that passed the check but was never admitted raises only that signal,
  never `peer_disconnected`.
- **Never evicting.** A token presented while a live connection holds its seat gets SEAT_HELD, and
  the client retries. Evicting would let anyone who read the token off the cleartext wire push the
  real player out.
- **Releasing.** A claim ends:
  - on `peer_disconnected`;
  - on `peer_authentication_failed`;
  - in the code that calls `disconnect_peer`, which raises neither signal.

  After a claim ends:
  - a deliberate leave makes the seat `left` at once (D26);
  - a dropped link puts the seat in D26's hold. **Inside the hold, the token may claim the seat
    again** (the owner's call, 2026-09-25). When the hold runs out, the seat is `left`.
- **Refusing with a reason.** Every refused auth is answered with a status through `send_auth`:
  WRONG_TOKEN, SEAT_HELD, TOO_LATE or SHUTTING_DOWN. **The server does not hang up in the same
  breath**; the client hangs up once it has read the status. This is CLAUDE.md's
  message-before-disconnect trap, reached through auth: in the review's run, a hang-up at once
  lost the reason every time, and waiting delivered it every time. `auth_timeout` is the backstop.
- **From the go signal on,** no token is accepted and `refuse_new_connections` is set.

**Readiness is a flag on the SEAT.** It is set by `report_ready` from the seat's current connection,
and cleared when the claim is released. `receive_readiness` carries the SLOTS of the announced
setup, not peer ids, because the clients never saw the new ids.

**The gate:**
- the match starts when every seat that is not `left` is ready, or at the D15 timeout if at least
  `min_players` are ready;
- D15's clock starts when the countdown ends, a time the match file carries;
- **the go roster is always built fresh from the claimed, connected, ready seats, renumbered as
  `_roster_of_ready` does**, and is checked against `min_players` on every path. It is never the
  setup as it stands.

A seat that is never claimed is waited for until the load timeout, by the owner's retry rule. That
is longer than today's D26 hold for a crashed loader, because the match process never sees a
connection close.

### Step 7. The go signal

It carries the FINAL setup, with the new ids, and the match runs exactly as today. The client finds
its own seat by `local_slot`, as it already does. Nothing in gameplay compares peer ids.

### Step 8. The end

**The match process exits on EVERY road into `_finish_match`**, and never goes back to listening.

| How the match ended | Who writes the RESULT |
|---|---|
| the last player left | the match process |
| a D15 abort, including one where no seat was ever claimed | the match process |
| a D45 shutdown | the match process, from its shutdown handler, before `Net` quits |
| a crash, an out-of-memory kill or a signal | the lobby, from the reaped status in stage (a), or the unit's state in stage (b) |
| the child never became READY | the lobby |
| the lobby killed the child | the lobby, as "killed" |

- **The RESULT carries what a relay can know:**
  - the roster (slot, name, colour);
  - start and end;
  - every departure, in order, with its reason and relay turn;
  - whether a desync was announced, and on which tick;
  - how the match ended.

  **It carries NO winner.** Under lockstep no server process computes the outcome, so the claim in
  `multiplayer.md` §9 that "the server already computes the outcome" is no longer true. A trusted
  result would need the turn log replayed on a server, or the clients' reports cross-checked.
- The writer copies the roster before `_finish_match` clears it, and reuses the summary dictionary
  LockstepService already builds.
- **A clean end is proven by the RESULT file, never by the exit code.**
  - A death by signal reads as the raw signal number, so the match role's own exit codes are 64 and
    above, below 128.
  - An exit with no RESULT is logged as "died", with the code.
- Every link the match process has told it is out is closed with `peer_disconnect_later`.
- The lobby reaps the child, frees the port, deletes the run files, and logs one line with the
  match id and the number of matches still running.
- **A match nobody leaves** holds a cap slot until its players go; a player sitting on the end panel
  keeps the heartbeat going. Today that blocks the whole server; after D44 it holds one slot. A
  bound for it is open (§8).

### Step 9. Leaving

- After a match, `MatchStart.leave_match()` hangs up, and the browser dials the lobby when it opens
  (D20).
- **A client that a MATCH process tells it is out hangs up on that process before it changes
  scene.** That covers any `receive_match_cancelled` and any refusal during auth. The client hangs
  up once it has the reason.
  - Without this, the browser opens still connected to the match process and never dials the
    lobby, and every Create times out with the "different code" sentence.
  - Today the process that cancels IS the lobby, which is why staying connected was right.

### Failure paths, each with a sentence to the player

- **The child never becomes READY, or dies while booting:** cancelled in the lobby, like a
  countdown (step 3). Nobody has moved yet.
- **A member leaves during the spawn window:** the same cancel (step 3).
- **A player cannot reach the match port, or is refused:**
  - silence and SEAT_HELD are retried until the load timeout, and the player is then left behind
    by D15;
  - every other refusal ends at once, on the browser, with its own sentence (§6).
- **A claimed player's link drops during loading:** D26's hold, inside which they may claim again.
- **The match process dies mid-match:** the relay-loss handling (P0, §6).
- **A deploy (D45):** see §4. The lobby cancels every start it has not announced, and each child
  tells its own players.
- **The lobby dies:** in stage (a), every match dies with it. In stage (b), they carry on (§4).

---

## 3. Security

- **Tokens** (steps 1 and 6):
  - one per human seat, at least 16 random bytes;
  - never in a broadcast structure, the go signal, the RESULT, a log line or a match record;
  - valid until the go signal, then dead;
  - a claim never evicts.

  ENet is unencrypted, which is the same exposure as today: an attacker on the path could already
  inject into a session.
- **The match file is private because its directory is.** The drop-in sets
  `RuntimeDirectoryMode=0700`. The defaults are 0755 for the directory and 0644 for a file written
  at runtime. The lobby deletes a match file itself when it reaps a child that never read it.
- **Authentication protects the rpc surface, not ENet's slots.** An unanswered CONNECT holds a slot
  silently, for up to ENet's maximum timeout, before any auth runs. That is as true of the lobby
  port as of a match port, so it is not new. Therefore:
  - a match process keeps a `max_peers` several times its seat count, rather than the lobby's;
  - it sets `refuse_new_connections` from the go signal;
  - the box gets a per-source PACKET-RATE limit on the lobby port and the match range in P5 (an nft
    meter or hashlimit). Not connlimit: that counts flows, and ENet carries every peer of one
    socket over one flow.

  Spoofed or distributed floods are an accepted residual risk.
- **Every packet from a peer that is still authenticating prints an engine ERROR**, and no script
  rate limit can cap that. This is accepted, since the lobby port already has the same kind of
  exposure. What script CAN cap, it does:
  - refusals and dropped strangers are counted, and logged as one summary line per interval (and
    in the RESULT), never one line per attempt;
  - a match process's `Lobby` endpoints return before they log;
  - a client never sends `register_player` on a match connection.
- **The lobby port never sets `auth_callback`.** The old-build refusal (D29) has to reach a client
  that knows nothing of auth. An auth gate on the lobby would drop every old build with no reason,
  and print an engine error per packet.
- **`Net`'s handshake rpcs are frozen.** `refuse_protocol_version` and `state_protocol_version` keep
  their names, arity and modes, and no `@rpc` is ever added to `Net`.
  - Godot numbers a node's rpcs by their position in that node's name-sorted list. A new rpc that
    sorts before the handshake misroutes an OLD build's handshake, and every tester is then
    dropped with no reason, which is the failure D29 exists to replace.
  - A new endpoint goes on another autoload.
- **The lobby is the public door, and each countdown now costs a process.** So:
  - a lobby has one child at most;
  - spawns are serialised;
  - there is a per-source-address limit on children loading or running, with a sentence;
  - the lobby closes a handed-off connection itself if the client does not go (step 4).
- **Isolation contains a flooder to their own match. It does nothing for the other players of that
  match**, whose byte budget is per seal, not per second. A per-second budget is open work in
  `multiplayer.md`, not this plan.
- **No traffic from one match reaches another process's players**, since `server_relay` is already
  off and every relay entry point refuses non-members.

---

## 4. Hosting

### Stage (a): children of `ltw-server`

- **Spawning.**
  - On Linux, `OS.create_process` forks, calls `setsid()`, and execs. `setsid` changes the session,
    not the cgroup, so a child stays in the service's cgroup, and `KillMode=control-group` still
    reaches it.
  - Godot sets close-on-exec on every socket and file, so a child never holds the lobby's port.
    Only stdout and stderr are inherited.
  - On Windows the child gets no console and no inherited handles, **so its output is lost**. That
    is why `--log-file` is on every spawn line. It is also what the dev loop and every P2-P4 proof
    read.
- **There is one `godot.log` per user.** Without `--log-file`, every process of the project writes
  `user://logs/godot.log`, and each boot rotates and truncates it, the lobby's own log included.
- **Liveness and reaping.**
  - `OS.is_process_running(pid)` reaps a child that exited on its own, and caches its status.
  - **A child the lobby kills behaves differently on Linux.** `OS.kill` reaps it itself and never
    updates Godot's table. A later `is_process_running` or `get_process_exit_code` on that pid
    logs an engine error and reads 0, which looks like a clean exit.
  - So a killed child leaves supervision in the same call, and the lobby logs it as "killed".
  - The Windows dev loop answers differently (-1), so this is proven on the box (P5).
- **A wedged child** still counts as running. Each match process touches a heartbeat file every few
  seconds, and the lobby kills and reaps a child whose heartbeat is stale, logging "wedged". The
  same file is stage (b)'s liveness signal.
- **Ports.**
  - A range in `NetworkConfig`, opened once with `ufw allow <first>:<last>/udp`, and in the Windows
    dev rule for cross-PC tests.
  - ENet binds without `SO_REUSEADDR`, so a taken port fails to bind rather than being shared.
    That is a reliable answer, and the child turns it into an exit code (step 2).
- **The service file**: the drop-in `-InstallShutdown` writes gains three things.
  - **`OOMPolicy=continue`.** It keeps the unit up when a CHILD is killed for memory. **It does not
    choose which process the kernel kills.**
    - The kernel picks by badness, which is mostly size. The lobby boots to about the size of a
      match, and a slimmer match process would make the lobby the LARGEST. So each match process
      raises its own `/proc/self/oom_score_adj` at boot, which needs no privilege. Every match then
      dies before the lobby does.
    - `OOMScoreAdjust=` lowering the lobby is optional hardening. If it is used, every child MUST
      raise itself, because children inherit the value.
    - A true per-match memory ceiling is possible even in stage (a), without root:
      `Delegate=memory pids`, plus `DelegateSubgroup=`, plus a sub-cgroup per child with
      `memory.max`. Weigh it after P5 shows whether a leak is a real risk.
  - **`RuntimeDirectoryMode=0700`** (§3).
  - **`LogRateLimitIntervalSec` and `LogRateLimitBurst`, set deliberately.** In stage (a) the lobby
    and every match share one journald bucket, and a flood from one empties it for all.
- **D45 in stage (a).** ExecStop creates the lobby's shutdown file. The lobby then:
  1. refuses every new start (already true today);
  2. cancels every lobby whose child it has not announced, with D45's reason, and kills that
     child;
  3. creates the shutdown file of every announced child, and waits for them, with a bound;
  4. quits.

  From then on each child answers every auth with SHUTTING_DOWN, tells its players, closes their
  links with `peer_disconnect_later`, and exits.
  - The lobby's poll, a child's poll, both notices and both closes must fit inside
    `TimeoutStopSec`. P5 checks the drop-in's value against that sum.
  - `KillMode=control-group` stays the backstop.
  - A lobby CRASH runs ExecStop too, with `$MAINPID` unset. Today's wait loop then falls straight
    through, and the cgroup kill freezes every match without a word. Optionally, ExecStop can
    create every child's shutdown file and then wait until the unit's cgroup holds nothing but
    itself. Then even a crash ends each match with D45's sentence.
- **The journal.**
  - On the box's systemd, journald tags each child's lines with the child's own `_PID` and command
    line, so the lines are NOT under the lobby's pid.
  - The spawn line maps each pid to its match id.
  - Lines that a tool reads with `-o cat` (the summary, a desync, the RESULT line) must still carry
    the match id. That was the open "match id on every relay line" item; it is now required.
- **The deploy (`deploy_server.ps1`) stops first**, in this order:
  1. stop the service (ExecStop gives D45's notice);
  2. fetch and reset;
  3. `--import`;
  4. `chown -R ltw:ltw`, after the import, which runs as root;
  5. start, keeping the pid assertion.

  Today's order resets and imports while the old server is still serving, then restarts. With
  spawning, the old lobby could start a match from the new or half-imported tree, and that
  child's version gate would then refuse players who are on the right build. The cost of stopping
  first is that the browser is down for the length of the import.

  `Get-OpenMatches` stops replaying the journal, where every child's "Listening on port" line
  would reset its count. It counts running match processes directly instead, alongside a
  "Matches running" line the lobby writes at every spawn and reap.
- **The dev loop.**
  - The run directory is `user://run` on Windows and `/run/ltw-server` on the box.
  - `stop_server.ps1`, and `run_server.ps1`'s check for a server already running, also match
    `--match-server`. Today both look for `--server`, which `--match-server` does not contain.
    `-List` shows each match process's port.
  - On Windows a child outlives its lobby. A match process with no seat claimed by the load
    timeout exits on its own, and `stop_server.ps1` stops the rest.

### Stage (b): a systemd unit per match

- **The mechanism.** There are three ways; choose once stage (a) has been measured.
  - **A polkit rule over D-Bus.** Not sudo: `NoNewPrivileges=yes` stops a process from gaining
    privileges, but it does not block a D-Bus call that polkit checks.
    - The rule must pin the subject user `ltw`, the action `manage-units`, an ANCHORED pattern for
      the template's instances, and the verbs `start` and `stop` only.
    - The same action also authorises TRANSIENT units, which carry their own `User=` and
      `ExecStart=`. A loose rule would make a compromised lobby root.
    - The lobby starts only the fixed template `ltw-match@<port>.service`: never through
      `systemd-run`, and never through a shell.
    - polkitd may not be installed on the box; check with `-Facts`.
  - **A pool of pre-started units.** It needs no runtime permission, but costs idle memory and CPU.
  - **A lingering user manager for `ltw`.** Root runs `loginctl enable-linger ltw` once, and the
    lobby runs `systemd-run --user --no-block --unit=ltw-match-<port> -p MemoryMax=<cap> …`. No
    root at runtime and no polkit, but it needs `ltw` to have a working user manager, which is
    unknown.
  - Whichever is chosen, the lobby passes `--no-block` on every `systemctl` call, because
    `OS.execute` blocks the main thread for the whole job.
- **Instances are named by port.** The lobby checks `systemctl is-active` before a start, because
  starting a unit that is already active silently succeeds. A restarted lobby lists taken ports
  with `systemctl list-units 'ltw-match@*' --state=active`.
- **Run files live where no unit's stop removes them**: a `tmpfiles.d` entry
  (`d /run/ltw 0700 ltw ltw -`), or `RuntimeDirectoryPreserve=yes` on `ltw-server`.
  - By default, systemd deletes `/run/ltw-server` on every stop of the lobby, including the
    crash-restart that stage (b) exists to survive.
  - A match unit's own RuntimeDirectory would likewise delete its RESULT before the lobby reads it.
- **Match units get no `PartOf=` or `BindsTo=` on `ltw-server`**, unless `ltw-server` has
  `RestartMode=direct`. Under the default, a lobby crash-restart becomes a try-restart of every
  PartOf unit, which kills every match.
- **D45 in stage (b) is applied by the DEPLOY.**
  - The deploy stops every match unit, each with its own D45 ExecStop, before it touches the
    checkout.
  - The lobby's ExecStop never cancels them, because ExecStop also runs after a crash.
  - Only an UNPLANNED lobby death leaves matches running.
  - If the owner would rather let old matches finish on old code, that is a new decision, and it
    needs a checkout per release.
- **Liveness of a process that is not a child** comes from the unit's state or the heartbeat file.
  Never from `is_process_running`, which logs an engine error on every call for a non-child.
- **Logs** land under the match unit, so every journal read (`Get-OpenMatches`, `-Facts`, `-Log`)
  also covers `ltw-match@*`.

---

## 5. Capacity

- **Memory binds first** under this shape, not CPU.
  - The cap is the number of match processes, counted from spawn to reap.
  - It is set from the load test on the box.
  - It is enforced in the lobby with a sentence ("The server is full"), below the size of the port
    range.
  - ENet IGNORES a connection over `max_peers` rather than refusing it, so the sentence can only
    come from the lobby.
  - The lobby's `max_peers` bounds only the browser population. A match process keeps its own
    (§3).
- **Before sizing the cap,** P2 measures what the match role's boot costs, and what a slimmer boot
  would save (the Findings has the split). A match process needs the relay, not the content. But a
  slimmer boot may drop content, never an rpc autoload (D31).
- **The load test:**
  - **memory** from N idle match processes, started from dummy match files with no clients, read
    as the drop in `MemAvailable` as N goes from 0 upward. That is the marginal cost of a match.
    VmRSS counts the shared binary pages in every process, so it overstates the cost. A debug hold
    stops the processes from exiting at the load timeout;
  - **the summary line gains `VmHWM` (the peak) and `RssAnon`**, so a match's own growth is
    visible;
  - **boot-to-READY time**, idle and with others booting at once. It sets the READY ceiling;
  - **the worst tick of a running match while others boot.** It says whether spawns must stay
    serialised;
  - **CPU and traffic** from a few real probe matches;
  - **a fake client**, only if those disagree with the Findings. It goes through the real connect,
    auth and rpc path but simulates nothing, and runs from off the box;
  - **a run whose journal shows "Suppressed N messages" is a failed run.**

---

## 6. Client changes: one build, with a protocol bump

- **`Net`:**
  - **`move_to(port, token)`** dials `current_address()` at the given port.
    - It assigns the new ENetMultiplayerPeer directly and then closes the old one. The status
      then goes CONNECTED, CONNECTING, CONNECTED, and never OFFLINE. OFFLINE is what makes
      MatchStart forget the match today.
    - A retry does not pass through OFFLINE either.
  - **The move has states of its own**, and ends only as admitted, given up or refused. While it
    runs, `server_disconnected`, `connection_failed` and `peer_authentication_failed` all route to
    one `move_failed(reason)`. They do not reach `disconnected_from_server` or the browser's
    failure handling.
  - **`auth_callback` is set only for a match dial.** `join()`, `leave()` and the teardown clear
    it. The one SceneMultiplayer is shared by every connection the process makes, so a callback
    left set breaks every later lobby dial.
  - **`Lobby` does not register on a match connection.**
  - **The handshake rpcs are frozen** (§3).
- **`MatchStart` (client):**
  - keeps the setup and its token across the move;
  - **treats readiness as a STATE, not an event.** It sends `report_ready`:
    - when the match connection is admitted, if loading has finished;
    - when loading finishes, if the connection has been admitted;
    - again, after a re-claim.

    Sent only once, the report is lost whenever loading beats the move. On a warm client, that is
    every match after the first;
  - ends the move with its own sentence for each refusal status and for giving up. The sentences
    are drafted in P4 and handed to the owner to word;
  - **on any cancel from the match process, hangs up first and then opens the BROWSER** (step 9).
- **`MatchLoading`:**
  - rows are keyed by SLOT, and the player's own row by `local_slot`, from a `receive_readiness`
    that carries slots (step 6);
  - it gains a line for the move ("Connecting to the match...") and one for a failure.
- **`SessionLog`** notes the roster again from the go signal. The lobby-time roster's peer ids are
  not the match's, and a D15 short start renumbers the slots.
- **`Lobby` (client):** nothing survives the handoff. After a match, the browser dials the lobby as
  it already does.
- **`protocol_version` is bumped.**
  - An older build drops the new payload keys (`MatchSetup.from_dict` reads only the keys it
    knows), so it would sit in a loading screen the lobby no longer serves. The bump refuses it at
    the door with "update the game".
  - The bump lands in the same commit that switches match processes on (§7).
- **The two client fixes the Findings called for are DONE** (2026-09-25) and need no bump:
  - a match ends with a sentence when the server vanishes (a crash, running out of memory, a
    reboot);
  - the cancel reason stays on screen after the disconnect.

---

## 7. Phases

Each phase is done when its proof has RUN. Check the positive control before believing a green
result (`CLAUDE.md`).

**Off until it ships.** Every phase lands on `main`, and any deploy ships `main`, including a
deploy by another session.
- So until P5 the handoff is OFF. A `NetworkConfig` switch, false in the shipped `.tres`, keeps the
  lobby on today's in-process path. The P2-P4 proofs turn it on from the command line.
- The server logs the switch at boot.
- The protocol bump lands in the same commit that turns the switch on, at the release (P5). So a
  deploy before then changes nothing for multi-match.
- The in-process path is deleted in P7.

**Gates.**
- **P4 does not start before the owner's port test** has run from the testers' networks. If a
  tester cannot reach the match range, stop and bring the owner the choice: a forwarder on the
  public port, which changes the client side.
- **P5 does not start before the Linux half of the spawn spike** has run on the box.

**P0: baseline and live bugs.** DONE 2026-09-25; see the Findings.
- Also done: `deploy_server.ps1` no longer restarts when there is nothing to deploy. It says how
  many matches a restart is about to cancel, read from the journal, and it can install the D45
  drop-in (`-InstallShutdown`).
- Also done: the two client fixes in §6.
- **One more live bug, found by the review. Fix it before P2; it does not depend on D44.**
  MatchStart's loading gate counts heads.
  - `_drop_peer` removes the dropped player from `_expected` but not from `_ready_ids`. So a player
    who reports ready and then drops lets the count pass while another player is still loading.
  - `_start_match(_setup)` then starts the FULL setup. That includes the dropped player, and also
    a player dropped before reporting ready, which breaks D15's "no area spawns for them".
  - Fix, on today's in-process path:
    - while the gate waits, a DISCONNECT (`_on_peer_left`) removes that player from `_ready_ids`
      at once and broadcasts readiness again. This happens at the disconnect, not only at the
      drop after D26's hold. A player inside the hold still counts as expected and not ready, so
      the start waits out the hold;
    - the gate is "every peer in `_expected` is in `_ready_ids`", never a count;
    - the go roster is always `_roster_of_ready()`, on both paths. On both paths, a go roster
      below `min_players` aborts with D15's sentence. Today only the timeout path checks it;
    - "You did not finish loading in time." goes only to peers still connected.
  - Prove it with LockstepProbe in a FOUR-player load. The probe and the runner gain:
    - `--players <n>`, so the host starts at n members;
    - `--quit-after-ready` and `--quit-before-ready`, each a hard exit with no goodbye;
    - `--ready-delay <s>`, longer than ENet's detection plus D26's hold;
    - a count of join clients in `run_lockstep_probe.ps1`.
  - The run: one probe quits after reporting ready, one quits before, and one delays. The go
    roster must hold exactly the host and the delayed probe, and the relay's "Match start" line
    must come after the delayed probe has loaded.
  - **Positive control:** the same run on the parent commit starts early, with all four players
    in the go roster.
  - A three-player run of the same shape must end in D15's abort, never in a start.
- Left:
  - running `-InstallShutdown` once, right after the next deploy, which brings the code for it
    (`server.md`). Until then a restart freezes a running match. P5 re-runs it for its new lines;
  - handing out the client build that carries the fixes. It goes out with a deploy of the same
    commit, never alone, because the lobby-seat rpc (`Lobby.request_seat_state`) moved D31's
    hash.

**P1: spikes, all small and all thrown away.** The measurements are in the Findings.
- **SceneMultiplayer authentication carrying a token: DONE, and it holds.**
  - Both ends set `auth_callback`. The client answers `peer_authenticating` with `send_auth`, then
    `complete_auth`. The server calls `complete_auth` only for the right token.
  - A right token was admitted, and its rpc RAN.
  - A wrong token was refused.
  - A peer that never authenticated was dropped at `auth_timeout`. Its rpc call "succeeded"
    locally and NEVER ran on the server.
  - A right token sent after the timeout was refused.
  - **The review settled the rest from the engine source:**
    - a refusal can travel back inside auth (`send_auth`), but only if nobody hangs up in the same
      breath;
    - `peer_connected` fires only on admission;
    - a peer that passed the check but was never admitted raises only
      `peer_authentication_failed`;
    - the callback runs for every auth message, so the rules in step 6 have to be the code's; the
      engine enforces none of them.
- **A Godot process spawning a Godot process: the Windows half is DONE.**
  - `OS.create_process` launched the child from a headless parent.
  - Its READY file was seen, and its exit and exit code were read through
    `is_process_running` / `get_process_exit_code`. Nothing was left running.
  - The review settled from source that Linux forks, calls `setsid`, execs, and closes every socket
    on exec. **The run on the box is still the owner's, and it gates P5.**
- **The port test from testers' networks: the owner's, not run yet. It gates P4.**
  - The box's only firewall is ufw (no Hetzner firewall), so opening a test port is one
    `ufw allow <port>/udp`.
  - A second server for the test can run as a transient unit:
    `systemd-run --unit=ltw-porttest --uid=ltw --gid=ltw /opt/godot/godot --headless --path /srv/ltw/LTW_Test -- --server --port <port>`.
  - Testers start the game with `-- --port <port>`.

**P2: the match-process role.**
- Everything in steps 2, 6, 7 and 8 that runs in the match process:
  - Boot's `--match-server`;
  - the seat table and its gate;
  - `auth_callback`, with its rules and statuses;
  - the re-key on admission;
  - readiness per seat, reported by slot;
  - the go roster;
  - exiting on every road into `_finish_match`;
  - the RESULT file and the exit codes;
  - the heartbeat;
  - the honoured shutdown file;
  - `oom_score_adj`;
  - the exit on a failed bind.
- LockstepProbe gains a role that reads its setup and token from a hand-written match file, dials
  the match port with its token, and reports ready. P4's client reuses its auth helper.
- The boot-memory attribution (§5).
- The code comments in Lockstep and Net that cite D19 as current are updated here.
- **Prove**, each by a line that must be PRESENT:
  - a match process started BY HAND from a hand-written match file plays a full probe match. Each
    probe prints its slot, its own connection id, and the `network_id` the go signal gave that
    slot. Equal ids prove the re-key ran;
  - "Editor helper removed" appears in the child's log;
  - a seat that reports ready and then drops before go is not in the go roster, and the start waits
    for the rest. A seat that drops before it is ready gets no area;
  - a claimed seat that drops can claim again inside D26's hold, and cannot after it;
  - a second live claim for a held seat gets SEAT_HELD;
  - a connection whose peer id equals another seat's lobby-era id claims only its own seat;
  - a wrong token, and a token after the go signal, are refused with their statuses, and the client
    reads them;
  - a taken port exits with its code;
  - a shutdown file present at boot is honoured.

**P3: the lobby side.**
- Step 1, step 3, step 4 and the lobby's half of step 8:
  - tokens in their own map;
  - the port pool;
  - the spawn when the countdown begins, with renames refused;
  - READY, then liveness, then the ceiling;
  - the spawn window's rules;
  - the send-only announce, and the silent close;
  - the handed-off connections;
  - the cap and its sentence, and the per-source limit;
  - serialised spawns;
  - reaping, and killed children;
  - the "Matches running" line.
- The dev loop: `stop_server.ps1`, `run_server.ps1` and `server.md`. (`CLAUDE.md`: `server.md` is
  updated with every control.)
- The code comments in Lobby, NetworkConfig and MatchStart that cite D19 as current are updated
  here.
- **Prove:**
  - a spawn that never becomes READY cancels cleanly;
  - a taken port respawns on the next one;
  - a member leaving in the spawn window cancels the start and kills the child;
  - a full server says so;
  - each client's announce holds exactly one token, its own;
  - `stop_server.ps1` leaves no match process behind.

**P4: the client side** (§6), behind the switch.
- **The protocol bump is NOT committed in P4.** Nothing reads `protocol_version` through the
  switch, so a bump on `main` would refuse every tester at the next deploy.
- P4's old-build proof runs with the bump applied in the working tree only, and reverted
  afterwards. The bump itself lands in P5's release commit, with the switch.
- **Prove** with LockstepProbe, which gains `--lobby <name>` so that two pairs cannot join each
  other's lobby:
  - two, then three matches at once;
  - a desync in one match reaches only its players;
  - a hard kill of one match process leaves the others running;
  - a dial that fails is retried and gets in. This is driven by a probe flag that dials a closed
    port first, and it must print a `dial_attempts` above one;
  - each failure shape (nothing listening, a wrong token, a mismatched build) ends with its own
    sentence, and the setup is kept throughout the retries;
  - a client whose load finishes before its dial succeeds is still counted ready;
  - a client held past the load timeout ends in the browser, connected to the LOBBY, with its
    reason on screen;
  - after a match, and after a failed move, the same client process opens the browser and lists
    lobbies;
  - an old build is refused with the sentence. The old build must be a checkout of the last
    handed-out commit, NOT the new code with `protocol_version` edited, which would share the new
    rpc table;
  - regression: TutorialProbe runs headless, one offline skirmish goes through the loading screen,
    and the Findings' scenario table is re-run with every match behind a handoff.

**P5: stage (a) on the box, which is the release.**
- Before it: the port test and the Linux half of the spawn spike have run.
- `deploy_server.ps1` gets:
  - the stop-first order, with chown after the import;
  - counting match processes directly;
  - the drop-in's new lines.

  `-InstallShutdown` is re-run to apply them BEFORE the switch is turned on, and asserts the
  effect by reading the settings back with `systemctl show`.
- The port range goes into ufw, with the per-source packet-rate limit.
- **Every box step is the owner's to run.** A Claude session cannot reach the box, so the
  implementer hands over exact commands and says what success looks like.
- **The order, which matters:**
  1. **If the P0 code is not on the box yet:** push `main` with the switch still off, deploy it,
     run `-InstallShutdown` right after, and hand out the client build the same day. The
     lobby-seat rpc moved D31's hash, so this deploy and its build go together.
  2. **Re-run `-InstallShutdown`** with the new lines (`OOMPolicy`, `RuntimeDirectoryMode`, the
     log rate limit). From then on, every restart honours D45.
  3. **Measure BEFORE the release.** Start a second server as a transient unit with the switch
     on, on a port outside the public one, as P1's port test does. Give it the drop-in's settings
     as `-p` properties and its own `--log-file`. Run the load test and the probe matches
     against it. Set the cap and the READY ceiling in the `.tres` from what they show, then stop
     the unit.
  4. **The release commit:** the switch on, the protocol bump and the measured values. Push,
     then deploy. The deploy stops through ExecStop, so anyone playing is told. Hand out the
     bumped client build the same day (D30).
  5. The deploy-cancel and OOM proofs need the real unit with its drop-in. They run after the
     release, with nobody playing.
- **Prove:**
  - a deploy with two matches running tells the players of both;
  - killing one child leaves the other running;
  - with nobody playing, a real out-of-memory kill of one match process:
    - once under `OOMPolicy=stop`, where the unit stops. That is the positive control;
    - once under `continue`, where only that match dies.

    The journal shows the OOM line both times;
  - each match process's `oom_score_adj` reads back as raised;
  - a child killed at the READY ceiling is logged as killed, and the journal has no "not a child"
    error;
  - the load test (§5) sets the cap and the READY ceiling.

**P6: stage (b).** Everything in §4, stage (b):
- the mechanism and its permission;
- instances named by port;
- run files outside the lobby's RuntimeDirectory;
- no `PartOf`;
- D45 applied by the deploy;
- the liveness signal for a non-child;
- recovery after a lobby restart;
- journal reads widened to the match units.

**Prove:**
- a SIGKILLed lobby leaves every match running, and its restarted self sees them and reuses none
  of their ports;
- a deploy with a match unit running cancels that match with D45's sentence.

**P7: docs.**
- `multiplayer.md`:
  - §2, §5.7 and §11.3;
  - §11.1, including its "until it lands, one process does both" line;
  - §13's row;
  - §9, which must say that under lockstep no server computes a winner;
  - D44's row;
- `server.md`: the controls, the log lines, the firewall line, and the passages that describe one
  match at a time;
- the README's Status section;
- any trap that cost a session, into `CLAUDE.md`;
- delete the in-process single-match path that the switch kept alive;
- remove the links to this file from `Docs/README.md`, `README.md` and D44's row, then delete
  this file.

---

## 8. Choices the review weighed

- **Files rather than a control connection.**
  - A stdout pipe can deadlock when nobody drains it.
  - A loopback socket from child to lobby was also possible. It would push READY and RESULT, carry
    a cancel from the lobby, and serve as stage (b)'s liveness signal by simply being connected.
  - Files were kept for stage (a) because P1 proved them and they work the same on Windows. P6
    decides between heartbeat files plus the unit's state, and a control link.
- **Engine authentication rather than a claim rpc.** It is proven by P1 and by the review's reading
  of the source. What is left is the seat mapping, in P2.
- **The version check stays after admission,** on both processes, rather than folded into the auth
  message.
  - The lobby and its children always run one checkout, which the deploy guarantees, so the fold
    bought almost nothing.
  - It would have moved the refusal to where no rpc can reach.
- **Spawning when the countdown begins**, not when it ends.
  - D24 already makes the setup final then, and the boot hides inside the countdown.
  - The cost is a boot per cancelled countdown, bounded by one child per lobby and by serialised
    spawns.
- **Moving at the START of loading**, not at the go signal.
  - The dial overlaps the local load, and a failure lands inside D15's window.
  - The price is readiness that has to be restated, paid in §6.
- **Re-keying `network_id` rather than keying the relay on slot.** The relay needs a map from peer
  to slot either way, and re-keying touches only MatchStart's gate.
- **Never evicting a held seat**, rather than letting the last claim win.
  - A legitimate redial waits until the dead link is noticed.
  - A stolen token cannot push the real player out.
- **Closing the lobby silently at the handoff**, which is the owner's call.
- **Stopping the service before a deploy touches the checkout.**
  - It costs browser downtime for the length of the import.
  - It removes every way a match could boot from a tree its lobby did not boot from.
- **Off on `main` until the release.**
  - It costs a switch, and a path kept alive for a while.
  - It buys a `main` that any session can deploy.
- **Stage (a) before (b).** (a) is testable locally and is most of the code. What (b) adds is
  surviving a lobby crash, and it needs root-level setup on the box.
- **Open: a bound for a match nobody leaves**, such as a player idling on the end panel. The relay
  cannot know when a match is decided, so the bound would be a maximum match length or an idle
  rule. Decide at P5, with the load test.
