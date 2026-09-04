# Handover: server performance, 2026-09-03 → 04

**This is a LIVING document.** (`lockstep-migration.md`, added 2026-09-04, is the other one.)
It exists because the work
below spans a machine change and a fresh session. **Delete it, or fold it into
`multiplayer.md`, once the work it describes has landed.** It is not a finding — the dated
measurements live in
[Findings/2026-09-03-server-tick-overrun.md](Findings/2026-09-03-server-tick-overrun.md) and are
never edited. This file is the *state of play* and the *plan*.

Read that finding first. This one assumes it.

---

## 1. Do this before anything else

### 1.1 The working tree is uncommitted and the server runs code that is not in git

> **DONE, 2026-09-04. This whole section is history.** The server was rebuilt, deployed from
> git, and `deploy_server.ps1 -Check` now reports server, origin and local on the same commit
> with a clean tree. Nothing below needs doing; it is kept because §5.4's lesson survives it.
>
> The state it described, kept for the record:
>
> **DONE on the git side, NOT on the server side.** `origin/main` now carries 2026-09-03's
> work, and the working tree was clean when 2026-09-04 started. The server has still not been
> deployed to it, so everything below stands as written - run the deploy before testing
> anything, and note that the working tree is dirty again with 2026-09-04's change (§2a).

The public server's checkout is at `db86a4f` — the same commit as `origin/main` — but the files
on it were **copied in by hand** (`scp`), not deployed. So `git -C /srv/ltw status` on the server
is dirty and its HEAD tells you nothing about what it is running.

**Fix it in this order:**

```powershell
.\Tools\deploy_server.ps1 -Check    # what is it running vs origin
git add -A ; git commit ; git push  # yours to do
.\Tools\deploy_server.ps1           # hard-resets the server to origin/main
```

The deploy does `git reset --hard origin/main`, so it **wipes the hand-staged files and replaces
them with the committed ones**. That is the intended cleanup, and it is why staging by hand was
safe. Until it runs, client and server can silently differ — which cost real debugging time on
2026-09-03 (see §5.4).

### 1.2 Restart the Godot editor

It retains stale parse errors across runs. After 2026-09-03's file churn it was showing ~57
errors for identifiers that no longer exist anywhere in the project. `--import` and a filesystem
scan do NOT clear them. Only a restart does.

---

## 2. What was done on 2026-09-03, and what it bought

Four fixes, all pure GDScript, none touching a rule or a balance number.

| # | Fix | Where |
| --- | --- | --- |
| 1 | **`CreepIndex`** — per-area grid of creeps, rebuilt whole once per tick, read many times. Returns a SUPERSET; every caller still tests exact distance, so no answer changes. Rebuilt lazily on first query of a tick so it cannot depend on node order. | `Scripts/Game/CreepIndex.gd`, `PlayerArea.creeps_near()` |
| 2 | **Grid cache** — the area's transform and the grid's width/depth/cell size held instead of recomputed. `is_point_free()` was building an **inverse matrix** and making three `References` trips, ~4× per creep per tick, for four answers that cannot change during a match. Invalidated by `NOTIFICATION_TRANSFORM_CHANGED`. | `Scripts/Game/PlayerArea.gd` |
| 3 | **Aura: index + emitter skip** — only four passives in the whole roster emit an aura (`grants_aura()`), so the five virtual calls per passive per neighbour were nearly always wasted. Index narrows to the neighbourhood, `emits_aura()` skips the rest. | `Creep._refresh_aura`, `CreepPassive.grants_aura`, `Creep.emits_aura` |
| 4 | **Aura phasing** — every creep started its clock at the full interval, so a wave that spawned together swept together forever after. Now spread by `unit_id`, one phase per tick of the interval. Interval moved to config and raised 0.25 → 0.5 s. | `Creep._aura_phase`, `GameConfig.creep_aura_refresh_seconds` |

Also: distance is now tested **before** the predicate calls in `TargetFinder` (three float ops
reject most candidates; `_is_attackable` is five calls).

### Measured, on the real server

Hetzner CX23, 2 shared vCPU, Intel Xeon Skylake @ 2.1 GHz, **0% steal**. Budget is **50 ms**
(20 Hz). Generic tower mix + Forest Troll unless stated.

| Load | p50 before | p50 after | p95 before | p95 after |
| --- | ---: | ---: | ---: | ---: |
| 16 towers, 217 creeps | 37.10 | **21.23** | 106.47 | **39.86** |
| 16 towers, 429 creeps | 63.53 | **34.41** | 308.68 | **55.35** |
| 90 towers, 219 creeps (Firelord + Wendigo) | 25.78 | **29.91** | 81.66 | **48.13** |
| 240 towers, 418 creeps (4-player shape) | — | **47.89** | — | 75.16 |

**p95 improved 2.7×–5.6×.** Variance collapsed with it: p95/p50 was ~2.9× and is now ~1.6×,
which is the stutter mechanism itself rather than merely a smaller version of it.

**Still short of the goal.** The user wants 4+ players with 400+ creeps and hundreds of towers.
The 4-player row above has the median on the budget line and p95 well over it.

---

## 2a. 2026-09-04: §4.1 was built, measured, and REVERTED

**Staggered creep movement is dead. Do not rebuild it.** It worked exactly as designed, bought
about 16% off the worst tick, and looked so bad that the user called it unplayable. The code
is gone; what follows is why, because the reason is more useful than the fix was.

### What it did

Each creep took its step every Nth tick with the time banked since its last one, phased off
`unit_id` so the population spread evenly across the N ticks. Verified: a per-tick probe over
~310 creeps counted 148-163 moving on every tick, dead even, no clumping. The move block
halved, 7.7 ms → 4.2 ms. A full maze still routed - creeps reaching the exit went 1607 → 1626
over 25 s, so no tunnelling and no sticking.

### What it bought, measured ON THE SERVER, paired

Same deployed commit, interval flipped in place between runs. Creep-heavy shape (16 towers,
308 creeps):

| interval | avg | p50 | p95 | max |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 36.63 | 35.08 | 55.46 | 74.73 |
| 1 | 42.26 | 42.34 | 62.81 | 73.10 |
| 1 | 38.25 | 36.53 | 56.29 | 77.52 |
| 2 | 35.20 | 34.38 | 50.76 | 62.12 |
| 2 | 33.87 | 32.36 | 51.20 | 62.47 |

Every interval-1 run maxed at 73-78 ms and both interval-2 runs at 62 - about 16% off the
worst tick, with no overlap. On the tower-heavy Firelord/Wendigo scenario: p50 32.83 → 32.80,
**no change at all**, which is expected - 90 towers against 219 creeps is a tick dominated by
targeting, and this touched none of it.

### Why it looked terrible, and what that actually proves

**It is not that 10 Hz is too slow to look smooth. It is that the client was interpolating
across the wrong interval.**

`ReplicationService` applies a snapshot on the client's own physics tick, and Godot's physics
interpolation smooths between the last two tick transforms. When the server does not move a
creep on a tick, the two transforms are IDENTICAL - so the creep renders frozen for a whole
tick period, then covers a double step in the next one. A sawtooth in velocity, per creep,
at 10 Hz. That is the "laggy as fuck", and it is an artefact of the mismatch, not of the rate.

**This matters for what comes next.** A UNIFORM lower simulation rate does not have this
problem: every creep moves every tick, and the interpolator lerps across the whole tick
period, which is what makes 24 fps film look like motion. Halving the tick rate globally is a
different proposition from staggering within it, and the failure of this experiment is not
evidence against it.

### The variance is bigger than anything written here previously admits

Identical code, same box, minutes apart, gave p50 of **35.08, 42.34 and 36.53** - a 21%
spread. Section 2's table and the finding's tables are single runs compared across hours,
which is inside that noise band. Nothing there is wrong, but no single-run difference under
about 20% on this machine means anything on its own.

**Measure paired from now on**: same commit, flip the one variable in place, alternate runs.
That is what made the result above legible when a cross-deploy comparison showed nearly
nothing. This is the most durable thing the day produced.

## 3. Where a creep tick goes now

> **SUPERSEDED 2026-09-04.** This table measures PARTS and the parts never added up to the
> whole - which is exactly what hid the real answer. A creep tick was ~98 µs, of which ~50 µs
> was a single `Log.info` on the leak path. After moving the per-creep log events to
> `Log.debug` a creep tick is ~49 µs, `move` is the top cost again at ~21 µs and `aura` second
> at ~10 µs. See `Findings/2026-09-04-log-info-in-the-creep-tick.md`. The numbers below are
> kept because the move breakdown inside them is still the best one taken.

Measured by timing segments **inside** `Creep._physics_process` (scaffolding since deleted — see
§6 if you need it again). Per creep, ~214 creeps, after fixes 1–2:

| Segment | µs/creep | Notes |
| --- | ---: | --- |
| **move** | **77** | still the dominant cost |
| ├ step | 25.5 | of which `pos_write` 12.9, `slide_tests` 5.3 |
| ├ stepmath | 8.5 | |
| ├ hasstep+replan | 4.3 | was 19.4 before the grid cache |
| ├ stall / face / trail | ~9 | |
| aura | 42 → much less after fixes 3–4 | |
| status / regen / ability / passives / orders | <4 each | already cheap |

**Tower cost, measured by varying tower count:** ~**0.15–0.20 ms per tower per tick**. Do NOT
trust `est_targeting_ms_per_tick` from the bench — see §5.2.

---

## 4. What to do next, in priority order

### 4.1 Staggered movement — TRIED, REVERTED, DO NOT REBUILD

See §2a. It works, it is worth ~16% of the worst tick, and it is unplayable to look at. The
step-length table this section used to carry was also computed from the wrong creep: it
assumed 2.25/s, the roster's fastest walk at 4.0, and a speed aura over one of those makes
5.0. But the obstacle is a TOWER, a whole grid cell rather than the half-cell internal grid,
so a step has to exceed a full cell to cross one unsampled - four times the interval, not two.
Recorded in case a swept test is ever needed for another reason.

### 4.2 The unexplained outlier - SOLVED 2026-09-04

> **It was `Log.info("Creep leaked", ...)`, at roughly 10 ms a call.** Rare, enormous, and
> exactly the shape the spikes had: a wave arriving at the exit together logs several leaks in
> one tick. `Log.info` calls `get_stack()` on every invocation. Fixed by moving the per-creep
> events to `Log.debug`; the creep tick halved and max fell 6.8x on the dev PC. Full write-up
> in `Findings/2026-09-04-log-info-in-the-creep-tick.md`. The section below is kept for the
> candidates it ruled in and out.

> **A lead, from 2026-09-04's runs, not chased.** On the dev PC two scenarios with nearly the
> same MEDIAN have wildly different tails: a full maze of 780 towers and 240 creeps runs
> p50 24.5 / max 44, while 16 towers and 308 creeps runs p50 26 / max 165. Same median, four
> times the tail. Whatever spikes is therefore about creep DENSITY in an open lane rather
> than about towers, spawning (only a handful of creeps spawned in that window) or the flow
> field (nothing was built or sold). The aura sweep is the one part the finding already calls
> genuinely superlinear, and an open lane is where it is densest. Worth testing first.

Even after every fix, **max is ~93 ms** on the Wendigo scenario while p95 is 48. Something
spikes rarely and hard, and it was never chased. Candidates never ruled out: a wave arriving
(spawn batch), a tower dying, `_rebuild_flow_field` (measured at 1.6–4.7 ms per call, fires on
every placement and sale). Find it before assuming the distribution is clean.

### 4.3 Replication phase B / client extrapolation

> **DEFERRED 2026-09-04, on architecture grounds rather than on its merits.** D2
> (server-authoritative replication) is under review against deterministic lockstep - see
> `multiplayer.md` §4.1 - and lockstep DELETES this entire layer. Do not build it until that
> is settled. The rest of this section stands and is the right design if D2 is kept.

The user's own framing is the best argument for it: *"90% of what moves or shoots is very
predictable. Player commands are rare and creeps are not commandable anyway."*

Sending spawn events plus velocity instead of every unit's position 20×/second collapses
bandwidth **and** decouples the visual rate from the simulation rate — which removes the main
objection to a lower movement tick (§4.1), because clients would draw smooth motion regardless
of how often the server actually moves anything. This is `multiplayer.md` 3.3 and D17.

### 4.4 Client-side instantiation burst — never measured

`ReplicationService._apply_units` instantiates **every unseen unit in one frame**, with no budget
or spreading, and a creep prefab is 40–52 nodes. A wave of 20 creeps is ~1,000 nodes in one
frame, on every client at the same instant. This was a competing explanation for the original
stutter, was never separately measured, and is **not ruled out**. Measure before assuming the
server fixes cover the client.

### 4.5 The GDExtension question — evidence, not opinion

The user asked whether the server should be rewritten in C++. **The answer so far is: not yet,
and the evidence is on the record.** Roughly 3× came out of four mechanical GDScript changes
with no cost to readability — the tick was doing avoidable work, not sitting on a language
floor.

What remains after that is many small operations each costing microseconds (a `global_position`
write at 12.9 µs, step maths, slide tests). *That* is the GDScript per-operation tax, and it is
real. So if another large multiple is needed after §4.1–4.3:

- **A GDExtension used by BOTH client and server** is the shape. One implementation, so D3
  ("one copy of the simulation, shared by client and server") survives.
- **A separate C++ server is NOT.** It would mean two implementations of the same simulation
  that must agree bit-for-bit forever — a desync factory, in a language the user does not read.
- C# is the middle rung: ~5–10× faster than GDScript, far more learnable, same "shared by both
  sides" requirement, and it complicates the Linux deployment (needs the .NET runtime).

---

## 5. Traps that cost time on 2026-09-03

### 5.1 `towers=0` in the bench means FILL THE MAZE

Zero is `PerfBench`'s sentinel for "densest legal layout" — it produces **390 towers per area**,
the opposite of what it reads like. There is no way to ask for a creeps-only world. Cost a run.

### 5.2 `est_targeting_ms_per_tick` is an assumption, not a measurement

It is `one_search × towers × lanes` (`PerfProbes._estimate`), which assumes **every tower
searches every tick**. That holds for a full maze where most towers have nothing in range. It is
false in a lane packed with creeps, where a tower holds a target and `AttackComponent` never
reaches the search. It over-reported targeting by **6×** and sent the investigation down the
wrong path for an hour. Measure by varying tower count instead.

### 5.3 Never stop `ltw-server` while anybody is playing

The bench needs exclusive CPU, so it stops the service. Doing that mid-match makes
`Net.is_online()` false on every client, and `MatchSession.is_authority()` is
`!Net.is_online() || Net.is_server()` — so **each client silently becomes its own authority and
carries on playing a private game**. It looks exactly like a replication bug. Check for
connected peers first, or ask.

> **This is also a real design issue worth fixing.** Given D13 (no reconnect, out is out), a
> client that loses the server should stop and say so, not play on in a world nobody shares. It
> is the most confusing possible failure mode. Not yet written up anywhere but here.

### 5.4 Hand-staged files diverge silently

Copying files to the server by `scp` is fine for measuring, but the moment the user plays, the
client and server can be running different code. This produced a "cheats checkbox unticks
itself" bug that looked like a UI fault and was actually the server's `MatchSettings.from_dict`
dropping a key it had never heard of. **`from_dict` defaults are deliberately forgiving, which
makes version skew silent.** Deploy from git before testing anything.

### 5.5 A new script in an existing folder needs `--import`

Already in `CLAUDE.md`, hit twice anyway. `godot --path . --headless --import` after adding any
file with a `class_name`.

### 5.6 Three hypotheses that were tested and are WRONG — do not redo them

- **Pathfinding replans.** `_replan` fired **zero** times in a loaded lane. Counting it is what
  ruled it out.
- **Physics interpolation on a headless server.** Turning it off changed nothing.
- **Visual nodes the server never draws.** Stripped 8,400 mesh nodes (12,232 → 3,958 total, 3×
  fewer); **no improvement.** Godot dirties child transforms lazily and nothing headless ever
  reads them. Stripping models on the server is still worth doing for memory and spawn cost, but
  it will not help the tick.

---

## 6. How to measure

The harness is `Scenes/Tools/perf_bench.tscn` + `Scripts/Tools/PerfBench.gd` +
`Scripts/Tools/PerfProbes.gd`, driven by `Tools/run_bench.ps1`. It reports p50/p95/**max** —
variance is what matters for stutter, not the average.

**Run it on the SERVER, not the dev PC.** The rented box is materially slower than a desktop,
and the 2026-08-29 performance work was validated on hardware nobody plays against. Stop the
service first (and see §5.3):

```bash
ssh root@<server> 'systemctl stop ltw-server'
ssh root@<server> 'HOME=/root /opt/godot/godot --path /srv/ltw/LTW_Test --headless \
  res://Scenes/Tools/perf_bench.tscn -- scene=server players=2 creeps=96 towers=45 \
  tower=fire_greater_firelord_stats creep=ancient_wendigo_stats seconds=15'
ssh root@<server> 'systemctl start ltw-server'
```

That command is **the reported scenario** and the one to compare against: 45 Firelords, 96
Ancient Wendigo. Baseline after 2026-09-03: p50 29.91, p95 48.13, max 93.36.

`run_bench.ps1` gained `1v1-fewtowers` and `client-fewtowers` — the few-towers/many-creeps shape
the matrix had never covered, and the shape the stutter was actually reported in.

**To profile inside a tick again**, the approach that worked: a temporary static accumulator
under `Scripts/Dev`, called from a *copy* of the hot function so the shipping path pays only a
bool check, gated on an environment variable, printing every N ticks. Delete it afterwards —
`Scripts/Dev` is scaffolding. Do **not** measure by re-calling functions from a probe and
multiplying; that is what §5.2 got wrong.

---

## 7. Loose ends not related to performance

- **Two correctness checks never confirmed by a human**: that creep **auras still apply**
  (fixes 3–4 touched that path), and that **tower placement still works** (fix 2 changed
  `world_to_internal_cell`, which `can_place` uses). Both are believed fine; neither was
  verified in a real match.
- **Cheat #4 (load saved layout) does not work.** Reported, not investigated.
- **Income countdown UI is frozen on clients.** `_income_elapsed` only advances on the
  authority, so `seconds_until_income()` returns the full interval forever. Gold arrives
  normally — it is cosmetic. The fix is one float in the snapshot, and it is **one shared clock**
  (`PlayerManager`'s own comment says so), not one per player.
- **A third instance of the same class of bug** as the income timer and the skeleton revive:
  authority-only state that presentation reads and nobody replicates. Worth a sweep rather than
  three more one-off fixes. Single-player hides all of them, because there the client *is* the
  authority.
