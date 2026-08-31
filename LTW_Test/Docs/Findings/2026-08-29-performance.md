# Performance: what a full match costs — 2026-08-29

First load test of the simulation and the renderer, and the four fixes that came out of it.

**These numbers are a snapshot.** One machine, one day, Godot 4.7.2, `gl_compatibility`,
placeholder art. They are here because a finding is dated and nothing else in `Docs/` may
carry a live value — see [README.md](README.md). Do not copy them anywhere. To get current
numbers, run the tool.

## The question

How many towers and creeps can the game hold before it stops keeping up, and where does the
time actually go? Ten players was the target, since that is what the map has slots for.

## How it was measured

`.\Tools\run_bench.ps1` — the whole matrix, one Godot process per scenario, JSON per scenario
into `Reports/` (gitignored).

| Piece | Where |
| --- | --- |
| Harness | `Scripts/Tools/PerfBench.gd` |
| Per-loop probes | `Scripts/Tools/PerfProbes.gd` |
| Scene | `Scenes/Tools/perf_bench.tscn` |
| Driver | `Tools/run_bench.ps1` |

It fills every player's maze serpentine-dense through `Builder`'s own placement path, holds
every lane at the population cap, and times the tick from `SceneTree.physics_frame` to the last
node processed. Then it times the individual scans on their own, so a slow tick names the loop
that spent it instead of only being slow. The client scenarios additionally report draw calls
and real CPU/GPU render time, with `shadows=off` and `shadow_distance=<n>` as diagnostics.

The world it builds is the legal maximum: the build zone filled to the densest layout that
still leaves a route, and every lane at `population_cap`.

## What was found

Budget is one tick at the rate in `project.godot`. Every figure is `tick_ms avg`.

| Scenario | Towers | Creeps | Units | Before | After |
| --- | --- | --- | --- | --- | --- |
| 1v1, towers only | 390 | 0 | 398 | 3.46 ms | 2.44 ms |
| **1v1, full** | 390 | 200 | 598 | **121.60 ms** | **29.66 ms** |
| 10 players, towers only | 1950 | 0 | 1990 | 14.99 ms | 12.47 ms |
| **10 players, full** | 1950 | 1000 | 2990 | **620.31 ms** | **152.63 ms** |
| 10 players, full, archers only | 1950 | ~1000 | 2159 | 476.07 ms | — |

Three things that mattered more than expected:

**A 1v1 was already over budget.** This was never a ten-player problem waiting in the future;
the two-player game missed the tick by well over double the moment both lanes were full.

**Creeps, not towers.** 1950 towers on an empty field cost 15 ms. The same field with creeps in
it cost 620. Towers are close to free; what is expensive is the per-creep work every tower does.

**Not the elemental roster.** Swapping the tower mix for plain archers saved about a quarter.
The cost was structural, so the fancy abilities were never the thing to look at.

### Where the tick went (per-call, at a full lane)

| Loop | Cost | Notes |
| --- | --- | --- |
| `TargetFinder.best_target` | 333 µs | The dominant cost by a wide margin |
| `Creep._separation` | ~116 µs | Pairwise over the lane |
| creep aura scan | ~80 µs | Four times a second, not every tick |
| `Replication._build_snapshot` | 1.7 ms at 398 units, 10.9 ms at 2990 | Also 178 KB per snapshot at 2990 units → ~3.5 MB/s **per client** |
| `PlayerManager.population_for` | 141 µs at 398 units, 2.2 ms at 2990 | Sorts every unit id per call |
| `MatchSession.live_units` | 41 µs at 398 units, 460 µs at 2990 | The minimap builds this **every render frame** |
| `PlayerArea.can_place` | ~6 µs | Flood fill; per render frame while a build ghost is armed |
| `PlayerArea._rebuild_flow_field` | ~190 µs | Per placement and per sale |

Targeting dominated for a reason that is worth keeping in mind: a tower with nothing in range
never fires, so its cooldown never starts, so the existing "only search when the cooldown is
ready" throttle never applied to it. It searched the whole lane every tick, all match, and found
nothing every time. Most of a full maze is in that state at any moment, so **the cost was
overwhelmingly failed searches, not successful ones.**

### Rendering

Client scene, 1v1, camera on one lane. `render_cpu` / `render_gpu` are the renderer's own
measurements, not script time.

| | Draw calls | Primitives | Render CPU | Render GPU |
| --- | --- | --- | --- | --- |
| As it was | 26,970 | 1.01 M | 14.19 ms | 14.26 ms |
| Shadow distance trimmed | 12,717 | 0.48 M | 8.33 ms | 8.38 ms |
| Shadows off | 2,952 | 0.11 M | 4.03 ms | 4.27 ms |

Ten players, same three states: 71,621 draws / 40.6 ms → 13,595 / 13.8 ms → (not measured).

Two causes, and the first was a settings bug rather than a cost of shadows:

**The sun's cast distance covered the whole map.** `directional_shadow_max_distance` sat at
Godot's default, which reaches past the far edge of a twelve-lane map, so every shadow cascade
redrew all twelve lanes to light the one the camera was pointed at. Shadows were ~89% of the
draw calls.

**Nothing is instanced.** A tower model is 3–39 separate `MeshInstance3D` nodes; a creep model
is 40–52. So a creep costs roughly five times a tower to draw and there are more of them — at
the population cap, one lane's creeps alone are four to five thousand mesh instances.

CPU and GPU render times track each other almost exactly, which is the signature of being
draw-call bound rather than fill or shader bound. A faster GPU would not have helped much.

## What was changed

| Change | Where |
| --- | --- |
| Creep separation runs for **attacker creeps only**, and is skipped without a call for everything else | `GameConfig.creep_separation_limit` / `attacker_separation_limit`, `Creep._crowding_push` |
| Target search walks the lane **once** instead of two to four times | `TargetFinder._scan` |
| `PlayerArea` keeps a **signal-maintained creep list** instead of `get_children()` per call | `PlayerArea.creeps()` |
| A search that finds nothing **waits a few ticks**, phase-staggered by unit id | `GameConfig.idle_target_scan_ticks`, `AttackComponent._next_scan_wait` |
| Sun casts shadows only as far as the camera sees, plus a **player-facing off switch** | `SunLight`, `UserSettings.shadows_enabled` |
| Snapshot really does run after the match scene | `ReplicationService` — see Traps |

The separation change is a rule change and is written up in `game_rules.md`. The scan wait is
the only one with a gameplay cost: a creep entering range is noticed up to
`idle_target_scan_ticks` ticks late. A tower that has a target, or is on cooldown, is
unaffected — and the wait is cleared outright whenever the answer could have changed (target
lost, target died, Prioritize toggled), so no player action is ever delayed by it.

## Still open

Roughly in order of value per unit of work.

1. **A spatial hash per `PlayerArea`.** Targeting is still the largest single cost, and the
   creep aura scan has the same shape. One structure fixes both, and puts separation back
   within reach if it is ever wanted for the whole roster. This is the big one.
2. **Target acquisition on the client.** `AttackComponent` asks `is_authority()` nowhere, so
   every client runs the full search for every tower in every lane — a server's simulation bill
   paid to point barrels, most of them in lanes nobody is looking at. Only the damage is gated
   (`Unit.take_damage`), so this is presentation, not a correctness bug. The fix is not a gate
   on its own — a gated client would draw nothing — but the server naming what each tower fired
   at, which is the same spawn-event shape replication phase B wants. Recorded in
   `multiplayer.md`'s accepted-costs table.
3. **Snapshot size.** The whole world, every unit, every tick. Already `multiplayer.md` phase B;
   now there is a measured number behind it.
4. **`population_for` and `live_units`.** Both walk every unit in the match, the first sorting
   as it goes, and the minimap calls the second every render frame. Cheap to fix, small win.
5. **`TargetFinder.buildings_in_radius` and `_nearest_building`** still call
   `area.get_children()` in their loops. Towers are static and these run far less often, so it
   was left alone — but it is the same fix as the creep cache.
6. **Instancing or mesh merging.** Deliberately NOT done. All of this is placeholder art and
   real models would change every render number above. When it is wanted, it belongs in
   `Tools/ModelGen` rather than in hundreds of scenes, since the placeholders are the same
   primitives repeated — the ideal `MultiMesh` case.

## Traps

Both cost time here and are general enough to have been written into `../../CLAUDE.md` as well.

**`process_priority` does not order `_physics_process`.** Godot 4.3 split the two: it orders the
render frame, and `process_physics_priority` orders the tick. A node setting only the first and
expecting to run last in the tick runs in plain tree order instead. `ReplicationService` had
exactly this, which meant the snapshot described the previous tick — the thing its own comment
said it must not do. Found because the bench hit it first and reported an entire world as
costing thirty microseconds a tick.

**A new script in an EXISTING folder is not imported by a `--path` run.** A new folder is
scanned; a new file dropped into a folder Godot already knows is not. Its `class_name` never
reaches the global class cache, and every script referencing it fails to parse with
"Identifier not declared in the current scope" — which reads exactly like a typo.
`godot --path <project> --headless --import` fixes it.
