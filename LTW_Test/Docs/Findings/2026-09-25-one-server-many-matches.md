# One server, many matches: what each shape costs, and nine bugs found on the way

**2026-09-25.** Asked: the server runs one match at a time. How could that limit be lifted, what
would each way of doing it cost, and what would it break? Two shapes were weighed:

- **A:** every match in the one relay process.
- **B:** a process per match.

The owner chose B for independence between matches (D44 in `multiplayer.md`; the plan is
`multi-match.md`). This file records the investigation behind that choice, the bugs it turned up,
and the first fixes, which landed the same day.

## How it was measured

- **A multi-agent review.**
  - Four investigators, one per question: moving clients between processes, hosting and cost,
    what one match can do to another in a shared process, and future work plus deploys.
  - Each was followed by a skeptic that re-read the cited code and re-ran what it could.
  - A critic then read across all four.
  - Every claim below is the skeptics' corrected version, not the first draft.
- **Throwaway Godot projects in the session scratchpad**, never in the repo:
  - ENet probes: peer ids, reconnect cost, delivery around a disconnect, relay forwarding.
  - An error-containment project.
  - A copy of the godot_ai logger.
  - Boot and memory of a headless server.
  - A timer around one scene load.
- **The kept `LockstepProbe`, driven by a scratchpad runner**:
  - A relay and two probe clients, headless, on loopback.
  - The same nine scenarios before and after the fixes, three or four at once on separate ports.
  - A clean copy of HEAD standing in for a tester's build against the fixed relay.
- **Machine:** the office dev PC (Ryzen 7 5800X, Windows 11), Godot 4.7.1 editor binary.
  **Nothing was measured on the rented box**, because SSH is blocked from the agent. Every server
  figure below is either playtest 8's, or labelled as the dev PC's. The box's cores are slower.

## What a relay match costs (option A)

- **Memory per match is small.** A match's relay state is bounded by counts:
  - 440 turns of seal history;
  - a 420-turn checksum window;
  - per-peer tables.

  With honest clients that is tens of kB. *[code]*
- **CPU per match could not be told apart from the idle loop.** A 2-player match measured 3.9% of a
  core against 3.4% idle on the dev PC. Playtest 8 found the same on the box. *[measured]*
- **The per-tick fan-out stays small at any realistic size.** One `rpc_id` costs 15–23 µs, flat from
  8 peers to 400. At 400 peers the whole fan-out came to 13.9 ms of a 50 ms tick on the dev PC.
  *[measured]*
- **The first ceiling is `max_peers`, not CPU.** It caps connections for the whole process, lobby
  browsers included. ENet does not refuse a connection over the cap, it ignores it. The client then
  waits out its timeout and reports that the server did not answer. *[measured]*
- **The engine already contains script errors.** *[measured]*
  - A runtime error stops only the function it happens in, and the caller carries on with the
    return type's default.
  - Other signal handlers, later rpcs and neighbouring `_physics_process` nodes all keep running.
  - The one exception: an error written directly in a loop BODY ends the whole enclosing function.
  - A stack overflow survives, at a cost of about 0.9 s of stall, mostly printing, on Windows.

## What a process per match costs (option B)

- **Boot.** A headless server reaches "Listening" in 1.63–1.76 s on the dev PC, almost all of it
  CPU (1.55–1.64 CPU-s), so it will be slower on the box. That has not been measured there. The bare
  engine boots in 0.12–0.14 s. *[measured]*
- **Memory.** *[measured; the attribution inferred]*
  - About 202 MB private at boot.
  - 42–54 MB more when the match scene opens (+70 MB at box level in playtest 8).
  - The bare engine is 40 MB, so about 160 MB of every process is this project's scripts, autoloads
    and addons.
  - D16's own mitigation, a stripped server export, would not reach that 160 MB. It also does not
    apply as deployed: the server runs a checkout.
- **Capacity.** On the 3.8 GB box, with playtest 8's 3.1 GB free:
  - about 8–9 match processes with a safety margin;
  - 11–12 if a match process skips the match scene. *[derived]*
- **Moving a player to another process is not an "address change", it is an identity transfer.**
  *[measured]*
  - A peer id is chosen by the CLIENT at random on every connection. Even re-dialling the same
    server gives a new one.
  - Every id is public, because the lobby list carries it.
  - So the roster has to be re-keyed on arrival, which needs a secret token per seat.
  - The move itself is cheap: 26.7 ms on loopback.
- **systemd.** The unit's likely defaults are `KillMode=control-group`, `ExitType=main` and
  `OOMPolicy=stop`. Under those, child processes die with the lobby, with any restart, and with an
  out-of-memory kill of ANY one of them. Real isolation needs `OOMPolicy=continue` at least, and one
  unit per match to survive a lobby crash. The unit file is not in the repo, so its real settings
  are unknown. *[documented defaults; the unit unread]*

## Read on the box, the same day

The owner ran `deploy_server.ps1 -Facts`, which only reads. What it showed:

- **The service.**
  - `ltw-server` runs as `ltw`, with `Restart=always` and `NoNewPrivileges=yes`.
  - It has no `ExecStop`.
  - Nothing is set for `KillMode`, `OOMPolicy` or the stop timeout, so systemd's defaults apply:
    `KillMode=control-group`, `OOMPolicy=stop`, and a 90 s stop timeout.
  - `NoNewPrivileges` means a process of this service can never use `sudo`. A lobby that starts
    per-match units (B's second stage) has to go through polkit, or use pre-started units.
- **The machine.**
  - Ubuntu 26.04.1 with systemd 259.
  - 2 cores and 3.8 GB, 3.06 GB available at the time, no swap.
- **Godot on the box is 4.7.2**, where the dev PC is on 4.7.1. That doesn't matter for a relay
  that simulates nothing, but everything measured on the dev PC's engine should be re-checked on
  the box's.
- **Firewall.** The box's own firewall (ufw) is on, and lets in only SSH and UDP 7777. There is
  no firewall at Hetzner's side (the owner checked the console).
- **UDP ports.** 7777 is taken by the game. The only others in use belong to system services,
  Tailscale among them, so a range just above 7777 is free.
- **Match summaries**, from before the fixes, when the relay still opened the match scene:
  - Two 2-player matches, one of 26 s and one of 8 minutes.
  - Whole-process CPU of about 4.2% of one core.
  - 283 MB resident, 187 MB static.
  - Worst tick 58–72 ms, no late ticks.
  - About 3 kB/s sent.
  - This is the first per-match reading from the target. The figure B needs next is the same
    line from a relay that opens no match scene.

## What a deploy did to a running match

- **It froze the match for good.** Godot on Linux installs no SIGTERM handler, so
  `systemctl restart` ended the relay mid-sentence. Measured with a hard kill standing in for the
  signal, on Windows loopback:
  - both clients stalled at once;
  - they noticed the server was gone only 16.4 s and 20.5 s later;
  - they then sat on "Waiting for the server" until the player pressed Leave.
- **Closing cleanly without a word was worse.** Both clients went offline, and each played on
  alone: units rose from 88 to 151, a creep kept walking, and lives kept climbing.
  - The cause: under lockstep, `is_authority()` reads a static set at match start, so going offline
    changes nothing.
  - `multiplayer.md` §11.1 blamed the replication-era formula for this. That note is older than
    lockstep. *[measured]*
- **`MatchStart.receive_match_cancelled`, sent mid-match, takes a client out of the match at once**
  and shows the reason. The reason stays on screen only until the connection closes; after that the
  browser's reconnect message replaces it. *[measured]*

## What loses a message sent just before a disconnect

CLAUDE.md's trap said a queued rpc is only flushed at the end of the frame. On 4.7.1 that is not
what happens:
- `ENetMultiplayerPeer` flushes after every packet. An `rpc_id` arrived 1–4 ms after the call while
  the sender blocked for 1.2 s.
- The loss is at the RECEIVER: when a disconnect arrives in the same receive pass, ENet resets that
  peer's queues and throws away what came in with it.

Delivery of a notice followed by each way of closing (Windows loopback, 64 B and 20 kB):

| Then | Delivered |
| --- | --- |
| `peer_disconnect_later()` | 4 of 4 |
| `peer_disconnect()`, which goes out a frame later | 2 of 2 |
| `disconnect_peer(id, true)` | 1 of 4 |
| `disconnect_peer(id, false)` | 0 of 2 |
| `host.flush()`, then `disconnect_peer(id, true)` | 0 of 2 |

So flushing first does not help. Waiting helps, and `peer_disconnect_later()` helps most: it only
disconnects once everything sent has been acknowledged.

## Bugs found along the way, all live before this change

1. **The godot_ai runtime helper ran on the production relay and kept every log line for the life of
   the process.**
   - The measured retention: about 1 kB per ordinary line, 5.8 kB per script error, and 4.25 kB per
     rpc the engine refused.
   - It only drains while a debugger is attached, which never happens under systemd.
   - Any connected peer could grow it by sending rpcs the engine refuses.
   - The addon puts its autoload back into `project.godot` whenever the editor runs, so deleting the
     line would not have stuck.
2. **The lobby lost its configs for the length of every match.** The relay swapped its entry scene
   for the match scene, and `References` follows the current scene. So during any match:
   - colour picks were refused with "That is not a color.";
   - lobby sizes went uncapped;
   - settings were sanitised with no limits. *[code]*
3. **Every match opened with its players stalled about a second at turn 0.** After the go signal had
   already left, the relay loaded `server_match.tscn` synchronously on its one thread: 1.06–1.22 s
   cold on the dev PC. *[measured]*
4. **`server_relay` was on.** Any connected client, a lobby browser included, could push reliable
   traffic through the relay onto every other peer's connection. That is the channel the seals ride.
   *[measured]*
5. **The replication-era `Commands.submit_command` was still served under lockstep.** A modified
   match member could make the relay apply a pause to its own match objects. *[code]*
6. **Orders had a count cap but no size cap.** Every accepted order is kept for the whole give-up
   window, and the flood warning was logged once per seal per flooder. *[code]*
7. **The lobby list went to every connected peer, players in a match included**, on the channel
   their seals use: about 1.1 kB per 4-player lobby, on every lobby change anywhere. *[measured size]*
8. **`ServerMain`'s log view cost 12–13 ms per connect or disconnect** once it held 500 lines, on a
   headless server with no window to show it in. *[measured, dev PC]*
9. **Match ids restarted at `match-1` on every boot.** *[code]*

## What was changed

All of it is server-side, and the `@rpc` surface is byte-identical: the 35 declarations were
diffed. So testers' current builds keep connecting.

| Change | Fixes |
| --- | --- |
| The lockstep relay opens no match scene. The roster comes from `MatchStart.running_setup()`, and `MatchSession.begin_relay()` sets the one flag a session used to set. | 2, 3, and the route in 5 |
| `Boot` frees the godot_ai helper on the server role. Its own `_exit_tree` detaches the logger. | 1 |
| `server_relay` is off on the server. | 4 |
| `submit_command` is refused under lockstep, before anything is logged. | 5 |
| A per-player byte budget per seal (`max_pending_order_bytes`), and the flood warning is logged once per player per match. | 6 |
| The lobby list goes only to peers not in a match. | 7 |
| No log view when headless. | 8 |
| Match ids carry the boot's clock. | 9 |
| A clean shutdown: `--shutdown-file` names a file whose appearance makes the relay cancel every match with the reason, wait `shutdown_notice_seconds`, close every connection with `peer_disconnect_later()` and quit. | the deploy freeze |

**The shutdown only works once the server's service file creates that file on stop**, and that edit
has not been made yet (see Still open).

Before and after, the same scenarios on the same runner:

| Scenario | Before | After |
| --- | --- | --- |
| Plain 1v1 | 1.11 s stall at turn 0 | 0.06 s; 522 turns, 0 desyncs |
| Third peer browsing mid-match | 1.28–1.33 s | 0.11 s; match unaffected |
| Forged checksums from a browser | no desync | no desync |
| Planted desync | caught on both peers | caught on both peers |
| One peer hitching 900 ms every 3 s | healthy peer held 1.78 s | healthy peer held 0.11 s |
| Hard kill | survivor saw the drop | same |
| Wedged peer | relay dropped it, survivor saw it | same |
| 15% seal loss | 71 recovered by the echo | 72 |
| Pause | both peers stopped on turn 312 and resumed on 512 | both on 328 and 528 |
| Second match on the same relay | not run | both matches agree and seal |
| HEAD clients against the fixed relay | not run | play and agree; a hard kill's drop still reaches the survivor |
| Shutdown asked for mid-match | not run | both clients "Match cancelled", neither plays on; relay exits by itself 4.2 s later |

### The client half, added the same day

The client needs no protocol change for either of these, so older builds keep connecting:

- **A match on screen ends when the server goes away.** `MatchStart._on_server_lost` takes the
  client to the lobby browser with "The connection to the server was lost. The match has ended."
- **The browser keeps a notice above its connection status until the player acts.** Before, it
  wrote the notice into the same line it immediately overwrote with "Connecting…". A lobby room
  closed by a lost connection passes on the reason it arrived with, rather than "Lost connection
  to the server".

Measured with the same runner, the probe now reporting which scene each client ended on and
what its status line said:

| Scenario | Both clients |
| --- | --- |
| Shutdown asked for mid-match | "Match cancelled"; browser status still reads "The server is restarting. The match was cancelled." after dialling again |
| Relay hard-killed mid-match | Stalled, told 13.3 s and 14.9 s after their last turn - the link's stretched timeout - then the browser with the lost-server sentence; no units left |
| Relay closed cleanly with no notice (`--quit-after`) | Told within milliseconds; browser with the same sentence; no units left, so no private game |
| Plain 1v1, for regressions | 526 turns, 0 desyncs |

### Two spikes for B, the same evening

These were throwaway projects in the session scratchpad, on the dev PC. `multi-match.md` P1 has
what they mean for the plan.

**`SceneMultiplayer` authentication carrying a seat token.** One server with `auth_timeout` 3 s,
and four clients:

| Client | Server | Its rpc |
| --- | --- | --- |
| right token | admitted (`peer_connected` only after `complete_auth`) | ran |
| wrong token | hung up at once | never ran |
| never authenticates | dropped at the timeout | never ran - though `rpc_id` returned OK on the client |
| right token, after the timeout | dropped; the late `send_auth` returned an error | never ran |

**A Godot process launching a Godot process.** A headless "lobby" started a headless "match"
with `OS.create_process`:
- the match's READY file appeared after 111 ms;
- its exit, with its exit code of 7, was read 2.2 s after launch;
- nothing was left running afterwards.

The 111 ms is a two-script project. The real server boots in about 1.6 s here, and the box will
be slower.

## What the plan's review found, the same night

The plan for B (`multi-match.md`) was reviewed from six angles, each finding checked by a second
pass that tried to refute it. None was refuted outright: some were judged plausible rather than
confirmed, several were corrected in part, and the second pass found a few the first had missed.
The engine and systemd facts below were found along the way. Each one is either measured on 4.7.1
(Windows, headless, in throwaway projects), or read from source: Godot's master branch for most
engine files (4.7 where a copy was saved), which can differ from 4.7.1 in detail, and systemd's man
pages and source. The Linux process facts were read, not run. What the plan does about each is in
the plan.

**A live bug in today's single process** (read from the code):
- MatchStart's loading gate compares COUNTS: `_ready_ids.size() >= _expected.size()`.
- `_drop_peer` prunes `_expected` and never `_ready_ids`.
- Take a player who reports ready and then drops. After D26's hold, the count passes while
  another player is still loading, and `_start_match(_setup)` starts the whole setup, the dropped
  player included.
- A player dropped BEFORE reporting ready is started with too, which breaks D15.
- The relay's silence check removes that player later. So the area exists for a while rather than
  for the whole match, but it should never have existed.

**Boot:** `is_dedicated_server` matches `--server` exactly, or `--server=`. A process started with
`--match-server` alone would take the CLIENT branch and keep the godot_ai helper.

**Authentication** (measured, then read in `scene_multiplayer.cpp`):
- The callback runs for EVERY auth message from a peer that is still pending, including after the
  server has already called `complete_auth`. One peer drove it 2001 times in one run.
- `peer_connected` and `connected_to_server` fire only when BOTH ends have completed.
- A peer that passed the server's check but left before completing its own side raises only
  `peer_authentication_failed` on the server, never `peer_disconnected`.
- `SceneMultiplayer.disconnect_peer` blocks signals around its own removal, so code that hangs up
  that way must clean up after itself. A close through ENet (`ENetMultiplayerPeer.disconnect_peer`,
  `peer_disconnect_later`) still raises the signals, on a later poll.
- A refusal sent with `send_auth`:
  - followed at once by `disconnect_peer`, arrived 0 times in 6;
  - with the CLIENT hanging up after reading it, arrived 6 times in 6;
  - followed by `peer_disconnect_later()` on the server, arrived in the one run that tried it.
  It is the message-before-disconnect trap again, reached through auth.
- Every non-auth packet from a pending peer prints an engine ERROR (`ERR_CONTINUE`). A flood with
  no token produced 11,475 such lines in about 10 s, and ran 0 of 66,150 rpcs. The legitimate
  client's rpc ran (the positive control).
- A client that still has `auth_callback` set, dialling a server without one, fails at
  `auth_timeout`, with engine errors on both ends. The one SceneMultiplayer is reused for every
  connection, and nothing clears the callback.

**rpc numbering** (measured, two throwaway builds):
- Godot addresses an rpc by its position in the NAME-SORTED list of that node's rpcs.
- When `Net` gained an rpc that sorts before `state_protocol_version`, an old client's handshake
  landed on `refuse_protocol_version`. When the new name sorted after it, the old client got its
  sentence as before.
- So `Net`'s handshake rpcs are frozen, and D31's row is corrected to say "position in the
  name-sorted list".

**ENet** (measured, then read in `thirdparty/enet`):
- A half-open CONNECT, one that is never answered, holds a slot until ENet's maximum timeout,
  before any auth runs. A legitimate client got into a full server only at 31.66 s.
- A CONNECT over `max_peers` is ignored, with no reply.
- ENet binds without `SO_REUSEADDR`, so a taken port fails to bind.
- ENet carries every peer of one socket over one UDP flow, so a firewall limit that counts
  connections (connlimit) counts one.

**Processes** (Windows measured; Linux read in `os_unix.cpp`):
- On Linux, `create_process` is fork, then `setsid()`, then `execvp`. A failed exec returns OK to
  the parent, and the child dies with raw status 9.
- Godot sets FD_CLOEXEC on every socket and file, so a child never holds the lobby's port.
- On Windows, a child made by `create_process` has no console and inherits no handles. Nothing it
  prints reached the parent's streams.
- Every process of the project writes `user://logs/godot.log`, and each boot rotates it and
  truncates it. A child's boot took over the parent's file mid-run. `--log-file` avoids it.
- `OS.kill` on Linux is SIGKILL followed by a blocking `waitpid`, and it never updates Godot's
  process table. A later `is_process_running` on that pid prints "not a child" and returns false,
  and `get_process_exit_code` returns 0. Windows answers -1 instead.
- A death by signal reads as the raw wait status: 9 for SIGKILL, 6 or 134 for an abort. An
  ordinary `quit(9)` reads the same as SIGKILL.
- `is_process_running` on a pid that is not a child prints an engine error on every call.

**systemd** (read in the man pages and the source):
- `OOMPolicy=continue` decides what happens to the unit after an out-of-memory kill. It does NOT
  choose the victim. The kernel picks by badness, mostly size. Raising a process's own
  `oom_score_adj` needs no privilege.
- `ExecStop` runs after a crash too, with `$MAINPID` unset.
- `RuntimeDirectory` is 0755 by default, and it is removed on EVERY stop, including an automatic
  restart, unless `RuntimeDirectoryPreserve=` says otherwise.
- With the default `RestartMode`, a crash-restart of a unit try-restarts every unit that is
  `PartOf=` it.
- `systemctl start` on a unit that is already active succeeds silently.
- journald's stdout stream re-reads its sender when the PID changes, so a forked child's lines
  carry the child's own `_PID` (journald v249 and later; the box runs v259). The last lines a child
  writes before it exits may lack it. The rate-limit bucket is per unit.
- polkit's `manage-units` action also authorises TRANSIENT units, which carry their own `User=`
  and `ExecStart=`.
- `NoNewPrivileges` does not block a D-Bus call that polkit checks.

## The loading gate, fixed and measured the same day

The review's live bug: `MatchStart`'s gate compared the SIZE of `_ready_ids` with the size of
`_expected`, and `_drop_peer` pruned only the second of them. So a player who reported ready and
then vanished left a flag behind that made the two numbers meet.

Measured on this Windows dev PC with `run_lockstep_probe.ps1`, four clients on loopback: a host
waiting for four members, one join that hard-exits once the server's readiness echo names it, one
that hard-exits before reporting at all, and one that holds its report back for 30 seconds without
going quiet. The hold is 10 s and the load timeout 60 s, so 30 s sits clear of both.

| | Before | After |
| --- | --- | --- |
| Match announced | 4 players | 4 players |
| `Client loaded` before the start | 2 of 4 | 2 of 4, then `Client unloaded`, then 1 more at 2 of 2 |
| Readiness taken back at the disconnect | no line | `Client unloaded`, at the disconnect |
| `Match start` | **4 players**, before the slow loader reported | **2 players**, after it reported |
| Sealed stream opened with | 4 peers, 2 of them dead | 2 peers, both alive |
| Host's stall waiting for the dead | 9.83 s | 0.06 s |
| Host's `drops_seen` | 2, mid-match | 0 |
| The slow loader's `self_ready` | false - it played anyway | true |

The relay then had to give up on the two dead players a second time, from inside the match
("Player has gone silent" at relay turns 0 and 1), because they had been started into it.

Three players of the same shape, which leaves one live player against a `min_players` of 2:

| | Before | After |
| --- | --- | --- |
| Outcome | a 3-player match, 210 turns, one live player | `Match abandoned before it started` |
| The host ended on | `Main` | `LobbyRoom`, status "Not enough players finished loading." |

Regressions on the fixed copy: a plain 1v1 ran 540 turns with 0 desyncs and both peers agreeing,
and a mid-match hard kill still dropped the peer and reached the survivor (`drops_seen` 1).

**What the harness gained, and why each piece is a positive control:**
- `--quit-after-ready` waits to see its OWN id in the server's readiness echo before dying, so it
  dies at a moment the server has recorded rather than one the client merely sent.
- `--ready-delay <s>` blanks the setup's match id so `MatchLoading`'s automatic report is refused,
  then restores it and reports. **Blocking the main thread instead measures something else
  entirely**: a peer that stops polling stops answering ENet, so it reads as a silent player and
  gets the hold, not as a player who is still loading.
- `self_ready` and `reported_late` in the probe's result line, and `CLIENTS LAUNCHED` in the
  runner's summary. A run that quietly started two clients and one that started four read
  identically without it.

## P2, P3 and P4 built and measured, the same day

The handoff exists and plays matches. Measured on this Windows dev PC, on
loopback, with two harnesses:

- `Tools/run_match_probe.ps1` hand-writes a match file and runs a real match
  process with real probe clients against it. **No lobby in it at all**, which is
  the point: testing the child against a lobby that also has to work would not say
  which half was wrong.
- `Tools/run_lockstep_probe.ps1 -MatchProcesses` drives the whole road through the
  real lobby: countdown, spawn, READY, announce, move, claim, re-key, play.

**The positive controls are `claims` and `go_id`.** A run with `claims` at zero
never claimed a seat, and `go_id` equal to `own_id` is what proves the re-key
ran - that the roster the relay stamps orders against is the one the client's
socket answers to. A run can look perfect and have exercised neither.

### The child, alone (P2)

| Scenario | Result |
| --- | --- |
| Two seats, hand-written match file | full match, 350 and 358 turns, 0 desyncs, `go_id` = `own_id` on both |
| A seat dropped mid-load, re-claimed inside D26's hold | `claims=2` with a NEW peer id, re-reported ready, played on; 747 turns |
| A third seat holding its report back 22 s | the gate waited for it; `Match start` came after its `Client loaded` |
| A token that is nobody's seat | `WRONG_TOKEN`, its sentence on the client, counted in the RESULT's refusals |
| Another seat's token, presented while its owner holds it | `SEAT_HELD` seven times, `move_attempts=7`, the owner undisturbed |
| A token presented after the go signal | `TOO_LATE`, read by the client as "The match started without you." |
| The port already held by a first match process | exits 65 (`PORT_TAKEN`) in 1.8 s |
| No seat ever claimed | exits at the 60 s load timeout, writes a RESULT (`aborted`) |
| A shutdown file planted BEFORE the child listened | honoured, not cleared as stale; exits in 4.2 s (`shutdown`) |
| A shutdown while the match is running | both clients told, 207 turns played, `shutdown` |

### The whole road, through the lobby (P3, P4)

| Scenario | Result |
| --- | --- |
| One handoff | 443 turns, 0 desyncs, `go_id` = `own_id` |
| Two matches on one lobby process | own ports (7800, then 7801), own children, both clean, first reaped before the second spawned |
| A peer hard-killed mid-match | survivor ran 640 turns |
| A third peer browsing while a match runs | match untouched (540 turns); the browser never in one |
| A deploy (D45) mid-match | both clients on the lobby browser carrying "The server is restarting. The match was cancelled." |
| A planted desync | caught on both peers by the relay inside the child |
| The same code with the switch OFF | "Match processes are OFF", 434 turns, no handoff attempted |

Boot-to-READY on this machine: **1.5 to 1.8 s**, consistently, which is what the
READY ceiling has to be sized against on the box rather than here.

Regression: the tutorial probe plays a whole offline match through the loading
screen in an isolated copy of HEAD plus these files - 481 passes, 3 failures, and
those three fail on HEAD too (tutorial pointer borders, nothing to do with this).

### Seven bugs the batteries found

Recorded because each one looked like a pass from outside:

1. **The readiness report was lost whenever the move finished after loading.**
   `_end_move` ran before the status reached CONNECTED, and `is_online()` is false
   while CONNECTING - so the rpc was dropped and the match waited out D15 for a
   client that had loaded long ago. Only reachable on the path where the move took
   a retry, which is why the plain scenario passed.
2. **The client forgot its setup the frame its match link closed**, which made the
   owner's re-claim rule correct on the server and unusable from the client.
3. **A missing match file exited with a code and no log line at all.**
4. **A D45 shutdown during loading was recorded as an abort**, blaming the players
   for a restart.
5. **A healthy match was killed for being wedged, twice, on two mechanisms** - see
   the liveness-file trap in `CLAUDE.md`.
6. **The probe's own re-key control read the ANNOUNCED setup**, whose ids are the
   lobby's, so it compared a lobby id against a match id, found them different,
   and would have reported a re-key that never happened.
7. **`-BlockPort` did not block the port.** A .NET `UdpClient` does not stop ENet
   binding the same one, so the first `PORT_TAKEN` run "passed" with the child
   listening happily on a port the harness believed it held. It now holds the port
   with a real match process.

Numbers 6 and 7 are the same failure in the harness rather than in the code, and
both are the positive-control rule: the run proved the harness wrong and said
nothing.

## Still open

- **The service file.** Now prepared as `deploy_server.ps1 -InstallShutdown`: a drop-in that
  adds `--shutdown-file`, an `ExecStop` that creates the file and waits for the process to exit,
  and a bounded stop timeout.
  - It runs once, right after the deploy that brings the code for it.
  - B's first stage adds `OOMPolicy=continue`, `RuntimeDirectoryMode=0700` and the log rate
    limit lines to the same drop-in, and re-runs it before the switch is turned on.
- **The client half reaches players only with the next client build.** Until then a hard-killed
  relay still freezes them.
- **B itself.** See `multi-match.md`.
- **On the box:**
  - a match process's boot time and memory (the journal's `Relay match summary` lines already carry
    `rss_mb`);
  - whether testers' networks reach any UDP port other than 7777.
- **Not done:**
  - a match id on every relay log line (both desync lines lack one);
  - rate limits on the refusal paths that log.

## Traps

- **General traps moved to `CLAUDE.md`:** the corrected explanation of why a message sent just
  before a disconnect is lost, and the godot_ai helper on a server.
- **The pause scenario ran and measured nothing.** The probe pressed Pause 8 s in, while the match's
  opening hold was still on, so the press did nothing. `pauses_seen: 0` is what caught it;
  `--pause 20` works.
- **Another session's edits in progress in the same working tree stopped every headless run from
  compiling:** new `class_name`s that had not been imported yet. Testing in `git archive HEAD` plus
  only the changed files, with a copy of `.godot`, kept the runs independent of that. It also gave a
  pure HEAD copy to stand in for a tester's build.
