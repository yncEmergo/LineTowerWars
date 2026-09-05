# Hardening the lockstep build: four silent desyncs, a real relay, and the client budget

**2026-09-05.** Windows dev PC and the rented Hetzner server. Commits `8a38719` through
`3641604`.

## What was asked

Act on [2026-09-05-lockstep-review.md](2026-09-05-lockstep-review.md) - an independent read of
the multiplayer system - after verifying it rather than trusting it. Then finish the lockstep
implementation: correctness, the relay decision, robustness, and the performance question
nobody had answered.

## Verifying the review first

Five of its seven findings were confirmed by reading the code. Two were not, and both matter:

- **"A desync is detected and then nothing happens" is FALSE.** `DesyncNotice.gd` listens to
  `desync_detected` and is instanced in `match_hud.tscn` at `process_mode = 3`
  (PROCESS_MODE_ALWAYS), so it survives the pause and does tell the player.
- **Its main open worry is not real.** It flagged that the lockstep hold sets `SceneTree.paused`
  from inside `_physics_process`, and that if the pause only took effect on the NEXT frame a
  stalling peer would advance one world tick further than a peer that did not - a silent
  desync. **Measured with a two-node probe using explicit `process_physics_priority`:**

      PAUSER: setting tree.paused = true on frame 3
      PAUSER: setting tree.paused = false on frame 6
      WORKER RAN ON FRAMES: [1, 2, 6, 7, 8, 9]

  Pause and unpause both take effect within the same physics frame. A held peer advances
  exactly zero world ticks and resumes on the tick the hold clears. The mechanism is sound.

One imprecision worth recording: the review said making the server a relay "removes a full
one-way trip from the input path". It does not - the binding constraint is client to server to
client either way. What it removes is one of two equally tight things to wait on, so it cuts
stall probability rather than latency.

Its Finding 5 (transcendentals) was confirmed AND checked for completeness: two further `sin`
and `atan2` sites it did not list turned out to be presentation and dead code respectively.

## What was found and changed

### Four sources of silent divergence (phase 1)

Each produced two different worlds with nobody told.

1. **A drop desynced the match.** `_on_peer_left` returns early on anything but the server, so
   `player_dropped` only ever fired there - right under replication, where clients saw the maze
   vanish in the next snapshot, and dead after the cutover. The server erased the leaver's
   units and the clients did not. It reached the draft too: `StartingTech` waits on the same
   signal, so one peer dying during a draft held the survivors in a paused world for the rest
   of the match. Now a `Command.PlayerAction` the server issues into the turn stream.
2. **Two owners of the pause, no counting.** `set_paused` was a bool, so a stall clearing
   released the draft's hold as well as its own, and that peer then advanced ticks nobody else
   ran. Latent only because `tech_mode` ships as PICK. Now named holders.
3. **`pow` in the live damage pipeline and `sin` writing a checksummed position.** Neither is
   specified by IEEE-754 and the peer group is Windows clients against a Linux server.
4. **The checksum could not see the cause of a desync, only its effects**, and compared
   positions with a millimetre of slack.

### The server is now a relay (phase 3)

D2 was changed on the reasoning that "a lockstep server is a relay that runs no game loop", and
that is not what the cutover built: `is_authority()` answered true on the server, it loaded a
full match scene, and every client waited on its word every turn. It now builds no world, keeps
no turn clock, and is not in `_expected_peers`.

Two bugs that introduced, both found and fixed before shipping:

- **A relay cannot use `schedule()`** - it books into the next turn this machine has not closed,
  and a relay closes none, so phase 1's drop order would have sat in `_outgoing` for ever.
  `inject()` books off the highest turn the relay has HEARD instead.
- The relay **recorded every turn it forwarded and never ran one**, so `_incoming` grew for the
  whole match.

### Redundancy (phase 4)

One reliable message per turn meant a single lost packet froze every peer until ENet
retransmitted. The re-send has to be a SECOND, UNRELIABLE message: a reliable channel is
ordered, so a copy inside the next reliable packet cannot overtake the lost one either.

**Proven by disabling the reliable path entirely** and running a match on the echo alone - 467
turns, 50 orders, 0 desyncs, both peers identical. That experiment was reverted; only the
redundancy ships.

## Numbers

All two-peer headless unless stated. Every run: both peers identical, checksums including the
RNG state and exact bit-for-bit positions.

| Run | Result |
| --- | --- |
| Phase 1, all four in place | 465 turns, 46 orders, 0 desyncs |
| Kill a peer mid-match | 1364 turns, 0 desyncs; drop applied at tick 437 with 23 units erased **on both machines** |
| Relay, normal match | 466 turns, 50 orders, 0 desyncs |
| Relay, kill a peer | relay logs `injecting a server order turn 456, seen 436`; survivor applies at tick 457; 1178 turns, 0 desyncs |
| Echo only, reliable path disabled | 467 turns, 50 orders, 0 desyncs |

### The server's idle spin

Nothing had ever set `Engine.max_fps`. A dedicated server with **no clients and no match** used
**24% of one core**. Capped at 120: **12%**.

### The ENet flush did NOT measure as a win

The review predicted "tens of milliseconds". Paired alternating runs on one commit, flipping
only `flush_immediately`:

    flush ON  medians: 76, 76 ms
    flush OFF medians: 83, 76 ms

Inside the noise. Kept because it is sound, costs nothing, and is what makes the frame cap safe
- but the claim is unsupported here, not confirmed.

### Real-link latency, and how much a single median is worth

Three runs of the SAME build against the rented server at 26 ms ping: medians **144, 111, 125
ms**. A 33 ms spread. The delay adapts to 2 turns, so the band is (100, 150] and every one of
those is a draw from it. **A single median cannot resolve anything smaller than about 35 ms on
this link** - which is worth knowing before anybody chases a 13 ms "regression" again.

### The client tick budget - the largest open risk, now measured

Never measured before. `run_bench.ps1 -Only client -Quick`, on the dev PC, against a 50 ms
budget:

| Scenario | World | tick p50 | p95 | max | Headroom |
| --- | --- | --- | --- | --- | --- |
| client-1v1 | 390 towers, 200 creeps, 600 units | 15.5 ms | 21.4 | 28.8 | **2.34x** |
| client-ten | 1950 towers, 1000 creeps, 3000 units | 76.5 ms | 106.6 | 142.4 | **0.47x** |
| client-fewtowers | 16 towers, 311 creeps | 13.1 ms | 15.4 | 16.7 | 3.24x |

**The 1v1 prototype is not at risk.** It has better than 2x headroom on this machine, which is
the milestone the project is actually building.

**Twelve players is about 2x over budget on a gaming PC**, and that is now measured on
client-class hardware rather than extrapolated from server constants. The review's estimate
(2-3x over) had the right shape.

Largest single micro in the loaded client scene: `flow_rebuild_us=710`. Treat
`est_targeting_ms_per_tick` with the suspicion `CLAUDE.md` already documents - it is an
assumption, not a measurement.

## What is still open

- **Whether the redundancy helps under real packet loss.** Loopback drops nothing, so the
  benefit is by construction. Wants a link conditioner.
- **Whether the flush pays on a real link with a real relay hop.** Needs two deploys to A/B.
- **The per-unit simulation cost**, for twelve players. Measured above; not started. The
  ordering the review gives is right: stop dispatching `_physics_process` per node before
  anything else, because that is the order-of-magnitude change and the spatial hash is
  percentages.
- **How the stall panel LOOKS.** A headless run proves it loads and does not error; it cannot
  say whether it reads well.
- Health, cooldowns and construction progress are still quantised to a thousandth through the
  `checksum_state()` virtual. Positions are exact now; those want the same and it is a wider
  change, since three classes override that method.

## Traps

**A comment that asserts an invariant is not the invariant** - the review's own trap, and it
held up twice here. `_set_held`'s "whoever wants it held has it held" was false, and
`erase_player`'s "a client sees it all vanish through replication" described a mechanism the
cutover had deleted. Both read as settled when skimmed, which is exactly why they survived.

**A deploy that checked the files is not checking the process.** Already in `CLAUDE.md` from
2026-09-04; the fixed script now proves the restart by comparing the service pid, and printed
`Restarted: pid 43919 -> 46463` on the first deploy that used it.

**PowerShell's `Set-Content -Encoding utf8` writes a BOM**, which lands in a `.tres` as an
invisible diff. Caught by `git diff` during the A/B; use `git checkout` to restore rather than
rewriting the file.
