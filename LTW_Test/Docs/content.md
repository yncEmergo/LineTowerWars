# Authoring content

How a tower, a creep, a disc or an ability is actually added to the build: which files it is
made of, in what order they have to exist, and what refuses it when one is wrong.

This is the **procedure**. It is not the rules (`game_rules.md`), not the numbers
(`unit_data.md`), and not the visual language (`Tools/ModelGen/PLACEHOLDER_ART.md`). Nothing
here is a design decision; every rule below is enforced by something that will complain at
boot if it is broken.

It exists because the roster is complete and the next person to touch it will be **changing**
content rather than building it out — retuning a creep, splitting a refund share, filling in
one of the rules `unit_data.md` still marks NOT BUILT — and that person needs to know which
half of a file is generated before they edit it.

---

## The shape of a unit

Every unit in the game is the same four things, whatever kind it is.

| | What | Where |
| --- | --- | --- |
| **Stats** | A `.tres` deriving from `UnitStats` — `BuildingStats` for a tower or a disc, `CreepStats` for a creep. **The authority on that unit.** | `Resources/UnitStats/…` |
| **Prefab** | The scene it spawns as, named by the stats **as a `res://` path string**, never held as a `PackedScene`. | `Scenes/Units/…` |
| **Card** | An `Array` of `UnitAbility` resources on the stats. This IS the command card, and it is what the server checks an order against. | `Resources/Abilities/…` |
| **Icon** | A `Texture2D` on the stats, baked from the unit's own model. | `2DArt/Icons/` |

An ability that BUYS a unit — build, upgrade, morph, send — points at that unit's **stats**,
never at its prefab. That is what lets a card quote a price without loading a model. See the
resource rules in `CLAUDE.md`.

---

## Ids

Two separate namespaces: `UnitStats.unit_type_id` and `UnitAbility.ability_id`. Both are
authored, both must be unique inside their own namespace, and both are **permanent** once
written — they are what crosses the wire, so renumbering one silently changes what an order
means.

**To pick the next one, scan the folder and take the highest plus one.** The number itself
carries no meaning: ids were handed out in creation order, and any grouping or gap in them is
an accident. Do not read one, and do not try to preserve one.

```
grep -rho "unit_type_id = [0-9]*" Resources/UnitStats | sort -t= -k2 -n | tail -1
grep -rho "ability_id = [0-9]*"   Resources/Abilities | sort -t= -k2 -n | tail -1
```

**A duplicate is a failed boot, not a shipped bug.** `Main._build_registries` scans the whole
of `ContentConfig`'s three folders and refuses a collision loudly. The scan is recursive and
finds ORPHANS too — an ability on nobody's card still owns its number, which is precisely what
stops a second one being authored into it while the first card is still being built.

**Two people authoring at once will collide**, because both will read the same highest number.
Boot after adding, before doing anything else.

---

## Adding a creep

Creeps are the hand-authored roster: their stats were written by hand and `unit_data.md` 8.1
makes those files the authority. Only their PREFABS are generated.

1. **Stats** — a `CreepStats` `.tres` in `Resources/UnitStats/Creeps/`. Numbers come from
   `unit_data.md` §6. Beyond the ordinary unit fields it carries what a creep is: pack size,
   gold cost, income gain, bounty, unlock delay, stock and its regeneration, population, and a
   mana pool where a trait runs on one.
2. **Traits** — each is a `CreepPassive` resource in `Resources/Abilities/Passives/`, listed in
   the stats' `abilities`. A passive is a SHARED resource: one file is every creep of that type
   at once, so it may hold no per-creep state. Per-creep state lives on the creep — that is
   what `CreepMana` and `StatusEffects` are.
3. **Prefab** — `python Tools/ModelGen/generate.py models` after adding the creep to
   `creep_roster.py`. The prefab stage owns the three numbers measured off the model: health
   bar height, click box and stride length.
4. **Icon** — `godot --path . res://Scenes/Tools/icon_gen_3d.tscn -- new`. It scans
   `Resources/UnitStats` rather than carrying a list, so it finds the new creep on its own, and
   `new` bakes only what has no picture yet.
5. **Send ability** — a `SendCreepAbility` `.tres` in `Resources/Abilities/Creeps/` pointing at
   the stats, added to the right tier's `send_building_tierN_stats.tres` card. A tier is one
   command card, so a tier's card is full at one card's worth.
6. **Mirror the row** in `unit_data.md` §6 in the same commit. The `.tres` is the authority;
   that table is the readable copy and goes wrong silently.

---

## Adding or changing a tower or a disc

**These are GENERATED.** Their stats, prefabs, passives, build abilities, upgrade abilities and
morphs are all written by `Tools/ModelGen`, and a hand edit to any of them is thrown away by
the next run without a word.

So the file to change is the generator, not its output:

| To change | Edit |
| --- | --- |
| A Basic tower's numbers | `roster.py` |
| An elemental tower's numbers | `element_roster.py` |
| An elemental tower's named ability | `element_abilities.py` |
| A disc's numbers or effect | `disc_roster.py` |
| What any of them looks like | `style.py`, `disc_style.py`, or the matching `*_models.py` |
| How they are wired up | the matching `*_content.py` |

Then run the stage and read `git status` before doing anything else — a full run also applies
every pending change the checked-in output had not caught up with. `Tools/ModelGen/README.md`
covers that trap in full, and `PLACEHOLDER_ART.md` is required reading before touching a model.

**The behaviour behind a named ability is not generated.** A `TowerPassive` subclass under
`Scripts/Abilities/TowerPassives/` is ordinary hand-written GDScript; the generator only
authors the `.tres` that points at it and fills in its numbers.

---

## What refuses bad content, and when

Everything below runs at boot, so **booting once is the whole check**. Read the editor log,
not the game log — `Log.err` from a running game surfaces there with a stack trace.

- **`ContentConfig.validate()`** — every content folder resolves. A moved folder makes the
  registry quietly SHORTER, which looks exactly like a client running different content, so it
  is a message rather than a mystery.
- **`UnitStats.validate()`**, walked from the builder and the senders — every `res://` path a
  stats resource declares actually exists. The editor does not rewrite a path string when a
  scene moves, which is the price of naming scenes by path, and this is what pays it. It walks
  the whole upgrade chain, so a broken `.tres` in the middle of a line is caught.
- **The three registries** — `AbilityRegistry`, `UnitTypeRegistry`, `TechRegistry` — every id
  unique within its namespace.

Two failure modes that do **not** look like content errors:

- **A new script in an existing folder is not imported by a `godot --path` run.** Its
  `class_name` never reaches the global class cache, so every script naming it fails with
  "Identifier not declared in the current scope" — which reads exactly like a typo in a file
  that is plainly correct. Fix with `--headless --import`, or let the editor notice the file.
- **A property written ABOVE the `script = ExtResource(...)` line in a `.tres` is silently
  discarded.** It is applied to the plain `Resource` and thrown away when the script replaces
  it. No warning, no error. This once cost a debugging cycle with fourteen `unit_type_id`s all
  reading back as 0.

---

## Where a number lives

One rule, and it decides most arguments: **a cost or a stat belongs to the thing it describes,
never to the ability that buys it.** A tower's gold cost is on its `BuildingStats`, a creep's on
its `CreepStats`. The ability reads it off there, so the number cannot drift between two files.

An ability may cache a value derived only from its OWN exports, because every user of that
shared resource would compute the same answer. It may hold nothing else.

---

## Related

- `CLAUDE.md` — the hard rules these procedures implement, and the engine traps.
- `game_rules.md` — what the content has to DO, and which rules are built.
- `unit_data.md` — the numbers, and §8.2's plan to generate its tables out of these files
  instead of shadowing them by hand.
- `Tools/ModelGen/PLACEHOLDER_ART.md` — required before building visuals for anything new.
- `Tools/IconGen/README.md` — the HUD's own glyphs, which are a different thing from a unit
  icon and are drawn rather than baked.
