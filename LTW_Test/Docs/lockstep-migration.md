# Lockstep migration — plan and session handover

**Written 2026-09-04 for a context reset and a machine swap.** Two things in one file on
purpose: what state the work is in, and what the next session does. **This is a LIVING
document — delete it when the migration lands or is abandoned.**

The DECISION and its reasoning are not here. They are `multiplayer.md` §4.1 (D2 under review)
and D31. Read those first; this file assumes them.

---

## 0. START HERE — for a session picking this up cold

**Your task is §3.1, then §3.2, then §3.3. In that order. Do not start §3.4.**
§3.4 is the cutover and needs the user watching, because none of it can be verified by running
it once. If you finish 3.1–3.3, stop and report rather than continuing.

**Read before touching anything:** `CLAUDE.md`, then `multiplayer.md` §4.1 and D31, then §1–§2
below. `game_rules.md` only if a triage question turns on a rule.

**First three commands, in order:**

```powershell
.\Tools\deploy_server.ps1 -Check   # what is deployed, and is the tree clean
git log --oneline -3               # has the user committed since this was written
.\Tools\stop_server.ps1 -List      # a local server up for hours is running OLD code
```

**Five things that cost this project real time. None is optional.**

1. **`git checkout -- <file>` can destroy another agent's uncommitted work.** More than one
   agent works in this tree. To undo your own edit to a shared file, COPY IT ASIDE FIRST and
   restore from that copy. Check `git status` before assuming a file is yours.
2. **A long-lived local server runs the code it PARSED AT BOOT.** Every pull or edit since then
   has moved the files out from under it. Restart it after any change. `stop_server.ps1 -List`
   prints uptime for exactly this reason.
3. **Measure PAIRED.** This hardware varies ±20% run to run, so a single before/after across two
   deploys proves nothing. Same commit, flip one variable in place, alternate runs.
4. **A profile of anything that WRITES is a profile of the platform.** The log fix measured 2.1×
   on the Windows dev PC and 7% on the Linux server. Never quote a dev-PC number for I/O.
5. **Writing to the public server is refused by tooling permissions.** Read-only `ssh` works;
   `scp`, `sed -i` and `systemctl` on the server do not. `deploy_server.ps1 -Restart` does work.
   Hand server-side changes to the user rather than fighting it.

**Definition of done for this session:** §6 filled in, the §3.2 changes applied and verified,
the §3.3 harness working and demonstrated, and a report saying which §3.1 items were judged
HARD. Everything left uncommitted for the user to read — **never commit, never push** (`CLAUDE.md`).

---

## 1. State of play

### 1.1 What is deployed

The public server runs `c4dbe375`. `.\Tools\deploy_server.ps1 -Check` is the authority on this
and should be the first thing run in a new session.

### 1.2 What is NOT committed

**Two agents have been working in this tree.** At the time of writing, ~33 modified files:

- **Another agent's gameplay work** — a leak-log UI (`Scripts/UI/LeakLog.gd`,
  `LeakMessage.gd`, two scenes), plus edits to `ReplicationService.gd` (+71),
  `Creep.gd`, `Unit.gd`, several tower passives and stats. **Not mine, do not revert it.**
- **This session's work** — see §1.3.

**The hazard this creates, and it has already bitten once:** `git checkout -- <file>` on a
shared file destroys the other agent's uncommitted work. When instrumenting a file that both
agents touch, COPY IT ASIDE FIRST and restore from that copy, never from git.

### 1.3 What this session changed

| Area | Change |
| --- | --- |
| `Creep`, `PlayerArea`, `SendBuilding` | six per-creep `Log.info` → `Log.debug` |
| `Building` | full-health guard on `_regenerate`, early-out in `_advance_passives` |
| `PlayerArea` | route cache on `route_to_exit`, cleared by `_set_footprint` |
| `NetworkService` | **@rpc surface hash in the handshake (D31)** |
| `LobbyBrowser`, `MenuConfig` | timeout so a silent lobby request says so |
| `Tools/stop_server.ps1` | server uptime + staleness warning |
| Docs | `Findings/2026-09-04-...md`, `CLAUDE.md` log rule, `multiplayer.md` §4.1 + D31, `server.md` |

### 1.4 Do this first, next session

1. **`deploy_server.ps1 -Check`** — know what is deployed before anything else.
2. **The D31 handshake change is a PROTOCOL BREAK and both sides must go together.** It changes
   the arity of `state_protocol_version` / `refuse_protocol_version`. Deploying the server
   without updating clients (or the reverse) gives one confusing error on the first connect.
   Deliberate: an arity change fails loudly on the handshake method itself rather than silently
   shifting every other rpc index. Commit, push, deploy, and use a fresh client.
3. **The live refusal path was never tested end-to-end** — a client only dials out when the
   lobby browser opens, which cannot be driven headlessly. The hash itself IS tested (adding one
   `@rpc` moved it, reverting restored it). Worth one manual check: run a client against a server
   built from different code and confirm the message rather than an error.

---

## 2. What already exists that lockstep needs

Better than expected. Do not rebuild these.

- **`WorldChecksum`** (`Scripts/Game/WorldChecksum.gd`) already exists and is already reported
  at match start via `MatchStart.report_world_checksum` (`Main.gd:116`). Today it verifies the
  INITIAL world. Lockstep needs the same thing every N turns; that is an extension, not a build.
- **A fixed 20 Hz tick**, and every gameplay loop already in `_physics_process`.
- **No physics engine** (D1) — the single largest source of cross-machine drift, absent by rule.
- **A seeded match RNG** — `MatchSession.match_rng()`.
- **Commands already routed through the server** — `Commands.submit()`. Lockstep changes where
  that command goes, not the fact that it is a command.
- **One codebase for client and server** (D3), which lockstep needs and already holds.
- **`MatchSession.gd:438`** already carries a comment about dictionary order and checksums, so
  the problem has been thought about at least once.

**Counted, not yet triaged** (this is §3.1's job):

| Hazard | Count in `Scripts/{Game,Units,Combat,Abilities}` |
| --- | ---: |
| `Dictionary` declarations | 32 |
| `get_children()` calls | 15 |
| `rand*` outside the match RNG (whole `Scripts/`) | 25 |
| `Time.get_*` / `OS.get_ticks` in simulation code | **0** |

That last row is the good news: the hazard that is usually everywhere is already absent.

---

## 3. The migration, split by what needs a human present

**The split is the point of this plan.** Determinism hardening is separable from the model
switch, is most of the work, and is independently verifiable — so it can be done alone. The
cutover cannot.

### 3.1 Alone — the inventory

**Goal: a table in §6 with one row per hazard, and a count of the HARD ones.** That count is
what makes the lockstep decision real rather than a guess, and it is the gate §4.1 names.

**Where to look.** The simulation is `Scripts/{Game,Units,Combat,Abilities}` plus
`Scripts/Multiplayer`. `Scripts/UI`, `Scripts/Input` and `Scripts/Components` are presentation
unless something there writes gameplay state — check rather than assume, and note it if so.

Starting greps (counts as of 2026-09-04 in §2; re-run them, they will have moved):

```bash
grep -rn "Dictionary = {}" --include=*.gd Scripts/Game/ Scripts/Units/ Scripts/Combat/ Scripts/Abilities/
grep -rn "for .* in .*:" --include=*.gd Scripts/ | grep -iE "\.keys\(\)|dict|_of_|_by_"
grep -rn "get_children()" --include=*.gd Scripts/
grep -rn "randf()\|randi()\|randf_range\|randi_range\|shuffle()\|pick_random" --include=*.gd Scripts/
grep -rn "Time\.get_\|OS\.get_ticks\|Engine\.get_frames" --include=*.gd Scripts/
```

**Triage each hit into exactly one of:**

| Verdict | Means | Action |
| --- | --- | --- |
| **SAFE** | cannot reach a gameplay result — a Dictionary only ever keyed and read, never iterated; a roll behind `is_local_only()`; UI only | none, but say WHY in the row |
| **PRESENTATION** | reaches only what is drawn | none; add a one-line comment at the site so the next reader does not re-triage it |
| **EASY** | reaches gameplay, and the fix is mechanical — sort the keys, iterate an Array, use `match_rng()` | fix in §3.2 |
| **HARD** | reaches gameplay and the fix needs a design decision, or is not obviously behaviour-preserving | **do not fix.** Write down what makes it hard and leave it for the user |

**A Dictionary is only a hazard when it is ITERATED and the order can change an outcome.**
Iterating to sum a value is fine — addition commutes. Iterating to pick a target, break a tie,
or apply the first match is not. Read what the loop DOES before writing a row.

**The 25 `rand*` hits outside `match_rng()` are the highest-value part of this**, and most are
probably presentation. Each one that turns out to be gameplay is a real desync in waiting.

### 3.2 Alone — determinism hardening

> **DONE 2026-09-04.** There was one EASY row and no HARD ones, so this was small. What was
> changed:
>
> - **`StatusEffects.move_ratio`** now sorts the chill keys before multiplying them together.
>   Float multiplication is not associative, so how slowed a creep is depended on a
>   Dictionary's iteration order. Guarded on `size() < 2`, because this runs for every creep
>   on every tick and most creeps carry no chill at all — without the guard it allocates an
>   array per creep per tick to sort nothing.
> - **Four tie-break sites given the comment they were missing**: `TargetFinder._scan` and
>   `_nearest_building`, `DevourEssencePassive` and `VoidSpreadPassive`. None is a bug — each
>   is correct because the collection feeding it is ordered by construction — but none said
>   so, and all four break silently if anything ever reorders creeps or an area's children.
>   `_scan` now names the whole chain it depends on.
>
> **Acceptance met**: `creeps_spawned` was 1324 before and 1324 after, on the same seed and
> scenario. Tick timings moved around inside the ±20% noise band and no perf claim is made
> either way.

**Fix only the EASY rows. Leave every HARD row alone** and report it.

Every one of these is correct under the CURRENT architecture too, so none is a bet on lockstep
and none needs the model to change first:

- iterate sorted keys, or an Array, wherever iteration order can reach a gameplay result;
- replace `get_children()` order dependencies with the registries that already exist —
  `PlayerArea.creeps()`, `MatchSession`'s unit registry — where order matters;
- route every gameplay roll through `MatchSession.match_rng()`, and leave presentation rolls
  alone with a comment saying that is what they are;
- anything time-based becomes tick-based.

**Verify after each group of changes, not at the end:**

```powershell
# $GODOT is YOUR Godot 4.7 binary - the two dev machines keep it in different
# places and under different names, so do not paste a path from this file.
& $GODOT --path . --headless --import   # must parse clean
& $GODOT --path . --headless res://Scenes/Tools/perf_bench.tscn -- scene=server players=2 creeps=120 towers=0 seconds=20
```

**Acceptance: `creeps_spawned` unchanged from the run before your change.** Same seed, same
scenario, same number of creeps through the same maze — that is the cheap proof that gameplay
did not move. It is what proved the route cache safe on 2026-09-04. A changed count means you
altered behaviour; find out why before continuing.

### 3.3 Alone — the proof harness

> **DONE 2026-09-04.** `Scripts/Tools/DeterminismBench.gd` +
> `Scenes/Tools/determinism_bench.tscn` — in `Tools`, beside `PerfBench`, because the user
> chose to KEEP it. `Scripts/Dev` is the folder that gets deleted; this is not in it.
>
> ```powershell
> # record a run, then record it again from the same seed
> & $GODOT --path . --headless res://Scenes/Tools/determinism_bench.tscn -- seed=7 players=2 ticks=300 every=10 out=user://det_a.json
> & $GODOT --path . --headless res://Scenes/Tools/determinism_bench.tscn -- seed=7 players=2 ticks=300 every=10 out=user://det_b.json
> # replay A's RECORDED COMMANDS into a fresh match
> & $GODOT --path . --headless res://Scenes/Tools/determinism_bench.tscn -- replay=user://det_a.json ticks=300 every=10 out=user://det_r.json
> # and ask where, if anywhere, two runs first differ
> & $GODOT --path . --headless res://Scenes/Tools/determinism_bench.tscn -- compare=user://det_a.json,user://det_b.json
> ```
>
> **Demonstrated, all three ways round:**
>
> | Test | Result |
> | --- | --- |
> | record twice, same seed, 300 ticks | `IDENTICAL across 31 samples` |
> | replay A's 102 recorded commands into a fresh match | `IDENTICAL across 31 samples` |
> | same seed, 800 ticks | `IDENTICAL across 81 samples` |
> | **one creep moved 1mm at tick 170** | **`DIVERGED first at tick 170`** |
>
> The last row is the one that matters: a checker that has only ever been seen to pass is not
> evidence. `perturb=<tick>` exists to make it fail on demand.
>
> **`WorldChecksum` WAS then widened, on the user's call (2026-09-04).** It covered identity
> and position but not health or gold, so a desync that moved only a creep's health was
> invisible to it — which was right for the job it had (one comparison at match start, where
> nothing has happened yet and health and gold are implied by the config it already hashes)
> and wrong for the job lockstep gives it. It now also carries each unit's current and maximum
> health, and each player's gold, income and lives in slot order via the new
> `PlayerManager.states_in_slot_order()`.
>
> Free today, because it still runs exactly once per match and only when networked. The cost
> to watch is under lockstep, where it would run every N turns: the expensive part is building
> a string per unit and hashing the join, NOT the two extra numbers per entry. If it ever
> needs to be cheap, replace the string join with a rolling integer hash rather than trimming
> what it covers.
>
> **MANA is still deliberately absent**, and that one is not laziness: it lives on `Building`
> and `Creep` rather than on `Unit`, so reaching it needs a cast — and a cast on exactly this
> kind of walk is what silently kept three whole systems off the wire once already
> (`CLAUDE.md`, known weaknesses). It wants a virtual on `Unit` first, the way
> `status_entries()` had to become one.
>
> The harness still takes a second `deep` sample of its own, which now overlaps the widened
> `WorldChecksum` almost entirely. Kept as a cross-check: two independently written hashes
> disagreeing about whether two worlds match would itself be worth knowing.
>
> **What it does NOT prove.** Two runs of the same binary on one machine. That covers the
> whole iteration-order and unseeded-randomness family — which is what §6 inventoried — and
> covers nothing about cross-machine float divergence. The next step up is two different
> machines running `replay=` against the same trace and comparing; the harness already
> supports it, and it has not been done.
>
> **Two traps it paid for, both worth knowing before extending it:**
>
> - **The driver must not draw from `MatchSession.match_rng()`.** It did at first. Record
>   generates its command stream and replay does not, so the two consumed a different number
>   of rolls and every gameplay roll afterwards got a different number — the replay diverged
>   from its own recording, entirely because of the test.
> - **`Command.to_dict()` is the WIRE format and does not survive JSON.** Godot sends a
>   `Vector3` as twelve bytes; `JSON.stringify` turns it into the string `"(0, 0, 0)"`, and
>   `from_dict` then hands back something unusable. The replay ran, raised nothing, injected
>   nothing, and read exactly like a determinism failure at the first sampled tick. The trace
>   is a file format and carries its own encoding.

**Without this there is no way to know determinism holds**, and a desync in a real match is
unreproducible from a bug report. Build it before the cutover, not after.

Shape:

- record every `Commands.submit()` — tick number and payload — to a file;
- replay that file into a fresh match from the same `MatchSetup` and the same RNG seed;
- compare `WorldChecksum.of(...)` at the end, and ideally every N ticks so a divergence is
  located rather than merely detected;
- report the first tick at which the two differ.

`WorldChecksum` already exists (`Scripts/Game/WorldChecksum.gd`) and is already used at match
start from `Main.gd:116` — extend it, do not rebuild it. If it does not currently cover
something a desync would move (creep health, positions, gold), say so rather than quietly
widening it.

Live in `Scripts/Dev` per `CLAUDE.md`. **`Scripts/Dev` is scaffolding that gets deleted** — but
this one is the exception worth arguing for keeping, so flag it to the user rather than
deciding alone.

**Demonstrate it works**: replay the same log twice and show the checksums match, then perturb
one value and show it reports the right tick. A harness nobody has seen fail is not evidence.

### 3.4 TOGETHER — the cutover

Not to be done unsupervised, because none of it can be verified by running it once:

- turn scheduling and input delay — feel-dependent, needs a human looking at it;
- `Commands.submit()` broadcasting the turn's command set instead of executing server-side;
- every `if !MatchSession.is_authority(): return` gate — the inversion of `CLAUDE.md`'s hardest
  rule, and it touches essentially every gameplay loop;
- deleting `ReplicationService` and everything that reads a snapshot;
- per-turn checksum comparison and what a desync DOES when detected.

---

## 4. What lockstep does and does not buy — carry this forward

Measured, not assumed. Do not let the next session re-argue it from first principles.

**It buys**: the binding constraint moves off the 6€ rented box and onto player hardware, which
is roughly 3× faster per core — and it scales with players' machines rather than with hosting
spend. `ReplicationService` and all of §3.3/phase B are deleted, along with the whole family of
bugs that exists only because there is a replication boundary. No interpolation seam.

**It does NOT buy**: a cheaper simulation. Every client simulates every lane, so the work is
duplicated rather than reduced, and the match runs at the speed of the SLOWEST peer. **The
per-unit cost still has to come down**, and minimum spec becomes the constraint instead of the
server. For a 1v1 this is comfortable; for twelve players it is worse than today unless the
per-creep cost drops.

**The security premium D2 was paying is near zero for THIS game** — there is no fog of war and
no hidden information in `game_rules.md`, so the maphack lockstep enables buys nothing.

---

## 5. Where performance stands, so it is not re-derived

Full detail in `Findings/2026-09-03-server-tick-overrun.md`,
`Findings/2026-09-04-log-info-in-the-creep-tick.md` and
`Findings/2026-09-04-staggered-creep-movement.md` — which between them absorbed
`performance-handover.md`, deleted 2026-09-04. The short version:

- Server, creep-heavy 1v1 shape: **p50 ~34 ms, p95 ~53 ms** against a 50 ms budget. Median
  inside, tail still just over.
- A creep tick is ~49 µs, of which `move` ~21 and `aura` ~10. A tower is ~22 µs.
- Both ticks are attributed to a sub-1 µs residual. **There are no cheap wins left in them.**
- The spatial index is BUILT and used by targeting and every radius query. It is not a pending
  item, whatever older notes say.
- A spawn costs ~448 µs, now that the route is cached. Instantiation plus `add_child` is 81% of
  what remains — **stripping the `Visual` child on a headless server is the largest single item
  left on that path**, and is small.

**The measurement rule this all rests on:** this box varies ±20% run to run, so compare PAIRED —
same commit, one variable, alternating runs. And a profile of anything that writes output is a
profile of the PLATFORM: the log fix measured 2.1× on Windows and 7% on Linux.

---

## 6. The determinism inventory

**Filled in 2026-09-04 by §3.1.** A read-only pass over `Scripts/{Game,Units,Combat,
Abilities,Tech,Multiplayer}`. Kept in full, SAFE rows included, so the next reader does not
re-triage what has already been checked.

**Headline: the simulation is in far better determinism shape than §2 assumed.** One EASY
fix, no HARD ones. The hazard §3.1 expected to dominate — loose `rand*` calls — does not
exist.

### 6.1 RNG — clean

Every gameplay roll already goes through `MatchSession.match_rng()`. Each call site was read,
not merely counted.

| File:line | What | Verdict | Note |
| --- | --- | --- | --- |
| `BombardmentPassive:72`, `EtherealAuraPassive:44`, `SpawnOnDeathPassive:66`, `GerminatePassive:115`, `PressuringWaterPassive:102`, `VolcanicEruptionPassive:77`, `AttackHit:258`, `HitPattern:125`, `TowerBuffs:277`, `TechManager:278` | gameplay rolls | SAFE | all `MatchSession.match_rng()` |
| `AttackStats.roll_damage`, `PlayerArea.random_spawn_point`, `RNGUtil.*`, `StartingTech._rng` | take an `rng` PARAMETER | SAFE | every gameplay caller passes `match_rng()` — checked `AttackComponent:597`, `BombardmentPassive:85`, `Creep:2054`, `SendBuilding:512`. Only `PerfBench` passes anything else |
| `LobbyService:475`, `MatchSetup:50` | bare `randi()` | SAFE | this IS the match seed. It must be unpredictable, and it is then shared with every peer |
| `LobbyInfo._shuffle_lanes:120` | its own `RandomNumberGenerator` | SAFE | seeded FROM the match seed, server-only, and the RESULT is broadcast rather than re-rolled anywhere |
| `BountyPopup:81-83`, `LightningBolt3D:101-102` | bare `randf_range` | PRESENTATION | a floating gold number and a lightning squiggle. `LightningBolt3D` already documents itself as such |

### 6.2 Time — clean

| File:line | What | Verdict | Note |
| --- | --- | --- | --- |
| — | `Time.get_*` / `OS.get_ticks` / `Engine.get_frames` in simulation | SAFE | **zero.** The only hits are `SelectionController:434` (the double-click window, presentation), `ServerMain:63` (a log timestamp) and `Scripts/Dev/*` (probes) |

### 6.3 Dictionary iteration

| File:line | What | Verdict | Note / action |
| --- | --- | --- | --- |
| **`StatusEffects:316`** | `moving *= 1.0 - amount` over `_chills` | **EASY** | **The one real find.** Float multiplication is not associative, so the slow a creep carries depends on the order its chills are walked. Sort the keys — `_append_chills:951` in the same file already does exactly that, so the fix matches the file's own style |
| `StatusEffects:951,964` | `_append_chills` / `_append_grips` | SAFE | already `keys.sort()`, and this is the path that crosses the wire |
| `StatusEffects:891,1110,1135,1153` | halve / advance / expire | SAFE | each entry advanced independently; erase order cannot matter |
| `TowerBuffs:289`, `TowerStatus:143` | timer decrement + expire | SAFE | same shape |
| `PlayerArea:353` | `_rubble` countdown | SAFE | same shape |
| `PlayerManager:444,452` | `_states` — income floor, pay income | SAFE | independent per player |
| `PlayerManager:298` | `value_for` sums `invested_gold` | SAFE | INTEGER addition, which commutes exactly |
| `Building:438` | `inherit_ability_state` copies a dict | SAFE | key-for-key copy |
| `CreepWarding:95` | `_worst_type` picks a maximum | SAFE | **already carries an explicit tie-break** (`key < best`). Somebody thought about this one |
| `SendBuilding:169,193,231` | `_stocks` | SAFE | `stock_entries` is self-describing by `unit_type_id`, so the reader keys by id rather than by position |
| `MatchSession:429` | `live_units()`, unordered | SAFE | only `Minimap` and `PerfProbes` call it, and its docstring already says why it does not sort |
| `WorldChecksum:66,91` | the checksum itself | SAFE | sorts slots AND unit ids. **§3.3 rests on this and it is sound** |
| `UnitTypeRegistry:55`, `AbilityRegistry:87`, `TechRegistry:196` | boot validation | SAFE | log-only, and runs before a match exists |
| `UnitAbility:340` | placeholder substitution | PRESENTATION | builds a description string |

### 6.4 `get_children()` and collection order

| File:line | What | Verdict | Note / action |
| --- | --- | --- | --- |
| `PlayerManager:298`, `AncientBloomPassive:95` | sum / count | SAFE | integer accumulation |
| `LightBurstPassive:65` | heals everything in radius | SAFE | applied to all, and `heal()` clamps |
| `DiscUpgradeAbility:92` | returns true on the first match | SAFE | an existence test — a boolean cannot depend on order |
| `TowerLayout:64` | writes the layout file | SAFE | a developer cheat, and order affects only line order in the file |
| `CrashLightningPassive:93`, `TargetFinder:81` | append every match | SAFE | the SET is order-independent, and both feed callers that apply to all of it |
| **`TargetFinder._offer`** | targeting; ties go to the creep found FIRST | SAFE, **fragile** | fed by `creeps_near` → `CreepIndex.near`, which walks buckets over `range(min_x, max_x + 1)` and fills them from `PlayerArea._creeps`, an **Array**. So the order is deterministic by construction. It is also the hottest path in the game, and nothing states that dependency at the site |
| **`TargetFinder._nearest_building:228`** | first wins ties | SAFE, **fragile** | same class — depends on child order under the area, which follows the build commands |
| **`DevourEssencePassive:120`** | `distance <= best_distance`, so LAST wins ties | SAFE, **fragile** | same class |
| **`VoidSpreadPassive:77`** | ties on price AND distance fall to the first found | SAFE, **fragile** | same class, and the narrowest of the four |
| `PlayerArea:697` | seeds `_creeps` from the existing children | SAFE | feeds the order the four rows above depend on |
| `_rebuild_flow_field` | `_flow.build(...)` | SAFE | walks the blocking grid by index; no dictionary |

### 6.5 Summary

- **SAFE: the overwhelming majority · PRESENTATION: 3 · EASY: 1 · HARD: 0**
- **The HARD count is ZERO.** Nothing found needs a design decision to fix, and nothing found
  is other than obviously behaviour-preserving. On this axis, the lockstep rework is small.
- **The one EASY fix is `StatusEffects:316`**, and it is correct under the CURRENT
  architecture too: the server's own answer for how slowed a creep is should not depend on
  dictionary order either.

**The thing worth carrying forward is not a row, it is a CLASS.** Four sites resolve an exact
tie by taking whichever candidate was reached first, and all four are correct today only
because the collection feeding them happens to be ordered — an `Array` in spawn order, or
scene children in build order. Under lockstep every peer replays the same commands, so those
orders agree and so do the answers. **Nothing at any of those four sites says so.** A later
change that reorders creeps or buildings for an unrelated reason — a pooling scheme, a sort
for rendering, a spatial rebuild that walks a Dictionary — breaks all four silently and
produces a desync with no visible cause.

That is a comment-and-tie-break job rather than a bug, it is cheap, and it is the thing most
likely to be regretted if it is skipped. Recommended for §3.2 alongside the one EASY fix, and
it is what should be done FIRST if the budget is small.

### 6.6 Cross-machine maths — checked 2026-09-04, one item

Separate from everything above, because it is the axis a single machine cannot test.

**IEEE 754 exactly specifies `+`, `-`, `*`, `/` and `sqrt`**, so those are bit-identical on
every conforming machine and are not a risk. `length()`, `distance_to()` and `normalized()`
ride on `sqrt` and are safe with them - and most hot paths here use `length_squared()` anyway.

What the standard does NOT specify is the transcendentals - `sin`, `cos`, `atan2`, `pow`,
`exp`, `log` - which are library code and differ between platforms and CPU vendors. The whole
simulation contains seven such calls:

| Site | Verdict |
| --- | --- |
| `Projectile:129` arc, `GroundHazard:146` flicker, `AttackComponent:745` barrel, `AttackDelivery:76` effect facing | PRESENTATION - the arc is declared visual by `CLAUDE.md` |
| `MobileUnit:111,116` | writes only `rotation.y`. Presentation unless something gates an action on having finished turning - worth one check |
| **`CreepDive:92`** — `sin(PI * progress()) * _reach` | **the only one reaching a gameplay position.** The Phoenix dive arc |

**The Phoenix dive is being REWORKED anyway** (its current behaviour is not what LTW 12.4a
does), so this is not a fix to make now - it is a constraint on the rework: **whatever
replaces it should reach its position with multiplication rather than with `sin`.** A parabola,
`4x(1-x)`, has nearly the same shape and is IEEE-exact everywhere. A lookup table also works.
Recorded here so the constraint is not discovered after the rework instead of before it.

**Not triaged, deliberately:** `Scripts/Dev/` currently holds `CreepProbe.gd` and
`AttackerProbe.gd`, which use `Time.get_ticks_msec()`. That folder is scaffolding
(`CLAUDE.md`) and never ships, so it is out of scope — but it is worth knowing it is not
empty right now.

### 6.7 Per-machine INPUT — found in play 2026-09-04, one item

The axis section 6 did not have: not "do two machines compute the same answer", but **"do two
machines start from the same numbers"**. An order that reads anything belonging to the machine
it runs on — a file, a user:// path, an environment variable, a clock — feeds a different
input into an identical simulation, and lockstep has no way to notice until the checksum
turn.

| Site | What | Verdict |
| --- | --- | --- |
| **`CommandService._apply_cheat_load_layout`** | opened `GameConfig.cheat_layout_path` on every peer | **WAS BROKEN — fixed.** Only the presser has that file, so the other peer built nothing and the worlds parted on the turn the key was pressed. This is what "the layout cheat does nothing in multiplayer" was |
| `CommandService._apply_cheat_save_layout` | WROTE that path on every peer | **WAS WRONG — fixed.** Harmless to the simulation, since it changes nothing, but one player pressing save silently overwrote everybody else's saved maze |

The fix is the general one for this class and is worth copying rather than re-inventing: the
per-machine thing is read **where the key was pressed**, and travels inside the `Command`
(`Command.layout`, `TowerLayout.to_dict`). Every peer then runs the order over the same
numbers, which is what lockstep already assumes about every other order.

**Nothing else in the simulation reads a per-machine input**, which is why this axis has two
rows and both are the same cheat. It is listed anyway because the NEXT thing that wants to
read a file or a config on an order will look exactly as reasonable as this one did.

## 7. Out of scope — do not do these

Recorded so a session with time left does not helpfully wander into them.

- **The cutover (§3.4).** Needs the user present. This is the whole reason the plan is split.
- **Stripping the `Visual` child on a headless server.** Real and worth doing — it is the
  largest remaining item on the spawn path (§5) — but it is a PERFORMANCE change and would
  confound the determinism work. Separate session. Note it will not move the TICK, only
  memory and the spawn path: `Findings/2026-09-04-staggered-creep-movement.md` measured
  that.
- **Lowering the tick rate to 10 Hz.** Touches every timer and cooldown in the game, and its
  client-interpolation half is replication work lockstep would delete. Parked deliberately.
- **Bumping `protocol_version`, committing, pushing, or deploying.** Git is the user's
  (`CLAUDE.md`). The D31 handshake is already a pending protocol break; do not add a second one.
- **Touching `Resources/` balance values.** Nothing in this task needs a stat changed. If a
  determinism fix appears to require one, that is a HARD row, not an edit.
