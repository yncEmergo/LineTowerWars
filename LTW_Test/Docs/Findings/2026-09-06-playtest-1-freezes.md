# Playtest 1: the ~1 second freezes are content loading, not the network

**2026-09-06.** First real playtest: two players, two machines, against the rented server.
Build `a88eaa1`. Both players' session logs captured.

## What was reported

> Occasional lag spikes of ~1 s each, where we both at the same time had a game freeze and then
> it continued. Random, roughly every 30-60 s, and NOT during high input — sending 100 creeps
> each went smoothly.

Also a short pause right after the load screen where input did not go through.

## How it was checked

Both session logs, aligned **by turn number rather than by wall clock**. That alignment is the
whole method and it is what made the answer unambiguous — see Traps.

The logs do not record stall DURATIONS, only stall starts. Durations were recovered from the
gaps between periodic entries: `turn.state` is written every checksum turn, so a wall-clock gap
much larger than that cadence is a freeze, wherever it happened and whether or not anything
logged it.

## What was found

### The network was not involved at all

RTT was rock steady for the whole match: **18-21 ms with a variance of 3-4 ms in 118 of 122
samples**, and `delay_turns: 1` throughout. The only two outliers are the match-start reading,
which is ENet's seeded estimate before it has measured anything.

A one-second network outage would show as a large RTT spike in the following sample. There is
none.

### Both machines froze at the SAME TURNS

| turn | host froze | cai froze |
| --- | --- | --- |
| 780 | 0.90 s | 1.04 s |
| 790 | 0.75 s | 1.07 s |
| 2370 | 0.90 s | 0.95 s |
| 2470 | — | 0.99 s |
| 9040 | 1.05 s | 0.74 s |

**This is the finding.** Two machines freezing at the same point in the SIMULATION, rather than
at the same moment in wall-clock time, cannot be the network and cannot be one slow machine:

- network lateness would hit different turns on each side, because it depends on when a packet
  was lost rather than on what the world was doing;
- one machine hitching would produce a gap on the OTHER machine only, as it waited.

Both peers being slow at the same simulation step means both were doing the same expensive work
— which means the cause is in the content the turn touched.

### Every freeze is a first instantiation

Cross-referencing the turn stream against the first appearance of each ability:

| turn | trigger |
| --- | --- |
| 780, 790 | the first towers FINISH CONSTRUCTION. `build_lesser_archer` was ordered around turn 520; the model is instantiated when the build completes, roughly thirteen seconds later |
| 2370 | the first sheep spawn (`send_sheep` ordered at turn 2324) |
| 2470 | the first tower shot — projectile and impact scenes |
| 9040 | `upgrade_fire_pit_to_magma_well`, one turn after the order |

`UnitStats.scene()` loads its `PackedScene` **synchronously, on the game thread, the first time
something spawns one**. `MatchLoading` thread-loads only `Main.tscn`; everything that scene
names by `res://` path is left until first use.

That is the deliberate design recorded in `CLAUDE.md` — a resource names a scene by PATH so
that loading a tower's stats does not drag in its model. It keeps memory and load time down and
moves the cost to first use. **Under lockstep that cost is then paid by everybody**: both peers
simulate the same turn, both load the same scene, both stall.

It explains every part of the report. Random, because it follows content rather than the clock.
Not during heavy input, because sending a hundred of an already-loaded creep costs nothing — it
is the FIRST one that loads. Simultaneous, because lockstep makes it so. And turns 780/790 look
unrelated to any order because the load happens at build COMPLETION, not at the order.

### The separate thing the logs also show

Time held, per minute, from turn progress against wall clock (cai's side):

```
  0- 60s :  4.3%      300-360s :  1.0%
 60-120s :  0.1%      360-420s :  1.2%
120-180s :  2.5%      420-480s :  1.3%
180-240s :  0.2%      480-540s :  3.0%
240-300s :  0.0%      600-660s : 14.8%   <- last minute, 125 stalls
```

Overall: host lost 6.8 s of 497 s (1.4%), cai 14.1 s of 630 s (2.2%). The match ran at 19.55
turns per second against an ideal 20.

**The last minute is not the network either** — it is the tick cost approaching the budget as
the world fills, which is the per-unit cost already recorded as the thing that limits player
count.

**And the margin that would have absorbed it was removed on a measurement that did not
transfer.** `jitter_margin_ms` was set to 0 on paired runs in `2026-09-05-lockstep-review-2-
response.md` — runs that were HEADLESS, with no renderer and therefore almost no frame-time
variance. On a real client the margin absorbs frame-time jitter as well as network jitter, and
at `delay_turns: 1` there is only about 30 ms of slack before a tick overrun makes a peer's word
late. That is `CLAUDE.md`'s own "measure on the target" rule, broken by the person who wrote the
paired-measurement rule into it.

## Answers to the two direct questions

- **The game PAUSED; it did not fast-forward.** A stalled peer's clock stops - `_frames` does
  not advance - so the match simply loses that second. 19.55 turns/sec against 20 is that loss.
- **The connection was fine.** One of the cleanest links in any log this project has produced.

## What is still open

- The fix: warm content before it is first needed. See `multiplayer-todo.md`.
- Shader compilation is a SECOND cost and preloading does not remove it. Under
  `gl_compatibility` shaders compile on first DRAW, not on load, so a scene that has been
  preloaded can still hitch the first time it is rendered.
- The late-match escalation, which is the per-unit simulation cost and not this.

## Traps

**ALIGN TWO PEERS' LOGS BY TURN, NOT BY WALL CLOCK.** It is what turned "one of us was
laggy" into a definite answer in one step. Same turn means the simulation; same wall-clock
instant means the network or one machine. The two logs started eight seconds apart and no
amount of staring at timestamps would have shown it.

**A stall log records a start, not a duration**, so a count of stalls says nothing about time
lost. The gaps between periodic entries recover it, and this is the second time in two days
that a stall COUNT proved to be the wrong measurement - it is already in `CLAUDE.md`.

**Both sides' logs, or the answer is a guess.** The first pass on this had only one side and
concluded the host was the machine hitching. That was wrong: both were, at the same turns. One
log cannot distinguish "the other peer is slow" from "we are both slow together", because the
only thing either records is waiting for the other.
