# Adding a roster of placeholder visuals

How the Basic tower roster got its look, written down so the next roster gets
the same one. The elemental towers, the creeps and the technology discs have
all been built to it since; where a roster answered one of its questions, the
answer is recorded here next to the question.

**The discs are the roster that broke the mould, and that is the interesting
case.** A disc has no model at all - it is painted onto the floor - so almost
none of section 7 applies to it and the whole of sections 4 and 5 had to be
answered a different way. What did carry over is everything that matters: the
three axes, the rule that colour belongs to the elements, and the rule that
motion is reserved for the top rung. Read section 12 before assuming a new
roster has to be made of primitives.

[README.md](README.md) is the tool reference — what the files are and how to
run it. This is the method.

**The source game's own towers are in
`ReferenceFilesFromOtherProjects/TowerVisualReferences/`**, one screenshot per
element, and that folder's own README says which tower is which cell of which
sheet. They are what a builder here should be argued against — not copied, since
these are primitives and those are finished art, but a tower whose reference is a
green orb sitting on the ground should not come out an orange orb on a pole.

---

## 0. Whose rules these are

**Every visual rule in this document was authored by Claude, not decided by the
user.** What the user asked for is placeholder visuals. The rules exist because
a roster built with none is a roster that stops matching the one before it —
they are for CONTINUITY, so the twelfth creep looks like it came from the same
game as the first.

So: **none of them is a hard rule.** Where this file, `style.py` or
`game_rules.md` says "hard rule", "never" or "must", read it as *this is the
convention the existing rosters were built to, and breaking it for one unit
costs the continuity it was buying*. That is a real cost and worth arguing
about. It is not a prohibition, and changing one is ordinary work rather than a
violation.

Two of them have already moved, which is the proof that they can:

- "AIR is translucent" was written when the only flyer in the game was a ghost.
  The first solid flyer retired it — being made of vapour belongs to the
  `wraith` body plan now, and the family keeps the two tells that were really
  carrying it.
- "A creep's only lit parts are its eyes" gained a named exception when a
  burning Boss arrived, because a creature made of fire that gives off no light
  is reading as the wrong monster.

**What IS worth holding to is where a change goes.** Change it in `style.py`
and re-generate, so the whole roster moves together — a hand edit to one
generated model is overwritten by the next run and leaves that unit as the only
one disagreeing. That is the only part of the "hard" language that was ever
load bearing.

The genuinely hard rules of this project are elsewhere and are the user's: no
physics engine, only the authority simulates, authored ids. Those are in
`CLAUDE.md`. Nothing about how a tower looks is one of them.

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
| What KIND within it? | body plan and hide colour | quadruped, biped, arachnid, golem, wraith, treant, brute |
| How STRONG is it? | a ladder on GOLD COST | mass, eye brightness, carapace, then plates, spines, a crest |

**The creep ladder's SIZE rung is CAPPED and the others are not**, which is the
one asymmetry in it and is worth knowing before authoring a shape. The whole
roster lives inside a narrow band of sizes whose ceiling belongs to a top tier
Boss, because a tier carries no mechanical meaning and a field of creeps two
and three times each other's size is chaotic to read. `style.CREEP_MAX_HEIGHT`
and `CREEP_MAX_RADIUS` are that band, `creep_models.generate()` reports any
creep over it, and `game_rules.md` has the reasoning. Eyes, carapace, plates,
spines and crest carry the rest of the ladder and may climb freely.

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
  - and the ceiling that is safe depends on HOW MUCH OF THE MODEL the accent
    is. A brightness that reads as a hot detail on a Basic tower - where the
    accent is a crystal the size of a thumb on grey stone - blows a whole
    elemental Ultimate to a white ball, because on half that roster the accent
    IS the biggest object on the model. Two rosters sharing one shader want two
    ceilings.
- **A ramp applied as a flat multiply is wrong at BOTH ends of a palette.**
  Darkening every element's stone by a fifth for its cheapest path tier took
  the ones that are near-black BY DESIGN - Fire's basalt, Void's hide - to
  unlit lumps with no element left in them, while brightening the top tier did
  nothing at all to Holy, which was already ivory and had nowhere to go. Scale
  the gain by the HEADROOM the colour actually has in the direction it is being
  pulled: full effect in the middle of the range, tapering to none at the end
  it is heading for. `style.element_path_tone` is the worked version.

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

Three rules worth carrying to any roster:

- **Continuous AND stepped, together.** Size, trim colour and glow ramp
  smoothly so neighbours stay distinguishable; collar/bolts/crown/halo are
  steps so the expensive ones are distinguishable across a whole map.
- **A LADDER MUST NOT BE THE LOUDEST THING ON THE MODEL**, and this is the
  expensive lesson of the elemental roster. That roster was given this exact
  ladder - the same rings, the same metal ramp - and it failed, twice over. The
  metal was the loudest thing on every tower, so thirty different silhouettes
  read as one silhouette with its top swapped; and two neighbouring rungs of a
  six step metal ramp are nearly the same colour, so the thing being shouted at
  the player was also the thing hardest for them to actually read.
  - a ladder is a SECONDARY question. What a player has to read first is what
    the tower IS, and a device that answers "how expensive" cannot be allowed
    to sit on top of the answer to "what is this"
  - the elemental fix was to take metal off everything above the base pair and
    put the ladder into the element's OWN material instead - one value ramp on
    the stone - so the loud thing on the model is the thing that says which
    element and which path. See style.py, THE PATH LADDER
  - it works there and would NOT work on the Basic roster, which has no colour
    to ramp. That is the whole reason there are two ladders
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

The disc roster took a layer AWAY. It has no `disc_abilities.py` - its ten
effects and their thirty sets of numbers are small enough to sit in
`disc_roster.py` beside the prices - and its `disc_models.py` writes no
primitives at all, only one material and a two node scene per disc. It also
carries a `disc_style.py` of its own rather than a section of `style.py`, on
exactly the grounds the three rosters up there are kept apart: a disc cannot
accidentally take a tower rule if it never sees one. What it DOES reach into
`style.py` for is the ten element hues and the ten side counts, so a Fire disc
and a Fire tower cannot disagree about what Fire looks like.

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

- **A FULL `generate.py` run rewrites every roster, not the one you are on.**
  If the generator source has moved on since the checked-in output was last
  written, that run also lands every pending change with yours — card slots,
  material brightness, a projectile changing class. It is the tool working
  correctly and it is still not what you asked for. Read `git status` after the
  first run and decide deliberately. `git checkout --` on the rest is a poor
  fallback: reverted files can end up referencing resources that a
  half-finished change deleted, and the project stops booting.
- **A PLAN CAN OFFER A PART THE FAMILY NEVER USES.** The machine builder makes
  a swinging arm because the first machine in the roster was an attacker; the
  second was not, and the prefab stage wired a strike component to it because a
  `Swing` node existed. It errored on the creep's first frame. What a MODEL
  offers and what a FAMILY actually does are two questions, and the content
  stage has to ask the second one.
- **A family rule can be two rules wearing one coat.** AIR was written as "no
  legs, a shadow disc, and translucent" while the only flyer in the game was a
  ghost. The first solid flyer made it obvious that translucency was the
  WRAITH plan's, not the family's — drawn as vapour, a Wyvern reads as a
  spirit. When a rule stops fitting the second member of its category, check
  whether it was ever about the category.
- **On a TRANSLUCENT creep the rim colour IS the colour.**
  `creep_vapour.gdshader` mixes both the albedo and the alpha towards `rim` by
  the same fresnel term, so the silhouette - the only part a player really
  sees - is almost purely rim, and the three body tones only tint an interior
  that is 22% opaque. Authoring a wraith three shades darker changes nothing
  visible. What actually moves its value is its `rim` and its `face_alpha`,
  which is why density is a per-creep number rather than one constant.
- **A baked icon flatters a translucent creep**, for the same reason: its
  near-clear interior composites against a transparent background rather than
  against a dark lane, so a ghost reads several steps paler in its icon than in
  the game. Judge a wraith by running it, not by its PNG.
- **A creep's icon is a render of its model, so it cannot exist before the
  model does.** A `.tres` that names a missing texture takes the WHOLE resource
  down with it - Godot aborts the file, and every other property on it reads
  back as a default. Author the stats without the icon, generate, bake, then
  add the icon reference.

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
  - and a head hung off a body that is ALREADY leaning takes its angle
    against that lean rather than against the world, so it needs a rotation
    the other way to come back to level. Left at the body's own lean, the
    creature spends the whole match looking at ground the camera never sees,
    with the two lit dots that are its face pointing at the floor
- **From directly above, whatever is at the FRONT of a model is its face**,
  whether or not that is where the face is. A bar laid across the shoulders,
  a raised brow, a pair of pale fists at the end of long arms - any of them
  will sit between the camera and the eyes, and a creep whose eyes are covered
  reads as having no facing at all. Leave a gap for the head to be the
  frontmost thing, and put the brow BEHIND the eyes rather than over them.
- **A LADDER CAN RUN OUT SILENTLY, and this one did.** The creep ladder is
  measured in half decades of GOLD and its ramps were authored with six rungs,
  which covered the roster it was built for. It did not cover the next two
  brackets: `creep_rung` clamps at the end of the ramp, so everything above
  3,162 gold quietly landed on one rung, and by the end of tier 2 a third of
  the roster shared one carapace colour and one eye brightness. Nothing errors,
  nothing looks wrong in a diff, and the ladder simply stops saying anything
  about the expensive half of the game. **Adding a bracket is a reason to count
  the rungs it needs**, and extending a ramp afterwards moves every unit that
  was clamped - which is the ladder doing its job rather than churn, but is
  worth deciding on purpose.
  - the SIZE ramps are the exception and must NOT be extended with the rest.
    They are capped on purpose (`style.CREEP_SIZE_RUNG_CAP`), which is also
    what let this be fixed without a single existing model changing size.
- **A rung nobody stands on has never actually been looked at.** The creep
  ladder's ramps were authored for six rungs and only five were occupied, so
  the top rung's emissive carapace had never been rendered: a flat plate
  catching the sun came out salmon pink, and every claw and horn on the first
  creep to reach that rung read as rusted iron. Whatever a ladder's top rung
  is worth is a guess until something is standing on it.
- **A RING is a strong shape and a weak tier tell.** It reads instantly, which
  is exactly why it is a bad thing to spend a ladder on: put one on every tower
  in a roster and the ring is what a player sees first on all of them. Where a
  ring is doing real work is separating TWO towers that are otherwise the same
  shape - the elemental base pair, where it survived - and there it wants two
  metals as far apart as metals get rather than two rungs of one ramp.
- **A cluster of same-sized parts is a bunch of grapes, whatever it is on.**
  This was learned on fur and it is not about fur. The first Sludge Monstrosity
  was a mound, four humps, five vents and five bubbles all within a whisker of
  the same size, and it came out as a plate of ice cubes with no silhouette at
  all. What fixes it is a HIERARCHY: one part that is unmistakably the body,
  parts that are plainly smaller than it, and one of whatever the detail is -
  not eight things the same size. It matters most on the organic builders,
  because a machine gets away with repetition and a creature does not.
- **A cluster of same-sized spheres is a bunch of grapes, not a creature.** Fur
  built as five round lumps the size of the chest reads as a snowbank from
  every angle. What makes fur read is a RAGGED OUTLINE, so the lumps have to
  be small, flattened, and confined to one part of the body - and the tone
  budget matters as much as the size: if the pale tone is spent on the back,
  the fists have to come down to the body tone or the silhouette is all
  highlights and no shape.
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
- **`creep_roster.py` / `roster.py`** — the row. A new roster member is a row
  first; a new BUILDER is only for a creature the existing plans would have to
  lie about.

Do not write counts, or the current value of a tuning knob, into any `.md`.
See CLAUDE.md.

---

## 12. A roster with no model at all

The technology discs, and the reason this section exists is that they are the
first thing here that is NOT made of primitives. If the next roster is a rune,
a marker, a zone or anything else that lies on the floor rather than standing
on it, this is the shape of the work.

**What a disc is:** one flat quad running one shader, and nothing else. No
`modelkit`, no primitives, no `Turret`, no `Muzzle`, no height ramp, no width
ramp. `disc_models.py` writes a material per disc and a two node scene to hang
it on, and that is the whole models stage.

**Why:** the camera looks down. A thing set INTO the ground would show almost
nothing of a raised shape anyway, and drawing one would have cost the single
most valuable thing the disc roster has to say - that a tower stands up and a
disc lies flat. That is the first question a player asks of a maze square and
it now has a one glance answer that no amount of silhouette work could match.

**How the three axes came out:**

- WHICH KIND is answered by being flat, before colour or shape or size. It is
  the loudest thing about a disc and it is the thing that matters most
- WHICH ELEMENT is the glyph's colour and its SIDE COUNT, reusing both from
  `style.ELEMENTS` rather than restating either. Same two answers the elemental
  towers give, in the same order, which is why a Holy disc and a Holy tower are
  both eight sided
- WHICH TIER is the glyph's RADIUS and nothing else. **One rule where the tower
  ladders are six**, and that is the real lesson: a flat circle has one thing
  to say everything with, so a second rule laid over the first would be
  fighting it for the same pixels. Resist adding one
- The ULTIMATE turns slowly, because MOTION IS RESERVED FOR THE TOP RUNG and
  that rule survived the roster having nothing else in common with the towers

**The traps this one paid for:**

- **A flat quad cannot rise.** `Building` scales a visual on Y over a
  construction, which for a plane is no change at all - so a disc looked
  finished the instant it was ordered. It spends the same ramp on X and Z
  instead and opens out from a point. Anything else that lies flat will hit
  this
- **A fade would have been the obvious answer and is not available.** Opacity
  has to be written per building, and `gl_compatibility` has no per-instance
  shader uniforms. That is also why there is one material per disc rather than
  one shared material with the glyph overridden - the same constraint that
  gives the towers one energy material per line and tier
- **The ground patch had to be a different PATTERN, not a different colour.**
  Colour is spoken for (section 3), so a disc's plate could not simply be
  tinted to tell it from a tower's. It is a true circle cut with rings and
  spokes against the tower's rounded square of cracked slabs, in the same stone
- **The preview came free by reusing a uniform name.** The disc shader declares
  `preview_tint` because that is what `BuildingFoundation.gd` writes, so a disc
  ghosts green and red like everything else in the game without a line being
  written for it. Worth copying: match the existing name rather than inventing
  one and wiring it
