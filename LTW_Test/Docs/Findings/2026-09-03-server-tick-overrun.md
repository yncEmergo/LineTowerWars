# The multiplayer stutter is the server missing ticks — 2026-09-03

**Cause identified, and three fixes measured.**

An earlier draft of this investigation concluded the opposite - that server overload was
unlikely - from the process's LIFETIME CPU AVERAGE, which included all the idle time before
the match. That draft was deleted rather than kept, because it never landed anywhere. The
lesson survives it and is worth stating once: **an average is the wrong statistic for a
stutter.** Stutter is variance, and the number that finds it is p95 next to p50.

**These numbers are a snapshot.** One machine, one day. See [README.md](README.md).

## The question

A 2-player match on the public server hitched for roughly 0.1 s about once a second while a
lot of creeps were on the field, then ran smoothly until the next hitch. Very few towers were
built. It happened to **both players at the same moment** and reproduced every time.

## How it was measured

Two measurements, both on the rented server itself — a Hetzner CX23 (2 shared vCPU, x86),
Ubuntu 26.04.1, Godot 4.7.2 headless. Not on a developer PC, which turns out to matter.

1. **Process CPU accounting**, sampled once a second from `/proc/<pid>/stat` while a real
   match was played from a dormitory connection.
2. **`Scenes/Tools/perf_bench.tscn`**, the existing harness, run directly on the server with
   the game service stopped so nothing contended:

```
/opt/godot/godot --path /srv/ltw/LTW_Test --headless \
  res://Scenes/Tools/perf_bench.tscn -- scene=server players=2 creeps=<n> towers=8 seconds=12
```

The sweep holds towers at 8 per area — the reported condition was *few* towers — and varies
creeps. Every scenario in `run_bench.ps1` before today filled the maze, so nothing in the
matrix had ever asked what a lane of creeps costs with only a handful of towers around it.

**Trap, and it cost a run here:** `towers=0` does NOT mean zero towers. Zero is
`PerfBench`'s sentinel for *fill the maze*, so that argument produces 390 towers per area —
the opposite of what it reads like. There is no way to ask for a creeps-only world.

## What was found

**Measured — CPU during the live match.** Idle with no match: 3–4% of one core. During the
match: mean 37.8%, **peak 97.0%**, in four distinct bursts of a few seconds each rather than a
constant load. The simulation is single-threaded, so one core is the ceiling.

**Measured — the tick sweep.** 16 towers total in every row; creeps are the whole variable.

| Creeps | tick avg | p50 | **p95** | max | headroom |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 4.39 ms | 4.32 | 7.32 | 8.90 | 6.83× |
| 105 | 28.82 ms | 25.59 | **51.48** | 72.11 | 0.97× |
| 217 | 47.25 ms | 37.10 | **106.47** | 133.51 | 0.47× |
| 429 | 104.31 ms | 63.53 | **308.68** | 388.50 | 0.16× |

**The budget is 50 ms** (20 Hz). It is already gone at ~105 creeps, on a field with sixteen
towers on it.

**The variance is the symptom.** p95 is two to three times p50 throughout. At 217 creeps the
median tick is a comfortable 37 ms and the 95th percentile is 106 ms — so most ticks are fine
and occasional ones take two to three tick periods. That is precisely the reported shape: a
~0.1 s freeze, then smooth again. An average alone would have hidden it completely.

**Where the time goes.** The harness's `est_targeting_ms_per_tick` says 18 ms at 217 creeps, and
**that number is wrong for this scenario** — it is `one_search × towers × lanes`
(`PerfProbes._estimate`), which assumes every tower searches every tick. That holds for a full
maze where most towers have nothing in range; it is false in a lane packed with creeps, where a
tower holds a target and `AttackComponent` never reaches the search at all. Recorded because the
same trap will catch the next person to read that field.

Measured instead by varying tower count at a fixed ~200 creeps:

| Towers | Creeps | p50 |
| ---: | ---: | ---: |
| 16 | 217 | 36.19 ms |
| 80 | 201 | 48.87 ms |
| 390 | 200 | 91.24 ms |

That is **~0.15–0.20 ms per tower per tick**, so sixteen towers cost about 3 ms, not 18. The
corrected attribution at 16 towers and 217 creeps, against a 36 ms median:

| | Cost | Share |
| --- | ---: | ---: |
| Baseline — towers, zero creeps | 4.3 ms | ~12% |
| **Per-creep simulation, everything but the aura scan** | **~22 ms** | **~60%** |
| Creep aura scan | ~11 ms | ~30% |
| Tower targeting | ~3 ms | ~8% |
| Snapshot build | 0.68 ms | ~2% |
| Creep separation | 0.00 ms | 0% |

**The cost is per-CREEP, not per-tower.** Tick time grows linearly in creep count at roughly
140–200 µs each — so this is not one runaway quadratic scan, it is ordinary per-creep work
repeated. The aura scan is the one genuinely superlinear part and is the fastest-growing share
(9% of creep cost at 105 creeps, 33% at 217, 39% at 429).

Separation costs nothing, confirming the attacker-only rule from 2026-08-29 is holding.
Replication is innocent at this scale — worth recording, since whole-world snapshots were the
obvious suspect.

**The uncomfortable number**: ~100 µs of non-aura work per creep per tick. At 2.1 GHz that is
about 200,000 cycles to advance one creep one step. Whatever that is, it is the largest single
share of the tick and nothing in `Docs/` currently explains it.

**Inferred, not measured.** The server missing its tick explains "both players at the same
moment" without anything else being wrong: when a tick overruns, the snapshot goes out late and
every client freezes together. No client-side cost can produce that synchronisation. The
client's own instantiation burst on a new wave (`ReplicationService._apply_units` builds every
unseen unit in one frame, and a creep prefab is 40–52 nodes) was a competing explanation and is
NOT ruled out as a contributor — it was never separately measured, because the server numbers
already account for the whole reported symptom.

**Inferred — the hardware moved and the budget did not.** 2026-08-29 measured 390 towers and
200 creeps at 29.66 ms on a developer PC. This server needs 47.25 ms for 16 towers and 217
creeps. The earlier performance work was validated on a machine substantially faster than the
one matches are actually played against, so the headroom it bought was smaller than it looked.
Comparing the two rows is not like-for-like — the tower counts differ enormously — so treat the
direction as solid and the ratio as rough.

## Where the creep tick actually went

Measured by timing the segments of `Creep._physics_process` in place, rather than re-calling
them from a probe - the mistake above is exactly why. Per creep, at ~214 creeps:

| Segment | Before any fix | Notes |
| --- | ---: | --- |
| **move** | **131 µs** | the answer; 68% of the whole tick |
| aura | 42 µs | |
| status | 3.6 µs | |
| regen | 3.1 µs | |
| ability / passives / orders | <1.5 µs each | |

And inside `move`: `step` 50 µs, `stepmath` 21 µs, `hasstep+replan` 19 µs, the rest under 5 µs.
**`_replan` never fired once** - the pathfinding that looked like the obvious suspect was not
running at all, and counting it was what ruled it out.

The cost was `PlayerArea.is_point_free()`, which a walking creep asks about four times a tick -
once for its waypoint and twice more to slide along whatever is in the way. Each call ran
`to_local()`, which builds an **inverse matrix**, and reached `References` three more times for
the grid's width, depth and cell size. None of those four answers can change during a match.

## What was changed

Two fixes, both pure GDScript, neither touching a gameplay value or a rule:

1. **`CreepIndex`** - a per-area grid of creeps, rebuilt whole once per tick and read many
   times, so a range question reads the creeps NEAR a point. Returns a superset; every caller
   still tests the exact distance, so no answer changes.
2. **`PlayerArea` grid cache** - the area's transform and the grid's dimensions held rather
   than recomputed, invalidated by `NOTIFICATION_TRANSFORM_CHANGED` so it cannot go stale.

Measured on the same server, same scenarios:

| Creeps | p50 before | p50 after | p95 before | p95 after | max after |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 56 | — | 15.03 | — | 26.12 | 34.94 |
| 105 | 25.59 | **18.29** | 51.48 | **36.40** | **49.01** |
| 217 | 37.10 | **22.47** | 106.47 | **72.69** | 105.04 |
| 429 | 63.53 | **40.29** | 308.68 | **184.42** | 252.50 |

A **third fix** followed, once the profiler was pointed inside the aura sweep: every creep was
asking every neighbour's every passive five questions, and only FOUR passives in the whole
roster emit an aura. `PlayerArea.aura_sources()` now hands out the emitters - filtered through
`TargetFinder.is_attackable`, so the rules did not move - and the sweep is a handful of distance
tests instead of a radius scan plus hundreds of virtual calls.

Final, all three fixes, same server:

| Creeps | p50 before | p50 after | p95 before | p95 after | max after |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 217 | 37.10 | **21.23** | 106.47 | **39.86** | 57.15 |
| 429 | 63.53 | **34.41** | 308.68 | **55.35** | 74.61 |

**p95 improved 2.7x at 217 creeps and 5.6x at 429.** The variance collapsed with it - p95 was
2.9x the median before and is now 1.6x, which is the stutter mechanism itself going away rather
than merely shrinking.

### The fourth fix, and the one the user found

The three above were measured on a generic tower mix and Forest Trolls. The reported scenario
was 45 Firelords and 96 Ancient Wendigo, and it reproduced far worse than the generic shape at
the SAME counts - p95 81.66 against 42.90 - with near identical medians. Swapping only the
creep reproduced almost all of it, so it was the creeps.

Ancient Wendigo carries `regen_aura_3`. Two things followed:

**A regression, introduced by fix 3 above.** `aura_sources()` walked the emitters instead of
the neighbourhood, which is faster only while emitters are RARE. Every Wendigo emits, so it
degenerated to walking the whole lane. Corrected: the sweep now goes through the spatial index
FIRST and then skips non-emitters, which is better than either half alone.

**No phasing at all.** `_aura_elapsed` was initialised to the full interval on every creep, so
a wave that spawned on one tick swept on one tick forever after - the exact mistake
`AttackComponent._next_scan_wait` documents for tower targeting, in a loop that had never been
given the same treatment. The sweep is now spread by `unit_id`, one phase per tick of the
interval, and the interval moved to `GameConfig.creep_aura_refresh_seconds` (0.25 -> 0.5).

On the reported scenario:

| | p50 | p95 | max | headroom |
| --- | ---: | ---: | ---: | ---: |
| before | 25.78 | **81.66** | 114.28 | 0.61x |
| after | 29.91 | **48.13** | 93.36 | **1.04x** |

**The median rose while p95 fell 41%.** That is what phasing does and is the confirmation that
the diagnosis was right: the same total work, spread evenly instead of arriving in clumps.
p95/p50 went from 3.2x to 1.6x.

A four player shape, 240 towers and 418 creeps: avg 50.29, p50 47.89, p95 75.16, max 98.68. The
median now sits on the budget line where the same load used to be far past it, and p95 still
misses. That is the honest state of the 4+ player goal: closer, not there.

Per-creep, the two fixes took `move` from 131 µs to 77 µs: `hasstep+replan` 19.4 → 4.3,
`stepmath` 21.1 → 8.5, `step` 49.5 → 25.5.

`Tools/run_bench.ps1` also gained two scenarios (`1v1-fewtowers`, `client-fewtowers`) covering
the few-towers/many-creeps shape the matrix had never tested.

**The conclusion that matters for the language question:** 40% came out of two mechanical
GDScript changes with no cost to readability. The tick was not near a GDScript floor; it was
doing avoidable work. That is evidence about what a rewrite would and would not buy.

## What is still open

1. **Where the ~100 µs per creep per tick actually goes.** The largest share of the tick, and
   completely unattributed — no probe covers `Creep._physics_process` as a whole. Everything
   below is smaller than this. Measure before optimising anything else.
2. **The spatial hash per `PlayerArea`.** Still worth doing and still the recorded number one
   from 2026-08-29, but the measurement above resizes it: it addresses the aura scan (~30% of
   the tick) and tower targeting (~8%), not "most of the tick" as first written here. Expect
   roughly a third off, which does NOT on its own bring p95 back inside the budget at 200
   creeps. It is a real fix and a partial one, and those are different claims.
3. **Client-side instantiation on a wave.** Unmeasured. Worth timing before assuming the
   server fix alone makes the stutter go, since it would produce a hitch of its own shape.
4. **Where the threshold actually is.** The sweep jumps 0 → 105 creeps. The budget is crossed
   somewhere in that gap and it would be useful to know where, since it is the number that says
   how many creeps a 1v1 can currently hold.
5. **Benchmark on the target hardware, not the dev machine.** The harness runs on the server
   unchanged, as this finding did. Any future performance claim about the networked build
   should be measured there.
