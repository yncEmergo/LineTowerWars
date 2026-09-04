# Staggered creep movement — built, measured, reverted — 2026-09-04

**Answered: can a creep take its step every Nth tick instead of every tick, and is it worth it?**

**It works, it is worth about 16% of the worst tick, and it is unplayable to look at.** The
code was reverted the same day. This finding exists so it is not rebuilt, and because the
REASON it looked bad is more useful than the optimisation was — it is a fact about the
replication boundary, not about the tick rate.

**These numbers are a snapshot.** One machine, one day. See [README.md](README.md).

This absorbs §2a and §5.6 of the former `performance-handover.md`, which was deleted on
2026-09-04 once its live parts had been moved into the reference documents. The rest of that
file's measurements were already in
[2026-09-03-server-tick-overrun.md](2026-09-03-server-tick-overrun.md) and
[2026-09-04-log-info-in-the-creep-tick.md](2026-09-04-log-info-in-the-creep-tick.md).

## The question

`move` was the top remaining cost in a creep's tick. Movement is also the one part of a creep
that does not have to happen every tick to be correct: a creep that takes a double-length step
every second tick ends up in the same place. Does spreading that work across N ticks buy back
the tail?

## What was built

Each creep took its step every Nth tick, with the time banked since its last one, phased off
`unit_id` so the population spread evenly across the N ticks rather than all moving together.

**The phasing worked.** A per-tick probe over ~310 creeps counted 148–163 of them moving on
every tick — dead even, no clumping. The move block halved, 7.7 ms → 4.2 ms.

**A full maze still routed.** Creeps reaching the exit went 1607 → 1626 over 25 s, so nothing
tunnelled through a tower and nothing stuck.

## What it bought — measured on the SERVER, paired

Hetzner CX23. Same deployed commit, interval flipped in place between runs, alternating.
Creep-heavy shape: 16 towers, 308 creeps.

| interval | avg | p50 | p95 | max |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 36.63 | 35.08 | 55.46 | 74.73 |
| 1 | 42.26 | 42.34 | 62.81 | 73.10 |
| 1 | 38.25 | 36.53 | 56.29 | 77.52 |
| 2 | 35.20 | 34.38 | 50.76 | 62.12 |
| 2 | 33.87 | 32.36 | 51.20 | 62.47 |

Every interval-1 run maxed at 73–78 ms and both interval-2 runs at 62 — **about 16% off the
worst tick, with no overlap between the two groups.**

On the tower-heavy Firelord/Wendigo scenario: p50 32.83 → 32.80, **no change at all**. Expected
— 90 towers against 219 creeps is a tick dominated by targeting, and this touched none of it.

## Why it looked terrible, and what that actually proves

The user's verdict was "laggy as fuck" and unplayable. **The cause is not that 10 Hz is too
slow to look smooth. It is that the client was interpolating across the wrong interval.**

`ReplicationService` applies a snapshot on the client's own physics tick, and Godot's physics
interpolation smooths between the last two tick transforms. When the server does not move a
creep on a tick, those two transforms are IDENTICAL — so the creep renders frozen for a whole
tick period and then covers a double step in the next one. A sawtooth in velocity, per creep,
at 10 Hz.

**That is an artefact of the mismatch, not of the rate**, and it has two consequences worth
carrying forward:

- **A UNIFORM lower simulation rate does not have this problem.** Every creep would move every
  tick and the interpolator would lerp across the whole tick period, which is what makes 24 fps
  film read as motion. Halving the tick rate globally is a different proposition, and the
  failure of this experiment is not evidence against it. (It is not free either, for unrelated
  reasons — `multiplayer.md` §5.6.)
- **A client rendering its own simulation cannot have this seam at all.** That is one of the
  things deterministic lockstep would buy, and `multiplayer.md` §4.1 cites this day for it.

## The variance is bigger than any earlier write-up admitted

Identical code, same box, minutes apart, gave p50 of **35.08, 42.34 and 36.53** — a 21% spread.

Every table in the 2026-08-29 and 2026-09-03 findings is single runs compared across hours,
which is inside that noise band. Nothing in them is wrong, but **no single-run difference under
about 20% on this machine means anything on its own.**

**Measure paired**: same commit, flip the one variable in place, alternate runs. That is what
made the result above legible when a cross-deploy comparison had shown nearly nothing. It is
the most durable thing the day produced and it is now a rule in `../../CLAUDE.md`.

## Two other hypotheses tested the same week and WRONG — do not redo them

Both from the 2026-09-03 push, recorded here rather than lost with the handover file. The
third of that set — pathfinding replans, which fired zero times in a loaded lane — is written
up in [2026-09-03-server-tick-overrun.md](2026-09-03-server-tick-overrun.md).

- **Physics interpolation on a headless server.** Turning it off changed nothing.
- **Visual nodes the server never draws.** Stripping them took the tree from 12,232 nodes to
  3,958 — 8,400 mesh nodes gone, 3× fewer — for **no improvement to the tick.** Godot dirties
  child transforms lazily and nothing headless ever reads them, so they cost nothing per tick.
  Stripping models on a headless server is still worth doing for MEMORY and for the SPAWN path
  — [2026-09-04-log-info-in-the-creep-tick.md](2026-09-04-log-info-in-the-creep-tick.md) makes
  it the largest single remaining item there — but it will not move the tick.

## What is still open

1. **A uniform lower tick rate** is untested and is the surviving version of this idea. It is
   parked deliberately: it touches every timer and cooldown in the game, and its
   client-interpolation half is replication work that lockstep would delete.
2. **The step-length safety check, if a swept test is ever wanted.** The table this
   investigation originally carried was computed from the wrong creep — it assumed 2.25/s when
   the roster's fastest walk is 4.0 and a speed aura over that makes 5.0. The obstacle is a
   TOWER, a whole grid cell rather than the half-cell internal grid, so a step has to exceed a
   full cell to cross one unsampled: four times the interval, not two.
