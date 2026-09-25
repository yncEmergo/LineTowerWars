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

**The check pass.** Three more readers (completeness, correctness, the implementer) then went over
the rewrite itself, against the code and the other docs, and their findings are folded in too. The
handoff section lists what they moved. They changed no decision either: what they caught were
places where the rewrite contradicted itself, named a contract without fixing it, or would have
had the next session guess.

---

## Where it stands: the handoff

**Keep this section current.** A session on another machine starts here, and nothing else carries
over: Claude's memory and scratch files stay on the machine that wrote them.

**Last updated 2026-09-25, when the check pass was folded in.**

**Done:**
- The decisions (§0), including the rejoin rule taken after the review.
- P0: the server fixes, the client fixes and the deploy script's new controls.
- P1: the authentication spike, and the Windows half of the spawn spike.
- The review, and this rewrite of the plan around it.
- **The check pass on that rewrite is folded in and its file deleted.** Three readers
  (completeness, correctness, the implementer) went over the rewrite; what they found is in the
  sections below rather than in a list of its own. The shape did not change. What did:
  - a pending token holds its seat, and a release names its peer;
  - the D26 state is `dropped`, so that "held" means one thing;
  - no TOO_LATE after go, because `refuse_new_connections` resets a dial before auth runs;
  - an ORDERED exit, so the D15 and D45 sentences are not cut off by the quit that follows them;
  - the match file, the auth bytes, the RESULT and the exit codes fixed as CONTRACTS in P2,
    because P3 reads and writes against them;
  - the switch named, and the client keyed on the ANNOUNCE rather than on it;
  - everything MatchStart tells "the players" before go found through the seat table;
  - D15's clock started at the announce, and the cap counting a start rather than a spawn.
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
2. **P2**, behind the switch that keeps the handoff off on `main` (§7). It starts with that switch.
3. P3 (gated on the owner's port test), then P4, then P5 (gated on the Linux spawn half), which is
   the release.

**The owner still owes:**
- the port test from testers' networks (§7, P1). It gates P3;
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

**The relay code does not change.** `LockstepService` finds a sender's slot by `network_id`,
reading the roster through `MatchStart.running_setup()`, which is null until the go signal.
(`CommandService` reads a `MatchSession`, which a relay does not have, so on a relay it always
answers 0, and its replication-era endpoint is refused under lockstep.) So a match process runs
them as they are, once the roster carries the ids of the connections it actually has.

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
- writes the MATCH FILE into its run directory. **Its form is a contract between P3, which writes
  it, and P2, whose harness hand-writes it**, so it is fixed here. It is one JSON object,
  `<run dir>/<match id>.match`, written under a temporary name and renamed into place. Its keys:
  - `format`: a number. The child exits with `BAD_MATCH_FILE` on a mismatch;
  - `setup`: `MatchSetup.to_dict()`;
  - `tokens`: the announced slot, as a string, mapped to the token as 32 lowercase hex
    characters. `Crypto.generate_random_bytes` returns a `PackedByteArray`, which does not
    survive a plain JSON round trip as one;
  - `countdown_ends`: Unix seconds from `Time.get_unix_time_from_system()`, which the lobby and
    the child share because they run on one machine. D15's clock runs from then, or from the
    child's own READY if that is later (step 6);
  - `lobby_pid`: logged by the child and nothing more. **A match never acts on its lobby's
    death**, because stage (b) exists for matches to outlive it.

  Every per-match file (match, READY, RESULT, heartbeat, shutdown, log) is named by the match id,
  so no file can be taken for another MATCH's; a respawn of the same match clears the failed
  spawn's files first (step 2).
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
- Spawns are serialised, one child booting at a time, until P5 measures whether the box's cores
  can take more. A boot costs whole CPU-seconds, and every running relay needs its tick on time.
- **A Start pressed while another child is booting still begins its countdown.** Its spawn is
  QUEUED, and is made when the booting child writes READY or is reaped.
- **The cap counts a START from the moment its countdown begins** - queued, booting or running -
  until its child is reaped or its countdown is cancelled. `_start_refusal` checks that count, so
  a queued start holds its place, and "The server is full" is decided at Start rather than after a
  countdown has run. Counting from the spawn instead would let several Starts pressed while one
  child boots all pass the cap, and overshoot it when the queue drains.
- **The READY ceiling counts from the actual spawn, not from the queue**, so a queued child is
  never killed by a ceiling that started before it existed.

### Step 2. The match process boots

In this order:
1. **Boot treats `--match-server` as a dedicated server**, so the godot_ai helper is dropped. The
   log line "Editor helper removed" is the positive control. Today `is_dedicated_server` matches
   `--server` exactly, so without this change a match process would boot as a CLIENT.
2. **It refuses to boot with `lockstep_enabled` off.** The replication comparison runs in a single
   process, as it does today.
3. **It raises its own `/proc/self/oom_score_adj`** to a positive `NetworkConfig` value (Linux
   only) and reads it back (§4). A read-back that differs is an error line and the boot carries
   on, since this is protection rather than a precondition. On Windows the step is skipped
   silently.
4. **It reads the match file, then deletes it, and clears every seat's `network_id`.** Until a
   seat is claimed, it is identified by its token.
5. **It installs `auth_callback` and `auth_timeout`** (a named `NetworkConfig` value) before
   `Net.host()` assigns the peer, next to `server_relay`.
6. **It keeps every rpc autoload, `Lobby` included**, because the D31 hash walks all of them. In
   this role, `Lobby`'s endpoints return at once and log nothing.
7. **It binds its port. A bind that fails exits at once with `PORT_TAKEN`** (step 8, which names
   every exit code). It does not log NOT LISTENING and wait.
8. **A shutdown file already present when it hosts is HONOURED.** It is not deleted as stale: its
   name is minted per match, so it cannot be stale. Today's `_arm_shutdown_file` deletes it, which
   would swallow a D45 request aimed at a child that is still booting.
9. **Only then does it write READY**, with its pid.

**The lobby polls in a fixed order:** READY first, then liveness (`is_process_running`), then the
ceiling.
- A READY seen in the same poll as the ceiling wins.
- A child that has already exited is handled at once. A `PORT_TAKEN` exit is respawned once on the
  next free port; any other exit cancels the start.
- **A respawn first deletes every file the failed spawn left, then writes the match file again**,
  because the first child deleted it on reading (item 4) and both spawns share one match id - so a
  heartbeat or log left by the failed child would otherwise be read as the new child's. The lobby
  accepts only a READY whose pid (item 9) is the child it is waiting for.
- The ceiling is set from P5's boot measurement on the box. It is only the backstop for a hang.

### Step 3. The spawn window

Between the spawn and the announce, the countdown is running and the child is booting. **The whole
window counts as the countdown for D24:**
- A member leaving, the host leaving (D23), the host's Cancel, or a D45 shutdown cancels the start
  as a countdown cancel does today, with the same sentence.
- The child is KILLED. It is never asked to stop through its shutdown file, because it may not be
  listening yet. Its port is freed and its files are deleted.
- If the countdown reaches zero before READY - which serialised spawns make likely whenever two
  lobbies start close together - the room keeps reading "Starting the match...", with the host's
  button still offering Cancel and everyone else's disabled: `is_starting` stays true until the
  announce. The same rules hold until then. Today the room would offer the host an enabled Start
  in that gap. The host's button is NOT simply disabled, because during a countdown that button IS
  the Cancel this rule depends on.
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
  itself if it is still connected when the load window, counted from its own announce, ends. The
  client hangs up to move; this is for a client that does not.
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

The match process keeps a SEAT TABLE, keyed by the ANNOUNCED slot. Each seat holds its token, its
current peer id (0 when it has none), a `ready` flag, and a state:

| state | meaning | leaves it when |
|---|---|---|
| `unclaimed` | never admitted | admitted with its token -> `claimed` |
| `claimed` | admitted; peer id set; the `ready` flag is meaningful | `report_leaving` -> `left`; `peer_disconnected`, or the code's own hang-up -> `dropped`, clearing `ready` and the peer id |
| `dropped` | inside D26's hold | admitted again with its token -> `claimed`, and the next drop starts a fresh hold; the hold runs out -> `left` |
| `left` | out for this match | never |

**The D26 state is `dropped`, not "held".** A seat in the hold MAY be claimed again, which is the
owner's rule, while SEAT_HELD refuses a claim because another connection already holds the seat.
One word for both makes a proof read as the opposite of the decision.

MatchStart's `begin()` is not reused. With every id cleared, it would start at once, because 0 is
at least 0. With the lobby's ids, it would wait for connections that will never come.

- **Checking.** `auth_callback`:
  - refuses a payload over a small fixed size;
  - parses a fixed layout, never with `bytes_to_var`;
  - for a valid token whose seat is `unclaimed` or `dropped` AND has no pending entry, records
    `pending[peer] = seat` and completes auth. **From that moment the seat is TAKEN**: any other
    connection presenting its token gets SEAT_HELD, until that pending entry or the claim that
    follows it is released. Without this the seat still reads `unclaimed` between the check and
    admission, so two connections presenting one token within a round trip both pass and both are
    admitted - which the retry rule in step 5 produces with no attacker at all, whenever a
    client's dial timer fires after the server has already accepted it;
  - answers the first wrong token with WRONG_TOKEN and accepts no further auth message from that
    connection, nor any after its check has passed. One connection claims at most one seat. **It
    does not hang up in the same breath** (see Refusing): the client hangs up on reading the
    status, and `auth_timeout` ends the connection if it does not;
  - **a `peer_connected` for a seat a live peer already holds cannot happen under these rules.** If
    it does, the newcomer is disconnected and counted, and the seat keeps its holder.
- **The auth bytes are a contract, fixed here.** They are what P5's client build and every later
  match process speak, and changing them afterwards costs a bump.
  - The client's message is exactly the 16 token bytes. Any other length is WRONG_TOKEN.
  - A refusal is one byte from an append-only enum declared once, in a script both roles load:
    WRONG_TOKEN, SEAT_HELD, TOO_LATE, SHUTTING_DOWN.
  - Success carries no status: it is `complete_auth`.
  - **Every refusal is decided and sent inside the callback call for that message.** The client
    calls `send_auth` and then `complete_auth` at once (P1's pattern), so once its completion has
    arrived the server's `send_auth` fails. A status sent from a later frame never leaves.
  - In the announce and in the match file, a token travels as 32 hex characters.
- **Claiming.** The pending entry becomes the claim on `peer_connected`, which fires on admission;
  only then is the seat re-keyed and its link stretched (D41), rather than at go.
  - The cost of stretching at the claim is that **a claimed loader that crashes is noticed only
    once the stretched timeout runs out**, past the relay's silence allowance, and D26's hold
    starts then. The others wait longer for that seat than they do today.
- **Never evicting.** A token presented while another live or pending connection holds its seat
  gets SEAT_HELD, and the client retries. Evicting would let anyone who read the token off the
  cleartext wire push the real player out.
- **Releasing, and a release NAMES ITS PEER.** `peer_disconnected`, `peer_authentication_failed`
  and a hang-up by the match process release a seat only when the departing peer is that seat's
  pending or current peer. **The departure of a superseded or refused connection changes
  nothing.** Otherwise an abandoned first connection timing out later would release the seat its
  live successor holds, and drop that seat into D26's hold while its player is connected.
  - A pending entry is not a claim: `peer_authentication_failed` discards one and changes no seat
    state. A peer that passed the check but was never admitted raises only that signal, never
    `peer_disconnected`.
  - A claim ends on `peer_disconnected`, or in the code that calls `multiplayer.disconnect_peer`
    (SceneMultiplayer), which raises neither signal. **A close through ENet** -
    `Net._disconnect_peer`, `peer_disconnect_later` - **still raises `peer_disconnected`, or
    `peer_authentication_failed` for a pending peer, on a later poll**, and the claim is released
    there, once. Releasing in the code as well would release it twice, and read a close the server
    made on purpose as a dropped link.
  - **A seat the server closes on purpose is marked `left` BEFORE the close**, so that signal does
    not put it in the hold.

  After a claim ends:
  - a deliberate leave makes the seat `left` at once (D26);
  - a dropped link puts the seat in `dropped`, D26's hold. **Inside the hold, the token may claim
    the seat again** (the owner's call, 2026-09-25). When the hold runs out, the seat is `left`.
- **Refusing with a reason.** Every refused auth is answered with a status through `send_auth`:
  WRONG_TOKEN, SEAT_HELD, TOO_LATE or SHUTTING_DOWN. **The server does not hang up in the same
  breath**; the client hangs up once it has read the status. This is CLAUDE.md's
  message-before-disconnect trap, reached through auth: in the review's run, a hang-up at once
  lost the reason every time, and waiting delivered it every time. `auth_timeout` is the backstop,
  and a server-side `peer_disconnect_later()` after `send_auth` also delivered it in the one run
  that tried it.
- **TOO_LATE answers a token whose seat is `left`, and a connection still pending at the go
  signal.** It can answer nothing later than that. **From the go signal on `refuse_new_connections`
  is set, and ENet resets every later dial at its own CONNECT event** - before `_add_peer`, before
  the callback, before any auth runs - and sends nothing back. So a player who dials after go gets
  no status at all: their move reads it as silence, retries, and ends with its give-up sentence at
  the load timeout.
  - The alternative, if a late player must be told why, is to NOT set `refuse_new_connections` and
    to answer every auth after go with TOO_LATE, paying the engine ERROR per pending packet that
    §3 already accepts. It is not chosen.

**Readiness is a flag on the SEAT.** It is set by `report_ready` from the seat's current connection,
and cleared when the claim is released. `receive_readiness` carries the SLOTS of the announced
setup, not peer ids, because the clients never saw the new ids.

**Everything MatchStart does to "the players" before go finds them through the SEAT TABLE**, never
through `_expected` or the setup's ids, which a match process does not fill before go. That covers
the D15 abort's sentence, the "You did not finish loading in time." notice at go, the D45 notice
during loading (`_on_shutdown_started`, which today also returns unless `_in_match`),
`_on_peer_left`'s hold, readiness broadcasts, `has_player` and `_slot_of`. Each goes to the seats
claimed at that moment. Reused as it stands, every one of those recipient lists is empty: a D15
abort and a D45 shutdown during loading would reach the players only as a lost connection, which
breaks D45's "tells the players".

**The gate:**
- the match starts EARLY when every seat that is not `left` is claimed and ready, so an
  `unclaimed` or `dropped` seat blocks it;
- otherwise at the D15 timeout, where the go roster is the claimed, ready seats;
- **D15's clock starts at the ANNOUNCE**, which is the later of the countdown's end - the time the
  match file carries - and the moment this process wrote READY. So a slow boot never shortens
  anybody's load window. Counting from the countdown's end alone would silently take every second
  between zero and the announce out of it, and shrink the retry rule by the same amount;
- **the go roster is always built fresh from the claimed, connected, ready seats, renumbered as
  `_roster_of_ready` does**, and is checked against `min_players` on EVERY path, the early one
  included. Below it the match is aborted with D15's sentence. It is never the setup as it stands;
- **at go, every seat outside the go roster becomes `left`**, its hold is discarded, and no
  PLAYER_LEFT is issued, because it never had an area.

A seat that is never claimed is waited for until the load timeout, by the owner's retry rule. That
is longer than today's D26 hold for a crashed loader, because the match process never sees a
connection close.

### Step 7. The go signal

It carries the FINAL setup, with the new ids, and the match runs exactly as today. The client finds
its own seat by `local_slot`, as it already does. Nothing in gameplay compares peer ids.

### Step 8. The end

**The match process exits on EVERY road into `_finish_match`**, and never goes back to listening.

**Exiting is ORDERED, and is never a `quit()` in the frame of the last notice.** Every link still
open is closed with `peer_disconnect_later`; the process waits until they have all closed or
`shutdown_close_seconds` has passed, reusing Net's CLOSING phase; then it writes the RESULT and
quits.
- `_abort` sends `receive_match_cancelled` and calls `_finish_match` in the same call, and
  `_on_shutdown_started` runs synchronously inside `shutdown_started.emit`. So a quit placed in or
  just after `_finish_match` destroys the socket in the frame of the D15 and D45 sentences, and
  CLAUDE.md's message-before-disconnect trap loses them at the receiver - which is exactly the
  silent failure both sentences exist to replace.
- On the D45 road, Net's own shutdown already does the notice, the close and the quit. The match
  role only writes the RESULT before `_finish_shutdown` quits.

| How the match ended | Who writes the RESULT |
|---|---|
| the last player left | the match process |
| a D15 abort, including one where no seat was ever claimed | the match process |
| a D45 shutdown | the match process, from its shutdown handler, before `Net` quits |
| a crash, an out-of-memory kill or a signal | the lobby, from the reaped status in stage (a), or the unit's state in stage (b) |
| the child never became READY | the lobby |
| the lobby killed the child | the lobby, as "killed" |
| the heartbeat went stale | the lobby, as "wedged" |

- **The RESULT is a contract too**, because P2 writes it and P3 reads it. It is one JSON object in
  `<run dir>/<match id>.result`, written under a temporary name and renamed into place. Its keys:
  - `match`;
  - `ended`: one of `all_left`, `aborted` (D15, including one where no seat was ever claimed) or
    `shutdown` (D45); or, written by the lobby, `died`, `never_ready`, `killed` or `wedged`;
  - `seats`: per ANNOUNCED slot - the numbering the match file used, not the go roster's, since a
    D15 short start renumbers - the name, the colour, the go slot (0 if it was not started with),
    and how it went (`left`, `timed_out`, `went_silent`, `never_claimed`, `not_loaded`), each with
    its relay turn, or -1 for a departure before go, when no turn exists;
  - `started` and `ended_at` in Unix seconds, `started` being 0 for a match that never began;
  - `desync_tick`, or null;
  - the refusal and stranger counters.

  **It carries NO winner.** Under lockstep no server process computes the outcome, so the claim in
  `multiplayer.md` §9 that "the server already computes the outcome" is no longer true. A trusted
  result would need the turn log replayed on a server, or the clients' reports cross-checked.
- The writer copies the roster before `_finish_match` clears it, and reuses the summary dictionary
  LockstepService already builds.
- **A clean end is proven by the RESULT file, never by the exit code.**
  - **The exit codes are named constants in one script both roles read**, each with one meaning:
    - `0`: ended normally, and a RESULT exists;
    - `PORT_TAKEN`: the bind failed (step 2). The lobby respawns once on the next free port and
      writes the match file again from its own copy, because the first child deleted it;
    - `BAD_MATCH_FILE`: the match file was missing, unreadable, or of another `format`;
    - `LOCKSTEP_OFF`: refused to boot with `lockstep_enabled` off.
  - **The lobby acts on `PORT_TAKEN` alone.** Any other code, and any exit with no RESULT, is
    logged as "died" with the code.
  - A death by signal reads as the raw wait status, which without a core dump is the signal number
    itself, and Linux signals run up to SIGRTMAX at 64. **So the match role's own codes lie between
    65 and 126.**
- Every link the match process has told it is out is closed with `peer_disconnect_later`.
- **The lobby reaps the child, frees the port, reads the RESULT only once the child has exited,
  adds `exit_code`, and logs it as one `Match result` journal line carrying the match id.** That is
  the RESULT line §4 says tools read with `-o cat`; for a child that left no RESULT, the lobby
  writes the line itself. **The line is what tools read, and nothing keeps the file.** The lobby
  then deletes the match, READY, RESULT, heartbeat and shutdown files, and logs one line with the
  match id and the number of matches still running.
  - **It KEEPS the most recent match LOGS** rather than deleting them with the rest. On Windows the
    log is a child's only output, and is what the dev loop and every P2-P4 proof read (§4):
    deleting it at reap would take it away before the harness could check its positive control.
- **A match nobody leaves** holds a cap slot until its players go; a player sitting on the end panel
  keeps sending `submit_alive`, so the relay's silence check (D35) never drops them. Today that
  blocks the whole server; after D44 it holds one slot. A bound for it is open (§8).

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
  - it sets `refuse_new_connections` from the go signal, which ENet honours at its own CONNECT
    event, before any auth runs, so a dial after go is never told why (step 6);
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
  - there is a per-source limit on children loading or running, **counted by the HOST's address**:
    the children for lobbies that address hosted. It is checked at Start, with a sentence, and the
    limit is a `NetworkConfig` value. Players behind one NAT share it, which is accepted;
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
  seconds **from its main loop, from READY on**, and the lobby kills and reaps a child whose
  heartbeat is stale, logging "wedged" and writing its RESULT line. The same file is stage (b)'s
  liveness signal.
  - **The lobby judges staleness only after READY.** The boot is synchronous and writes no
    heartbeat, so judging from the spawn would kill slow but healthy boots and overlap the READY
    ceiling, which is the only bound before READY.
  - The period and the staleness bound are named `NetworkConfig` values, the bound several periods
    long.
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
  3. creates the shutdown file of every announced child **at the START of its own NOTICE phase**,
     so the children's notices and closes run alongside its own rather than after them - which is
     what the `TimeoutStopSec` sum below assumes;
  4. quits, but not until every child it told has been reaped or the bound has passed:
     `_finish_shutdown` waits on the supervisor. Net's shutdown on its own quits as soon as the
     LOBBY's links have closed or `shutdown_close_seconds` has passed, and waits for no child. The
     bound is a named `NetworkConfig` value, checked against `TimeoutStopSec` in P5.

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
    - **Its units are TRANSIENT and named `ltw-match-<port>`**, so the generic bullets below do not
      apply to it as written: the naming, `is-active` and `list-units` lines take `systemctl
      --user` and that name, the D45 stop needs `-p ExecStop=` on the `systemd-run` line because a
      transient unit has none otherwise, and its logs are read by `_SYSTEMD_USER_UNIT`, never by
      `-u ltw-match@*`.
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
  - The cap counts a START from the moment its countdown begins - queued, booting or running -
    until its child is reaped or its countdown is cancelled (step 1).
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
    as the drop in `MemAvailable` as N goes from 0 upward, **minus a margin for the lobby's own
    growth**. That is the marginal cost of a match. VmRSS counts the shared binary pages in every
    process, so it overstates the cost. A debug hold stops the processes from exiting at the load
    timeout;
  - **the summary line gains `VmHWM` (the peak) and `RssAnon`**, so a match's own growth is
    visible. The summary is written only at match END, so the harness ALSO samples each child's
    `/proc/<pid>/status` during the run: a match killed for memory is the case the cap exists for,
    and it is the one that leaves no summary;
  - **boot-to-READY time**, idle and with others booting at once. It sets the READY ceiling;
  - **the worst tick of a running match while others boot.** It says whether spawns must stay
    serialised;
  - **CPU and traffic** from a few real probe matches;
  - **a fake client**, only if those disagree with the Findings. It goes through the real connect,
    auth and rpc path but simulates nothing, and runs from off the box;
  - **a run whose journal shows "Suppressed N messages" is a failed run.**

---

## 6. Client changes: one build, with a protocol bump

- **Every client change here is keyed on the ANNOUNCE, never on the switch.** The switch (§7) gates
  the LOBBY only, and this code lands on `main` while it is off. So a client takes the move path
  only when `receive_match_starting` carries a port and a token. Without them - the in-process
  path, which stays on `main` until P7 - it behaves exactly as today: it does not move, it reads
  `receive_readiness` as peer ids, and after a cancel it returns to the lobby room still
  connected.
  - A client built from `main` at any point before P5 therefore plays against today's server
    unchanged, and so do the builds already handed out.
  - Keyed on the switch instead, all three would be wrong against the in-process path: no port or
    token is announced, readiness still carries peer ids, and a cancel comes from the lobby
    itself. **A client that hangs up there leaves its lobby** - `Lobby._on_peer_left` ->
    `_remove_from_lobby`, which closes the whole lobby if that client was the host - so a D15 abort
    would dissolve lobbies for everybody on that build.
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
    - **It ends as ADMITTED at `connected_to_server`**, and the client stretches its own link then
      (D41), as the match process does at the claim.
    - `move_to` **collapses the candidate list to `current_address()`**, so a retry dials that one
      address and never walks on to the lobby's other candidates. It sets `auth_timeout` from the
      same `NetworkConfig` value as the match process.
    - **Until the go signal, a `refuse_protocol_version` on the match connection still belongs to
      the move.** It ends it as REFUSED with the build sentence, is never retried, and the setup is
      kept until that sentence is on screen. Today that refusal tears down to OFFLINE and
      MatchStart drops the setup before any sentence is shown, which is what P4 has to prove it no
      longer does.
    - **The client gives up at its announce time plus the load timeout.** The retry interval is a
      named `NetworkConfig` value.
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
    that carries slots (step 6) - **but only on a connection the client moved to.** On the
    in-process path readiness still carries peer ids and is read as it is today, so a build from
    `main` draws the right rows against a server with the switch off;
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
- So until P5 the handoff is OFF. **The switch is `NetworkConfig.match_processes_enabled`**, false
  in the shipped `.tres`, and it keeps the lobby on today's in-process path. `--match-processes` on
  the LOBBY's command line turns it on for that process, read through `CommandLineUtil` as `--port`
  is, and that is what the P2-P4 proofs use. `run_server.ps1` gains a parameter for it, and
  `server.md` names the control. **Only the lobby reads it**; a match process is its own role.
- The server logs the switch at boot.
- With it off, nothing an existing build can observe changes: the announce carries no port and no
  token, and `receive_readiness` still carries peer ids. **The client side is keyed on the ANNOUNCE
  rather than on the switch** (§6), which is what keeps a build from `main` working against a
  server that has it off.
- The protocol bump lands in the same commit that turns the switch on, at the release (P5). So a
  deploy before then changes nothing for multi-match.
- **That last sentence holds only while P2-P4 add, rename or re-arity no `@rpc` and add nothing to
  `wire_config()`.** D31's rpc hash and the wire check are compared on every connection and are NOT
  behind the switch, so a change to either refuses every tester with "The server is running
  different code" at the next deploy of `main`, switch or no switch. §3 already anticipates one ("A
  new endpoint goes on another autoload"); a change of that kind that cannot wait lands with the
  bump, in P5's window.
- The in-process path is deleted in P7, and the switch with it.

**Gates.**
- **P3 does not start before the owner's port test** has run from the testers' networks. If a
  tester cannot reach the match range, stop and bring the owner the choice: a forwarder on the
  public port, which changes the lobby side and the client's dial, or D44's rejected in-process
  relay, which changes everything from P2 on. **P2 may go first either way**, because a forwarder
  needs match processes too.
- **P5 does not start before the Linux half of the spawn spike** has run on the box. P3 may land
  before it only because the switch keeps it off; if the Linux run contradicts §4 (the fork, the
  cgroup, `OS.kill`), P3 is revised before P5.

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
- **The port test from testers' networks: the owner's, not run yet. It gates P3.**
  - The box's only firewall is ufw (no Hetzner firewall), so opening a test port is one
    `ufw allow <port>/udp`.
  - A second server for the test can run as a transient unit:
    ```
    systemd-run --unit=ltw-porttest --uid=ltw --gid=ltw \
      /opt/godot/godot --headless --path /srv/ltw/LTW_Test --log-file /tmp/ltw-porttest.log \
      -- --server --port <port>
    ```

    `--log-file` is not optional: the test server runs as `ltw`, so it shares the live lobby's
    user:// directory, and without it its boot rotates and truncates the lobby's own `godot.log`.
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
  - the exit on a failed bind;
  - the match role's own `max_peers` (§3);
  - **the four contracts P3 then reads and writes against**: the match file, the auth bytes, the
    RESULT and the exit codes (steps 1, 6 and 8). They are settled here, before P3 is written.
- LockstepProbe gains a role that reads its setup and token from a hand-written match file, dials
  the match port with its token, and reports ready. P4's client reuses its auth helper.
  - **The harness writes TWO copies of the match file**: one for the match process, which deletes
    it at boot, and one the probes read - otherwise a probe started afterwards finds nothing. Each
    probe takes `--match-port <p> --match-file <copy> --slot <n>` and reads its token from its
    slot's entry.
  - It gains `--redial-after <s>`, which closes the link with no goodbye and dials again with the
    same token, and prints `claims=<n>`.
- The boot-memory attribution (§5).
- The code comments in Lockstep and Net that cite D19 as current are updated here, and so is
  `NetworkService.rpc_signature`'s account of rpc numbering: it still says Godot addresses an rpc
  by its INDEX in the method list, so that one method added anywhere shifts every later one. D31's
  corrected row says it is the position in the name-sorted list of THAT node's rpcs, and §3's
  frozen-handshake rule depends on the corrected reading.
- The comment on `MenuConfig.disconnect_grace_seconds` ("This is NOT a reconnect window - out is
  out") gains the loading-phase exception, in the commit that builds the re-claim.
- **Prove**, each by a line that must be PRESENT:
  - a match process started BY HAND from a hand-written match file plays a full probe match. Each
    probe prints its slot, its own connection id, and the `network_id` the go signal gave that
    slot. Equal ids prove the re-key ran;
  - "Editor helper removed" appears in the child's log;
  - a seat that reports ready and then drops before go is not in the go roster, and the start waits
    for the rest. A seat that drops before it is ready gets no area;
  - a claimed seat that drops can claim again inside D26's hold, and cannot after it. **The
    positive control is `claims=2`** together with the go signal carrying that slot's NEW id; the
    late case must read TOO_LATE;
  - a token presented while another live or pending connection holds its seat gets SEAT_HELD;
  - **two connections presenting one token within a round trip**: one is admitted, the other reads
    SEAT_HELD, and the abandoned one timing out later does NOT release the seat;
  - a connection whose peer id equals another seat's lobby-era id claims only its own seat. The
    probe for it is a raw `ENetConnection` whose connect data is the chosen id, since ENet takes
    that as the peer id, sending the auth bytes by hand;
  - a wrong token gets WRONG_TOKEN and a token for a `left` seat gets TOO_LATE, and the client
    reads both; **a dial AFTER the go signal is never admitted at all**, and the probe prints a
    rising `dial_attempts` and ends with its give-up sentence;
  - **a D15 abort, and a shutdown file created during loading, each reach every claimed seat with
    its own sentence**, read from the probe's screen line, and the process exits only once they
    have been delivered;
  - a match process with no seat claimed exits at the load timeout and writes a RESULT;
  - a taken port exits with `PORT_TAKEN`;
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
  - serialised spawns, and the queue behind them;
  - reaping, killed children, and the stale-heartbeat kill logged as "wedged" (§4);
  - the `Match result` line, and the match logs that are KEPT at reap (step 8);
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
  - **a client built from this code plays a probe match AND takes a D15 abort against a server
    with the switch OFF**, through today's in-process path: it neither moves, nor mis-draws its
    loading rows, nor leaves its lobby;
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
  3. **Measure BEFORE the release**, so that the cap and the READY ceiling are set from the load
     test rather than guessed (§0). Start a second server as a transient unit with the switch on,
     on a port outside the public one, as P1's port test does, giving it the drop-in's settings as
     `-p` properties and its own `--log-file`:

     ```
     systemd-run --unit=ltw-mmtest --uid=ltw --gid=ltw \
       -p OOMPolicy=continue -p RuntimeDirectory=ltw-mmtest -p RuntimeDirectoryMode=0700 \
       /opt/godot/godot --headless --path /srv/ltw/LTW_Test --log-file /tmp/ltw-mmtest.log \
       -- --server --match-processes --port <p> --shutdown-file /run/ltw-mmtest/shutdown
     ```

     Run the load test and the probe matches against it. Set the cap and the READY ceiling in the
     `.tres` from what they show, then stop the unit.
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
  - **a pending peer flooding one match's port for a whole rate-limit interval does not remove
    another match's summary line, or the lobby's spawn lines, from the journal.** §4 sets those
    values deliberately, and a load test with no flood in it never tests them;
  - the lobby's D45 bound, the children's notices and both sets of closes fit inside
    `TimeoutStopSec`;
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
  - §8, whose "Until it lands, one process does both (D19)" line goes. It is in §8, not in §11.1
    as an earlier draft of this plan said;
  - §11.1, whose "A grace period is not a reconnect" bullet gains the loading-phase re-claim (D44);
  - §13's row;
  - §9, which must say that under lockstep no server computes a winner;
  - D30's row, whose "(D19)" becomes D45;
  - D41's row: in a match process the stretch starts at the CLAIM, not at go;
  - D44's row;
- `server.md`: the controls, the log lines, the firewall line, and the passages that describe one
  match at a time;
- the README's Status section;
- any trap that cost a session, into `CLAUDE.md`;
- delete the in-process single-match path that the switch kept alive, and the switch itself with
  its boot log line;
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
- **Never evicting a seat a live connection holds**, rather than letting the last claim win.
  - A legitimate redial waits until the dead link is noticed. With the link stretched at the claim
    (D41), that means the STRETCHED timeout, past the relay's silence allowance, not ENet's
    default. So a re-claim inside D26's hold becomes possible only after it, and a link that breaks
    late in loading reaches D15 first. **The load timeout has to stay well above the stretched link
    timeout plus the hold** for the re-claim rule to mean anything.
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
