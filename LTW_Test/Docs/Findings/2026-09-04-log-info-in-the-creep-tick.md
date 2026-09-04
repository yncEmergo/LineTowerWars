# Half the creep tick was one log line — 2026-09-04

**Answered: where the unattributed ~100 µs per creep per tick actually went.**

That was open question #1 of
[2026-09-03-server-tick-overrun.md](2026-09-03-server-tick-overrun.md), which said "measure
before optimising anything else". This is that measurement. The answer is that **roughly half
of all creep simulation time was a single `Log.info` call**, and it is also the explanation for
the unexplained max spikes that finding left open.

> **READ THE SERVER SECTION BEFORE QUOTING THE HEADLINE.** "Half the creep tick" is a WINDOWS
> number. On the Linux server the same fix is worth about 7%, because most of the cost is
> output and Windows output is roughly five times more expensive. The fix is right either way;
> the size of it is not what the dev-PC profile said.

**These numbers are a snapshot.** See [README.md](README.md).

## The question

Every previous profile covered PARTS of a creep's tick, and the parts did not add up to the
whole. `move` was 77 µs of a tick believed to be ~100 µs, the rest of the named segments were
under 4 µs each, and nothing accounted for the difference. Nobody had ever timed the whole
`Creep._physics_process` against the sum of its pieces.

## How it was measured

A temporary `TickProbe` under `Scripts/Dev` (deleted afterwards, as that folder requires),
holding static accumulators keyed by segment name. `Creep._physics_process` was split so the
whole body could be bracketed by one clock pair, and each segment inside it by another. Per
creep-tick averages, printed every 60 physics frames.

**The residual is the point.** `TOTAL` minus the sum of the named parts is what nothing
explains, and driving it to zero is what found the answer.

Run on the DEV PC — `perf_bench.tscn`, `players=2 creeps=150 towers=8 seconds=15`, giving 308
creeps across two lanes. Absolute microseconds are therefore dev-PC numbers; the server is
slower. The SHARES are what matter and they transfer.

**Verifying the probe was not the story.** Re-running with the inner marks stripped, leaving
only the outer bracket, gave `TOTAL` 97.8 µs against 100.6 µs with them — so the instrument
cost ~3 µs and the residual was real, not an artefact.

## What was found

**Measured — first pass, gaps open:**

| Segment | µs per creep-tick |
| --- | ---: |
| move | 21.8 |
| aura | 11.0 |
| trail | 2.8 |
| atexit | 2.6 |
| regen | 2.0 |
| status | 1.5 |
| passives / ability / orders | ~1 each |
| **TOTAL** | **93–105** |
| **residual — nothing explains this** | **~55** |

Closing every gap — timing the head of the function and each of the four early-return paths —
drove the residual to **0.63 µs** and put all 55 µs on one key: the path where a creep reaches
the exit.

**Measured — the attribution.** That path fires about **0.005 times per creep-tick** (a
couple of creeps leaking per tick out of ~310) and yet accounted for **54.6 µs of the 99.8 µs
average**. Which works out at roughly **10 milliseconds for one creep reaching the exit.**

Breaking that path down further:

| Inside `_reach_end` | µs per creep-tick |
| --- | ---: |
| **`Log.info("Creep leaked", …)`** | **49.7** |
| `_recycle_into` | 4.2 |
| `_next_maze` | 0.04 |
| `_steal_life` | 0.03 |
| `reached_end.emit()` | 0.01 |

**One log line was 92% of the cost of a creep leaking, and ~50% of all creep simulation.**

**The mechanism, from `addons/log/log.gd`.** `Log.info` calls **`get_stack()`** on every
invocation — a full GDScript call-stack capture, which is what produces the `[Creep:2041]`
prefix — and then `print_rich()`, which parses BBCode and writes out. The level check runs
FIRST, so `Log.debug` at the default `INFO` level returns immediately and costs nothing.

**Inferred, and it fits exactly.** This is also the "unexplained outlier" of
`performance-handover.md` §4.2 — max ~93 ms while p95 was 48. A wave arriving at the exit
together logs several leaks in one tick, at ~10 ms each. Nothing else in the tick has that
shape: rare, and enormous when it fires.

**Worth stating plainly:** the volume was already a known problem for a different reason.
`CLAUDE.md` records that `logs_read(source="game")` times out because "the Log.gd volume
saturates the buffer". That was the same call sites, seen from the other end.

## What was changed

Six events moved from `Log.info` to `Log.debug`. Nothing else, no rule and no balance number.
The first four came out of the profile; the last two out of the sweep it prompted:

| Where | Event |
| --- | --- |
| `Creep._reach_end` | "Creep leaked" — the frequent one |
| `Creep._watch_for_stall` | "Creep re-routing after making no progress" |
| `Creep` revive | "Creep revived" |
| `PlayerArea._displace_creeps_in` | "Creep displaced by a building" |
| `SendBuilding.send` | "Send refused" — behind a `repeat_on_hold` ability, so per tick |
| `SendBuilding.send` | "Out of stock" — same |

The lines still exist and still say the same thing; they are one log-level flip away.

**The rule that came out of it, and the durable part of this finding: a log call on a
PER-CREEP or per-tick path must be `Log.debug`. `Log.info` is for per-player-action events** —
a tower sold, an upgrade started, a lobby created. The `Building` call sites are all of that
second kind and were correctly left alone. The cost is not the writing, it is the
`get_stack()`, and it is paid whether or not anybody ever reads the line.

**Measured, DEV PC (Windows), same scenario, probe removed — read the server section below
before quoting any of this:**

| | avg | p50 | p95 | max |
| --- | ---: | ---: | ---: | ---: |
| before | 35.4 | 25.3 | 94.0 | 162 |
| **after** | **16.8** | **16.4** | **20.7** | **23.7** |

Per creep, `TOTAL` went **98.5 µs → 49.2 µs**: the creep tick halved.

**p95 improved 4.5× and max 6.8×.** The variance collapsed with it — p95/p50 was 3.7 and is
now 1.26, which is the stutter mechanism going away rather than shrinking.

### Measured on the SERVER afterwards — and the dev-PC number DOES NOT TRANSFER

Taken once the fix was deployed. Hetzner CX23, same creep-heavy scenario, three runs each,
both sides with the movement stagger OFF so the only difference is the log call:

| | p50 runs | median |
| --- | --- | ---: |
| `Log.info` | 35.08, 42.34, 36.53 | 36.5 |
| **`Log.debug`** | 35.05, 34.09, 34.07 | **34.1** |

**About 7% on the server, against 2.1× on the dev PC.** Which works out at roughly 2 ms per
call on Linux against the ~10 ms measured on Windows.

**So the claim earlier in this finding that "the SHARES are what matter and they transfer" is
WRONG**, and is left standing above only so this correction has something to point at. They did
not transfer. `Log.info` costs `get_stack()` plus `print_rich()`, and the OUTPUT half of that is
far more expensive on a Windows console than on a Linux one — roughly five times so. A profile
of an I/O-bound call is a profile of the PLATFORM, not of the code.

**The fix is still right** — it is free, it removes a real ~2 ms spike source, and the log
volume was already a problem in its own right — but it is a 7% fix on the machine that matters,
not a halving. **Any future claim about a call that writes output has to be measured on the
target platform or not made.**

The paired test could not be run in place — writing to the server was refused by tooling
permissions all session — so the two rows above come from separate deploys rather than an
in-place toggle. Three runs each and the medians do not overlap, but that is weaker evidence
than the dev-PC pairing, which is why the figure is given as "about 7%".

## The tower tick, profiled the same way — and it is clean

With the creep tick halved, the same probe was pointed at `Building._physics_process` and
`AttackComponent._physics_process`, on a FULL MAZE (390 towers per area, 240 creeps) where
towers dominate. **There is no second surprise.** The residual came to ~0.6 µs inside
`Building` and ~1 µs inside `AttackComponent`: the cost is real work, spread thin.

Measured, per building-tick:

| Segment | µs | Note |
| --- | ---: | --- |
| `AttackComponent` total | ~11.4 | its own node, its own `_physics_process` |
| ├ `_acquire` (target search) | 5.0 | the largest single item |
| ├ firing | 3.4 | fires on 15% of ticks, so ~23 µs per shot |
| ├ drop-lost / can-attack / may-acquire | ~4 | |
| `Building` body total | ~10.3 | |
| ├ regen | 3.4 | **fixed, see below** |
| ├ passives | 2.5 | |
| └ orders / status / ability / sell / head | ~4 | |

So a tower costs about **22 µs per tick**, not the 150–200 µs the 2026-09-03 finding derived by
varying tower count. That estimate was several times too high; this one reconciles with the
whole: 780 towers × 22 µs + 240 creeps × 49 µs ≈ 29 ms against a measured 27 ms tick.

**Two safe fixes came out of it**, both mirroring guards `Creep` already had:

- `Building._regenerate` computed its regeneration rate and called `heal()` every tick for
  every tower, including the near-totality that are at full health, where `heal()`'s own clamp
  threw the answer away. Guarded on full health, exactly as `Creep._regenerate` always was:
  **3.38 → 1.03 µs**, a quarter off the whole `Building` body.
- `Building._advance_passives` walked its passive list twice for a tower with no passives and
  no disc over it, which is most of a basic maze. Early-out added.

**Honest about what those two buy at the whole-tick level: nothing measurable on this machine.**
~2.5 µs × 780 towers is ~2 ms, and the full-maze scenario swings 24.3–30.0 ms between identical
runs here. They are real — measured directly, in isolation — and they are inside the noise of
the benchmark that contains them. Recorded as such rather than dressed up.

**Scope of the log fix, stated plainly.** It is worth 2.1× on the creep-heavy shape (few
towers, many creeps) and **nothing on a full maze**, because there creeps die to towers rather
than reaching the exit and the leak path barely runs. That is the shape the stutter was
reported in, so it is the right one to have fixed — but it is not a universal 2×.

## The spawn path, measured the same day — and it is the PATHFINDING

Nothing had ever timed putting one creep into the world, and it is the load a player feels
when they hold the send key. Measured with a temporary `SpawnProbe`, full maze, ~1550 spawns.

**Measured, per spawn, dev PC:**

| | before | after | |
| --- | ---: | ---: | --- |
| **`_replan()`** | **547** | **67** | the route to the exit |
| `add_child` | 178 | 188 | |
| `instantiate` | 167 | 175 | the prefab, model and all |
| placement / setup / passives | ~15 | ~15 | |
| **total** | **~904 µs** | **~448 µs** | |

**Pathfinding was 61% of it — instantiating the whole node tree was under a fifth.** The
prediction going in was the opposite: that building a ~45-node prefab on a server that never
draws it would dominate. It does not.

**What was changed.** `PlayerArea.route_to_exit` now caches the route by its starting cell.
The answer depends only on that cell and the blocking grid, and the grid is written in exactly
one place - `_set_footprint` - so the cache is emptied there and no caller can forget. The
arrays are SHARED with every creep holding one, which is safe only because a creep reads its
route and advances an index into it and nothing mutates `_path`; that is stated in the comment
so the next person to change it knows what they would be breaking.

Bounded because a creep only re-plans where it SPAWNS - the 2026-09-03 finding counted zero
replans in a loaded lane - so the keys are the spawn strip, not the grid. `ROUTE_CACHE_LIMIT`
guards the case where that stops being true, by emptying rather than evicting.

**Correctness: `creeps_spawned` was 1549 before and 1549 after**, on the same seed and
scenario - the same number of creeps got through the same maze - with no "no route" warnings.

**Honest about the whole-tick effect: none that this benchmark can see.** ~450 µs saved on a
spawn, at ~3 spawns a tick, is ~1.4 ms against a ~22 ms tick, which is inside the noise here.
**Its value is in BURSTS**: a wave of twenty creeps arriving on one tick cost ~18 ms and now
costs ~9 ms. That is a p95/max fix, not a median one, and it should be judged on the tail.

**And it inverts the next step.** Instantiation plus `add_child` is now **81%** of what remains
of a spawn, where it was 38%. Stripping the `Visual` child on a headless server - already
flagged in `performance-handover.md` §5.6 as "worth doing for memory and spawn cost, but it
will not help the tick" - is now the largest remaining item on this path.

## What is still open

1. **Re-measure on the server**, paired, once this is deployed. Everything above about the
   server is a before with no after.
2. ~~Sweep the other `Log.info` call sites.~~ **Done, and it found two more.**
   `SendBuilding`'s "Send refused" and "Out of stock" sit behind a `repeat_on_hold` ability,
   so a player holding the send key with nothing to send reaches them EVERY TICK - about
   200 ms of server time per second, from one held button. Both moved to `Log.debug`. Nothing
   else in `Scripts/` is on a per-unit path: the `Building` calls are per-click, and
   `VoidSpreadPassive` logs per conversion rather than per attempt.
3. **What remains is NOT scan-bound, and the spatial hash is already built.** An earlier draft
   of this line called the spatial hash "the clear number one" and that was wrong twice over:
   - `CreepIndex` has existed since 2026-09-03 and `PlayerArea.creeps_near()` goes through it.
     `TargetFinder.creeps_in_radius` and `TargetFinder.best_target` both call `creeps_near`, so
     **tower targeting and every radius query in the game are already indexed.** The only
     remaining linear walks over `area.creeps()` are creep separation and `_hold_apart`, both
     ATTACKER-ONLY, and separation is off for the ordinary roster.
   - `move`, at ~21 µs the top remaining creep cost, **is not a scan at all**. It is
     `is_point_free` grid reads, the two slide tests and the transform write. No spatial
     structure touches it.

   So the honest position is that there is no large unbuilt indexing win left. What remains is
   distributed per-unit work, and the next real number to get is the SPAWN path, which nothing
   has ever measured: node instantiation plus the one `_replan()` each new creep does.
4. **A release export may be cheaper still.** `get_stack()` returns an empty array in release
   builds; the server runs the editor binary, which is a debug build. Untested, and not a
   reason to leave `Log.info` on a hot path either way.

## Traps

**Measure the whole against the sum of its parts, and drive the residual to zero.** Every
earlier profile here measured parts, and every one of them missed this, because a segment that
is never entered by most creeps does not show up in a per-segment table at all. The residual is
what caught it.

**A rare-but-huge cost hides from averages per unit.** At ~0.005 calls per creep-tick this
looked like nothing in any table organised by "what does a creep do each tick". It was half the
budget.

**`sed`-style edits by first-match are dangerous in a large file.** Instrumenting
`if _status != null && _status.is_held(): return` hit the identical line in `can_attack()`
first, which returns `bool` — an instant parse error. Cheap here because it failed loudly;
worth remembering where it would not.
