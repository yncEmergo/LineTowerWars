# Line Tower Wars - Unit, Tower and Technology Data

**What this is.** Every number in *Warcraft III Line Tower Wars* as of version **12.4a**
(2026-08-04): every tower, creep, technology disc and core system, with its costs, stats,
upgrade paths and abilities. It is the balance sheet of the game this project is remaking,
and it is the file to look a number up in before authoring it into a resource.

## Why the prototype copies it

**The goal for the prototype is to be a near-exact copy of Warcraft III Line Tower Wars
12.4a**, and to use that as the starting point for further development rather than as a
finished destination.

That is a deliberate choice, for two reasons:

- **The project owner knows that game extremely well.** Copying a design they can already
  play from memory removes the largest unknown in a prototype: whether the thing is any
  good. It is known to be good. What is unknown is only whether this implementation
  reproduces it.
- **It is already balanced.** LTW 12.4a is the result of many years of continuous active
  development on the original map. That balance is worth far more than anything this
  project could invent from scratch at prototype stage, and it comes for free.

So where this document and an instinct disagree, this document wins. Original design
decisions come AFTER the copy works, not during it - and when one is made, it is made
knowingly, against a baseline that is known to play well.

**The one deliberate departure is naming.** Section 2.4 renames every tower upgrade chain,
because the source game renames a tower at every tier and that makes the tech tree hard to
read. The old Warcraft III names are recorded in 2.4 and nowhere else.

## What this file is for, now and later

**Now:** a hand-maintained MIRROR. This file was written ahead of the content it describes
and for a long time almost none of it was implemented; that has stopped being true. The
towers, the creeps and the discs all exist, so for nearly every row here the `.tres` is now
the authority and the row is the readable copy of it - see 8.1. What is left of the original
job is the handful of rows still marked NOT BUILT, and the fact that this remains the only
place the whole balance can be read at once.

It may still hold numbers where nothing else may (see the "no live values in markdown" rule
in CLAUDE.md; this file and `game_rules.md` are its two exceptions), because these numbers
ARE the design being copied rather than a restatement of what some script happens to do.

**Once a unit is implemented, its `.tres` becomes the authority** and the row here becomes a
mirror of it. Where the two disagree the `.tres` wins, and this file is wrong and must be
fixed. Until the generator below exists, the rule is: change the `.tres`, then change the
row here, in the same commit.

**Later:** this file stops being hand-maintained. The intended end state is that it remains
the single readable overview of the complete balance of the game - so that nobody, human or
otherwise, has to open thirty resource files to answer one question - but that its tables
are GENERATED from those resources rather than typed alongside them. Section 8 has the
proposed shape.

**That is now the largest piece of tooling work outstanding, and the reason it was deferred
has expired.** It was held back for "not enough implemented content to make it pay"; the
rosters are complete, every table below now shadows a `.tres`, and each of them can drift
silently the next time a balance number is touched. Section 8.2 has the shape and nothing
blocks it.

## How to read a row

`game_rules.md` is the other half of this document and never repeats it: that file holds the
RULES - how sending, mazing, damage resolution, lives and the economy work - and points here
for every number those rules operate on. If you want to know what a Grunt costs, it is here.
If you want to know what happens when it reaches the end of a maze, it is there.

## How this was reconstructed, and how much to trust it

Four source files:

| File | Covers |
| ---- | ------ |
| `LTW 9.4 - Tower Data.tsv` | every tower, version 9.4 |
| `LTW 9.4 - Creep Data.tsv` | every creep, version 9.4 |
| `LTW 9.4 - Disc Data.tsv` | disc effects, version 9.4, base + Advanced only |
| `Changelogs 10.0 - current.txt` | every patch note from 10.0a to 12.4a |

The 9.4 tables are the baseline; every patch note from 10.0a forward was replayed onto them
in order. **There is a two-version gap: 9.5 and 9.6 sit between the sheets and the first
changelog, and their patch notes no longer exist anywhere.** The gap is visible whenever a
patch note's "changed from X" does not match the 9.4 value - for example 10.0a changes
the anti-air branch's 150g tower from 26-34 while the 9.4 sheet says 21-27. In those cases the patch note's
*result* is still correct and is what this document carries.

Confidence markers used below:

- **(no marker)** - the value was set or confirmed by a patch note between 10.0a and 12.4a,
  or supplied directly by the project owner.
- **`~`** - the value comes from the 9.4 sheet and was never touched by a patch note. It is
  probably still current but could have been changed in 9.5 or 9.6.
- **`?`** - genuinely unknown or contradictory in the sources. Every one of these is
  collected in "Open questions" at the end.

---

# 1. Core systems

## 1.1 Damage types and the armour matrix

Every attack carries a damage type, every damageable unit an armour type, and the pair
decides how much of the attack lands. There are five **physical** damage types.

| Armour \ Damage | Magic | Chaos | Normal | Piercing | Siege |
| --------------- | ----- | ----- | ------ | -------- | ----- |
| Light           | 150%  | 100%  | 80%    | 150%     | 100%  |
| Medium          | 80%   | 100%  | 150%   | 100%     | 80%   |
| Heavy           | 150%  | 100%  | 100%   | 80%      | 80%   |
| Fortified       | 66%   | 100%  | 80%    | 66%      | 150%  |
| Hero            | 66%   | 100%  | 80%    | 66%      | 80%   |
| Unarmored       | 100%  | 100%  | 100%   | 150%     | 125%  |

This is the 12.4a matrix and it is now also the one in `game_rules.md`. Two cells were
raised during the changelog period: **Magic vs Light** 125% -> 150% (11.0a) and **Piercing
vs Unarmored** 125% -> 150% (11.5a). 12.3a additionally fixed a bug where Piercing dealt
only 125% to Skittering creeps.

**Magic is a physical damage type.** It goes through the matrix above like any other - the
changelog writes phrases like "Magic Physical Damage". The damage that ignores the armour
matrix entirely is **Spell Damage**, a separate category:

- Spell Damage ignores armour type and armour value completely.
- Creeps resist it through explicit traits (Lesser Spell Resistance -33%, Spell Resistance
  -50%, Major Spell Resistance -66%, Bone Shield / Legendary Spell Resistance -75%).
- Towers and discs amplify it explicitly (Technology Disc: Arcane, Ultimate Titan Vault).
- Almost every tower *ability* deals Spell Damage; almost every tower *attack* is physical.
  No tower's basic attack is Spell Damage.

**Chaos** currently reads 100% against every armour type, which is a balancing value and not
a rule.

## 1.2 Attack speed

Attack speed in every table below is the **cooldown in seconds between attacks**, matching
how the source data and the in-game tooltip state it ("Speed: 3.0s"). Higher is slower.
DPS is `average damage / attack speed`.

## 1.3 Slow, stun and armour reduction

- Base slow duration is **4 seconds**; against a slow-resistant creep it is **2 seconds**.
- Slow amounts stack additively up to each effect's own cap, and creeps carry slow
  resistances that reduce the *application*, not the cap.
- Armour reduction comes in two flavours: **temporary** (a debuff with a duration) and
  **permanent erosion** (Shatter Armor, Devastating Attack, Ice Lance, Feasting Void,
  Unholy discs), which reduces the creep's armour for the rest of its life, usually down to
  a floor of 0.
- A few effects push armour **below zero**, down to -3 (the Divineshroom line's Light Burst).

## 1.4 Tower survivability

- Every tower has armour type **Fortified**, whatever its damage type.
- Health and armour depend **only on the tower's price tier**, never on its element. Every
  tower that costs the same has the same body.
- Towers regenerate **1.5% of maximum health per second**.
- Build time and upgrade time are **the same for every tower at every tier**.

**Basic towers**

| Tier | Health | Armour |
| ---- | ------ | ------ |
| 10g | 25 | 0 |
| 30g | 35 | 1 |
| 150g | 75 | 3 |
| 1,000g | 175 | 5 |
| 5,000g | 575 | 5 |
| 25,000g | 2,275 | 5 |

**Elemental towers** - armour 5 at every tier.

| Tier | Health | Armour |
| ---- | ------ | ------ |
| 200g | 100 | 5 |
| 800g | 150 | 5 |
| 4,000g | 750 | 5 |
| 10,000g | 1,500 | 5 |
| 30,000g | 3,000 | 5 |

## 1.5 What an attacking creep can target

Only creeps with the **Attacker** trait attack buildings at all, and when they do they can
only ever target a **tower**. Two things are not valid targets, ever:

- **Technology discs.** Armour type `Invulnerable`.
- **The builder.**

This is not "hard to kill" or "deprioritised" - they cannot be attacked, so no amount of
attacker pressure touches them, and it means the builder is never a target that has to be
protected or kited.

For a disc it is one half of a pair, and the other half is that **creeps walk over a disc** -
see section 5. So a disc is not a wall an attacker cannot open; it is a square an attacker has
no business with at all, because there was never anything there to open. Earlier drafts of
this file called it a wall, which contradicted section 5 and is wrong.

A destroyed tower leaves **rubble for 7 seconds**, during which no new tower can be built on
that cell.

## 1.6 Creep health regeneration

Creeps have **0 base health regeneration** (10.0a removed it and raised maximum health to
compensate). Regeneration on a creep now comes only from an ability or an aura.

## 1.7 Income, lives, sudden death

- **Income cap: 4,000,000.** Above that, Tier 4 income gain is reduced by 75% (12.4a).
  **BUILT.**
- Sudden Death starts at **25:00 game time** and *is* Tier 4: tiers 1-3 can no longer be
  used from that point, and every Tier 4 creep unlocks at once. **BUILT.**
- On entering Sudden Death, any player below 1,000,000 income is raised to 1,000,000.
  **BUILT.**
- The creep damage-taken modifier starts at 100% and falls by **1% per minute** during
  Sudden Death, making creeps progressively tankier. NOT BUILT.
- Starting lives depend on player count and ruleset; for the 1v1 prototype the relevant
  figure is the 2-player value: **80 lives (Unranked)** / **100 lives (Casual)**.
- Catch-up gold: when a player gets a new attacker with higher income than the previous one,
  they receive `(income difference) x 1.5` once. **BUILT, to a DIFFERENT RULE.** The
  prototype pays it when a player is ELIMINATED and the ring hands their victim a new
  attacker, and it pays `(the new attacker's current income) x 1`, whether or not that is a
  step up. The user's call, and simpler in two ways: it fires on one event rather than on a
  comparison nothing was tracking, and it needs no memory of who the previous attacker was.
  The multiple is `catch_up_gold_share` in `game_config.tres`. See `game_rules.md`, Life
  steal and recycling.

## 1.8 Selling and morphing

| Action | Refund | Time |
| ------ | ------ | ---- |
| Sell a Basic tower | 60% | 3 sec |
| Sell a Technology tower | 50% | 3 sec |
| Morph a Technology tower back down | 50% | - |
| Morph a disc back to inactive | - | 5 sec |

Sell time is the same for every building; only the refund percentage differs.
---

# 2. The technology system

**Implemented.** The system this section describes is built: `Resources/Tech/` holds one
resource per technology, `Scripts/Tech/` holds the rules, and the Research Center screen
sells them. The towers it gates are built too: an elemental upgrade names the technology it
needs by `tech_id`, and the same `TechManager.owns` call the Research Center makes is what
refuses it. The prices in 2.2 are mirrored by `game_config.tres` and the cross requirements
in 2.3 by the path technologies themselves, which is what lets the bijection be checked at
boot.

## 2.1 Ten elements, three techs each

There are **ten elements**: Arcane, Earth, Fire, Holy, Ice, Lightning, **Primal**, Unholy,
Void, Water. (Primal did not exist in 9.4 - it was added whole in 10.0a, so every Primal
number in this document comes from the changelog rather than the 9.4 sheet.)

Each element sells three separate technologies:

1. **Element Technology: Basic** - unlocks the free morph from the generic Elemental Core
   into that element's 200g base tower, and unlocks its 800g upgrade. Required before either
   of the other two.
2. **Element Technology (1): name** - unlocks path 1 of that element: the Lesser (4,000g) and
   Greater (10,000g) towers.
3. **Element Technology (2): name** - unlocks path 2 of that element: the Lesser (4,000g) and
   Greater (10,000g) towers.

Under the naming scheme in 2.4 each path has a single name across all three of its tiers, so
the technology is simply named after that: **Fire Technology (1): Moonbeam**,
**Fire Technology (2): Firelord**.

## 2.2 Tech cost

- Every player starts with **4 free technologies**.
- After that, each technology costs **50,000 x (number already bought beyond the free 4)**:
  the 1st paid tech costs 50,000, the 2nd 100,000, the 3rd 150,000, and so on.

## 2.3 The Ultimate towers and their cross-element requirement

An Ultimate tower is the 30,000g upgrade of a Greater tower. To unlock one you need **four
technologies**:

- its own element's Basic tech,
- its own element's path tech (1) or (2),
- and one **specific other element's** Basic + path tech.

The cross-requirement is a **bijection**: there are 20 Ultimate towers and 20 element-path
pairs, and each pair is the requirement of exactly one Ultimate. An Ultimate never requires
the other path of its own element. This means the four techs that unlock one Ultimate also
fully unlock the Greater tower of the required path, and leave you two techs away from that
path's own Ultimate - which is the chain the design is built around, and why the standard
opening is to spend all four free techs on a single Ultimate.

| Ultimate tower | Its path | Also requires |
| -------------- | -------- | ------------- |
| Ultimate Spellslinger | Arcane (1) | Ice (2): Crystal |
| Ultimate Arcane Orb | Arcane (2) | Water (2): Sludge Monstrosity |
| Ultimate Ancient Warden | Earth (1) | Arcane (2): Arcane Orb |
| Ultimate Scorpion | Earth (2) | Ice (1): Lich |
| Ultimate Moonbeam | Fire (1) | Void (1): Harbinger |
| Ultimate Firelord | Fire (2) | Lightning (1): Annihilation Glyph |
| Ultimate Divineshroom | Holy (1) | Primal (2): Beastmaster |
| Ultimate Titan Vault | Holy (2) | Fire (1): Moonbeam |
| Ultimate Lich | Ice (1) | Unholy (1): Gravedigger |
| Ultimate Crystal | Ice (2) | Holy (1): Divineshroom |
| Ultimate Annihilation Glyph | Lightning (1) | Unholy (2): Alchemist |
| Ultimate Orb Keeper | Lightning (2) | Holy (2): Titan Vault |
| Ultimate Primalist | Primal (1) | Fire (2): Firelord |
| Ultimate Beastmaster | Primal (2) | Earth (2): Scorpion |
| Ultimate Gravedigger | Unholy (1) | Void (2): Leviathan |
| Ultimate Alchemist | Unholy (2) | Arcane (1): Spellslinger |
| Ultimate Harbinger | Void (1) | Earth (1): Ancient Warden |
| Ultimate Leviathan | Void (2) | Water (1): Hurricane Elemental |
| Ultimate Hurricane Elemental | Water (1) | Lightning (2): Orb Keeper |
| Ultimate Sludge Monstrosity | Water (2) | Primal (1): Primalist |

Every one of the twenty element-path pairs appears exactly once in the right-hand column,
which is the check that this table is complete and correct.

Note that Ultimate Scorpion's requirement is **Ice (1)** even though the 10.0a patch note reads
"Technology requirements changed from Ice (1): Frozen Watcher to Lightning (2): Voltage". It
was moved back at some point after that without a note, and Ice (1) is the current value.

## 2.4 Tower naming - the project's own scheme

**The source game renames a tower at every upgrade, which makes the tech tree hard to read.
This project does not.** Every upgrade chain carries **one name**, and the tier is a prefix:

| Position in the chain | Name |
| --------------------- | ---- |
| first tier | **Lesser** *Name* |
| second tier | *Name* |
| third tier | **Greater** *Name* |
| fourth tier | **Ultimate** *Name* |

An elemental path has three tiers, so it uses Lesser / Greater / Ultimate and has no
unprefixed tier: Lesser Firelord -> Greater Firelord -> Ultimate Firelord. A Basic branch has
four, so it uses all of them: Lesser Cannon -> Cannon -> Greater Cannon -> Ultimate Cannon.

The Basic 10g/30g stub is a two-tier chain of its own and is named the same way:
Lesser Archer -> Archer. The element 200g and 800g towers keep their own individual names,
because they are shared by both of an element's paths and belong to neither.

### Elemental towers

| Element | Path | 4,000g | 10,000g | 30,000g | Old WC3 names (4k / 10k / 30k) |
| ------- | ---- | ------ | ------- | ------- | ------------------------------ |
| Arcane | 1 | Lesser Spellslinger | Greater Spellslinger | Ultimate Spellslinger | Archmage / Grand Archmage / Ultimate Spellslinger |
| Arcane | 2 | Lesser Arcane Orb | Greater Arcane Orb | Ultimate Arcane Orb | Arcane Pylon / Runeforged Sentry / Ultimate Arcane Orb |
| Earth | 1 | Lesser Ancient Warden | Greater Ancient Warden | Ultimate Ancient Warden | Earth Guardian / Ancient Protector / Ultimate Ancient Warden |
| Earth | 2 | Lesser Scorpion | Greater Scorpion | Ultimate Scorpion | Nettle / Thorns / Ultimate Scorpion |
| Fire | 1 | Lesser Moonbeam | Greater Moonbeam | Ultimate Moonbeam | Meteor Attractor / Armageddon / Ultimate Doom Guard |
| Fire | 2 | Lesser Firelord | Greater Firelord | Ultimate Firelord | Lava Serpent / Living Flame / Ultimate Firelord |
| Holy | 1 | Lesser Divineshroom | Greater Divineshroom | Ultimate Divineshroom | Glowshroom / Lightshroom / Ultimate Divineshroom |
| Holy | 2 | Lesser Titan Vault | Greater Titan Vault | Ultimate Titan Vault | Sunray Tower / Radiant Spire / Ultimate Titan Vault |
| Ice | 1 | Lesser Lich | Greater Lich | Ultimate Lich | Frozen Watcher / Icebound Core / Ultimate Lich |
| Ice | 2 | Lesser Crystal | Greater Crystal | Ultimate Crystal | Icicle / Tricicle / Ultimate Crystal |
| Lightning | 1 | Lesser Annihilation Glyph | Greater Annihilation Glyph | Ultimate Annihilation Glyph | Lightning Beacon / Thunder Conductor / Ultimate Annihilation Glyph |
| Lightning | 2 | Lesser Orb Keeper | Greater Orb Keeper | Ultimate Orb Keeper | Voltage / Storm Commander / Ultimate Orb Keeper |
| Primal | 1 | Lesser Primalist | Greater Primalist | Ultimate Primalist | Druid / Keeper / Ultimate Primalist |
| Primal | 2 | Lesser Beastmaster | Greater Beastmaster | Ultimate Beastmaster | Savage / Trapper / Ultimate Beastmaster |
| Unholy | 1 | Lesser Gravedigger | Greater Gravedigger | Ultimate Gravedigger | Poison Bloom / Fanatic / Ultimate Gravedigger |
| Unholy | 2 | Lesser Alchemist | Greater Alchemist | Ultimate Alchemist | Reaper / Soul Forge / Ultimate Alchemist |
| Void | 1 | Lesser Harbinger | Greater Harbinger | Ultimate Harbinger | Riftweaver / Zealot / Ultimate Harbinger |
| Void | 2 | Lesser Leviathan | Greater Leviathan | Ultimate Leviathan | Lasher / Ravager / Ultimate Leviathan |
| Water | 1 | Lesser Hurricane Elemental | Greater Hurricane Elemental | Ultimate Hurricane Elemental | Water Elemental / Seabound Wrath / Ultimate Hurricane Elemental |
| Water | 2 | Lesser Sludge Monstrosity | Greater Sludge Monstrosity | Ultimate Sludge Monstrosity | Lurker / Abyss Stalker / Ultimate Sludge Monstrosity |

### Basic towers

| Line / branch | 10g | 30g | 150g | 1,000g | 5,000g | 25,000g |
| ------------- | --- | --- | ---- | ------ | ------ | ------- |
| Archer | Lesser Archer | Archer | | | | |
| - sniper | | | Lesser Watch Tower | Watch Tower | Greater Watch Tower | Ultimate Watch Tower |
| - cannon | | | Lesser Cannon | Cannon | Greater Cannon | Ultimate Cannon |
| Cutter | Lesser Cutter | Cutter | | | | |
| - grinder | | | Lesser Carver | Carver | Greater Carver | Ultimate Carver |
| - stomper | | | Lesser Crusher | Crusher | Greater Crusher | Ultimate Crusher |
| Sentry | Lesser Sentry | Sentry | | | | |
| - magic | | | Lesser Defender | Defender | Greater Defender | Ultimate Defender |
| - anti-air | | | Lesser Turret | Turret | Greater Turret | Ultimate Turret |

Old WC3 names for the same towers, in the same order:

| Branch | 150g | 1,000g | 5,000g | 25,000g |
| ------ | ---- | ------ | ------ | ------- |
| sniper | Watch Tower | Guard Tower | Ward Tower | Ultimate Ward Tower |
| cannon | Cannon Tower | Bombard Tower | Artillery Tower | Ultimate Artillery Tower |
| grinder | Carver | Executioner | Mauler | Ultimate Mauler |
| stomper | Crusher | Wrecker | Mangler | Ultimate Mangler |
| magic | Defender | Bulwark | Construct | Ultimate Construct |
| anti-air | Rocketeers | Barrager | Turret | Ultimate Turret |

The 30g towers were Gunner, Grinder and Sentinel.

`?` **Fire (1) is the one path whose name is NOT its source Ultimate's.** Every other row
takes the name straight off the 30,000g tower the source game ships, which for Fire (1) would be
**Doom Guard**. The project calls the path **Moonbeam** instead, after the *Ultimate Moonbeam
Projector* the 9.4 sheet called the same tower - see the rename list below. It is a project
decision and the only one of its kind; the source names stay in the right-hand column.

`?` **The six Basic branch names are a proposal.** The rule used was "take the clearest name
already in that branch": five come from the 150g tower, and the anti-air branch takes **Turret**
from its 5,000g tower because "Rocketeers" is a plural unit name rather than a tower name. Any
of the six is trivial to change - they only exist here and in section 3.

### Renames inside the source game

Only worth knowing when cross-checking against the 9.4 sheet, since none of these names survive
into this project: Ice Obelisk -> Obelisk, Runic Obelisk -> Runic Monolith, Frozen Core ->
Icebound Core, Shock Generator -> Power Generator, Sunbeam Tower -> Radiant Spire, Ultimate
Kirin Tor Wizard -> Ultimate Spellslinger, Ultimate Devourer -> Ultimate Harbinger, Rift Lord ->
Zealot, Tide Lurker -> Lurker, Noxious Weed -> Nettle, Virulent Thorn -> Thorns, Septic Tank ->
Poison Bloom, Plague Fanatic -> Fanatic, Ultimate Moonbeam Projector -> Ultimate Doom Guard
- the last of those is the one this project undoes, see 2.4.

---

# 3. Basic towers

**IMPLEMENTED.** Every tower in this section exists as a `BuildingStats` resource under
`Resources/UnitStats/Towers/`, and per 8.1 those files are now the authority - this section is
the readable mirror. Change the `.tres` and the row here in the same commit.

Three things had to be decided to turn these rows into resources, because the source records
none of them. They are decisions rather than data, so they are written down here once:

- **Range and splash are divided by 128 and then SNAPPED TO THE NEAREST QUARTER CELL**,
  128 being the Warcraft III build tile. A 150 range Cutter reaches just over one cell, an
  800 range Sentry reaches most of the width of a lane, and a 1,000 range Turret very nearly
  all of it.
  - The quarter is the grain EVERY reach in the game is stated in, and it is what the tables
    below convert to rather than the raw division: 400 is 3, 700 is 5.5, 1,250 is 9.75. The
    raw figures were 3.125, 5.47 and 9.77, and a roster written that way is a wall of numbers
    nobody can hold or compare. It costs up to an eighth of a cell, which is less than the
    width of a creep.
  - The conversion is `cells()` in `Tools/ModelGen/roster.py` and it is the ONLY place it
    happens. The tables here keep the source figure, so a patch note can still be replayed
    onto them.
- **Attack speed is INVERTED.** This document states the cooldown in seconds, the way the
  source game does; `AttackStats.attacks_per_second` is its reciprocal, because the UI shows
  APS and a bigger number reading as faster is the less confusing of the two. Never copy one
  into the other without inverting it.
- **Delivery is chosen per BRANCH**, since 7.2 records that no projectile data survives: the
  Archer line fires a flat arrow, the Cannon lobs an arced shell, the whole Cutter line is
  instant, the Sentry line throws a bolt, and the anti-air branch fires a missile. Projectile
  speeds are a tuning value and are currently deliberately slow, so travel time is visible.

Two things this project ADDS, which the source does not have and which are therefore not
balance changes to it:

- **A windup**, the gap between an attack starting and its damage landing, authored only where
  a tower has a swing to play. It is taken out of the attack period rather than added to it, so
  it never changes a tower's rate - `game_rules.md` has the rule.
- **The Crusher branch's blast is measured from the TOWER**, not from the creep it hit. Its
  reach is barely over a cell while its blast is more than twice that, so what it does in
  practice is flatten the ground it stands on; the source's own tooltip describes it that way.
  Everything else in this section splashes from the impact as usual.

Always available, no technology required. Three independent lines, each starting at 10g, each
splitting into two branches at the 150g tier.

    Lesser Archer 10g -> Archer 30g -> Lesser Watch Tower 150g -> Watch Tower 1,000g -> Greater Watch Tower 5,000g -> Ultimate Watch Tower 25,000g
                                    -> Lesser Cannon      150g -> Cannon      1,000g -> Greater Cannon      5,000g -> Ultimate Cannon      25,000g

    Lesser Cutter 10g -> Cutter 30g -> Lesser Carver      150g -> Carver      1,000g -> Greater Carver      5,000g -> Ultimate Carver      25,000g
                                    -> Lesser Crusher     150g -> Crusher     1,000g -> Greater Crusher     5,000g -> Ultimate Crusher     25,000g

    Lesser Sentry 10g -> Sentry 30g -> Lesser Defender    150g -> Defender    1,000g -> Greater Defender    5,000g -> Ultimate Defender    25,000g
                                    -> Lesser Turret      150g -> Turret      1,000g -> Greater Turret      5,000g -> Ultimate Turret      25,000g

Each line keeps one name across its 10g and 30g towers, and each branch keeps one name across
all four of its own tiers. See 2.4 for the scheme and the old Warcraft III names.

**The builder can only place the three 10g towers.** Every tier above them is reached by
upgrading the tower below it, which is what keeps the build menu three buttons long while the
roster is thirty towers deep. The rule is in `game_rules.md`.

The three lines and what they are for:

- **Archer** is the ranged Piercing line. It either stays a long-range single-target sniper
  (Watch Tower) or becomes a splash cannon (Cannon).
- **Cutter** is the short-range Normal line. It either stays a fast no-splash grinder (Carver)
  or becomes a slow heavy stomper (Crusher).
- **Sentry** is the Magic line. It either stays a magic splash tower (Defender) or becomes the
  dedicated **anti-air** line (Turret), which cannot hit ground at any tier.

The gold column is the price of that one upgrade; "total" is the cumulative gold sunk into the
tower, which is what the sell refund is calculated from. Health and armour are in section 1.4
and depend only on the tier.

## 3.1 Archer line

| Tower | Gold | Total | Type | Damage | Speed | Range | Splash | Targets |
| ----- | ---- | ----- | ---- | ------ | ----- | ----- | ------ | ------- |
| Lesser Archer | 10 | 10 | Piercing | ~1-1 | ~0.667 | ~400 | - | Ground, Air |
| Archer | 30 | 40 | Piercing | ~3-3 | ~0.638 | ~500 | - | Ground, Air |
| Lesser Watch Tower | 150 | 190 | Piercing | ~8-10 | ~0.5 | ~700 | - | Ground, Air |
| Watch Tower | 1,000 | 1,190 | Piercing | ~38-40 | ~0.5 | ~700 | - | Ground, Air |
| Greater Watch Tower | 5,000 | 6,190 | Piercing | ~157-158 | ~0.5 | ~800 | - | Ground, Air |
| Ultimate Watch Tower | 25,000 | 31,190 | Piercing | ~609-610 | ~0.5 | ~800 | - | Ground, Air |
| Lesser Cannon | 150 | 190 | Siege | ~16-19 | ~2.0 | ~500 | ~150 | Ground |
| Cannon | 1,000 | 1,190 | Siege | 77-81 | ~2.0 | 500 | ~200 | Ground |
| Greater Cannon | 5,000 | 6,190 | Siege | ~294-298 | ~2.0 | ~600 | ~250 | Ground |
| Ultimate Cannon | 25,000 | 31,190 | Siege | 1,147-1,153 | ~2.0 | 600 | ~300 | Ground |

## 3.2 Cutter line

| Tower | Gold | Total | Type | Damage | Speed | Range | Splash | Targets |
| ----- | ---- | ----- | ---- | ------ | ----- | ----- | ------ | ------- |
| Lesser Cutter | 10 | 10 | Normal | ~1-1 | ~0.333 | ~150 | - | Ground |
| Cutter | 30 | 40 | Normal | ~3-3 | ~0.333 | ~150 | - | Ground |
| Lesser Carver | 150 | 190 | Normal | ~14-16 | ~0.333 | ~150 | - | Ground |
| Carver | 1,000 | 1,190 | Normal | ~69-75 | ~0.333 | ~150 | - | Ground, Air |
| Greater Carver | 5,000 | 6,190 | Normal | ~291-299 | ~0.333 | ~200 | - | Ground, Air |
| Ultimate Carver | 25,000 | 31,190 | Normal | ~1,180-1,191 | ~0.333 | ~200 | - | Ground, Air |
| Lesser Crusher | 150 | 190 | Normal | ~24-26 | ~5.0 | ~150 | ~300 | Ground, Air |
| Crusher | 1,000 | 1,190 | Normal | ~136-141 | ~5.0 | ~150 | ~300 | Ground, Air |
| Greater Crusher | 5,000 | 6,190 | Normal | ~601-608 | ~5.0 | ~150 | ~350 | Ground, Air |
| Ultimate Crusher | 25,000 | 31,190 | Normal | ~2,395-2,403 | ~5.0 | ~150 | ~400 | Ground, Air |

`?` The 9.4 sheet has the Carver branch hitting Ground only at 150g and Ground + Air from
1,000g upwards. That looks like a data slip rather than a design, but it is what the sheet
says.

## 3.3 Sentry line

| Tower | Gold | Total | Type | Damage | Speed | Range | Splash | Targets |
| ----- | ---- | ----- | ----- | ------ | ----- | ----- | ------ | ------- |
| Lesser Sentry | 10 | 10 | Magic | ~2-2 | ~1.5 | ~800 | - | Ground, Air |
| Sentry | 30 | 40 | Magic | ~6-6 | ~1.5 | ~800 | - | Ground, Air |
| Lesser Defender | 150 | 190 | Magic | 8-11 | 1.2 | 800 | 100 | Ground, Air |
| Defender | 1,000 | 1,190 | Magic | 41-44 | 1.2 | 800 | 125 | Ground, Air |
| Greater Defender | 5,000 | 6,190 | Magic | 160-163 | 1.2 | 900 | 175 | Ground, Air |
| Ultimate Defender | 25,000 | 31,190 | Magic | 585-588 | 1.2 | 900 | 225 | Ground, Air |
| Lesser Turret | 150 | 190 | Siege | 19-27 | 0.8 | 900 | - | **Air only** |
| Turret | 1,000 | 1,190 | Siege | 162-170 | 0.8 | 900 | - | **Air only** |
| Greater Turret | 5,000 | 6,190 | Siege | 553-561 | 0.8 | 1,000 | - | **Air only** |
| Ultimate Turret | 25,000 | 31,190 | Siege | 2,022-2,030 | 0.8 | 1,000 | - | **Air only** |

## 3.4 Notes

No Basic tower has an ability. **Prioritize** (toggles between preferring nearby air
creeps and default targeting) exists on every tower that can hit both ground and air, and is
implemented - see `game_rules.md`. It is therefore offered by every tower in this section
except the Cannon branch, which cannot hit air, and the Turret branch, which cannot hit
ground.

**Elemental Core - 200g, Chaos, ~6-7 damage, ~1.0 speed, ~600 range, Ground + Air.** The
generic technology base tower, and IMPLEMENTED. It has no ability and is not part of any
Basic line; it is the thing that morphs for free into an element's 200g tower once that
element's Basic tech is owned. It is the fourth and last tower the builder can place.

The free morph falls out of the existing cost model rather than needing a rule of its own:
`gold_cost` is the price of ONE step, so an element's 200g base tower authors 0 there and 200
in `total_gold_cost`. The Core is what charged the 200, and the sell refund reads the total.

`?` The 9.4 sheet lists a "total cost" of 1,000 for it, which does not match its 200g price -
probably a spreadsheet artefact.

---

# 4. Elemental towers

**IMPLEMENTED.** Every tower in this section exists as a `BuildingStats`
resource under `Resources/UnitStats/Towers/`, and every ability in it as a
`TowerPassive` resource under `Resources/Abilities/Towers/`. Per 8.1 those files
are now the authority and this section is the readable mirror - change the
`.tres` and the row here in the same commit.

The three decisions section 3 had to make to turn its rows into resources are
made the same way here, and they are not repeated: range and splash are divided
by 128, attack speed is INVERTED into attacks per second, and health and armour
come from the price tier alone (1.4). Two more are made only here:

- **Delivery is chosen per PATH**, the way section 3 chooses it per branch, and
  on the same grounds - 7.2 records that no projectile data survives. What the
  ability DESCRIBES is what leaves the tower: the Moonbeam calls a meteor down, the
  Crystal fires a needle, the Beastmaster's attack is instant.
- **Every ability's numbers are authored in the game's own units**, not the
  source's: a 400 AoE is written as the 3 cells it snaps to and "-3.75% per
  hit" as 0.0375. The conversion happens once, in the generator's table, so a
  `.tres` can be read against its script without a divisor in the way.

Six pieces of these abilities are approximated or left out, and `game_rules.md`
lists all six under "What of the elemental abilities is NOT built" rather than
leaving them to be rediscovered.

`?` **A tower AURA builds up over a few seconds rather than landing whole.**
The source states an aura as one figure and applies it the moment a creep is in
range. Here every aura grips in equal steps - a creep gains one step per tower
per interval while it stands in the radius, and the aura is worth that share of
the figure below until it reaches the top. It drains again once nothing is
holding the creep, after a short window that lets the grip linger across a gap.
The figures in this section are what a FULLY built aura does; the ramp is in
GameConfig and is shared by all three towers that have one - Ultimate Titan
Vault, Ultimate Lich and the Sludge Monstrosity line.

`?` **A tower's aura and its attack are separate.** The source's Titan Defense
Mechanism reads as a tower whose attack debuffs AND whose aura debuffs; here a
tier with an aura has a plain attack and does all of it through the aura, while
the tiers below have no aura and debuff what they hit. Same effects, one source
each, and it is what the tower's own in-game description already describes.

`?` **"Slow duration increased by N sec" applies to slows as they LAND**, not to
the ones already running. Topping up running chills from an aura that reaches a
creep several times a second would make every slow on anything standing in it
permanent, which is plainly not what the source means.

`?` **Void 1's rift picks around the creep it is SHOOTING, and fires on an
attack.** The source marks a *random* creep within 300 AoE of the tower once its
mana is full. Here the tower has to be attacking for the rift to go off at all,
and the search is centred on the creep it is attacking rather than on itself: it
takes that creep if it can be taken, otherwise the nearest creep to it that can,
and does not fire at all if nothing in the AoE is eligible - which keeps the mana
for the next attack instead of spending it on nobody. The AoE, the delay, the
damage, the 9 second per-creep cooldown and the mana refund are all unchanged.
The reason is readability: a Harbinger covering a corner should rift the pack
going past that corner, and a random creep somewhere behind the tower is damage
a player cannot connect to anything they watched happen.

`?` **Void 1's per-creep cooldown runs from the LANDING, not from the mark.**
The source says a creep can only be affected once every 9 seconds and does not
say which end that is counted from. Counted from the mark it would be partly
eaten by the rift's own delay - 9 seconds on a 3.6 second rift would leave 5.4
seconds of freedom - so it is counted from the moment the creep is put back
down. The full 9 is then time the player actually watches the creep walk.

`?` **Void's spread wastes a failed attempt.** The source says Void Growth
triggers once; it does not say what happens if there is nothing to convert when
the bar fills. Here that counts as the one attempt - the tower does not keep the
charge waiting for a neighbour to be built later. Its priority when there IS
something (cheapest first, then nearest) is the source's own fallback rule
written as an ordering rather than as two searches.

`?` **Ice 2's pierce is a travelling SHOT here, not an instant line.** The source
resolves Ice Lance the moment the attack lands, on everything standing between
the tower and its target, out to the tower's attack range. This project fires a
real spike that flies in a straight line and damages creeps as it passes them,
and gives it a travel distance of its own - eight tower widths, longer than the
tower's range - instead of stopping at that range. So it can miss a creep that
walks aside and can catch one that walks in, neither of which the source does,
and it reaches a little further down the lane. The target count and the per-creep
damage ramp are unchanged. `game_rules.md` describes the rule.

`?` **One thing here is ADDED rather than copied, and it is the Moonbeam's
burning ground.** The source gives Fire (1) a plain meteor; this project has it
leave the crater alight for a few seconds afterwards, dealing a share of the
attack's own damage as Spell Damage over part of the splash radius it already
had. It is extra output the source does not grant, so the line is stronger here
than the table below reads - the `.tres` is the authority for the numbers, and
`game_rules.md` describes the rule. Worth revisiting if Fire (1) turns out
overtuned against the rest of the roster.

Every element has the same shape:

    Elemental Core 200g --(free, needs Basic tech)--> element base tower 200g
      -> 800g upgrade  (needs Basic tech)
        -> Lesser (1) 4,000g -> Greater (1) 10,000g -> Ultimate (1) 30,000g
        -> Lesser (2) 4,000g -> Greater (2) 10,000g -> Ultimate (2) 30,000g

The 200g and 800g towers are shared by both paths. The "Gold" column is the price of that
single upgrade, not the running total. Primal is the one exception to the price ladder: its
base tower (Quarry) is listed at 0 gold because it is reached by morphing an already-paid-for
Elemental Core - the same as every other element's 200g tower, just recorded differently in
the source.

Health and armour are not repeated per tower: they depend only on the price tier and are in
section 1.4. `Mana` columns are filled in only where a tower actually uses mana.

## 4.1 Arcane

- **Path (1): Spellslinger** - Apprentice -> Sorcerer -> **Lesser** -> Greater -> Ultimate
- **Path (2): Arcane Orb** - Apprentice -> Sorcerer -> **Lesser** -> Greater -> Ultimate

| Tower | Gold | Type | Damage | Speed | Range | Splash | Targets | Mana |
| ----- | ---- | ---- | ------ | ----- | ----- | ------ | ------- | ---- |
| Apprentice | 200 | Magic | 11-13 | 0.8 | 900 | - | Ground, Air | 32 |
| Sorcerer | 800 | Magic | 29-31 | 0.8 | 900 | - | Ground, Air | 64 |
| Lesser Spellslinger | 4,000 | Magic | 51-54 | ~1.0 | ~800 | - | Ground, Air | 50 |
| Greater Spellslinger | 10,000 | Magic | 225-228 | ~1.0 | ~800 | - | Ground, Air | 50 |
| Ultimate Spellslinger | 30,000 | Magic | 852-855 | ~1.0 | ~800 | - | Ground, Air | 90 |
| Lesser Arcane Orb | 4,000 | Chaos | 71-73 | 0.8 | ~900 | - | Ground, Air | 100 `?` |
| Greater Arcane Orb | 10,000 | Chaos | 216-218 | 0.8 | 900 | - | Ground, Air | 100 `?` |
| Ultimate Arcane Orb | 30,000 | Chaos | 602-604 | 0.8 | 900 | - | Ground, Air | 100 `?` |

**Arcanize (1)** *(Apprentice)* - attacks increase mana by 1. At maximum mana, damage dealt
is increased by **100%**.

**Arcanize (2)** *(Sorcerer)* - as above but **+150%** at maximum mana. Mana is not reduced
when the tower is upgraded.

**Spellcaster (1)** *(Lesser Spellslinger)* - regenerates 10 mana/sec. Casts **Frostfire**
every 3.34 sec on a creep within 600 AoE, dealing **90 Spell Damage per second for 15 sec**
and slowing it by 8% per tick up to 40%. At full mana an attack is spent as an **Arcane
Orb**: +110 bonus damage and 180 splash. Any target hit increases the Spell Damage of the
next Frostfire by 10%.

**Spellcaster (2)** *(Greater Spellslinger)* - identical shape. Frostfire **250 Spell
Damage/sec**, slow 10% per tick up to 40%; Arcane Orb +315 bonus damage, 240 splash.

**Spell Mastery** *(Ultimate Spellslinger)* - Frostfire **600 Spell Damage/sec for 15 sec**
within 800 AoE, slow 12.5% per tick up to 50%. Attacks use up to 33% of max mana to fire an
Arcane Orb: +750 bonus splash damage, 240 splash. Each target hit raises the next Frostfire's
Spell Damage by 15%. Regenerates 10 mana/sec. **Aether Attunement** is exclusive to this tier
as of 12.0a: 100% of damage dealt is re-applied to an attuned target every 0.5 sec; the
target can be set manually on a shared 30 sec cooldown (reset if it dies).

**Shifting Power (1)** *(Lesser Arcane Orb)* - attacks bounce up to 3 times, +2.0 mana per
target hit. Damage dealt is increased by the current mana percentage, up to +50%. Every other
attack is dealt as Spell Damage. +15% damage against flying creeps. Mana decreases by 2/sec.

**Shifting Power (2)** *(Greater Arcane Orb)* - bounces up to 4 times, +2.25 mana per target,
bounce range 220. +20% damage against flying. Otherwise as (1).

**Arcane Surge** *(Ultimate Arcane Orb)* - attacks bounce, +4 mana per target hit, bounce
range 240. Every other attack is dealt as Spell Damage. While above 80% mana, attacks bounce
to **2 additional targets** and mana drains at 15/sec instead of 8/sec. +33% damage against
flying creeps.

## 4.2 Earth

- **Path (1): Ancient Warden** - Rockfall -> Avalanche -> **Lesser** -> Greater -> Ultimate
- **Path (2): Scorpion** - Rockfall -> Avalanche -> **Lesser** -> Greater -> Ultimate

Earth 1 is the heavy Siege splash line with permanent armour erosion. Earth 2 was made pure
single-target in 12.0a.

| Tower | Gold | Type | Damage | Speed | Range | Splash | Targets | Mana |
| ----- | ---- | ---- | ------ | ----- | ----- | ------ | ------- | ---- |
| Rockfall | 200 | Siege | ~18-22 | ~2.5 | ~300 | ~250 | Ground | - |
| Avalanche | 800 | Siege | ~75-87 | ~2.5 | ~300 | ~250 | Ground | - |
| Lesser Ancient Warden | 4,000 | Siege | 230-248 | ~2.5 | ~400 | 300 (full damage) | Ground | - |
| Greater Ancient Warden | 10,000 | Siege | 518-536 | ~2.5 | ~450 | 350 (full damage) | Ground | - |
| Ultimate Ancient Warden | 30,000 | Siege | 1,492-1,510 | ~2.5 | ~500 | 400 (full damage) | Ground | - |
| Lesser Scorpion | 4,000 | Piercing | 196-206 | ~0.7 | ~700 | - | Ground, Air | - |
| Greater Scorpion | 10,000 | Piercing | 498-508 | ~0.7 | ~700 | - | Ground, Air | - |
| Ultimate Scorpion | 30,000 | Piercing | 1,246-1,273 | 0.5 | ~700 | - | Ground, Air | 999 |

**Shatter Armor (1)** *(Rockfall)* - attacks **permanently** reduce the armour of creeps hit
by 0.1, down to a floor of 1.

**Shatter Armor (2)** *(Avalanche)* - permanently -0.1 armour, down to a floor of 0.

**Devastating Attack (1)** *(Lesser Ancient Warden)* - attacks permanently reduce armour by
0.12, down to 0. Deals **full damage across the whole splash radius**.

**Devastating Attack (2)** *(Greater Ancient Warden)* - permanently -0.2 armour, full damage
across the splash radius.

**Nature's Guidance** *(Ultimate Ancient Warden)* - permanently -0.5 armour down to 0, full
damage across the splash radius, and heals the tower for **2.35% of damage dealt**.

**Germinate (1)** *(Lesser Scorpion)* - after not attacking for over 1 second, the next 5
attacks gain +10% damage per 0.5 sec of idling, up to +50%. Attacks can **critical strike for
+50% damage**; the chance rises as the target's health falls, up to 50%.

**Germinate (2)** *(Greater Scorpion)* - idle bonus +15% per 0.5 sec up to +75%; crit +50%
damage with up to 60% chance.

**Lethal Strike** *(Ultimate Scorpion)* - gains **5 mana per attack**; the critical strike
*damage* percentage equals current mana. Crit *chance* is based on the target's current health
percentage (lower health, higher chance) capped at 75%. Killing a target resets mana to 100.
Idling over 1 second gives the next 5 attacks +20% damage per 0.5 sec up to +100% **and a 100%
crit chance**; a kill refreshes that idle bonus to its maximum.

## 4.3 Fire

- **Path (1): Moonbeam** - Fire Pit -> Magma Well -> **Lesser** -> Greater -> Ultimate
- **Path (2): Firelord** - Fire Pit -> Magma Well -> **Lesser** -> Greater -> Ultimate

Fire 1 is a decaying-mana burst line: it is at its strongest the moment it is built and
weakens over roughly a 2-minute window. Fire 2 is a proc line built around Volcanic Eruption.

| Tower | Gold | Type | Damage | Speed | Range | Splash | Targets | Mana |
| ----- | ---- | ---- | ------ | ----- | ----- | ------ | ------- | ---- |
| Fire Pit | 200 | Normal | 17-20 | 2.0 | ~400 | ~150 | Ground, Air | - |
| Magma Well | 800 | Normal | 58-60 | 2.0 | ~400 | ~200 | Ground, Air | - |
| Lesser Moonbeam | 4,000 | Siege | 131-134 | ~3.0 | ~800 | 275 | Ground | 100 |
| Greater Moonbeam | 10,000 | Siege | 268-271 | ~3.0 | ~975 | ~325 | Ground | 100 |
| Ultimate Moonbeam | 30,000 | Siege | 871-874 | ~3.0 | 1,200 | ~400 | Ground | 45 |
| Lesser Firelord | 4,000 | Normal | 325-333 | 1.0 | ~400 | ~75 | Ground, Air | - |
| Greater Firelord | 10,000 | Normal | 549-557 | 1.0 | ~400 | ~100 | Ground, Air | - |
| Ultimate Firelord | 30,000 | Normal | 980-988 | 1.0 | ~500 | 200 | Ground, Air | - |

**Ignite (1)** *(Fire Pit)* - ignites a ground creep every 2.1 sec within a 400 radius,
dealing **5 Spell Damage per second for 8 sec**.

**Ignite (2)** *(Magma Well)* - as above, **13 Spell Damage per second for 8 sec**.

**Blazing Inferno (1)** *(Lesser Moonbeam)* - starts at 100% mana on upgrade, **loses 0.83%
mana per second and can never regain it**. Attacks deal up to **+300% damage** scaled by
current mana percentage. While mana is above 0, each attack also makes the tower explode for
**66% of the damage dealt** as Spell Damage within 200 AoE.

**Blazing Inferno (2)** *(Greater Moonbeam)* - same decay, explosion **80% of damage dealt**
within 250 AoE.

**Frenzied Flames** *(Ultimate Moonbeam)* - regenerates 10 mana/sec (max 45). Attacks
consume mana to spew flames at the target location for 3 sec within 300 AoE, dealing up to
**1,575 Spell Damage per second** scaled by the mana spent.

**Volcanic Eruption (1)** *(Lesser Firelord)* - 40% chance to deal **+100% bonus damage as
Spell Damage to up to 3 targets** and permanently reduce their armour by **7% of its maximum**.
The targets are creeps the tower's own SPLASH covers - the count is a ceiling on that area, not
a reach of its own - and the armour share is taken off the creep's base figure, so two
eruptions take the same number of points as each other.

**Volcanic Eruption (2)** *(Greater Firelord)* - 40% chance, **5 targets**, armour **-12%**.

**Magma Blast** *(Ultimate Firelord)* - 40% chance, **8 targets**, armour **-12%**. Every 5th
attack triggers it with 100% chance. Deals an extra **+6% bonus Spell Damage for every 10% of
base armour the target is missing**.

## 4.4 Holy

- **Path (1): Divineshroom** - Light Flies -> Holy Lantern -> **Lesser** -> Greater -> Ultimate
- **Path (2): Titan Vault** - Light Flies -> Holy Lantern -> **Lesser** -> Greater -> Ultimate

**Holy 1 is the anti-air path**: from the Lesser tier onwards it targets air creeps only, and
pays for that with heavy splash, slow and negative armour. Holy 2 is the multi-target support
line that amplifies everyone else's Spell Damage.

| Tower | Gold | Type | Damage | Speed | Range | Splash | Targets | Hits |
| ----- | ---- | ---- | ------ | ----- | ----- | ------ | ------- | ---- |
| Light Flies | 200 | Piercing | 11-12 | ~1.8 | ~800 | - | Ground, Air | 5 |
| Holy Lantern | 800 | Piercing | 35-36 | ~1.8 | ~850 | - | Ground, Air | 6 |
| Lesser Divineshroom | 4,000 | Normal | 232-233 | ~1.0 | ~400 | ~200 | **Air only** | 1 |
| Greater Divineshroom | 10,000 | Normal | 443-444 | ~1.0 | ~450 | ~250 | **Air only** | 1 |
| Ultimate Divineshroom | 30,000 | Normal | 1,124-1,126 | ~1.0 | ~500 | ~300 | **Air only** | 1 |
| Lesser Titan Vault | 4,000 | Piercing | 114-115 | ~1.8 | ~900 | - | Ground, Air | 7 |
| Greater Titan Vault | 10,000 | Piercing | 315-316 | ~1.8 | ~1,000 | - | Ground, Air | 8 |
| Ultimate Titan Vault | 30,000 | Piercing | 900-901 | ~1.8 | ~1,000 | - | Ground, Air | 11 |

"Hits" is the total number of creeps struck per attack (primary + additional).

**Bursting Light (1)** *(Light Flies)* - attacks hit 4 additional targets.

**Bursting Light (2)** *(Holy Lantern)* - attacks hit 5 additional targets.

**Light Burst (1)** *(Lesser Divineshroom)* - slows targets hit by **3.33% per hit up to 40%**
and reduces their armour by **0.12** per hit. The armour reduction can push armour **below
zero, down to -3**.

**Light Burst (2)** *(Greater Divineshroom)* - slow **4.16% per hit up to 50%**, armour
**-0.15** per hit, floor -3.

**Divine Spores** *(Ultimate Divineshroom)* - slow **6% per hit up to 66%**, armour **-0.25**
per hit, floor -3. Additionally heals friendly towers within 300 AoE for **10% of damage
dealt**.

**Luminous Grasp (1)** *(Lesser Titan Vault)* - attacks hit 6 additional targets; each target
takes **+12% Spell Damage for 5 sec** and is slowed by **14%**.

**Luminous Grasp (2)** *(Greater Titan Vault)* - hits 7 additional targets; **+12% Spell
Damage for 7 sec**, slow **18%**.

**Titan Defense Mechanism** *(Ultimate Titan Vault)* - hits 10 additional targets. Creeps
within a **700 AoE** aura take **+15% Spell Damage**, are slowed by **24%**, have their slow
duration extended by 2 sec, and have their attack damage reduced by 20%.

## 4.5 Ice

- **Path (1): Lich** - Obelisk -> Runic Monolith -> **Lesser** -> Greater -> Ultimate
- **Path (2): Crystal** - Obelisk -> Runic Monolith -> **Lesser** -> Greater -> Ultimate

Ice 1 is the chill / slow line with splash. Ice 2 was reworked in 11.4a into the **only tech
path in the game that fully ignores creep armour value**, in exchange for lower base damage.

| Tower | Gold | Type | Damage | Speed | Range | Splash | Targets |
| ----- | ---- | ---- | ------ | ----- | ----- | ------ | ------- |
| Obelisk | 200 | Magic | 14-17 | ~1.5 | ~500 | 100 | Ground, Air |
| Runic Monolith | 800 | Magic | 45-48 | ~1.5 | ~600 | 100 | Ground, Air |
| Lesser Lich | 4,000 | Magic | 162-166 | 1.5 | ~600 | 150 | Ground, Air |
| Greater Lich | 10,000 | Magic | 494-498 | 1.5 | ~600 | 150 | Ground, Air |
| Ultimate Lich | 30,000 | Magic | 946-950 | 1.5 | ~600 | 225 | Ground, Air |
| Lesser Crystal | 4,000 | Piercing | 205-207 | 1.4 | ~700 | - (pierces) | Ground, Air |
| Greater Crystal | 10,000 | Piercing | 489-491 | 1.4 | ~700 | - (pierces) | Ground, Air |
| Ultimate Crystal | 30,000 | Piercing | 1,333-1,335 | 1.4 | ~800 | - (pierces) | Ground, Air |

**Frost Attack (1)** *(Obelisk)* - each attack chills the target, **-3.75% movement speed per
hit, up to -20%**.

**Frost Attack (2)** *(Runic Monolith)* - **-4.5% per hit, up to -25%**.

**Frost Blast (1)** *(Lesser Lich)* - **-5.5% per hit, up to -30%**; slow duration increased
by 1 sec.

**Frost Blast (2)** *(Greater Lich)* - **-6.35% per hit, up to -36%**; slow duration increased
by 1.5 sec.

**Chilling Death** *(Ultimate Lich)* - creeps within a **700 AoE** aura have their attack
speed reduced by **15%**. Each attack chills **-7.5% up to -45%** and increases slow duration
by 3 sec. A target chilled by 45% is **Frostbitten**: it takes **2% of its maximum health as
Spell Damage**, and can only be Frostbitten once every 15 sec.

**Ice Lance (1)** *(Lesser Crystal)* - attacks pierce and hit every creep in a line towards
the target, out to the tower's attack range (this project flies a real spike a fixed distance
instead - see the note in the section preamble), up to **15 targets**. Damage increases by **5% per
target hit**. **Ignores creep armour value.**

**Ice Lance (2)** *(Greater Crystal)* - up to 15 targets, **+7.5% per target hit**, ignores
armour value.

**Crystalized Light** *(Ultimate Crystal)* - up to **20 targets**, **+10% per target hit**,
ignores armour value. Creeps hit that use mana for their abilities have their mana
regeneration crystalized, **losing 0.35 mana per second for 12 sec**.
## 4.6 Lightning

- **Path (1): Annihilation Glyph** - Shock Particle -> Power Generator -> **Lesser** -> Greater -> Ultimate
- **Path (2): Orb Keeper** - Shock Particle -> Power Generator -> **Lesser** -> Greater -> Ultimate

Lightning 1 is the long-range ramping single-target line. Lightning 2 was redesigned in 11.0a
into short-range single-target damage with stun utility (its old anti-air identity was
removed).

| Tower | Gold | Type | Damage | Speed | Range | Splash | Targets | Mana |
| ----- | ---- | ---- | ------ | ----- | ----- | ------ | ------- | ---- |
| Shock Particle | 200 | Chaos | ~20-20 | ~0.5 | ~200 | - | Ground, Air | - |
| Power Generator | 800 | Chaos | ~80-80 | ~0.5 | ~200 | - | Ground, Air | - |
| Lesser Annihilation Glyph | 4,000 | Chaos | 499-511 | ~2.0 | ~1,000 | - | Ground, Air | - |
| Greater Annihilation Glyph | 10,000 | Chaos | 1,122-1,134 | ~2.0 | ~1,250 | - | Ground, Air | - |
| Ultimate Annihilation Glyph | 30,000 | Chaos | 2,416-2,428 | ~2.0 | ~1,500 | - | Ground, Air | - |
| Lesser Orb Keeper | 4,000 | Chaos | 240-240 | 0.5 | ~200 | - | Ground, Air | 100 |
| Greater Orb Keeper | 10,000 | Chaos | 590-590 | 0.5 | ~200 | - | Ground, Air | 100 |
| Ultimate Orb Keeper | 30,000 | Chaos | 850-850 | 0.5 | ~200 | - | Ground, Air | 100 |

**Overcharge (1)** *(Shock Particle)* - attacks deal **+2 damage for every 10% of the target's
current health**.

**Overcharge (2)** *(Power Generator)* - **+7 damage per 10% current health**.

`?` The 9.4 sheet's ability cell for Shock Particle reads "Arcanize (2)", which is the
Sorcerer's ability and clearly wrong; the changelog treats Shock Particle as carrying
Overcharge (1). The sheet also has a stray "extra damage per hit: 15" column value for it.

**Focused Lightning (1)** *(Lesser Annihilation Glyph)* - each attack on the **same** target
increases base damage by **50%**, **capped at 5 attacks**. Attacking a new target resets the
bonus. *(The air-creep slow aura this tower used to have was removed in 11.6a.)*

**Focused Lightning (2)** *(Greater Annihilation Glyph)* - **+75%** per attack on the same
target, capped at 5.

**Annihilation** *(Ultimate Annihilation Glyph)* - **+100%** base damage per attack on the
same target, capped at 5, and each attack **chains to 2 additional targets within 500 radius**
at full damage. New target resets the bonus.

**Crash Lightning (1)** *(Lesser Orb Keeper)* - attacks gain **10 mana** and deal additional
damage equal to **1.2% of the target's current health**. At 100 mana the tower spends all of
it to **stun the target for 0.67 sec** and deal **300 bonus Spell Damage**.

**Crash Lightning (2)** *(Greater Orb Keeper)* - **15 mana** per attack, **1.8%** current
health, stun 0.67 sec, **800 bonus Spell Damage**.

**Arc Lightning** *(Ultimate Orb Keeper)* - **20 mana** per attack, **2.5%** current health.
At 100 mana: stun 0.67 sec, **2,500 bonus Spell Damage**, and the tower's *maximum* mana drops
by 5. When maximum mana falls below 20 it resets to 100 and **lowers the maximum mana of other
Ultimate Orb Keepers within 150 AoE by 20**.

## 4.7 Primal *(added in 10.0a - not present in the 9.4 sheets)*

- **Path (1): Primalist** - Quarry -> Coreway -> **Lesser** -> Greater -> Ultimate
- **Path (2): Beastmaster** - Quarry -> Coreway -> **Lesser** -> Greater -> Ultimate

Primal is the economy element: path 1 generates gold on every attack, at the cost of
generating less the more Primal towers are packed together. Path 2 is the stun/beast line.

| Tower | Gold | Type | Damage | Speed | Range | Splash | Targets | Mana |
| ----- | ---- | ---- | ------ | ----- | ----- | ------ | ------- | ---- |
| Quarry | 0 | Siege | 23-29 | 2.0 | 700 | - | Ground, Air | 4 |
| Coreway | 800 | Siege | 92-98 | 2.0 | 700 | - | Ground, Air | 4 |
| Lesser Primalist | 4,000 | Magic | 255-269 | 3.0 | 900 | - | Ground, Air | 90 |
| Greater Primalist | 10,000 | Magic | 637-651 | 3.0 | 900 | - | Ground, Air | 90 |
| Ultimate Primalist | 30,000 | Magic | 1,674-1,688 | 3.0 | 900 | - | Ground, Air | 90 |
| Lesser Beastmaster | 4,000 | Siege | 130-136 | 0.7 | 700 | - | Ground, Air | 100 |
| Greater Beastmaster | 10,000 | Siege | 348-354 | 0.7 | 700 | - | Ground, Air | 100 |
| Ultimate Beastmaster | 30,000 | Siege | 974-980 | 0.7 | 700 | - | Ground, Air | 100 |

**Break (1)** *(Quarry)* - gains 1 mana per attack; at full mana (4) **stuns the target for
0.8 sec**. *(This replaced the old gold-generating Prospect (1) in 12.0a - basic Primal no
longer makes gold, the whole economy is behind the Primal 1 upgrade.)*

**Break (2)** *(Coreway)* - gains 1 mana per attack; at full mana **stuns for 1.0 sec**.

**Ancient Bloom (1)** *(Lesser Primalist)* - generates up to **120 gold per attack**, reduced
by 48 for every nearby Primal Technology tower within 250 AoE, down to a minimum of 12.
*Quarry and Coreway no longer count towards that reduction as of 12.4a.* Generates 13
mana/sec; at full mana it blasts the earth for **350 Magic Physical Damage** to creeps within
200 AoE of the primary target and reduces their armour by 1 for 7 sec. Refunds 50% of the mana
if the blast hits 3 or fewer targets.

**Ancient Bloom (2)** *(Greater Primalist)* - up to **300 gold per attack**, -120 per nearby
Primal tower, minimum 30. Blast **775 Magic Physical Damage**, armour -2 for 7 sec, same 200
AoE and 50% refund rule.

**Primordial Bond** *(Ultimate Primalist)* - generates **750 gold per attack** flat, with no
crowding penalty. Generates 13 mana/sec; at full mana blasts for **1,800 Magic Physical
Damage** within 200 AoE and reduces armour by 3 for 7 sec, with the same 50% refund rule. The
Builder attack buff and the "root a creep about to steal a life" effect this tower had at
introduction are **removed**.

**Bloodthirst (1)** *(Lesser Beastmaster)* - attacks hit 1 additional target within 400 AoE
and gain **5 mana per target hit**. At full mana, unleashes a beast towards the target hit (or
a manually set point) up to 700 range, dealing **240 Siege Physical Damage** to ground creeps
in its path and **stunning them for 0.5 sec**. A creep can only be stunned this way once every
8 sec.

**Bloodthirst (2)** *(Greater Beastmaster)* - beast **570 Siege Physical Damage**, stun
**0.7 sec**.

**Stampede** *(Ultimate Beastmaster)* - attacks hit 1 additional target within 500 AoE, gain
5 mana per target hit, and **damage increases by 10% per 100 range to the target, up to
+100%**. At full mana, unleashes a beast up to **1,200 range** dealing **1,865 Siege Physical
Damage** and stunning for **1.2 sec** (8 sec immunity per creep). The beast's direction can be
set manually with the **Stampede Target** ability; targeting the tower itself resets
it to "wherever the attack landed".

## 4.8 Unholy

- **Path (1): Gravedigger** - Plague Well -> Defiled Fountain -> **Lesser** -> Greater -> Ultimate
- **Path (2): Alchemist** - Plague Well -> Defiled Fountain -> **Lesser** -> Greater -> Ultimate

Unholy 1 is the multi-target poison-stacking line (it inherited the AoE-explosion role from
Earth 2 in 12.0a). Unholy 2 is the permanent-damage-gain splash line.

| Tower | Gold | Type | Damage | Speed | Range | Splash | Targets | Mana |
| ----- | ---- | ---- | ------ | ----- | ----- | ------ | ------- | ---- |
| Plague Well | 200 | Normal | ~16-17 | ~1.0 | ~500 | - | Ground, Air | - |
| Defiled Fountain | 800 | Normal | ~58-59 | ~1.0 | ~600 | - | Ground, Air | - |
| Lesser Gravedigger | 4,000 | Normal | 148-152 | 0.7 | ~700 | - | Ground, Air | - |
| Greater Gravedigger | 10,000 | Normal | 246-250 | 0.7 | ~700 | - | Ground, Air | - |
| Ultimate Gravedigger | 30,000 | Normal | 1,089-1,093 | 0.7 | ~700 | - | Ground, Air | - |
| Lesser Alchemist | 4,000 | Siege | 254-260 | 2.0 | ~500 | ~250 | Ground, Air | - |
| Greater Alchemist | 10,000 | Siege | 649-655 | 2.0 | ~500 | ~250 | Ground, Air | - |
| Ultimate Alchemist | 30,000 | Siege | 1,678-1,686 | 2.0 | ~600 | ~300 | Ground, Air | 125 |

**Corruption (1)** *(Plague Well)* - corrupts creeps hit for **4 sec**; a corrupted creep
explodes on death for **28 Spell Damage** within a 160 radius.

**Corruption (2)** *(Defiled Fountain)* - 4 sec, **76 Spell Damage** within 160 radius.

**Poison (1)** *(Lesser Gravedigger)* - attacks hit **1 additional target** and apply a stack
of poison damage equal to **20% of the damage dealt**, up to 10 stacks. At 10 stacks the target
explodes, dealing the stored damage to **itself** as Spell Damage. A target can only explode
once every 3 sec; stacks reset on explosion.

**Poison (2)** *(Greater Gravedigger)* - hits **2 additional targets**, stack = **25% of damage
dealt**, same 10-stack self-explosion.

**Pestilence** *(Ultimate Gravedigger)* - hits **2 additional targets**, stack = **35% of
damage dealt**. The target explodes at 10 stacks **or when killed**, dealing the stored damage
as Spell Damage to **creeps within 200 AoE**, not just itself.

**Devour Essence (1)** *(Lesser Alchemist)* - permanently gains **+2 attack damage** per creep
killed, up to **+100**. The bonus carries over when the tower is upgraded. Once the cap is
reached, further bonuses go to the closest Unholy (2) tower within 300 AoE.

**Devour Essence (2)** *(Greater Alchemist)* - **+3 per kill**, cap **+200**, same overflow.

**Unholy Concoction** *(Ultimate Alchemist)* - **+5 per kill**, cap **+500**, same overflow.
Additionally, attacks **alter the armour type of creeps hit for 8 sec** (Goblin Shredder
included). A given creep can only be altered to a specific armour type once. The armour type
to apply is chosen manually on the command card and the active choice is displayed there.

## 4.9 Void

- **Path (1): Harbinger** - Voidling -> Voidalisk -> **Lesser** -> Greater -> Ultimate
- **Path (2): Leviathan** - Voidling -> Voidalisk -> **Lesser** -> Greater -> Ultimate

Void 1 is the teleport/delay line - it drags a creep backwards along the lane and burns a
percentage of its maximum health. Void 2 is the armour-eating line that grows its own attack
damage.

| Tower | Gold | Type | Damage | Speed | Range | Splash | Targets | Mana |
| ----- | ---- | ---- | ------ | ----- | ----- | ------ | ------- | ---- |
| Voidling | 200 | Chaos | 40-44 | ~3.0 | 400 | - | Ground, Air | 45 |
| Voidalisk | 800 | Chaos | 148-152 | ~3.0 | 400 | - | Ground, Air | 45 |
| Lesser Harbinger | 4,000 | Magic | 353-355 | 1.8 | ~600 | - | Ground, Air | 60 |
| Greater Harbinger | 10,000 | Magic | 933-935 | 1.8 | 700 | - | Ground, Air | 60 |
| Ultimate Harbinger | 30,000 | Magic | 2,670-2,672 | 1.8 | ~800 | - | Ground, Air | 60 |
| Lesser Leviathan | 4,000 | Chaos | 242-244 | 1.6 | ~400 | ~150 | Ground, Air | - |
| Greater Leviathan | 10,000 | Chaos | 561-563 | 1.6 | ~400 | ~200 | Ground, Air | - |
| Ultimate Leviathan | 30,000 | Chaos | 1,637-1,639 | 1.6 | ~400 | ~250 | Ground, Air | - |

**Void Growth (1)** *(Voidling)* - regenerates 1 mana/sec and gains 1 mana per attack. At 45
mana it **transforms a nearby Lesser Archer, Lesser Cutter or Lesser Sentry within 400 radius into
a Voidling** (falling back to an Archer, Cutter or Sentry if none is found). Triggers once only.
The mana is not spent and does not reset - see the note in the section preamble on what happens
when nothing is in range.

**Void Growth (2)** *(Voidalisk)* - at 45 mana, transforms a nearby **Voidling** within 400
radius into a Voidalisk. Once only.

**Temporal Rift (1)** *(Lesser Harbinger)* - regenerates 10 mana/sec. At full mana, a
**random** creep within a 300 AoE is marked (this project picks around its attack target
instead - see the section preamble); after a 3 sec delay it is returned to its previous
location and takes **(2% of its maximum health + 300) Spell Damage**. A creep can only be
affected once every 9 sec, the effect is cancelled if it steals a life, and **50% of the mana
is refunded if the creep dies during the delay**.

**Temporal Rift (2)** *(Greater Harbinger)* - 3.2 sec delay, **(3% of maximum health + 800)
Spell Damage**, same rules.

**Whispers of the Void** *(Ultimate Harbinger)* - every **60 sec** a Greater Harbinger within
500 AoE is converted into an Ultimate Harbinger. At full mana, marks a random creep within 300
AoE; after a **3.6 sec** delay it is teleported back, taking **(5% of maximum health + 4,250)
Spell Damage** and being **slowed by 45%, ignoring all slow resistances**. 50% mana refund if
it dies during the delay.

**Feasting Void (1)** *(Lesser Leviathan)* - attacks **consume 0.17 armour** from targets hit
(down to 0) and grant the tower **+1.5 attack damage**, up to **+90**. The bonus resets if the
tower does not attack for 3 sec.

**Feasting Void (2)** *(Greater Leviathan)* - **-0.20 armour** per hit, **+3 attack damage**,
cap **+200**, same 3 sec idle reset.

**Hungering Void** *(Ultimate Leviathan)* - **-0.27 armour** per hit, **+8 attack damage**, cap
**+600**. At maximum bonus the tower gains **10% life steal** against its primary target. Same
3 sec idle reset.

## 4.10 Water

- **Path (1): Hurricane Elemental** - Splasher -> Tidecaller -> **Lesser** -> Greater -> Ultimate
- **Path (2): Sludge Monstrosity** - Splasher -> Tidecaller -> **Lesser** -> Greater -> Ultimate

Water 1 is the anti-air paralysis line with a Chaos-damage attack modifier; Water 2 is the
aura-slow line with a periodic stun.

The Sludge Monstrosity line has NO SPLASH on any tier, which is the source game's own
answer and is the whole shape of the path: everything it does to a crowd it does through
its aura, and its attack is a single heavy hit on one creep.

| Tower | Gold | Type | Damage | Speed | Range | Splash | Targets | Mana |
| ----- | ---- | ---- | ------ | ----- | ----- | ------ | ------- | ---- |
| Splasher | 200 | Piercing | 12-13 | 1.0 | ~500 | ~75 | Ground, Air | - |
| Tidecaller | 800 | Piercing | 44-45 | 1.0 | ~500 | ~75 | Ground, Air | - |
| Lesser Hurricane Elemental | 4,000 | Piercing | 286-288 | 1.2 | ~500 | ~100 | Ground, Air | - |
| Greater Hurricane Elemental | 10,000 | Piercing | 753-755 | 1.2 | ~500 | 100 | Ground, Air | - |
| Ultimate Hurricane Elemental | 30,000 | Piercing | 2,322-2,324 | 1.2 | ~500 | 125 | Ground, Air | 100 |
| Lesser Sludge Monstrosity | 4,000 | Normal | 209-212 | ~1.5 | ~600 | - | Ground, Air | - |
| Greater Sludge Monstrosity | 10,000 | Normal | 561-564 | ~1.5 | ~600 | - | Ground, Air | - |
| Ultimate Sludge Monstrosity | 30,000 | Normal | 1,622-1,625 | ~1.5 | ~600 | - | Ground, Air | - |

**Crushing Wave (1)** *(Splasher)* - every 4th attack unleashes a Crushing Wave dealing **12
Spell Damage** to creeps hit.

**Crushing Wave (2)** *(Tidecaller)* - **44 Spell Damage** every 4th attack.

**Pressuring Water (1)** *(Lesser Hurricane Elemental)* - **50% chance to paralyze a random air
creep within 400 AoE for 1.5 sec** (9 sec immunity per creep; a paralyzed air creep cannot move
and can be attacked as though it were a ground creep). **Every 3rd attack is dealt as Chaos
Physical Damage with a +25% damage bonus.**

**Pressuring Water (2)** *(Greater Hurricane Elemental)* - paralyze 50% for **1.8 sec**; every
3rd attack Chaos Physical with **+33%**.

**Raging Tempest** *(Ultimate Hurricane Elemental)* - **75% chance to paralyze** a random air
creep within 400 AoE for **2.5 sec** (9 sec immunity). Gains 3 mana per target hit. **Every 3rd
attack spends all mana on a forked lightning dealing 2,000 Chaos Physical Damage to up to 1
target per 10 mana used.**

**Torrent (1)** *(Lesser Sludge Monstrosity)* - creeps within a 400 radius are **slowed by 4.8%
every 1.5 sec, up to 24%**. Every 3rd attack **stuns the primary target for 1 sec**.

> **The 1.5 sec in the three Torrent entries is wrong and the prototype deliberately
> departs from it.** The source game runs this off ONE aura stack, applied every 0.5 sec by
> every Sludge Monstrosity in range, and everything the aura does - the slow and the
> Ultimate's damage amplification - is read off that one stack count. So a creep standing in
> two of them fills the pile twice as fast, and the per-step figures below are per STACK.
> The caps are unchanged and are still the numbers that matter. Overridden on the project
> owner's instruction; see `TorrentPassive`, which is the authority.

**Torrent (2)** *(Greater Sludge Monstrosity)* - slow **7% every 1.5 sec up to 28%**; stun
**1.2 sec** every 3rd attack.

**Crippling Decay** *(Ultimate Sludge Monstrosity)* - creeps within a 400 radius take **+10%
damage from physical attacks** and are **slowed 9% every 1.5 sec up to 36%**. Attacking the
same target 3 times in a row **stuns it for 1.8 sec**.
---

# 5. Technology Discs

**IMPLEMENTED.** All thirty-one discs exist as `BuildingStats` resources under
`Resources/UnitStats/Discs/`, their ten effects as `DiscPassive` subclasses under
`Scripts/Abilities/DiscPassives/`, and per 8.1 those files are now the authority - the tables
here are the readable mirror. Change the `.tres` and the row in the same commit. They are
generated, so in practice that means changing `Tools/ModelGen/disc_roster.py` and re-running
the disc stage.

A disc is a building that occupies exactly one tower footprint and that **creeps walk over**.
It is used to fill the holes in a maze where a tower would not earn its place, and it pays for
itself with an aura or an on-step trigger.

**Walking over it is the load-bearing half**, and it is worth being explicit because 1.5 used
to read as though it were not. A disc claims its square against anything else being BUILT
there and blocks nothing at all: the route sweep does not see it, no arrangement of discs can
seal an area, and a creep standing where one goes up is left where it is. So a disc is what
fills the holes a maze already has, never another way of making one - which is also the only
reason the two on-step effects in 5.2 can exist. See `game_rules.md`, Technology discs.

## 5.1 Structure and cost

| Tier | Name | Cost | Requirement |
| ---- | ---- | ---- | ----------- |
| 0 | Technology Disc | 2,500 | none - unlocked from the start, does nothing |
| 1 | *Element* Disc | free morph | that element's **Basic** tech |
| 2 | Advanced *Element* Disc | 250,000 | at least **2 of the 3** techs of that element |
| 3 | Ultimate *Element* Disc | 1,000,000 | **all 3** techs of that element |

The source writes these "Technology Disc: Advanced Fire". The implemented names are the same
four tiers written the way a command card can print them, and shorter for a second reason as
well: a display name is what the icon renderer names its PNG after, and a colon is not a legal
character in a Windows filename.

- **A player may own only one Ultimate disc per element** (11.0a). This is the disc equivalent
  of "you cannot fill the whole maze with the best thing".
- Morphing a disc back down to the inactive Technology Disc takes **5 seconds** (11.7a raised
  it from 3, deliberately, to discourage swapping discs on the fly to counter an incoming
  send).
- **A disc cannot attack and cannot BE attacked.** Its armour type is `Invulnerable` and it is
  not a valid target for an attacking creep at all. Together with the walking rule above, that
  makes a disc a square an attacker creep can do nothing with: it cannot destroy one, and it
  was never held up by one either.
- The technology requirement is the one place in the game where technology is asked as a
  **count** rather than as a named id. "Two of the three" is not something a single `tech_id`
  can express, so a disc morph names the ELEMENT and how many of it are needed - see
  `Scripts/Abilities/DiscUpgradeAbility.gd`.

## 5.2 Disc effects by element

Effects come from the 9.4 disc sheet unless a patch note replaced them, plus the Ultimate-tier
values supplied for this project (the 9.4 sheet only recorded the base and Advanced tiers).

### Arcane *(reworked in 10.0a)*
On-step trigger. Whenever a ground creep steps on the disc it takes **+10% Spell Damage and
cannot benefit from friendly auras** for a duration. Can trigger once per second.

| Tier | Duration |
| ---- | -------- |
| Arcane | 12 sec |
| Advanced Arcane | 20 sec |
| Ultimate Arcane | 25 sec |

### Earth
Aura. Friendly towers within **300 AoE** gain attack speed.

| Tier | Attack speed |
| ---- | ------------ |
| Earth | +8% |
| Advanced Earth | +12% |
| Ultimate Earth | +15% |

### Unholy *(reworked in 11.0a)*
Aura, attack modifier. Friendly towers within **300 AoE** have their attacks **permanently
erode the armour of creeps hit**, down to 0.

| Tier | Armour erosion per hit |
| ---- | ---------------------- |
| Unholy | -0.05 |
| Advanced Unholy | -0.067 |
| Ultimate Unholy | -0.1 |

### Primal *(added in 10.0a)*
Aura. Friendly towers within **300 AoE** gain attack range.

| Tier | Attack range |
| ---- | ------------ |
| Primal | +100 |
| Advanced Primal | +200 |
| Ultimate Primal | +250 |

Stacking rule: a weaker Primal disc must not override the range bonus of a nearby stronger one
(this was a bug fixed in 12.3a, and is a real implementation trap).

### Fire
On-step trigger. When a ground creep steps on the disc, an explosion damages it for a
percentage of its **maximum health**. That creep is then immune to every Fire disc for a short
window, and the disc itself has its own cooldown.

| Tier | Damage | Disc cooldown | Creep immunity |
| ---- | ------ | ------------- | -------------- |
| Fire | ~20% of max health | ~30 sec | ~5 sec |
| Advanced Fire | ~24% of max health | ~30 sec | ~5 sec |
| Ultimate Fire | 33% of max health | 15 sec | 3.6 sec |

### Ice
Aura, attack modifier. Friendly towers within **300 radius** have their attacks chill the
target.

| Tier | Chill per hit | Cap |
| ---- | ------------- | --- |
| Ice | ~-1% | ~-20% |
| Advanced Ice | ~-1.5% | ~-30% |
| Ultimate Ice | -1.8% | -36% |

### Lightning
Aura. Friendly towers within **500 AoE** become **static**: they heal for a share of the
Physical Damage they deal, they return a share of the damage an attacking creep does to them,
and they have a chance to stun that creep for **2 seconds**.

| Tier | Healing (of Physical Damage dealt) | Return damage | Stun chance |
| ---- | ---------------------------------- | ------------- | ----------- |
| Lightning | 1% | 500% | 15% |
| Advanced Lightning | 1.6% | 750% | ~20% |
| Ultimate Lightning | 1.75% | 1,000% | 25% |

The return damage is dealt to the creep that attacked the tower, as a multiple of the damage
that creep just did. The 9.4 sheet's 300% / 350% predate the healing rework of this disc and
are wrong.

### Holy
Aura. Friendly towers within **500 radius** gain armour and health regeneration. Only the
armour scales with tier; the regeneration does not increase past the Advanced tier.

| Tier | Armour | Health regeneration |
| ---- | ------ | ------------------- |
| Holy | ~+3 | ~+165% |
| Advanced Holy | ~+6 | ~+200% |
| Ultimate Holy | +8 | same as Advanced |

### Void
Aura. Friendly towers within **300 radius** deal bonus damage, scaled by **how many distinct
non-disc tower types stand inside the radius**: a fixed amount per unique type, up to a cap.
This is the "reward a varied maze" disc.

| Tier | Per unique type | Cap |
| ---- | --------------- | --- |
| Void | ~+2% | ~+8% |
| Advanced Void | ~+2% | ~+16% |
| Ultimate Void | +3% | +24% |

### Water
Aura. Friendly towers within **300 radius** regenerate mana. That is the whole effect - the
**whirlpool** in the 9.4 sheet (pull ground creeps to the disc's centre and stun them) has since
been removed, so do not implement it.

| Tier | Mana regen |
| ---- | ---------- |
| Water | 2.0/sec |
| Advanced Water | 4.0/sec |
| Ultimate Water | 5.4/sec |

---

# 6. Creeps

**THE WHOLE ROSTER IS IMPLEMENTED.** Every creep in 6.2 to 6.5 exists as a `CreepStats`
resource under `Resources/UnitStats/Creeps/`, and per 8.1 those files are now the
authority - the tables here are the readable mirror. Change the `.tres` and the row in the
same commit.

Four decisions had to be made to turn those rows into resources, the same way section 3
records the ones the towers needed:

- **Movement speed is divided by 128 and snapped to the nearest quarter cell**, the same
  conversion section 3 uses for range and splash. A 210 speed Sheep walks 1.75 cells a second
  and crosses a 34 cell lane in about twenty seconds. So the whole roster moves at a speed a
  player can hold: 1.25 up to 4, in quarters.
- **Every creep aura radius is 700**, which snaps to 5.5 cells. It is stored once on
  `GameConfig` rather than per creep, because the rules give every creep aura in the game one
  radius - see `game_rules.md`.
- **Spell damage is a damage TYPE** in `Config/DamageTable.gd`, sitting outside the armour
  matrix rather than being a second pipeline.
- **A creep trait's card text is GENERATED from the trait's own numbers**, never authored
  beside them - see `CreepPassive.effect_text`. So a balance change to a `.tres` moves the
  tooltip with it, and a card can never quote a figure its passive does not use. The only
  authored descriptions left are the three `TraitPassive` entries below, which have no
  numbers to generate from.

Three traits are answered by the creep's stats file rather than by a passive on its card -
flying, attacking and being a Boss - because each decides something structural before any
passive could be asked. Their card entry is a `TraitPassive`, which carries the tooltip text
and no mechanics. Everything else in 6.6 is a real passive resource.

## 6.1 How the roster is organised

Creeps have **no upgrades**. They are sorted into four tiers.

**A tier is a cost bracket and nothing else.** It is not a power ladder, not a category a
rule can test, and not a thing a creep gains or loses. It exists to group the roster into
readable chunks, and each bracket ends on that bracket's Boss:

| Tier | Cost bracket | Ends on |
| ---- | ------------ | ------- |
| 1 | 10g up to and including 1,000g | Rot Golem, the 1,000g Boss |
| 2 | above 1,000g up to and including 100,000g | Infernal, the 100,000g Boss |
| 3 | above 100,000g up to and including 500,000g | Behemoth, the 500,000g Boss |
| 4 | everything above that | Sudden Death, no upper bound |

**A tier carries no mechanical meaning.** A creep does not become stronger, cheaper or
differently targetable for being in one. In particular a lower tier is never retired by a
higher one: once a creep is unlocked it stays sendable for the rest of the match, and a
player at 20:00 can still send Sheep. The one exception belongs to Sudden Death rather than
to the idea of a tier, and is recorded in 6.5.

**Unlocking is per creep, not per tier.** Every creep carries its own start delay and
becomes available when the match clock reaches it - one at a time, every 30 seconds, in
ascending cost order (12.0a; it used to be two per minute). Tiers appear to "unlock" only
because the creeps inside one share a stretch of the clock. The Unlock column in each table
below is the authority; the tier is just where that creep happens to sit.

Each of tiers 1 to 3 holds twelve creeps and tier 4 holds eleven, which is why the source
game can give each tier **its own send building**: twelve is exactly one 4 x 3 command card.

**The prototype copies the four-building arrangement, without the buildings.** Each tier
has a sender of its own carrying that tier's twelve creeps, and none of them stands
anywhere: they are reached through a row of four squares over the unit panel. A tier with
nothing implemented is a square drawn dead rather than a gap. See `game_rules.md` under
Sending creeps.

**Sending.** One send produces a **pack of 3** creeps for a normal creep and **1** for a boss
or a large creep. Bosses steal **2 lives** instead of 1. Stock replenishes over time; initial
stock on unlock is half of maximum.

| Creep kind | Max stock | Replenish |
| ---------- | --------- | --------- |
| normal ground | ~32 | ~8 sec |
| flying | ~16 | ~8 sec |
| boss | ~8 | ~16 sec |
| attacker (Corrupted Treant, Siege Engine) | 8 | 16 sec |
| Tier 4 normal | 32 | ~4 sec |
| Tier 4 flyer | 16 | ~4 sec |
| Tier 4 boss | 8 | ~8 sec |
| Mountain Giant | 16 | ~4 sec |
| Obsidian Statue | 32 | 16 sec |
| Demon | 4 (initial 2) | 32 sec |
| Treasure Goblin | 16 (initial 8) | 2 sec |

**Tier 4's reserves are a CEILING rather than a figure per creep**, and it is the project
owner's rather than the source's: 32 for an ordinary tier 4 creep, 16 for a flyer and for
the Treasure Goblin, 8 for a Boss. A creep the source states lower keeps its own number -
the Demon's 4 and the Mountain Giant's 16 - so the ceiling only ever takes a reserve down.
The 9.4 sheet's tier 4 figures ran up to 64, which made the tier's reserves the one place a
player never had to think about a limit.

**Which creeps count as a Boss for that is a MECHANICAL question, not a shape one.** Only
the two that carry the Boss trait do - the Phoenix and the Demon. The Obsidian Statue is
sent one at a time and costs three population, so it looks like one, but it steals a single
life and is a Boss in neither the roster nor any rule: it takes the ordinary 32. Its
replenish stays at the slower 16 sec it was given, which is the one figure it keeps from
having been read as a Boss.

**Food.** Population is charged **per creep, not per send**, so one normal send of 3 costs 3
food. Every creep in the 9.4 sheet costs **1 food**, bosses included - the Phoenix tooltip
confirms 1 even though it is a Boss. Two exceptions are recorded in the changelog:

| Creep | Food |
| ----- | ---- |
| Obsidian Statue | 3 |
| Demon | 5 |

There are no other exceptions. The default food cap is 100 and is a game-mode setting.

## 6.2 Tier 1

| Creep | Unlock | Cost | Income | Bounty | HP | Armour | Type | Speed | Sent | Traits |
| ----- | ------ | ---- | ------ | ------ | -- | ------ | ---- | ----- | ---- | ------ |
| Sheep | 00:00 | 10 | 2 | 0 | ~2 | 0 | Unarmored | 210 | 2 Sheep + 1 Timber Wolf | Fast Producing |
| Skeleton Warrior | 00:30 | 25 | 4 | 2 | 12 | ~0 | ~Medium | 210 | 3 | Death Pact (1) |
| Acolyte | 01:00 | 40 | ~5 | ~4 | 26 | ~0 | ~Heavy | 240 | 3 | Unholy Sacrifice (1) |
| Forest Spider | 01:30 | ~50 | ~6 | 4 | 48 | ~1 | ~Unarmored | 270 | 3 | Skittering |
| Swordsman | 02:00 | ~70 | ~8 | 5 | 77 | ~1 | ~Medium | 240 | 3 | Devotion Aura (1) |
| Fel Orc Grunt | 02:30 | ~100 | ~11 | 7 | 70 | ~2 | ~Heavy | 270 | 3 | Fel Blood |
| Vile Temptress | 03:00 | ~150 | ~16 | 10 | 118 | ~2 | ~Light | 280 | 3 | Endurance Aura (1) |
| Shade | 03:30 | 225 | 23 | 14 | 110 | ~0 | ~Unarmored | ~150 | 3 | Flying |
| Mud Golem | 04:00 | 400 | 40 | ~23 | 238 | ~2 | ~Fortified | 280 | 3 | Lesser Spell Resistance |
| Priest | 04:30 | 600 | 58 | 35 | 290 | 2 | Light | 270 | 3 | Regen Aura (1) |
| Corrupted Treant | 05:00 | ~750 | 50 | 90 | 265 | ~2 | ~Fortified | ~270 | 3 | **Attacker** |
| Rot Golem | 05:30 | ~1,000 | 92 | 150 | 1,325 | ~5 | ~Hero | ~270 | **1** | Boss (1) |

**Corrupted Treant attack: 4-5 damage, 0.5 sec speed.** `?` The speed is an ESTIMATE from
play and is **unverified** - the game does not state it and the developer has not been asked
yet. Two more figures the source records nowhere and this project therefore chose: its
**range is 150** (1.25 cells, enough to reach a tower's corner without walking into it) and
its damage type is **Normal**. All three are in
`Resources/UnitStats/Creeps/corrupted_treant_stats.tres`.

**Timber Wolf** is not sendable on its own. It only exists as part of the Sheep pack:
6 HP, 0 Light armour, 230 speed, 2 bounty. Its old sendable form, *Frost Wolf*, was removed
in 10.0a.

## 6.3 Tier 2

| Creep | Unlock | Cost | Income | Bounty | HP | Armour | Type | Speed | Sent | Traits |
| ----- | ------ | ---- | ------ | ------ | -- | ------ | ---- | ----- | ---- | ------ |
| Knight | 07:00 | ~1,000 | 95 | ~48 | 690 | ~2 | ~Medium | 310 | 3 | Armored (1) |
| Vengeful Spirit | 07:30 | ~2,250 | 208 | ~106 | 1,080 | ~2 | Light | ~290 | 3 | Death Pact (2) |
| Forest Troll | 08:00 | ~4,000 | 360 | ~190 | 2,050 | ~2 | Unarmored | ~420 | 3 | Skittering |
| Wyvern | 08:30 | ~7,500 | 657 | ~356 | 2,195 | ~2 | ~Medium | ~160 | 3 | Flying |
| Voidwalker | 09:00 | ~10,000 | ~850 | ~463 | 4,130 | ~3 | ~Heavy | ~250 | 3 | Regen Aura (1), Chaotic Void |
| Faceless One | 09:30 | ~12,500 | ~1,031 | ~579 | 6,435 | ~3 | ~Heavy | ~310 | 3 | Endurance Aura (2) |
| Dragonspawn | 10:00 | ~15,000 | ~1,200 | ~694 | 7,695 | ~3 | ~Medium | ~450 | 3 | Spell Resistance |
| Sea Turtle | 10:30 | ~20,000 | ~1,550 | ~926 | 10,085 | ~4 | ~Fortified | ~285 | 3 | Devotion Aura (2) |
| Banshee | 11:00 | ~30,000 | ~2,175 | ~1,354 | 7,860 | ~4 | ~Unarmored | 180 | 3 | Flying, Unholy Sacrifice (2) |
| Kobold Geomancer | 11:30 | 60,000 | 4,200 | 2,700 | 31,430 | ~4 | ~Light | ~330 | 3 | Regen Aura (2) |
| Siege Engine | 12:00 | 75,000 | 3,750 | 7,312 | 28,800 | ~4 | ~Fortified | ~200 | 3 | **Attacker (2)**, Bombardment |
| Infernal | 12:30 | ~100,000 | 5,000 | 13,500 | 74,255 | ~10 | ~Hero | ~410 | **1** | Boss (2), Spell Resistance |

**BUILT.** Every row above exists as a `.tres`, and those files are the authority.

Siege Engine attack damage: **44-52**. Bombardment fires a rocket at a random tower within
400 radius every 4 sec.

The Siege Engine needed the same three decisions the Corrupted Treant did, and for the
same reason - the source states none of them. Its attack **range is 400** (3 cells at
the divisor every other reach uses), its **speed is 0.5 attacks a second**, and its damage
type is **Siege**, which is what its 150% against a Fortified tower is for. `?` All three
are choices, not readings, and they are in
`Resources/UnitStats/Creeps/siege_engine_stats.tres`.

**Bombardment's damage the source records nowhere at all.** This project gives the rocket
the Siege Engine's own 44-52 Siege damage, single target, no splash, reaching the same 400
the trait states. `?` It is in `Resources/Abilities/Passives/bombardment.tres`, as an
ordinary `AttackStats` with a projectile - so giving it splash later is an edit to that
file rather than to any code.

**Chaotic Void's 26 is the creep's mana ceiling** and lives on the Voidwalker's stats with
the rest of what the creep is, not on the passive. Nothing else in tiers 1 and 2 has mana.

## 6.4 Tier 3

| Creep | Unlock | Cost | Income | Bounty | HP | Armour | Type | Speed | Sent | Traits |
| ----- | ------ | ---- | ------ | ------ | -- | ------ | ---- | ----- | ---- | ------ |
| Death Revenant | 14:00 | ~100,000 | 5,000 | ~4,038 | 39,400 | ~5 | ~Heavy | 340 | 3 | Death Pact (3) |
| Satyr Shadowdancer | 14:30 | ~125,000 | 6,250 | ~5,046 | 62,250 | ~5 | Medium | 350 | 3 | Endurance Aura (3), Armored (2) |
| Crypt Fiend | 15:00 | ~150,000 | 7,125 | ~5,700 | 83,405 | ~5 | ~Unarmored | ~475 | 3 | Skittering, Ethereal Aura |
| Necromancer | 15:30 | 175,000 | 8,312 | 7,000 | 121,800 (146,160 effective) | 0 (5 converted) | Light | 320 | 3 | Bone Shield, Unholy Sacrifice (3) |
| Spirit Walker | 16:00 | 200,000 | 9,000 | 7,500 | 93,675 | 6 | ~Medium | ~150 | 3 | Spiritual Aid, Ethereal |
| Ancient Wendigo | 16:30 | ~225,000 | 10,125 | ~8,015 | 222,915 | 80 | ~Fortified | ~290 | 3 | Hardened Skin, Regen Aura (3) |
| Shaman | 17:00 | 250,000 | 10,625 | 8,750 | 185,085 | 8 | ~Unarmored | ~350 | 3 | Elemental Warding, Wind Rush |
| Abomination | 17:30 | 275,000 | 11,687 | 9,625 | 231,850 | 10 | ~Heavy | ~500 | 3 | Regenerative Flesh |
| Gryphon Rider | 18:00 | 300,000 | 12,000 | 9,750 | 92,450 | 8 | ~Light | 250 | 3 | Flying, Devotion Aura (3) |
| Ogre Magi | 18:30 | ~350,000 | 14,000 | ~10,806 | 240,785 | 10 | ~Medium | ~370 | 3 | Earth Shield |
| Chaos Wardens | 19:00 | ~400,000 | ~16,000 | ~11,400 | 246,355 | 12 | ~Light | 440 | 3 | Chaos Barrier, Mana Drain |
| Behemoth | 19:30 | ~500,000 | ~20,000 | ~15,000 | 546,865 | 16 | ~Hero | ~360 | **1** | Boss (3), Major Spell Resistance, Abyssal Carapace |

Notes:

- **Necromancer** converts its base armour into maximum health: 4% of max health per armour
  point. It ends up with 0 effective armour and +20% health, so 121,800 base becomes 146,160.
- **Ancient Wendigo**'s armour is not a typo. Hardened Skin starts it at 80 armour, and a
  **single hit** that lands for 50 or more strips 1 point, down to a floor of 6. It needed
  two decisions the source does not state.
  - **PER HIT, never cumulative.** Small hits do not add up: a thousand of them leave the
    armour exactly as thick as they found it, and only blows over the line count. That is what
    makes a fresh Wendigo a wall - at 80 armour almost nothing lands hard enough - and what
    makes the way past it *bigger hits* rather than *more* hits. Anything that eats armour
    (Firelord, Ancient Warden, Leviathan) lifts every later hit over the line, and it comes
    apart quickly once it starts.
  - *Which* damage the 50 is counted in: the damage that ACTUALLY LANDS, after the armour
    matrix and after the armour points themselves, rather than the attacker's raw roll. So a
    hit that is heavy on paper and arrives as a scratch does not count. Both are one number in
    `Scripts/Abilities/Passives/HardenedSkinPassive.gd` if either turns out to be wrong.
  - The erosion is permanent for the creep's life, and an aura may still lift its armour back
    above the floor: 6 is what Hardened Skin erodes to, not a minimum the creep can never
    exceed.
- **Behemoth**'s Abyssal Carapace converts 90% of its maximum health into a damage absorption
  shield on spawn, so its visible health bar is a tenth of the number above. The 9.4 sheet
  recorded the post-carapace figure (54,736), which is why the two look so different.

**BUILT.** Every row above exists as a `.tres`, and those files are the authority.

Two figures in this tier are `?` CHOICES rather than readings, and both are the same gap:
the source states the mana CEILING three of these traits fire at and never states how the
pool gets there, because in Warcraft III it is the unit's ordinary mana regeneration and
this game has no equivalent. So a **mana regeneration rate** is authored per creep, next to
the ceiling it is counting towards, in `CreepStats.mana_regen_per_second` - the Spirit
Walker's and the Shaman's. The Chaos Wardens needs none: its pool only ever drains, and
Mana Drain is what refills it.

**Chaos Barrier's resistance at full mana is also a `?` choice.** The source says "reduced
based on current mana percentage" and states no figure at all, so what a full pool is worth
is authored on `Resources/Abilities/Passives/chaos_barrier.tres` rather than read from
anywhere.

**War Stance's aura radius is the shared creep aura radius, not the 2,000 the source
states.** Every creep aura in this game shares one radius so that a player learns the size
of an aura once (game_rules.md), and 2,000 would be most of a lane. The source figure is
recorded here; the game uses `GameConfig.creep_aura_radius_cells` like every other aura.

## 6.5 Tier 4 - Sudden Death

Tier 4 is the one place a tier does mean something, and it is Sudden Death that means it
rather than the tier itself. At **25:00** the whole of Tier 4 unlocks at once - no per-creep
start delay, unlike every other tier - and **tiers 1 to 3 stop being sendable from that
moment**. It is the only time a creep is ever taken away from a player.

Tier 4 is also special in two ways of its own: the creeps are much stronger for their cost,
because the game is meant to end; and they give **very little income**, dropping a further
75% above 4,000,000 income. Income below is shown as `normal (above 4M income)`.

| Creep | Cost | Income | Bounty | HP | Armour | Type | Speed | Sent | Traits |
| ----- | ---- | ------ | ------ | -- | ------ | ---- | ----- | ---- | ------ |
| Huntress | 500,000 | 10,000 (2,500) | 15,000 | 246,500 | 13 | ~Unarmored | 460 | 3 | Elune's Grace, Quickness, Skittering |
| Obsidian Statue | 600,000 | 12,000 (3,000) | 54,000 | 1,111,025 | 20 | ~Fortified | ~200 | **1** | Power of the Destroyer (food 3), Annihilation Aura, Exhume Ghouls |
| Mountain Giant | 600,000 | 0 | 36,000 | 282,470 | 15 | ~Fortified | 290 | 3 | **Attacker**, Stoneskin Fortitude, Blocked |
| Harpy Windwitch | 700,000 | 14,000 (3,500) | 21,000 | 158,715 | 9 | Light | 460 | 3 | Flying, Wicked Curse |
| Naga Siren | 800,000 | 16,000 (4,000) | 24,000 | 328,965 | 12 | Unarmored | 320 | 3 | Regen Aura (4), Siren's Song |
| Kodo Beast | 800,000 | 16,000 (4,000) | 24,000 | 286,285 | 14 | ~Heavy | 270 | 3 | Endurance Aura (4), Devotion Aura (4), War Stance |
| Goblin Shredder | 1,000,000 | 20,000 (5,000) | 33,000 | 802,720 | 16 | ~Medium | 400 | 3 | Goblin Engineering, Reactive Armor |
| Frost Wyrm | 1,500,000 | 30,000 (7,500) | 45,000 | 486,310 | 16 | ~Heavy | 320 | 3 | Flying, Unholy Sacrifice (4) |
| Phoenix | 3,000,000 | 0 | 150,000 | 782,700 | 20 | ~Hero | 220 | **1** | Boss (4), Flying, **Attacker**, Volatile Death, Legendary Spell Resistance, Dive |
| Demon | 4,200,000 | 0 | 0 | 1,098,835 | 50 | Hero | 260 | **1** | Boss (5) - steals 2 lives, Unfathomable Power (invulnerable, food 5) |
| Treasure Goblin | 333,333 | 15,625 | 30,000 | - | - | - | - | 3 | Escape Portal |

**BUILT.** Every row above exists as a `.tres`, and those files are the authority. So does
the **Ghoul**, which is not in the table because nothing sends one: three crawl out of a
dead Obsidian Statue and that is the only way any of them reaches the field.

**Treasure Goblin** is the odd one out: it cannot steal lives and is removed the moment it
takes any damage, giving its bounty to whoever hit it. It is a pure income accelerator, and
it **cannot be used at all above 4,000,000 income** (the gold spent is refunded - the
prototype refuses the send before any gold moves, which comes to the same thing). Eight
Treasure Goblins are worth +125,000 income.

Its **speed of 522** is the one figure the sources do not carry and the developer supplied.
Its health is **1**, which is a decision rather than a reading and is the honest shape of
"removed the moment it takes any damage": there is nothing to kill. Its armour and armour
type follow from that and are worth nothing.

**Ghoul:** 119,075 health is the only figure any source states. `?` Its armour, armour type,
speed, bounty and footprint are this project's, in
`Resources/UnitStats/Creeps/ghoul_stats.tres`. It has no price, no income, no reserve and no
card entry, exactly as the Timber Wolf has none.

Three more `?` choices, all of them numbers the source states nowhere:

- **Mountain Giant's attack**, which the source never gives although it names the creep an
  attacker. It is melee reach like the Corrupted Treant's, Siege damage because what it is
  for is taking towers apart, and slow enough that the swing reads.
- **Phoenix's attack**, unstated for the same reason. Magic damage, because a Phoenix is
  fire and its own Dive deals Spell Damage, and a short reach because it has to come down
  onto a tower rather than shoot at one.
- **How wide Dive's trail is.** The source states the damage and the duration and says
  nothing about the width, so it is authored on `Resources/Abilities/Creeps/dive_ability.tres`
  and is deliberately narrow: a dive is a line drawn through a maze rather than an area
  attack that happens to travel.

**Reactive Armor is READ AS BANDS, which is a choice.** As stated - "damage above 1,000
reduced by 75%; damage above 300 reduced by 95%" - the smaller threshold carries the harsher
reduction, which cannot both be a whole-hit multiplier: a 1,001 damage hit would then land
for more than a 999 one. Read as bands it is coherent: everything up to the first threshold
lands in full, everything between the two is cut by 95%, and everything past the second by
75%. The thresholds and the shares are three exports on
`Resources/Abilities/Passives/reactive_armor.tres`, so a different reading is an edit to
that file rather than to any code.

**Demon** is the last-resort stalemate breaker: invulnerable, ignores friendly auras, costs
5 food, and unlocks with Sudden Death. It cannot be killed, so it always steals its 2 lives -
but it is slow, expensive, has a max stock of 4, and replenishes only once every 32 seconds.

**Attacking creeps** are Corrupted Treant, Siege Engine, Mountain Giant and Phoenix. Their
initial stock is 1, and what they can and cannot target is in section 1.5 - towers only, never
a disc and never the builder. A disc is also nothing an attacker has to go THROUGH, since
creeps walk over one; see section 5.

Phoenix bounty is contradictory in the sources - 10.0a sets it to 270,000 but 10.7a says
"changed from 147,270 to 150,000" - and 150,000 is the correct one. Its speed of 220 is
confirmed by an in-game tooltip.

## 6.6 Creep trait glossary

Numbered traits are the same effect at increasing strength.

| Trait | Effect |
| ----- | ------ |
| Flying | Flies over towers; can only be hit by towers that target air. On the Phoenix this is merged with Attacker into a single "Flying Attacker" tooltip. |
| Attacker | Attacks towers and tries to destroy them; destroyed towers leave rubble for 7 sec. |
| Skittering | Never draws tower attention; always targeted last. |
| Boss (n) | Sent as 1 strong creep with higher base stats. Steals **2 lives** instead of 1. |
| Fast Producing | Stock replenishes faster than other creep types. |
| Death Pact (1/2/3) | Returns to life 1.5 sec after being killed, once, at 33% / 50% / 75% health. |
| Devotion Aura (1/2/3/4) | +1 / +3 / +4 / +5 armour to allied creeps within 700 AoE. |
| Endurance Aura (1/2/3/4) | +10% / +15% / +20% to BOTH attack speed and movement speed within 700 AoE; the Tier 4 one splits into +30% attack speed and +25% move speed. Only an attacking creep has an attack for the first half to act on. |
| Regen Aura (1/2/3/4) | +2 / +10 / +30 / +120 health regeneration per sec within 700 AoE. Replaced the old Ancient Aura in 10.0a. The Tier 1 figure is the Priest's, confirmed in game. |
| Unholy Sacrifice (1/2/3/4) | On death, heals allied creeps within 1 cell for 3 / 310 / 4,875 / 12,750. The RADIUS is this project's: the source states none, and one cell is deliberately tighter than any other burst in the roster, so the heal is worth something only to creeps that really were walking together. |
| Armored (1/2) | Physical **splash** damage taken reduced by 10% / 20%. |
| Lesser Spell Resistance | Spell Damage -33%, harmful spell durations -75%, 50% immune to movement chill. **All three halves are built** - the duration and chill ones arrived with tier 2, see 6.3. |
| Spell Resistance | Spell Damage -50%, harmful spell durations -90%, 50% immune to movement chill. |
| Major Spell Resistance | Spell Damage -66%, harmful spell durations -50%. |
| Bone Shield | Spell Damage -75%, 100% slow resistance, harmful spell durations -50%, converts base armour into 4% max health per point. |
| Legendary Spell Resistance | Spell Damage -75%, full slow immunity, immune to durational harmful spell effects. |
| Fel Blood | +3 health regeneration per sec. |
| Ethereal | Can walk **through towers**; increased health regeneration. |
| Ethereal Aura | Permanently +2 armour to a random creep within 700 radius every 6 sec. |
| Hardened Skin | Very high base armour; every 50 physical damage taken removes 1 armour, down to 6. |
| Chaotic Void | Any damage taken gives +1 mana; at 26 mana heals 5% of maximum health and resets. |
| Spiritual Aid | At full mana (6), heals a creep within 500 for 1% of its max health (cap 2,000) and grants +1 armour, up to 12. |
| Elemental Warding | Gains **70%** damage resistance against whichever damage type has dealt it the most damage. Can swap resistance once every 3 sec. |
| Wind Rush | At full mana (14, starting at 10), grants a creep within 400 AoE +40% movement speed for 3 sec; slower creeps are prioritised. |
| Regenerative Flesh | Harmful slow durations -65% (max 1.4 sec); +2.4 health regen per missing health percentage, capped at 240/sec; at 50% health the current slow percentage is halved, once. |
| Earth Shield | Every 14 sec shields a creep within 400 radius, removing chill/slow and healing 10% of max health over 12 sec. Also removes Ultimate Lich's Frostbite. |
| Chaos Barrier | Damage taken is reduced based on current mana percentage. Loses 5% mana every sec. Maximum mana 100. |
| Mana Drain | At 0 mana, drains 33% of a tower's mana within 180 AoE and gains 500% of the amount, up to a maximum of 75 mana. Can only trigger on the same tower once every 7 sec. |
| Abyssal Carapace | On spawn, 90% of maximum health is converted into a damage absorption shield. |
| Elune's Grace | 15 sec invulnerability shield the first time damage is taken (once), plus a 5 sec shield at 50% health. |
| Quickness | 50% chance to dodge attacks from towers with 900 or more attack range. |
| Blocked | Attack damage -8% for every Mountain Giant within 200 AoE (no effect at 3 or fewer), capped at -50%. |
| Stoneskin Fortitude | 100% resistance to slow effects. |
| Goblin Engineering | Cannot be chilled or slowed by more than 25%. |
| Reactive Armor | Damage above 1,000 reduced by 75%; damage above 300 reduced by 95%. |
| Wicked Curse | On death, curses up to 3 towers within 200 AoE for 10 sec, reducing their attack speed by 30%. |
| Siren's Song | Any damage taken gives +1 mana. At full mana (50) gains +50 maximum mana and heals 15% of max health; creeps within 300 AoE recover 1.6 armour if below their base armour, once per creep per 5 sec. |
| War Stance | At 30% health, gains Hero armour type, +7 armour, and an aura giving creeps within 2,000 AoE +20% attack damage. |
| Annihilation Aura | Towers within 300 AoE deal 15% less attack damage. |
| Exhume Ghouls | Spawns 3 Ghouls (119,075 HP each) on death. Formerly "Aphotic Chant"; the spawned creep used to be an Essence of Blight. |
| Volatile Death | On death, deals 1,000 Physical Damage to towers within 250 AoE. |
| Dive *(active)* | Phoenix dives forward and back in an arc up to 700 distance in the targeted direction, dealing **150 Spell Damage per sec for 4 sec**. 16 sec cooldown. The dive can be stopped with the stop ability; **if stopped, the Phoenix regenerates its armour to full**. |
| Unfathomable Power | Invulnerable, ignores friendly auras, food cost 5. |
| Escape Portal | Cannot steal lives, is removed once damaged, and gives its bounty to whoever damaged it. |

## 6.7 Abilities removed from creeps

Listed because they appear all over the 9.4 sheet and must **not** be implemented:

| Removed ability | Removed in | Why |
| --------------- | ---------- | --- |
| Dash (1-5) | 12.0a | Turn-rate bonus was hard to read; all ground creeps now share the default turn rate. Base movement speed values are unchanged. |
| Geomancy Aura (1/2) | 12.0a | Too hard to judge its strength in play. Armour values of the affected creeps were raised instead. |
| Necrotic Transfusion | 12.0a | Only on Death Revenant; too RNG-driven. (The Frost Wyrm version went in 10.6a.) |
| Shadowdance | 12.0a | Only on Satyr Shadowdancer; visually impossible to follow. |
| Ancient Aura (1/2) | 10.0a | Replaced by Regen Aura. |
| Lingering Void Aura | 11.5a | Tower attack-speed reduction on a Tier 1 creep was out of place. |
| Engine Overload | 11.0a | Goblin Shredder's static burst; the effect moved to Harpy Windwitch's Wicked Curse. |
| Hypothermia | 11.0a | Kodo Beast (then War Beast) extra-slow vulnerability. |
| Enduring Chill | 11.6a | Frost Wyrm slow-shedding on damage. |
| Secret Technique | 11.7a | Chaos Warden's 50% dodge vs short-range towers. Health raised to compensate. |
| Primordial Flux | 11.5a | Shaman mana gain from being slowed. |

12.0a also capped how many abilities a creep may carry, which is a useful design constraint
to keep: **Tier 1 at most 1, Tier 2 at most 1 (2 on the later ones), Tier 3 at most 2 (3 on
the later ones), Tier 4 at most 3.**
---

# 7. Open questions

Everything marked `?` above, gathered in one place. Nothing here was guessed at in the tables;
each is either missing from all four source files or contradictory between them.

**Nothing here blocks implementation.** Every value needed to author a tower, creep or disc is
now decided. What follows is the audit trail: source conflicts that were resolved, and values
that are correct-but-inherited and could in principle be stale.

## 7.1 Source conflicts, resolved

1. **Phoenix bounty**: 10.0a sets 270,000, 10.7a says "changed from 147,270 to 150,000".
   **150,000** is correct.
2. **Ultimate Scorpion's tech requirement** is **Ice (1)**, even though 10.0a says it was moved
   off Ice (1) onto Lightning (2). It was moved back with no patch note.
3. **Shock Particle's ability.** The 9.4 sheet lists "Arcanize (2)", which belongs to the
   Sorcerer. The changelog treats it as carrying Overcharge (1). Used Overcharge (1).
4. **Elemental Core "total cost" of 1,000** in the 9.4 sheet, against its 200g price.
5. **The Arcane Orb line's maximum mana.** Shown as 100 throughout, inferred from the drain
   rates in the ability text; no source states it.
6. **The Carver branch's target types.** The 9.4 sheet has Lesser Carver hitting Ground only
   while every tier above it hits Ground and Air. Probably a sheet slip.
7. **Chains that break inside the logged period.** A handful of patch notes quote a "changed
   from" value that does not match the result of the previous note, which means a silent change
   happened in between. The clearest cases are Holy Lantern (10.5a leaves it at 28-29, 11.5a
   says "from 33-35"), Lesser Titan Vault (11.3a leaves 95-96, 11.5a says "from 94-95"),
   Ultimate Lich (11.3a leaves 901-905, 11.6a says "from 901-951"), Ultimate Firelord's splash
   and Greater Harbinger's damage. In every case the *result* of the later note is what this
   document carries, so the current values are still right - but it means the changelog is not
   a complete record even after 10.0a.

## 7.2 Values inherited from 9.4 that may be stale

Every `~` in this document. They are not errors - they are values no patch note touched between
10.0a and 12.4a, so they are correct unless they were changed in 9.5 or 9.6, whose patch notes
no longer exist. The riskiest cluster is the **Basic towers**, because 10.0a's own patch notes
prove that the anti-air branch had its damage changed during that window (10.0a's "changed
from" values do not match the 9.4 sheet).

Also unrecorded anywhere and therefore absent from this document: **hotkeys and command card
positions** for towers and creeps (only scattered fragments appear in the changelog), and
**projectile speeds** (a long list of them was normalised to 1200 in 10.4a, but the full
per-tower table is not in the sources).

## 7.3 A note on in-game tooltips as a source

Tooltips read straight out of a running game are the best way to close gaps like these, and
three have been used here: the Chaos Wardens creep, the Phoenix, and the Technology Disc:
Lightning. They are authoritative for **text, mechanics and effects** - the Lightning disc's
healing and the fact that discs are Invulnerable both came from one, and neither is in any
source file.

Their **numbers** still need checking against the changelog, because a screenshot is a snapshot
of whatever build it was taken in. The three used here were captured in **12.2a**: the Chaos
Wardens tooltip shows 236,880 health, which 12.3a raised to 246,355, and the Phoenix tooltip
shows 759,905 health, which 12.4a raised to 782,700. Both tables in this document carry the
12.4a values.

---

# 8. Keeping this document current

## 8.1 The intended relationship to the resources

Stated in full at the top of this file. In short: the `.tres` is the authority once a unit
exists, this file is the readable mirror, and a number written in two places diverges the
first time one of them is edited - which is why the mirror should stop being written by hand.

## 8.2 Making it generated rather than hand-maintained - do this next

**Assessed three times, every time the same answer, and the last reason to wait has gone.**
It fits how this project is already built. The stats live in typed resources (`UnitStats`,
`BuildingStats`, `CreepStats`, `AttackStats`, `UnitAbility`), each keyed by an authored id,
and `ContentConfig` already names the folders to scan - which is exactly what a generator
needs.

It was deferred for "not enough content to make it pay". The Basic towers, the elemental
towers, the discs and all four creep tiers are now implemented, so every stat table in this
file shadows a resource, every one of them can go quietly wrong the next time a number is
tuned, and keeping the whole lot honest by hand is the tedious work the no-live-values rule
exists to avoid everywhere else. Nothing blocks it.

Proposed shape:

- A tool script under `Scripts/Dev` (or an `EditorScript`) run headless, that scans the
  content folders the same way the unit-type registry does, and writes the stat tables into
  this file between marker comments:

	  <!-- GENERATED:towers:begin -->
	  ... table rendered from the .tres files ...
	  <!-- GENERATED:towers:end -->

- Everything outside the markers - the prose, the upgrade paths, the ability descriptions,
  the open questions - stays hand-written and survives regeneration.
- Run it from the same place `Main._validate_content` runs, or as a manual step before a
  commit. It can double as a content check: a tower in this document with no matching
  `unit_type_id` is either unimplemented or misnamed.

Until enough content exists for that to be worth writing, this file is maintained by hand,
and the rule is: **change the `.tres`, then change the row here in the same commit.**

## 8.3 Scope note

Per the CLAUDE.md rule against writing counts and live values into markdown, this file is a
deliberate exception alongside `game_rules.md`, on the same grounds: these numbers *are* the
design being copied, not a restatement of what the code happens to do. No other `.md` in the
project should grow a stats table.
