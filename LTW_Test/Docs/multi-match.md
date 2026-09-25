# Multi-match: every match in a process of its own (D44)

**Written 2026-09-25.** This is a PLAN, not a record. When a phase lands, move what it built into
`multiplayer.md` and strike it here. Delete the file when the last phase has landed.

The measurements behind every claim here are in
`Findings/2026-09-25-one-server-many-matches.md`. This file repeats none of its numbers, because a
plan outlives the day they were taken.

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
  - Built in two stages:
    - **(a)** match processes as children of the lobby's service, with `OOMPolicy=continue`;
    - **(b)** one systemd unit per match, so that a lobby crash leaves running matches alone.
  - A new client build with a protocol bump is accepted.
  - A started match's lobby **disappears** from the browser.
  - A player whose move to the match process fails **may retry until the load timeout** (D15).
  - The match cap is set **from a load test**, not guessed.
- **D45. A deploy cancels running matches and tells the players**; it never refuses.

Read before touching anything: `../CLAUDE.md` (hard rules and engine traps), then
`multiplayer.md` §1, §2 and §11, then `server.md`.

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

**The relay code does not change.** `LockstepService` and `CommandService` already hold exactly
one match per process, keyed on the roster's `network_id`. A match process runs them as they are,
once the roster carries the ids of the connections it actually has. What changes is:
- who starts the process;
- how a client gets from the lobby to it;
- how the lobby learns what happened.

**It is not the "address change" the old docs called it.** A peer id is chosen by the CLIENT,
afresh on every connection, and every id is public. So the lobby's ids mean nothing to the match
process. The move is an identity transfer:
- a secret per seat;
- a claim on arrival;
- a roster re-keyed before anybody builds a world, because `network_id` is hashed into every
  checksum.

---

## 2. The handoff, step by step

1. **The countdown fires** (D24). The lobby does the following:
   - builds the `MatchSetup` as today;
   - makes one secret token per seat (`Crypto.generate_random_bytes`);
   - picks a free port from the match range;
   - writes a MATCH FILE with the setup, the seat tokens and the load timeout. The file lives in
     its run directory and only its own user may read it;
   - spawns the match process with `--match-server --match-file <f> --port <p> --shutdown-file <s>`.

   *Why a file, not arguments: `Boot` logs its arguments, and a token must never reach the
   journal.*
2. **The match process boots.**
   - It reads the match file, then deletes it.
   - It opens its port and writes a READY file. The lobby polls for it, with a ceiling.

   If the ceiling passes, the lobby kills the process, frees the port, and cancels with a sentence
   to the players still in the lobby. Nobody has left the lobby yet at that point, so nothing is
   stranded.
3. **The lobby announces the match**, through the existing per-peer `receive_match_starting`
   payload. It gains three keys: host, port, and that player's own token. No `@rpc` changes for
   this. At the same moment **the lobby closes itself silently** and leaves the browser list
   (owner's call). Its members are leaving, so there is nobody to send "lobby closed" to.
4. **Each client starts loading and moves at the same time.**
   - It closes its lobby connection without `MatchStart` forgetting the match, dials host:port, and
     authenticates with its token.
   - Authentication should use Godot's `SceneMultiplayer.auth_callback` / `send_auth`, NOT a new
     rpc. A peer is not admitted to the multiplayer layer until the server completes it, so an
     unauthenticated connection can call no rpc at all.
   - The version check (D29/D31) then runs as today, on the new connection.
   - A dial or a claim that fails is retried until the load timeout.
5. **The match process maps each claimed token to its seat** and rewrites that seat's `network_id`
   to the new peer id. `report_ready` counts per SEAT.
   - **D15 is unchanged:** when everybody is ready, or at the timeout, it starts with the seats
     that arrived. A seat never claimed is a player who never loaded.
6. **The go signal carries the FINAL setup, with the new ids**, and the match runs exactly as today.
7. **The match ends** when its last player has gone:
   - the match process writes a RESULT file: summary, players, how it ended, a ready-made match
     record for §9 of `multiplayer.md`;
   - it exits;
   - the lobby reaps it, frees the port, and logs one line.
8. **Leaving** stays as it is: `MatchStart.leave_match()` hangs up. When the lobby browser opens,
   it dials the lobby again (D20).

**Failure paths the design must cover, each with a sentence to the player:**
- **The match process never becomes ready:** cancelled in the lobby (step 2).
- **One player cannot reach the match port, or their token is refused:** retried, then dropped by
  D15.
- **The match process dies mid-match:** the players see the relay-loss handling (§6).
- **The lobby dies:** in stage (a) every match dies with it. In stage (b) they carry on, and the
  restarted lobby must learn which ports are taken (§4).

---

## 3. Security

- **A token is single-use, one per seat, and only ever travels to its own player** over the lobby
  connection. ENet is unencrypted, which is the same exposure as today.
- **The match process refuses an unauthenticated peer before it is admitted**, and also refuses
  all lobby rpcs, because it is not a lobby. With `server_relay` already off, no traffic from one
  match reaches another process's players.
- **The lobby process stays the public door.** Rate limits on the refusal paths that log are open
  work (see the Findings).

---

## 4. Hosting

**Stage (a): children of `ltw-server`.**
- **Spawning:** `OS.create_process(OS.get_executable_path(), …)` with the checkout's path. On Linux
  this forks. The Windows dev loop runs different launch code, so the Linux half is checked on the
  box.
- **Liveness:** `OS.is_process_running(pid)` works for a CHILD, and is also where a finished child
  is reaped.
- **Ports:**
  - a range in `NetworkConfig`, opened once in the box's firewall;
  - opened in the Windows dev rule too, for cross-PC tests;
  - handed out by the lobby and reused as matches end;
  - a port that fails to bind leaves the child alive, logging NOT LISTENING, which is why the
    READY file has a ceiling.
- **Service file:**
  - `OOMPolicy=continue`, so one process running out of memory ends only its own match;
  - the D45 shutdown: `ExecStop` creates the lobby's shutdown file and waits. The lobby then
    creates every child's shutdown file, waits for them (bounded), and quits itself. Each child
    runs `begin_shutdown`: its players are told, then disconnected. Anything still alive is killed
    by the default `KillMode=control-group`, which is the backstop.
- **Journal:** children inherit the lobby's stdout, so their lines appear under the lobby's pid.
  Every relay line must therefore carry its match id. That is open work, and it becomes required
  here.

**Stage (b): a systemd unit per match.**
- **Mechanism:** a template unit started by the lobby, each unit with a memory ceiling. There are
  two ways to allow that:
  - a polkit rule for exactly that unit, which the lobby uses over D-Bus. **Not sudo**: the
    service runs with `NoNewPrivileges=yes`, so none of its processes can ever gain privileges,
    and sudo needs to;
  - or a pool of pre-started units, which needs no runtime permission but costs idle memory.

  Choose when stage (a) has been measured.
- **Liveness:** `is_process_running` does not answer for a process that is not a child: on Unix it
  reports a non-child as NOT running. So stage (b) needs another signal, such as the unit's state
  or a heartbeat file.
- **A restarted lobby** reads the running match units and their run files before it hands out a
  port.

---

## 5. Capacity

- **Memory binds first** under this shape, not CPU. The cap is the number of match processes, set
  from the load test on the box. It is enforced in the lobby with a sentence ("The server is full"),
  below both the port range and ENet's `max_peers`. ENet IGNORES a connection over its cap rather
  than refusing it, so it cannot produce that message.
- **Before sizing it,** find out what the project's own share of a process's boot memory actually
  is (the Findings has the split). A match process needs the relay, not the content, and a slimmer
  boot raises the cap directly.
- **The load test** needs a FAKE CLIENT: one that goes through the real connect, auth and rpc path
  but simulates nothing, run from off the box so it does not steal the CPU being measured. The
  numbers are read from the journal: each match process's `Relay match summary` already carries
  its memory.

---

## 6. Client changes: one build, with a protocol bump

- **`Net`:** a move that swaps the connection without the status change that makes `MatchStart`
  forget the match, and without the loading screen treating it as a lost server.
- **`MatchStart` (client):**
  - keeps the setup across the move;
  - authenticates with its token;
  - retries within the load window;
  - on a cancel before the start, goes to the BROWSER, since its lobby is gone.
- **`MatchLoading`:** rows keyed by SLOT, not by peer id, because the id changes. A line for the
  move ("Connecting to the match…") and for a failure.
- **`Lobby` (client):** nothing survives the handoff. After a match the browser dials the lobby
  as it already does.
- **`protocol_version` is bumped.** An older build does not understand the new payload keys, so it
  would sit in a loading screen the lobby no longer serves; the bump refuses it at the door with
  "update the game".
- **The two client fixes the Findings called for are DONE** (2026-09-25) and need no bump, so
  they can ship in an earlier build than this one:
  - a match ends with a sentence when the server vanishes (crash, out of memory, reboot);
  - the cancel reason stays on screen after the disconnect.

---

## 7. Phases

Each phase is done when its proof has RUN. Check the positive control before believing a green
result (`CLAUDE.md`).

**P0: baseline and live bugs.** DONE 2026-09-25; see the Findings.
- Also done: `deploy_server.ps1` no longer restarts when there is nothing to deploy, says how many
  matches a restart is about to cancel (read from the journal), and can install the D45 drop-in
  (`-InstallShutdown`).
- Also done: the two client fixes in §6.
- Left: running `-InstallShutdown` once, right after the deploy that brings the code for it,
  and handing out the client build that carries the fixes.

**P1: spikes, all small and all thrown away.**
- `SceneMultiplayer` authentication carrying a token, with the D29/D31 handshake after it:
  - **prove** a peer with a wrong token can call no rpc;
  - **prove** a peer with the right one ends up on the right seat.
- A Godot server spawning a Godot server:
  - **prove** READY and exit are seen on Windows;
  - have the owner run the Linux half on the box.
- The port test from testers' networks (owner). The steps are in the session that produced this
  plan and will move into `server.md`.

**P2: the match-process role.**
- `Boot` and `BootConfig` gain `--match-server`.
- The process reads the match file, hosts one match with today's relay code, refuses lobby rpcs,
  writes READY and RESULT, and exits at the end.
- **Prove:** a match process started BY HAND from a hand-written match file plays a full probe
  match.

**P3: the lobby side.**
- Tokens, port allocation, spawn, READY with its ceiling, the announce with host, port and token.
- The lobby closing at the handoff, reaping, the cap and its sentence.
- **Prove:** a spawn that never becomes ready cancels cleanly, and a full server says so.

**P4: the client side** (§6), and the protocol bump.
- **Prove** with `LockstepProbe`, which gains a `--lobby <name>` so two pairs cannot join each
  other's lobby:
  - two, then three matches at once;
  - a desync in one match reaches only its players;
  - a hard kill of one match process leaves the others running;
  - a player whose dial fails retries and gets in;
  - an old build is refused with a sentence.

**P5: stage (a) on the box.**
- `OOMPolicy=continue`, the port range in the firewall, the children's shutdown, match ids on every
  relay line.
- **Prove:**
  - a deploy with two matches running tells both matches' players;
  - killing one child leaves the other running;
  - the load test sets the cap.

**P6: stage (b).**
- Per-match units, the permission, the non-child liveness signal, recovery after a lobby restart.
- **Prove:** stopping the lobby leaves a running match running, and the restarted lobby does not
  reuse its port.

**P7: docs.**
- `multiplayer.md` §2, §5.7 and §11.3;
- `server.md`'s controls and log lines;
- the README's Status section;
- any trap that cost a session, into `CLAUDE.md`;
- then delete this file.

---

## 8. Choices the review should challenge

- **A match file and a READY/RESULT file** rather than a control connection between lobby and
  match process. The files are simple, work the same on Windows, and cannot deadlock the way a
  never-drained stdout pipe does. The cost is polling.
- **Engine authentication** rather than a claim rpc. It admits nobody unverified, and leaves the
  `@rpc` surface alone. It is untested here, and that is what P1 is for.
- **Moving at the START of loading**, not at the go signal. The dial then overlaps the local load,
  and a failure lands inside D15's window, where it already has a rule.
- **Closing the lobby silently at the handoff**, which is the owner's call. The alternative kept it
  listed "In progress", and needed the lobby to hold members that are no longer connected to it.
- **Stage (a) before (b).** (a) is testable locally and is most of the code. What (b) adds is
  surviving a lobby crash, and it needs root-level setup on the box.
