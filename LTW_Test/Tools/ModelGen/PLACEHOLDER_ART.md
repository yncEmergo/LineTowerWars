# Adding a roster of placeholder visuals

How the Basic tower roster got its look, written down so the next roster gets
the same one. The elemental towers and the creeps have both been built to it
since; where a roster answered one of its questions, the answer is recorded
here next to the question.

[README.md](README.md) is the tool reference — what the files are and how to
run it. This is the method.

---

## 1. What placeholder art is for

It is not "something to look at until the artist arrives". It is the **design
of the readability**, built in primitives so the rules can be argued with
before anyone spends a week modelling. The shapes get thrown away. The rules
do not.

So the question is never "does this look nice". It is:

> From a top down camera, in a maze of thirty other things, can a player tell
> what this is, whose it is, and how dangerous it is — without reading text?

Everything below follows from that.

---

## 2. The three axes

A unit answers three questions, and **each one gets its own axis**. Never two
questions on one axis: the moment tier and family both live in colour, neither
reads.

| Question | Axis | Towers use |
| --- | --- | --- |
| What FAMILY is it? | shape and material | square stone / hex timber / round bone |
| What KIND within it? | one decisive silhouette | barrel, mortar, blades, hammer, orbit, rack |
| How STRONG is it? | a stepped ladder | six rungs of metal, size, glow, added parts |

For a creep roster the same three exist and need naming before the first model
is built. **The tier 1 creeps answered them like this** — the full rules are
in `game_rules.md` under Presentation, and this is only what they were chosen
against:

| Question | Axis | Creeps use |
| --- | --- | --- |
| What FAMILY is it? | what it does to the maze | ground walks / flying has no legs and a shadow disc / attacker is the only one with a LIT weapon |
| What KIND within it? | body plan and hide colour | quadruped, biped, arachnid, golem, wraith, treant |
| How STRONG is it? | a ladder on GOLD COST | mass, eye brightness, carapace, then plates, spines, a crest |

The reasoning that got there:

- **Family** — the creep TIER is the obvious candidate, and it is the wrong
  one. `game_rules.md` says a tier is a cost bracket and carries no mechanical
  meaning, so making it the loudest visual signal teaches a player something
  untrue. Prefer what a player must react to: does it walk, does it fly, does
  it attack back.
- **Kind** — the individual creep. This is where the silhouette work goes.
- **Strong** — health and bounty vary enormously across a roster. A ladder
  here is worth more than it is on towers, because a player cannot upgrade a
  creep and so has no other way to learn the ordering.

Decide all three, write them into `game_rules.md` under Presentation, and only
then open `style.py`.

---

## 3. Colour is spoken for

**The Basic roster is deliberately colourless** — stone grey through timber
brown — because the ten ELEMENTS each own a hue. That is a standing constraint,
not a phase:

- **Elemental towers** may use their element's hue freely. It is the one thing
  they have that Basic towers do not, and it is why Basic towers gave it up.
- **Creeps** had the same problem the Basic towers had, and it was solved
  differently: they keep a hide colour of their own, because a Sheep and a
  Skeleton have to be told apart at a glance, and ownership stays the
  minimap's job. What separates a creep from an element is a SECOND axis
  rather than the hue — creep hides are muted, a creep's only lit parts are
  its eyes, and it is drawn with an organic shader and stands on no foundation
  patch. Where a creep lands near an element that is deliberate: mud is earth
  coloured. All of it is in `style.py` next to the tower entries, so the
  three rosters are chosen against each other.

If a roster needs colour and cannot have it, spend the budget on **shape** and
on the **tone split** below instead. That is what the Basic towers did.

**Choose the hues AGAINST EACH OTHER, in one table.** Ten of them are more than
anybody holds in their head one at a time, and the failures are always PAIRS:
Arcane and Void are both purple in the source game, Ice and Lightning are both
blue-white, Fire and Earth and Holy all want a warm accent. Every one of those
was fixed by separating the pair on a SECOND axis rather than by nudging the
hue - a different lightness, a different material, a different stone value. The
reasoning is written into `style.ELEMENTS` next to the numbers, so whoever
changes one next can see what it was chosen against.

**Two traps that only appear at the TOP of the ladder**, and both cost a rebake
to find:

- **A pale palette disappears under the tier metal.** Mid-beige Holy stone was
  almost exactly the value of the bronze and silver trim rungs, so an Ultimate
  read as one lump of gold with no element in it. The fix is to move the STONE
  away from the metal in value - Holy went bright ivory - rather than to make
  the metal quieter, because the metal is the tier tell and is not negotiable.
- **A bright accent saturates to white.** Ramping the glow far enough that an
  Ultimate is unmistakably an Ultimate made every element's accent the same
  colour, so the hue was gone at exactly the tier the player has paid most for
  it. For a coloured roster it is the accent's FLOOR that should be raised; its
  ceiling barely moves.

---

## 4. Tone: nothing is one colour

Every family carries its material at three depths — `body`, `deep`, `pale`.
Three depths of ONE material, not three materials, which is what lets a model
have parts while still looking like one object.

Assign them by what a part DOES, not by taste:

- `deep` — plinths, undersides, anything low or carrying weight
- `body` — the bulk
- `pale` — heads, barrels, blades, anything raised or catching light

A model built entirely out of `body` is a lump from above however good its
silhouette is: the facets have nothing to catch against each other. This was
found the hard way — the first tower pass was one material per line and read as
nine sizes of the same tower.

The five roles (`body`, `deep`, `pale`, `trim`, `glow`) are named in
`modelkit.py` for what they DO, so a creep inherits them unchanged: hide,
shadowed hide, lit hide, claws, eyes.

---

## 5. The stepped ladder

Towers step on the six PRICE tiers. Every rung adds a piece the rung below does
not have, so a tier can be read by counting details:

    10g      bare. No metal on it at all
    30g      + the base trim ring, its first metal
    150g     + a collar under the head
    1,000g   + bolts around the shoulder
    5,000g   + crown fins
    25,000g  + a slowly turning halo

Two rules worth carrying to any roster:

- **Continuous AND stepped, together.** Size, trim colour and glow ramp
  smoothly so neighbours stay distinguishable; collar/bolts/crown/halo are
  steps so the expensive ones are distinguishable across a whole map.
- **Motion is the loudest signal a top down camera has**, so it is reserved for
  the top of the ladder. Nothing below an Ultimate has a moving part that is
  not its own attack.

**The first upgrade a player ever buys should be the one they can see from
across the map.** The 10g towers are roughly half the height of their 30g
upgrade, carry no metal at all, are built from the raw `deep` tone, and are
missing the part that names the line. That gap is deliberate and cost several
iterations to get big enough.

---

## 6. The pipeline

Everything is generated. Nothing is hand-placed.

```
style.py        the language: palettes, tone sets, the ladder rules
   ↓
<x>_roster.py   the table: one row per unit, straight from unit_data.md
   ↓
<x>_models.py   the shapes. One builder per family. THE REAL WORK
   ↓
<x>_content.py  stats, prefabs and abilities pointing at those models
   ↓
icon renderer   one PNG per unit, baked from the finished models
```

The elemental roster added one layer the Basic one did not need:

```
<x>_abilities.py  what each unit's named ability IS, and its numbers
```

It is a table rather than a `.tres` per tower written by hand, for the same
reason `roster.py` is: those numbers come out of `unit_data.md` and want to be
readable next to each other. It is also where the UNIT CONVERSION happens - the
source states 400 AoE and "-3.75% per hit", the game wants 3.12 cells and
0.0375 - so a `.tres` can be read against its script without a divisor in the
way.

Run it from the **project root**: `python Tools/ModelGen/generate.py`.

It is idempotent — a run with nothing changed rewrites every file byte for
byte, so `git status` after a run tells you exactly what your edit did. Check
that before believing anything else.

**Author in unscaled units.** `modelkit` applies the family's width and height
ramps on the way out; pre-scaling double-applies them.

---

## 7. Contracts a model must meet

Break one of these and nothing errors — the model is just quietly wrong.

**Creeps meet a different contract**, and it is the WALK that sets it:

- **`Gait`** — everything that bobs and leans as the creep travels.
- **`Leg1 .. LegN`** — hip pivots, at the MODEL ROOT and NOT inside `Gait`.
  A walk cycle is a body bobbing over feet that stay planted, so a leg hung
  under the bobbing node lifts its own foot off the floor twice a stride and
  the whole creature reads as swimming.
- optional `Gait/ArmL`, `Gait/ArmR` — limbs that counter-swing.
- optional `Gait/ArmR/Swing` — what an attacker chops with.
- optional `Shadow` — the disc under a flyer, which must be a
  `GroundShadow3D` and not merely a named node, or a portrait frames itself on
  a box a metre taller than the creep.

**A leg's LENGTH is derived from its hip height, never authored.** Authoring
both and hoping they add up is how a roster ends up with one creep wading and
another on stilts, and it is invisible in a diff: the numbers look perfectly
reasonable right up until something is rendered.

The tower contract, unchanged:

- **`Turret`** — the node that turns to face a target.
- **`Turret/Muzzle`** — where shots leave from.
  Every tower has both, including the ones with nothing to aim. One wiring
  across a whole roster beats nine special cases; a model missing one wires up
  to null and silently never fires.
- **Named nodes for animation** — `Turret/Spinner`, `Turret/Swing`,
  `Turret/Barrel`, `Turret/Rack`. The components that drive them live in the
  PREFAB, not the model, because they need the unit and a model has none — the
  same model scene is used by the build ghost, which must not recoil at
  anything.
- **Width and height scale separately**, so a rotated part no longer knows
  which ramp it takes. A cylinder laid on its side must pass `along="z"` or it
  gets shortened every time the roster gets lower.

---

## 8. Icons and portraits, for free

Both come out of the models with no extra art:

- **Icons** — `Scenes/Dev/icon_renderer.tscn`, which has to RUN because baking
  an image means rendering one and headless Godot has no renderer. It does not
  need the editor: `godot --path . res://Scenes/Dev/icon_renderer.tscn -- creeps`
  bakes one roster and leaves the others alone, which matters — re-baking a
  roster whose models have not moved is a few hundred files of churn for no
  change anybody asked for. One PNG per unit type in
  `2DArt/Icons/`, framed on the unit's own bounding box so every tier is the
  same size on a card. Re-run it whenever a model changes or the icon is stale.
  - **it names the file after the unit's DISPLAY NAME, not its key.** That works
    only because a display name is unique across the whole game, which is a
    thing to check before adding a roster that might reuse one.
  - it is a CHICKEN AND EGG with the content stage, and the generator knows it:
    a missing `.png` referenced from a `.tres` takes that whole resource down
    (see CLAUDE.md), so the content stage writes no `icon` line for a unit whose
    icon is not there yet. Generate, bake, generate again.
- **Portrait** — nothing to do. `UnitPortrait` copies the live unit's meshes
  into a transparent SubViewport, so a new roster is already shown correctly
  the moment its prefabs exist.

Both go through `VisualUtil`, which copies **meshes only**. A portrait must
never register a unit id, claim a grid cell or take a shot at anything.

The icon lives on `UnitStats.icon`, not on the ability that buys the unit — the
picture belongs to the thing it is a picture of, the same way its price does.

---

## 9. How to know it worked

In this order. Do not skip to the last one.

1. **`python Tools/ModelGen/generate.py`** — then `git status`. Unexpected
   churn means the generator disagrees with what is checked in.
2. **Headless boot** — `godot --headless --path . res://Scenes/Main.tscn`.
   Watch for "Registries built" and no `Parse Error`. This catches every
   unresolved path and every duplicate id.
3. **The probe** — `Scenes/Dev/tower_probe.tscn`. Anything that is a *timed
   state machine* goes here, because a screenshot cannot see it. It already
   proves attack rates, upgrade swaps and effect placement.
   - a probe that has to run the real match must be a SCENE that instances
     `Main.tscn`, never a `--script` main loop: a `--script` loop gets no
     autoloads and no global class table, so the world comes up black and every
     `MatchSession.is_authority()` in the project fails to resolve
   - what a probe should PRINT is the moving part's own number, tick by tick.
     A leg angle going 0.06, -0.22, 0.30 while the creep's z climbs is proof a
     walk cycle is driven by distance; a screenshot of it is not
4. **Look at it** — `generate.py --showcase` writes review scenes laying a
   family out as its own upgrade tree, and for creeps a second one from the
   MATCH CAMERA'S OWN PITCH, which is the only view that answers the question
   the roster exists to answer. **Run them**; the editor's cinematic capture
   renders them unlit.
   - `Scripts/Dev/CaptureRunner.gd` runs one and saves a PNG, for when nobody
     is sitting in front of the screen:
     `godot --path . --resolution 1600x900 --script res://Scripts/Dev/CaptureRunner.gd -- <scene> <out.png>`

**A screenshot is the weakest evidence available.** Anything under about two
seconds — a swing, a spray, a windup — cannot be caught reliably. Prove those
from state that persists, and hand the *feel* to the human.

---

## 10. Traps already paid for

Each of these cost real time. None of them errors.

- **`Transform3D` in a `.tscn` is written ROW BY ROW.** Handing it three column
  vectors transposes the basis, which for a rotation is its inverse: every
  authored angle comes out negated. It aimed the anti-air rack at the floor.
  `tscn.py` does the transpose in one place — do not re-derive it.
- **`gl_compatibility` has no per-instance shader uniforms and no
  `GeometryInstance3D.transparency`.** Both look like clean one-liners and both
  silently do nothing. Tier is baked into one material per tier; opacity
  duplicates materials per instance.
- **Particles emit in world space and fire the instant they are allowed to.**
  An effect that starts emitting as it enters the tree throws its whole load at
  the effects root's origin. Author `emitting = false` and call `play()` after
  positioning.
- **A `Button` grows to fit its icon**, and `custom_minimum_size` is a
  *minimum*. Set `expand_icon`, or one 256px icon blows the card apart.
- **A node's scale is captured in `_ready`.** Set it BEFORE `add_child` or an
  animation started from that scale overwrites it next frame.
- **The editor does not reload a script whose BASE CLASS changed.** The
  property is missing from the inspector and a filesystem scan will not fix it.
  Restart the editor; trust headless over the editor.
- **`const` cannot hold a constructor call.** `PackedStringArray([...])` is not
  a constant expression; the literal `[...]` is.
- **Never invent a `uid`.** Omit it and let Godot assign one. The editor DOES
  write them into generated files the moment it saves one, which is why a full
  run after somebody has had the project open reports a few hundred files
  changed that nobody touched. See README.md.
- **Width and height ramp SEPARATELY, and for a creature that breaks things.**
  It is free on a tower — a stack of axis aligned drums just gets squatter —
  and it is not free on anything with a limb. Two things go wrong and neither
  errors: a head authored as a sphere comes out a PANCAKE, because its radius
  took the width ramp and its height took the height one; and a leg placed by
  trigonometry lands at an angle NOBODY AUTHORED, because its x offset and its
  y offset were scaled by different numbers. The first creep pass had every
  head flat and the spider's knees inside its own abdomen. The fix is to make
  the two spaces explicit and convert between them at the call site —
  `CreepModel.up()` and `.down()` — so every number says which one it is in.
  Keeping the anisotropy is worth it: it is what makes the roster stocky, and
  stocky is what reads from above.
- **A rotated part's authored HEIGHT ends up somewhere else.** An axe head laid
  on its side, a toe pointing forwards: its authored y is now a width, and left
  alone it gets shorter every time the roster gets lower.
- **`metallic` near 1 renders BLACK.** Under `gl_compatibility` with no
  reflection probes and no sky, a metallic surface takes almost all its colour
  from reflections it does not have. Tower trim gets away with it because its
  top rungs emit; the creep carapace could not, because the eyes are the only
  thing in that roster allowed to be lit. It read as holes cut in the model
  until the metallic values came down.
- **A weapon authored straight down the arm's own axis is INSIDE the
  creature.** The first pass gave the Skeleton and the Swordsman blades that
  came out of their own shoulders and were invisible from every angle a player
  ever sees. Hang the weapon off a `Hold` pivot carrying one pose — out,
  forward and tilted — and every weapon in the plan inherits it.
- **A creature leans forward on a NEGATIVE rotation about X**, because Godot's
  forward is -Z. Getting the sign wrong stands every neck up over the animal's
  own back, and a fleece or a barrel then hides the join so it reads as a
  floating head rather than as a wrong angle.
- **Ids are claimed loudly.** `ability_id` and `unit_type_id` are permanent and
  never reused; scan the folder and take the highest plus one. A duplicate is a
  failed boot, which is the point — and it will happen if two people author at
  once, so re-check before committing.

---

## 11. What to write down when you are done

Placeholder art is a design artefact, so the RULES outlive it:

- **`game_rules.md`, Presentation** — the visual language as rules. What each
  axis says, what the ladder is, what colour is reserved for. Written so it
  survives real art replacing every model.
- **`style.py`** — the same rules as code, so a model cannot quietly stop
  obeying them.
- **`unit_data.md`** — only if a NUMBER changed. It mirrors the `.tres`, and
  the `.tres` is the authority once a unit exists.
- **This file** — if the method changed, not if the roster did.

Do not write counts, or the current value of a tuning knob, into any `.md`.
See CLAUDE.md.
