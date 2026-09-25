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

## Still open

- **The service file.** Now prepared as `deploy_server.ps1 -InstallShutdown`: a drop-in that
  adds `--shutdown-file`, an `ExecStop` that creates the file and waits for the process to exit,
  and a bounded stop timeout.
  - It runs once, right after the deploy that brings the code for it.
  - B's first stage adds `OOMPolicy=continue` to the same drop-in.
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
