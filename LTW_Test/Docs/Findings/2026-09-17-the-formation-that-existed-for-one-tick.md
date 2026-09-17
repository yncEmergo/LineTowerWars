# The formation that existed for one tick

**Supersedes [2026-09-16-attacker-pathing-and-group-movement.md](2026-09-16-attacker-pathing-and-group-movement.md)**,
whose diagnosis of the detour was right and shipped, and whose formation half was not enough.
That document's "what was changed: nothing yet" was true on its own date; this one says what
actually landed and which of its conclusions did not survive being measured.

**Asked:** the formation shipped the day before "barely improved" group movement. Why, and what
does the field actually do? The user's own hypothesis: units are still pushing each other away,
and maybe what feels good is no space restrictions while MOVING but a free space when standing
still or attacking.

**How it was measured:** `Scripts/Dev/FormationProbe.gd`, written for this and kept. It boots a
real `server_match.tscn`, spawns real attacker creeps, and sends a real order through
`Commands.submit_for` - so what it reports is the shipping path and not a re-implementation. It
prints `targets_distinct` (how many distinct destinations the group actually received) and
`ever_held`/`ring_cells_free` as positive controls, because the whole reason the previous verdict
was worthless is that the formation had been proven only as arithmetic and never once proven to
run. Research was a 19-agent workflow over the shipping-game literature plus a line-level audit.

**Machine:** the Windows dev PC, headless, Godot 4.7.2. Tick counts are simulation ticks at
20 Hz. Nothing here is a performance number, so the platform does not matter to the claims.

---

## What was found

### The formation fired. It just could not survive its own completion.

`targets_distinct=8 of 8` on the very first run: every creep of a ground-ordered pack really did
get its own spot. The previous round's work was not a no-op. What happened next was:

```
t=60   moving=8  miss=6.73     walking to their own spots
t=130  moving=6  miss=1.36
t=150  moving=4  miss=1.31     floor - never got closer
t=160  moving=0  miss=1.80     all orders complete
t=200  moving=0  miss=5.80     +1.0 every 10 ticks
t=260  moving=0  miss=11.79      = 2.0/s = exactly move_speed
```

`miss` is the mean distance from each creep to the spot it was assigned. It bottomed at 1.31 and
then **climbed at exactly the creep's move speed**, with `is_moving()` false the whole time. Four
of eight leaked to the end zone before the run finished.

The cause is one line: `Creep._march` falls through to `_travel` - the ordinary walk to the end
zone - when `_march_target` is null, and `_march` runs on the tick after the move task completes.
So a commanded pack arranges itself and immediately streams away. **The layout existed for about
one tick.** Two rules in `game_rules.md` contradicted each other here ("left alone, one walks to
the nearest tower" against "a pack that has arrived is standing still"), and the code implemented
both with the march winning.

### Attack orders never got a layout at all

`CommandService._slots_for` returned early whenever a command named a unit. So the single
commonest order in the game - a pack sent onto a tower - skipped the formation entirely and
aimed every creep at the tower's own centre, exactly as before the previous round. The probe's
first version only ordered onto ground, which is why it never saw this.

### The layout was correct only by accident

`Formation._legalise` rewrote **every** spot onto an internal-cell centre unconditionally, which
quantised the carefully derived pitch to the grid and threw the derivation away. What shipped was
a square block at the grid's own pitch. Contact distance for an attacker works out to its
`select_radius`, and measured against the roster:

| creep | contact | delivered pitch | parked overlap |
| --- | --- | --- | --- |
| Corrupted Treant | 0.344 | 0.500 | no |
| Siege Engine | 0.451 | 0.500 | no |
| Mountain Giant | 0.498 | 0.500 | marginal |
| Phoenix | 0.608 | 0.500 | **yes** |

The probe had been run with Treants, the safest creep in the roster.

### One hypothesis of mine was wrong, and one of the user's was right

I had claimed `_is_crowd_blocked` was the dominant cause. The probe measured `crowd_settled=0`
at every sample of the first run - it never fired once. With the hold in place a later run showed
one creep in eight stopping via `stop()` rather than `_arrive()`, so the mechanism is real but
intermittent and was never the main event. **The measurement beat the reasoning, including my
own.**

The user's hypothesis was right with one correction from the sources: it is not that moving units
are ghosts, it is that **separation is a soft, moving-only concession while occupancy is a hard,
stopped-only, exclusive claim** - two different numbers for two states. StarCraft 2 authors
`Radius` and `Separation Radius` as separate fields. Warcraft 3 stamps only *stationary* units
into the pathing grid. Company of Heroes runs zero unit-unit separation during a formation move
and switches to exclusive reserved spots on arrival. And no shipping RTS runs a symmetric
per-tick pairwise correction over commanded units, which is exactly what this project had;
where a push survives at all it is asymmetric by priority. Symmetric mutual avoidance is the
RVO/ORCA construction whose documented failure is oscillation *precisely when neighbours have
reached their goals*.

---

## What was changed

Four changes, each measured on its own.

**1. A commanded attacker holds its spot.** `_march` asks `_holding_position` before
re-targeting. Set on arrival, cleared by a new order, by Stop, and by the world moving the creep
- and deliberately **not** set while it has a target it was aimed at, so killing a named tower
still hands it back to the march rather than leaving it on the rubble.

**2. Every force deleted.** `_hold_apart`, `_away_from`, `_is_crowd_blocked`, `_crowd_settled`,
the `has_arrived_at` override and `CROWD_CONTACT_SLACK` are gone; `_separation_limit` returns
zero for an attacker. A commanded attacker now performs **zero** neighbour iterations per tick,
where it previously paid up to three whole walks over the lane's creep list.

**3. The layout moved into integer cell arithmetic.** Pitch is derived from the largest personal
space in the group, rounded up to a whole cell, and `_legalise` now only moves a spot that is
blocked or already taken. Every comparator is an integer, which is also strictly better for
lockstep than the float projection it replaced.

**4. Attack orders get a ring.** `PlayerArea.reach_cells` - already the goal set for an attack
order's route - is promoted to the spot set, and `assign_reach_cells` hands them out by one
multi-goal sweep, so a pack coming at one face claims that face. Overflow creeps get a spot on a
waiting ring outside reach and stand there; they do not retarget, because the player named that
tower. `AttackAbility._chase` walks to the assigned spot and holds only once arrived - holding on
`is_in_reach` alone would collapse the ring onto the outer reach arc, since the spots sit
deliberately inside reach.

### Before and after, same probe

Ground order, eight Treants:

| | before | after |
| --- | --- | --- |
| closest to assigned spot (mean) | 1.306 | **0.000** |
| reached own spot | 0 of 8 | **8 of 8** |
| leaked to the end zone | 4 | **0** |
| still holding 150 ticks later | n/a | **8 of 8** |

Delivered pitch against required, which is the Phoenix defect: Treant 0.500/0.344, Mountain
Giant 0.500/0.498, Phoenix **1.000/0.608** - previously 0.500 and overlapping.

Attack order on one tower, with `ring_cells_free=8` proving the branch ran:

- eight creeps: `targets_distinct=8 of 8`, all eight in reach and swinging, parked gap exactly
  0.500, stable for over a hundred ticks.
- twenty creeps onto the same tower: `targets_distinct=20 of 20`, no overlap anywhere, eight on
  the ring fighting and the rest standing in reserve. Killing the tower ends the order and the
  pack moves on.

Before this, both cases put all eight or all twenty on one point.

---

## What is still open

- **The feel has not been judged.** Every number here is headless and headless cannot draw. In
  particular: whether walking units visibly overlapping reads as acceptable, whether the block
  pitch is right, and whether the waiters read as a reserve or as stuck.
- **No paired performance measurement on the target.** The change removes per-unit per-tick work
  and adds per-order work, which is the direction the budget needs, but *should* is not a number
  and this has not been run on the rented server with one variable flipped in place.
- **No lockstep run has issued a group order.** The determinism bench issues no Move and no
  Attack at all, so a green trace over this work would be a test that never executed the code
  under test. That gap is unchanged from the previous round and is the next thing worth closing.
- **Occupancy is read off the world rather than booked.** A spot is offered only on ground no
  *standing* attacker covers, asked freshly per order. This cannot leak the way a claim ledger
  can - a creep that is gone is not standing anywhere - but it also means two orders issued on
  the same tick do not see each other's intentions, only each other's current positions.
- **A waiting creep does not step in when a spot frees.** Assignment happens once, at order
  time. Re-issuing the order re-assigns.
- **A flyer's ring is filtered by the blocking grid**, so a Phoenix ordered onto a tower buried
  in a wall may find no spot even though it could hover over it.

## Traps

**The scaffolding was deleted mid-investigation.** `Scenes/Dev` was removed by a concurrent
agent following CLAUDE.md's own rule about deleting `Scripts/Dev` and `Scenes/Dev`, between two
probe runs, which presented as `Cannot open file`. `Scripts/Dev/FormationProbe.gd` is worth
keeping on the same grounds as `LockstepProbe` and `ShaderProbe`: it is the only thing here that
can tell "barely improved" from "never ran".

**A probe's summary can be measured at the wrong moment.** The tower runs reported
`reached_own_slot=0 of 8` and `min_final_gap=0.000` while passing, because the summary fires long
after the pack has killed the tower and dispersed. The honest numbers came from sampling while
the target still stood. An end-state assertion is only valid if the state it asserts about still
exists.

**Several agents were editing the project at once**, and a half-written feature in
`Scripts/UI/UnitPanel.gd` made every headless run fail with three parse errors in one file and
`Failed to compile depended scripts` everywhere else - including in files that were fine. When a
headless run fails, read which file the errors are actually *in* before believing they are yours.
