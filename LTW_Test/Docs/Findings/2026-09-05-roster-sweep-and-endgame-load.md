# Sweeping the whole roster, and what an endgame maze really costs

**2026-09-05.** Windows dev PC, Godot 4.7.2, headless, commit `e60a404`. Everything below was
run from throwaway probes under `Scripts/Dev`, since deleted; each section names the probe so
it can be rebuilt.

## What was asked

Nobody has played most of this content. Check every tower, every disc and every creep, look for
interactions nobody meant, stress it at the player counts the lobby allows, and exercise the
networked build — before the first real test session.

## How it was measured

Five probes, all headless, all standing a real match up underneath themselves the way
`PerfBench` does — a `MatchSetup` parked in `MenuNavigation.pending_match` and the server match
scene instanced as a child. So what they drive is the shipping simulation, not a model of one.

**Buying wall clock without changing the tick.** Every probe that needed simulated time raised
`Engine.physics_ticks_per_second` and `Engine.time_scale` by the SAME factor.
`_physics_process` receives `time_scale / ticks_per_second`, so scaling both leaves the delta at
the game's own 0.05 s and only multiplies how many ticks a real second holds. Scaling
`time_scale` alone — the obvious thing — gives a 0.5 s tick instead, which is a different game.

The probes:

| Probe | What it did |
| --- | --- |
| `ContentAudit` | Loaded every `.tres` under `Resources/` and cross-checked ids, cards, upgrade chains, scene paths and attacks. Read-only. |
| `AbilityBench` | Stood each of the 111 towers and 31 discs alone in a lane for 30 simulated seconds against a held crowd of one creep type, and reported damage, status effects, mana and banked resources. Run three times: against a mid-tier ground creep, a weak ground creep so kills actually happen, and a flyer. |
| `DiscProbe` | Read each disc's boon straight off the neighbouring tower's `TowerBuffs` rather than inferring it from damage, so the six discs that change no damage are as testable as the two that do. |
| `CreepProbe` | Every creep walked an empty lane and then fought, reporting its DERIVED numbers — armour and health after its own passives, speed, shield, mana, dodge. |
| `InteractionProbe` | The cases a sweep cannot reach: every creep killed by hand so death passives fire, every attacker against a tower it outlasts, and two named interactions. |
| `StressBench` | Loaded the saved cheat layout into every lane and measured the tick, the way `PerfBench` does but with the maze a match really ends with. |
| `CheatProbe` | Each of the five developer cheats pressed through `Commands.submit_player_action`, the road `CheatController` takes. |
| `MpDriver` | A whole networked match per process against a real dedicated server: connect, lobby, start, play, report what lockstep saw. |

`MpDriver` is **not an autoload**, deliberately: `project.godot`'s `[autoload]` block cannot be
touched while the editor is open, and the driver has to survive the menu-to-match scene change.
It is added straight to the tree root by a boot shim, which is what an autoload is anyway. That
shape is worth reusing.

## What the content is

**Clean.** 381 abilities, 196 unit types and 30 technologies loaded, with no duplicate id, no
card with two entries fighting over one square, no null entry, no unresolvable scene path, and
no upgrade that costs less than what it upgrades from.

**Every tower's air/ground targeting matches `unit_data.md`** — 110 rows cross-checked
automatically against the doc's own Targets column, zero mismatches. And the dynamic sweep
agrees with the static one exactly: the 15 towers that did nothing to a flyer are precisely the
15 the file marks ground-only, and the 7 that did nothing to a ground creep are precisely the 7
marked air-only. Nothing in the roster can hurt neither.

**All 142 towers and discs ran 30 seconds each, three times over, with no script error and no
pushed error at all.** Nothing failed to stand up, nothing fell over, nothing logged.

Two loose ends, neither breaking anything:

- `cancel_order_ability.tres` (ability 127) is on no card the walk from the builder and the
  send buildings can reach.
- `DamageBlockPassive` is a complete, wired creep mechanic — `Creep._damage_block` sums it and
  `Unit.resolve_damage` applies it — that no `.tres` uses and `unit_data.md` never mentions.
  Either a creep is missing its trait or the class is dead.

## What the discs do

All thirty, read off `TowerBuffs.value_of` on a tower standing beside them rather than guessed
from a damage total. Every aura lends what its own text claims, and every tier scales:

- Earth +8 / +12 / +15% attack speed, Primal +0.75 / +1.5 / +2 cells of reach, Holy +3 / +6 / +8
  armour with regeneration flat past Advanced, Water 2 / 4 / 5.4 mana a second, Ice chill and
  cap, Unholy erosion, Lightning heal / return / stun, Void damage per distinct tower type.
- Both ON-STEP discs fire on a creep standing on them. Fire's detonation was checked
  numerically against a creep of known health and came out at exactly 20 / 24 / 33% of maximum,
  the three authored shares.

**The Primal stacking rule holds.** `unit_data.md` 5.2 flags "a weaker Primal disc must not
override the range bonus of a nearby stronger one" as a real implementation trap. Tried both
ways round — weak disc beating last and strong disc beating last — and the tower keeps +2 both
times. `TowerBuffs.grant` only lets a weaker value in once the stronger one has expired, which
is what makes it order-independent.

## What the creeps do

All 49 walk, fly or march, and their DERIVED numbers are right where a passive rewrites them:
the Behemoth's Abyssal Carapace converts nine tenths of 546,865 health into a 492,183-point
shield and leaves 54,687 on the bar; the Necromancer's Bone Shield turns its 5 armour into
health and reports 0 armour; the Huntress dodges 50% of anything reaching 8 cells or more;
Skittering and Ethereal read correctly on the four and one creeps that carry them.

Death passives were forced by hand, because the tanky half of the roster never dies in front of
a tower inside a test window — the Obsidian Statue has 1.1 million health. Killed outright with
Chaos, which no armour type in the table resists:

- Four creeps get back up: Death Revenant, Demon, Skeleton Warrior, Vengeful Spirit.
- The Obsidian Statue leaves three Ghouls where it fell.
- All four attackers — Corrupted Treant, Mountain Giant, Phoenix, Siege Engine — destroy a
  tower they are left alone with.

**One negative result that was not one.** The first creep sweep reported the Corrupted Treant
as "an attacker that never hurt the tower in front of it". It was standing in front of an
Ultimate Annihilation Glyph, which killed it before it swung. Against a Lesser Archer it flattens
the tower. A probe that never reaches the case looks exactly like a probe that disproved it.

## The interaction that is wrong: two Ultimate Orb Keepers

`unit_data.md` 4.9: Arc Lightning drops the tower's own maximum mana by 5 per cast, and when
that falls below 20 it resets to 100 and **lowers the maximum mana of other Ultimate Orb Keepers
within 150 AoE by 20**. `CrashLightningPassive._spend_ceiling` implements exactly that, and
`Building.set_max_mana` floors the result at zero.

Zero is absorbing. A tower at `max_mana == 0` can never be full (`has_full_mana` requires
`max_mana > 0`), so it can never cast, so it can never reach its own reset — and nothing else
in the game raises a ceiling. It is a dead ability for the rest of the match, with its mana bar
simply gone, because `secondary_resource()` returns null once `uses_mana()` is false.

Measured: two Ultimate Orb Keepers placed one cell apart, one of them fed and fired 400 times.
The one that fired ends at 55; **the one beside it ends at 0**. Five penalties do it, and the
victim only escapes by casting enough between them to bottom out and reset itself — so the
tower that gets bricked is the one with nothing in reach, which in a maze is the one behind.

Not fixed here: whether the source game floors it, and at what, is a balance question rather
than a code one. The cheap answer is a floor equal to `max_mana_floor` (20), which keeps the
anti-stacking penalty and removes the absorbing state.

## What twelve players actually costs

This is the headline, and it disagrees with what was on record.

`PerfBench` fills a serpentine maze out of the CHEAPEST tower of each line. That is the right
SHAPE and the wrong ROSTER: a match ends with Ultimates, and an Ultimate is the tier that
chains, splashes, carries an aura and leaves ground behind it. `StressBench` builds the saved
cheat layout instead — **181 buildings a lane: 150 Ultimates, 25 discs, 5 Obelisks** — through
`TowerLayout.restore`, and holds every lane at the population cap.

Server scene, headless, 20-second windows, budget 50 ms:

| Lanes | Towers | Creeps | tick p50 | tick p95 | p95 headroom |
| --- | --- | --- | --- | --- | --- |
| 2 | 362 | 200 | 17.2 | 27.2 | 1.84x |
| 6 | 1,086 | 600 | 52.0 | 78.2 | 0.64x |
| 10 | 1,810 | 1,000 | 85.3 | 130.5 | 0.38x |
| 12 | 2,172 | 1,200 | 102.5 | 157.2 | 0.32x |

Near enough linear at **8.6 ms per lane**, so the budget is crossed at about five lanes on the
median and under four on p95.

**The maze is not what costs it.** Twelve lanes of the same 2,172 towers with no creeps at all
runs at 16.9 ms p50. The creeps and what the towers do to them are effectively the whole tick.

The number on record — `CLAUDE.md`'s "a 1v1 has better than 2x headroom, twelve lanes is about
2x over" — came from the Lesser-tower mix and is optimistic for the endgame. With the real
maze, a 1v1 has 1.84x on p95 and twelve lanes is **3x over**, not 2x. Both remain true
statements about what they measured; they are measuring different mazes.

Under lockstep every client simulates every lane, so this is a client number as much as a
server one, and a dev PC is not slower than the rented box.

**The 1v1 milestone is not at risk.** Nothing above it is comfortable.

### The Obsidian Statue was three times an ordinary creep

Found by varying the creep rather than trusting the harness's own
`est_targeting_ms_per_tick`, which `CLAUDE.md` already warns is an assumption.

`AnnihilationAuraPassive` walked EVERY building in the lane on EVERY tick for EVERY Statue
alive, and re-applied a half-second debuff each time. Every other aura in the game runs on a
quarter-second beat; this one did not, and there is no reason in the code why not.

Paired, alternating, same commit, 12 lanes, 2,172 towers, one variable flipped in place:

| Creep filling the lanes | tick p50 |
| --- | --- |
| 100 Forest Trolls a lane | 101.8, 102.0 |
| 100 Obsidian Statues a lane | 299.2, 301.3 |
| 100 Obsidian Statues, with the beat | 170.5, 169.7 |

A Statue costs 3 population, though, so a hundred of them in a lane is three times what the cap
allows and the honest figure is at 33:

| 33 Obsidian Statues a lane | tick p50 |
| --- | --- |
| before | 118.8 |
| after | 94.2 |

**21% of the whole tick, at the legal population.** The run-to-run spread on this machine is
under 2%, so the difference is the change.

Verified the effect still lands: a tower with a Statue standing on it reports an
`attack_damage_ratio` of 0.85, the authored 15%.

## The networked build

A real dedicated server on loopback plus one headless client per player, each driven by
`MpDriver`. Every run sends real orders, because a turn stream with no input in it is the one
case that cannot desync.

| Scenario | Result |
| --- | --- |
| 1v1, 40 s | 780 turns on both peers, **0 desyncs**, 0.70 s held |
| 4 players, 40 s | 778-779 turns each, **0 desyncs**, 0.75 s held |
| A third peer connects mid-match and sits in the lobby browser | 781 turns, **0 desyncs**, 0.40 s held — the freeze the second review found stays fixed |
| A peer hard-killed mid-match | Survivors run the full match, 0 desyncs, and pay one 8 s stall — **but see below** |

### A player who lags out can take a healthy player with them

**Reproduced in 2 of 5 three-player runs, and it is a race, so the frequency is a property of
this machine's timings rather than of the bug.**

`LockstepService._drop_silent_peers` gives up on a peer the relay has not heard from for
`silent_timeout_seconds` (8 s). A peer sends a word by closing turns, and closing turns is
driven by `_frames`, and **`_frames` does not advance while the peer is stalled** — that is
what a stall is, and `_physics_process` says so explicitly.

So a peer waiting for the player who really did lag out is, from the relay's point of view,
silent in exactly the same way. Both timers expire within a tick or two of each other, and
`_drop_silent_peers` walks the whole roster in one pass, so it can drop the departed player and
an innocent one in the same frame — before the release it just issued can reach anybody and come
back.

What it looks like from the server:

```
[LockstepService] Player has gone silent, giving up on them { peer: <quitter>, seconds: 8.0 }
[MatchStartService] Player dropped from the match { slot: 2, why: went silent, left_in_match: 2 }
[LockstepService] Player has gone silent, giving up on them { peer: <healthy>, seconds: 8.0 }
[MatchStartService] Player dropped from the match { slot: 1, why: went silent, left_in_match: 1 }
```

Slot 1 went on playing for the rest of the match. Both survivors agreed about the drop, so
there is no desync — they agree on a **wrong roster**. The player's maze is erased on every
machine while they are still building in it, and `left_in_match` falls by one more than it
should, which is what decides when a match is over.

In one of the two failures it was the HOST that was wrongly dropped, so it is not slot-ordered.

The window is the round trip between the relay speaking for the departed and the released peer's
next word coming back. On loopback that is a tick or two against an 8 s timer, and it still fired
40% of the time. **On a real link the window is wider, not narrower** — which is the argument
for treating this as a live risk rather than a lab curiosity.

The shape of the fix is the one the second review already found for the deadlock: a stalled peer
is not a silent peer, and the relay is the machine that knows which is which. It knows exactly
who each peer is waiting on, because it is the one distributing the turns. Not attempted here —
it is a change to the drop rule and wants its own thought.

## The developer cheats all work, including the one on record as broken

`README.md` records the LOAD half of the layout pair as "reported not working on 2026-09-03 and
has not been investigated". Driven through `Commands.submit_player_action` exactly as
`CheatController` does it, all five work: gold, unlock creeps (47 sendable), unlock
technologies (30 owned), save, and load.

**Why it looks broken is worth knowing, because every tester will hit it.** Loading is
non-destructive and per entry: an entry whose cell is already taken is refused by the same
`can_place` a build order goes through, and skipped. So pressing #4 with the maze already
standing places nothing at all and logs `placed: 0 of 181` — which reads exactly like a dead
key. Clear the area first and all 181 go up.

Also verified separately: `TowerLayout.restore` puts all 181 entries of the saved layout into an
empty lane, in every one of twelve lanes, in about 160 ms a lane.

## What is still open

- **The drop cascade above.** The most serious thing here, and the only one that can spoil a
  live match.
- **Twelve players needs the per-unit work**, and needs more of it than the earlier number
  suggested. The per-node `_physics_process` dispatch and the spatial hash under
  `CLAUDE.md`'s known weaknesses are both still the answer; this only moves where the line is.
- **The Orb Keeper floor** is a one-line decision nobody has taken.
- **`DamageBlockPassive`** is either a missing creep trait or dead code.
- **`stop_server.ps1` cannot see a server started with a relative `--path`**, because it matches
  the command line against the project FOLDER NAME and `--path .` never contains it. Harmless
  when the documented `run_server.ps1` is used, which passes an absolute path; confusing when
  anything else starts one.

## Traps this turned up

**A save cheat is a destructive test.** `CheatProbe` pressed SAVE with one tower standing and
overwrote the 181-building meta layout in `user://Layouts/`, which is not in the repository and
has no other copy. It was restored byte for byte only because the file had been printed earlier
in the same session. Anything that exercises a WRITE has to be pointed at a scratch path first —
`GameConfig.cheat_layout_path` can be redirected in memory, and the probe now does.

**Scaling `Engine.time_scale` alone changes the game.** See the note under How it was measured.
This one belongs in `CLAUDE.md` if another probe ever needs simulated time in a hurry.

**Two probes writing `user://settings.cfg` at once.** Every headless client on one machine
shares the same settings file, and `LobbyIdentity.choose_name` writes to it. It did not bite —
the name is read once at registration — but two processes racing on one config file is not a
thing the game was built expecting.
