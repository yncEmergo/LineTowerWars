# Why a commanded attacker walks the long way round, and why a pack moves like a liquid

**Asked:** two complaints about commanding attacker creeps. An attack order on a tower with a
clear approach sends the pack round into the maze instead of straight at it. And a group told
to go somewhere behaves "like a fluid simulation" - drawn to the middle, adjusting forever,
with the first arrival sitting on the exact spot everybody else wanted.

**How it was investigated:** no measurement, no run. This is a read of the code against the
prior art, done as a 33-agent workflow: three independent diagnosers on different layers
(routing, the order loop, geometry/reach), one adversarial refuter per claim, two web research
agents on the shipping-game literature, two code-mapping agents on the movement pipeline and
on what lockstep permits, then three design proposals scored by three judges each. Nothing
below is a profile; the costs quoted are from the findings named at the end.

**Machine:** none. Every claim here is from source, and every one was traced by a second agent
against the file before it was kept.

---

## What was found

### The detour is four bugs in a row, not one

The complaint is one symptom with a stack of independent causes, each sufficient on its own to
produce it. That matters more than any single one of them: fixing only the obvious one leaves
the behaviour almost unchanged.

**1. The destination is chosen before the search that could have chosen it correctly.**
`AttackAbility._chase` aims the walk at the tower's own origin, which `footprint_world_center`
puts at the exact centre of the footprint - an occupied cell. `PlayerArea.route_between` finds
it blocked and substitutes `nearest_free_point`, an expanding-ring scan that takes the first
free cell it meets. It never sees the walker and never asks what is reachable.
`FlowField.build_to` then computes the genuinely shortest route to that cell. **The route is
optimal; the cell is wrong.** Straight-line distance is not geodesic distance, and a tower
defence maze is the worst map in existence for that confusion because a maze is built out of
U-shapes on purpose.

**2. The scan is centred on the wrong cell, and that is structural rather than unlucky.**
`Building.footprint()` multiplies `footprint_cells` by `internal_cells_per_cell`, so *every*
building's internal footprint is even on both axes. Its world centre therefore lands exactly on
an internal-cell boundary, and `world_to_internal_cell`'s `floor()` resolves it to the
footprint's **max-corner cell**. The radius-1 ring around that corner contains the east and
south faces and contains no cell of the north or west face at all - those are a whole ring
further out.

**3. The iteration order biases it again.** Within a ring the scan runs north-row-first,
west-to-east, which on an even footprint yields a hard preference: east face, south row, SE
diagonal, and only then anything else. Attackers walk down-lane from low z, so the cell chosen
is routinely on the far side of the tower from them. When that tower is part of a maze wall,
the shortest walk to its far face goes round the wall - correctly, and visibly.

**4. Nothing ever revisits it.** `_order_goal` holds the tower's own unmoving cell, so
`Creep.move_to`'s `goal != _order_goal` guard suppresses every re-plan for the whole walk. That
guard is right and is required by the rules ("an attack order re-aims its walk every tick and
must not cost a search every tick"); it simply means a wrong first answer is permanent.

Two further contributors, separately verified: the commanded walk has **no straight-line or
in-reach short-circuit at all**, where the *uncommanded* march has one - `_march` steers
straight at the nearest building and stops at its own reach - which is why the same creep walks
sensibly on its own and detours the instant a player left-clicks. And `FlowField.build_to`
narrows a sweep that *already takes a set of goals* down to exactly one cell, so an attack order
has no way to express what it actually wants.

**Why it reads as intermittent.** `_chase` stops the creep the instant `is_in_reach` is true,
and that is a flat centre-to-centre test with no body radii. In open ground the wrong-face route
skims inside reach on its first steps and the creep stops, looking fine. The visible detour
needs the mis-chosen cell to sit in a *different corridor* - which is exactly what a maze wall
provides.

### The "fluid" feel is a hand-rolled Continuum Crowds, and it has a name

Three mechanisms, all doing exactly what they were built to do:

1. **One destination for N units.** A command carries one `target_position` for a whole
   `unit_ids` array. Every unit converges on the same point.
2. **No honest termination.** A unit not standing *on* that point still has a reason to move,
   so it moves. The only exit is `_is_crowd_blocked`, which is a *negotiation*: you stop when
   somebody who already stopped is touching you and is nearer the point. The user's "the first
   unit to arrive blocks the exact destination" is literally that rule, working.
3. **A separation force with no equilibrium to reach.** `_hold_apart` runs unconditionally every
   tick for every attacker and corrects half its overlap with each neighbour. A pack piled on
   one point has no arrangement to settle into, so every push creates a counter-push forever.

One shared goal plus per-tick pairwise separation **is** Continuum Crowds (Treuille et al.,
SIGGRAPH 2006), a technique whose stated design goal is to make a crowd behave like a flowing
fluid. "Drawn to the middle" is a potential well; "keeps adjusting forever" is a field with no
terminal condition. **Tuning `attacker_separation_limit` cannot fix this.** The architecture is
the diagnosis.

A fourth, separate contributor to the unorganised look: a commanded walk is not smoothed.
`route_to_exit` caches corners via `aims_along` and re-tests each with `can_walk_straight`;
`route_between` returns raw cells and `_walk_to_order` steers at one cell centre at a time.
Because `next_cell` is eight-connected over a four-connected field and a strictly-closer
diagonal always wins, an ordered route spends its whole short axis first - a diagonal run, then
a straight run. So a commanded attacker walks a visible dogleg alongside an uncommanded creep
walking smoothly.

---

## What the field does instead

**For the attack order.** Every shipping RTS treats "attack that thing" as a different
pathfinding *query*, and the difference is the shape of the GOAL, not the shape of the search.
The query is "path to ANY tile I can hit it from" - a multi-goal search whose goal set is the
target's footprint dilated by attack range. OpenRA's `MoveAdjacentTo` is the readable worked
example, and its `PathFinder` carries `FindPathToTargetCells` (plural) for exactly this.
Picking one representative tile by Euclidean nearness first is the classic bug, and the symptom
is precisely the one reported.

This project already has the machinery: `FlowField._sweep` takes `goals: Array[Vector2i]` and
seeds every one at distance 0, which is how `build()` seeds the whole end-zone strip. Only
`build_to` narrows it to one. Seed the ring and the near face wins **by construction**, on the
walker's own side of any wall, with no heuristic and nothing to tune.

**For the group.** Shipping RTS games almost never send a group to one point. The order resolves
to N distinct destination SLOTS, generated once at order time from a shape anchored on the click
and oriented along the travel vector, with units matched to slots by an assignment that
preserves who was in front. Everything after that is cheap, because each unit is then an
individual with its own destination and arrival is per-unit and definite rather than a
negotiation over one contested tile. Pottinger's two 1999 articles are still the reference.

**The cautionary half is equally clear.** AoE2 DE shipped formation-FIRST movement - regrouping
before departing, walking backwards to hold shape - and patched it back out after players asked
for a switch to disable it. The formation must never delay or reverse the order. Zero-K ships
Hungarian assignment but caps it and lowers the cap when a solve runs long; a projection sort
delivers the property a player actually feels for `n log n`.

---

## What was changed

Nothing yet. This finding is the diagnosis; the design it produced is being implemented
separately and its reasoning belongs in the docstrings, not here.

The shape agreed on: seed the reach ring into one sweep for an attack order, and give a ground
order one slot per unit computed in `CommandService._apply` - the one function reached
identically by the offline path, by the lockstep path on every peer, and by the replication
server, and the only place the whole group is visible at once. The slot is written *into*
`target.position` per unit, so no wire field is added and nothing new reaches `checksum_state`.

The load-bearing detail is that the slot spacing is **derived** from `_crowd_radius()` rather
than authored independently: `_hold_apart` skips a pair once they are at least their combined
personal space apart, so slots at that distance mean a parked block computes a zero correction
and never moves. The jiggling stops because there is nothing left to correct, not because
anything was switched off.

## What is still open

- Whether a pack ordered onto one *tower* needs per-creep ring slots too. The ring alone gives
  each creep a correct approach but not an arrangement, so a pack arriving down one corridor is
  still shoved into place by `_hold_apart`. Decide it from a screenshot, not from an argument.
- Whether to smooth the commanded route with the `aims_along` machinery the exit walk already
  uses. It is half the unorganised look and is independently revertible, but `_path_aims` feeds
  `steps_to_exit`, which every tower's target ranking reads, so the order aims must be their own
  fields.
- `_hold_apart` and `_is_crowd_blocked` still walk the whole creep list, where `CreepIndex` and
  `creeps_near` already exist and are exactly the accelerator both want. Deliberately out of
  scope here: it changes the order a float sum accumulates, so it is deterministic but *not*
  byte-identical, and bundling it would destroy the ability to prove anything else is a no-op.
- The determinism bench issues no Move and no Attack at all, so a green trace over any of this
  work would be a test that never executed the code under test. That is the first thing to fix.
- `Creep._attack_reach()` returns the raw `attack_range` while `AttackComponent._reach` adds
  `attack_range_bonus()`, so an unordered marching attacker stops at a different distance from
  the one `is_in_reach` uses. Real, separate, and its own commit.

## Traps

**A `| head -N` on a probe pipeline and a positive control** are already in `../../CLAUDE.md`
and both apply directly here. The specific shape to watch: a "no detour" result from a test
where the reach-ring branch never fired is indistinguishable from a pass, so the ring branch
has to prove it ran.

**Thirteen candidate causes, zero refuted.** Every claim survived its adversarial check, which
is a weak signal on its own. What made it worth trusting is that the refuters returned
*corrections* rather than verdicts - one confirmed a claim's structure while calling its
severity, its "raw BFS staircase" characterisation and its tie-break story all wrong. Read the
corrections, not the verdicts.

**Two claims about cost that were wrong and are worth not repeating.** Seeding more cells into
the sweep is not cheaper than seeding one - `_sweep` visits each reachable free cell exactly
once whatever it was seeded with; more seeds only drain the queue from more fronts. And a group
ground order already costs one sweep per unit, because every unit calls `route_between`
separately, so giving each a different slot neither adds nor removes one.

## Where the numbers came from

No number in this finding was measured for it. The tick headroom it reasons against is
[2026-09-05-lockstep-hardening.md](2026-09-05-lockstep-hardening.md) and
[2026-09-05-roster-sweep-and-endgame-load.md](2026-09-05-roster-sweep-and-endgame-load.md).

## Sources

Attack-move and goal-region pathfinding: OpenRA `MoveAdjacentTo.cs` and `PathFinder.cs`;
0 A.D.'s pathfinder design document; openage's AoE2 pathfinding reverse-engineering notes;
Factorio FFF #117 and #121 on path reuse and truncation; Game AI Pro ch. 23 (Emerson, flow
field tiles) and ch. 28 (attack slots).

Group movement: Pottinger, "Coordinated Unit Movement" and "Implementing Coordinated Movement"
(Game Developer, 1999); Treuille, Cooper & Popović, "Continuum Crowds" (SIGGRAPH 2006);
Reynolds, "Steering Behaviors For Autonomous Characters" (GDC 1999); Zero-K's
`cmd_customformations2.lua`; AoE2 DE update 153015 patch notes and the player thread that
prompted it; Liquipedia on Brood War magic boxes.
