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
& "$env:USERPROFILE\Desktop\Godot 4.7.1.exe" --path . --headless --import   # must parse clean
& "$env:USERPROFILE\Desktop\Godot 4.7.1.exe" --path . --headless res://Scenes/Tools/perf_bench.tscn -- scene=server players=2 creeps=120 towers=0 seconds=20
```

**Acceptance: `creeps_spawned` unchanged from the run before your change.** Same seed, same
scenario, same number of creeps through the same maze — that is the cheap proof that gameplay
did not move. It is what proved the route cache safe on 2026-09-04. A changed count means you
altered behaviour; find out why before continuing.

### 3.3 Alone — the proof harness

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

Full detail in `performance-handover.md` and
`Findings/2026-09-04-log-info-in-the-creep-tick.md`. The short version:

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

**EMPTY — this is §3.1's output. Fill it in.**

One row per hazard. Keep SAFE and PRESENTATION rows: their value is that the next reader does
not re-triage them, and "we checked, it is fine" is a result.

| File:line | What | Verdict | Note / action |
| --- | --- | --- | --- |
| | | | |

**Summary, once filled:**

- SAFE: _n_ · PRESENTATION: _n_ · EASY: _n_ · **HARD: _n_**
- **The HARD count is the answer to "how big is the lockstep rework".** State it plainly in the
  report, with one line per hard item saying what makes it hard.

---

## 7. Out of scope — do not do these

Recorded so a session with time left does not helpfully wander into them.

- **The cutover (§3.4).** Needs the user present. This is the whole reason the plan is split.
- **Stripping the `Visual` child on a headless server.** Real and worth doing — it is the
  largest remaining item on the spawn path (§5) — but it is a PERFORMANCE change and would
  confound the determinism work. Separate session.
- **Lowering the tick rate to 10 Hz.** Touches every timer and cooldown in the game, and its
  client-interpolation half is replication work lockstep would delete. Parked deliberately.
- **Bumping `protocol_version`, committing, pushing, or deploying.** Git is the user's
  (`CLAUDE.md`). The D31 handshake is already a pending protocol break; do not add a second one.
- **Touching `Resources/` balance values.** Nothing in this task needs a stat changed. If a
  determinism fix appears to require one, that is a HARD row, not an edit.
