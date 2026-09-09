# Adding a roster of placeholder visuals

How the Basic tower roster got its look, written down so the next roster gets
the same one. The elemental towers, the creeps and the technology discs have
all been built to it since; where a roster answered one of its questions, the
answer is recorded here next to the question.

**The discs are the roster that broke the mould, and that is the interesting
case.** A disc has no model at all - it is three flat layers painted onto the
floor - so almost none of section 7 applies to it and the whole of sections 4
and 5 had to be answered a different way. Two of the rules below did not
survive it: motion for the top rung became meaningless, and the roster answers
"which element" on ONE axis where the towers use two. What carried over is
everything else, the three axes and the rule that colour belongs to the
elements above all. Read section 12 before assuming a new roster has to be made
of primitives, and read it as the record of what a rule costs when it is
wrong.

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

Three of them have already moved, which is the proof that they can:

- "AIR is translucent" was written when the only flyer in the game was a ghost.
  The first solid flyer retired it — being made of vapour belongs to the
  `wraith` body plan now, and the family keeps the two tells that were really
  carrying it.
- "A creep's only lit parts are its eyes" gained a named exception when a
  burning Boss arrived, because a creature made of fire that gives off no light
  is reading as the wrong monster.
- **"A Basic tower's tier is its trim metal" is gone entirely**, and it is the
  biggest of the three because it was that roster's whole identity. The user
  asked for two things — that the Basic towers read as ordinary
  tower-defence towers, and that the metal rings come off — which turned
  out to be one thing, because the rings WERE the ladder. See section 13.

**Note what the third one was NOT.** It was not a rule that stopped fitting a
new member of its category, which is what the first two were. It fitted every
tower it was ever applied to and was still the wrong rule, and the only thing
that surfaced it was somebody looking at the game and saying they did not like
it. No amount of internal consistency was going to catch that.

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
| What FAMILY is it? | shape, plus one painted accent | square watchtower / hex iron machine / round orb tower |
| What KIND within it? | one decisive silhouette | ballista, mortar, saw, dropping weight, orb, rack |
| How STRONG is it? | a stepped ladder | timber turning to stone, tint, size, added parts |

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

    10g      bare. No paint, no stone, no gallery
    30g      + paint, its first colour
    150g     + a projecting parapet, and the stone it stands on
    1,000g   + the corbels that carry the parapet
    5,000g   + a crown: the top of the tower changes shape
    25,000g  + a pennant, and it moves

Alongside that, continuously: the tower grows, its MASONRY CLIMBS from the
footing while the timber retreats into the gallery, and its surfaces darken and
enrich. The material boundary is the loudest of those three and is the one this
roster gained when the metal came off — see section 13.

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
upgrade, carry no PAINT at all, are built from the raw `deep` tone, and are
missing the part that names the line. That gap is deliberate and cost several
iterations to get big enough.

It used to be the missing trim RING that drew that gap, and when the metal came
off this rung had to be handed to something else or the cheapest tower in the
game would quietly have gained the tell its first upgrade is supposed to buy.
Worth noticing about any ladder rung: the RUNG is the rule, the thing drawing it
is not.

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

**What a disc is:** three flat quads and nothing else. No `modelkit`, no
primitives, no `Turret`, no `Muzzle`, no height ramp, no width ramp.
`disc_models.py` writes two shaders' worth of material and a three node scene,
and that is the whole models stage.

**Why:** the camera looks down. A thing set INTO the ground would show almost
nothing of a raised shape anyway, and drawing one would have cost the single
most valuable thing the disc roster has to say - that a tower stands up and a
disc lies flat. That is the first question a player asks of a maze square and
it now has a one glance answer no amount of silhouette work could match.

### The three layers, and why they are three

    Base    the shared square tower foundation, instanced unchanged
    Plate   a round worked disc set into it, identical on all thirty-one
    Glyph   a coloured circle. Colour is the element, size is the tier

The first cut had ONE layer doing all of it: a round patch with its own ground
pattern, the element as a coloured polygon inside it. Three things were wrong
with that and the fix for all three was to split it.

- **A disc did not read as a claimed square.** Every tower in the game marks
  its cell with the same square patch; a disc marked its cell with something
  else entirely, so the one thing the two DO have in common was the one thing
  the art denied. Instancing the tower foundation says "a building is here" in
  the words the rest of the game already uses.
- **ROUND ON SQUARE is a stronger read than two different rounds.** The
  foundation and the plate are the same stone - they have to be, because colour
  belongs to the elements - so shape is the only thing that can separate them,
  and a machined circle on a square patch separates instantly. The plate's
  diameter is tuned so the square shows at every corner; close that gap and the
  two layers merge back into one lump.
- **An upgrade could not grow only what it bought.** The tier is the size of
  the coloured part, and with one quad the colour was a radius UNIFORM - which
  cannot be animated per building, because the material is shared by every disc
  of a type and `gl_compatibility` has no per-instance uniforms. Putting the
  glyph on its own node made the tier the MESH's size and the growth that
  node's scale, and an upgrade now opens the colour out of the middle of a
  plate that never moves.

### The three axes came out

- WHICH KIND is answered by being flat, before colour or shape or size. It is
  the loudest thing about a disc and the thing that matters most.
- WHICH ELEMENT is the glyph's COLOUR, and nothing else. The first cut also
  gave each element the side count its towers are built on, so the roster would
  answer on two axes the way the towers do. **It was dropped on review and that
  is the lesson worth carrying:** a disc is read in peripheral vision while the
  player is watching a creep wave, and counting sides at that size is something
  the eye will not do. Colour it reads instantly.
  - what it cost is a second channel for a colourblind player, which the towers
    have and the discs do not. If that matters, the answer is not the polygons
    back - it is something read as fast as colour, like pips around the rim.
- WHICH TIER is the glyph's SIZE and nothing else. **One rule where the tower
  ladders are six**, and that is the real lesson: a flat circle has one thing
  to say everything with, so a second rule laid over the first would be
  fighting it for the same pixels. Resist adding one.
- **MOTION FOR THE TOP RUNG DIED HERE**, and it is worth knowing why rather
  than rediscovering it. The discs obeyed the rule by turning an Ultimate's
  glyph slowly; the moment the glyph became a circle that became a still
  circle. It was not replaced by a pulse or a second colour, because the tier
  is the size and that is the single rule. A visual rule can be true of every
  roster in the game and still be meaningless for the next one - see section 0.

### The traps this one paid for

- **A flat quad cannot rise.** `Building` scales a visual on Y over a
  construction, which for a plane is no change at all - so a disc looked
  finished the instant it was ordered. It spends the same ramp on X and Z
  instead, and on the GLYPH rather than the whole model where there is one.
  Anything else that lies flat will hit this.
- **A fade would have been the obvious answer and is not available.** Opacity
  has to be written per building, and `gl_compatibility` has no per-instance
  shader uniforms. That constraint is why the tier lives on the mesh, and it is
  the same one that gives the towers one energy material per line and tier.
- **The portrait rule nearly hid the whole unit.** `VisualUtil.portrait_skips`
  drops a `BuildingFoundation` from icons and portraits, correctly - a tower's
  ground patch is floor. While a disc WAS one foundation and nothing else, that
  left it with a blank portrait and an unbakeable icon. The three layer version
  fixes it by having layers that are not the foundation, which is a better
  answer than special-casing the rule was.
- **The icon camera needed its own angle.** Seen from the creeps' three quarter
  view a flat disc is a squashed ellipse with its glyph foreshortened into a
  smear - destroying exactly the two things the icon has to say. `IconGen3D`
  carries an elevation per roster for this, and discs are baked from very
  nearly overhead. Not exactly overhead: `look_at` with an UP of `Vector3.UP`
  degenerates when the camera is straight above its target.
- **The build preview came free by INSTANCING rather than rebuilding.** The
  foundation layer IS `tower_foundation.tscn`, so it ghosts green and red with
  no work at all, and `UnitModel` swaps the other two layers for the flat ghost
  material the way it does any tower mesh. The first cut wrote a `preview_tint`
  uniform into its own shader to imitate that, which worked and was a parallel
  path to keep in step. Reach for the existing scene first.

---

## 13. Rebuilding a roster that was already finished

The Basic towers, second pass. The first one is in git and was *faceted arcane
machinery*: nine grey plated silhouettes wearing a six rung ramp of trim metal.
It obeyed every rule in this document. It was still wrong, and the only thing
that surfaced that was the user looking at the game and saying so.

**The two requests were one request.** "Make the Basic towers look like
ordinary tower-defence towers" and "take the metal rings off" arrived as
separate notes in the same message, and they cannot be done separately: the
rings WERE the tier ladder — a base ring at 30g, a collar at 150g, bolts,
crown fins, a turning halo, on an iron-to-white-gold ramp. Deleting them
without a replacement leaves a roster with no answer to "how dangerous is
this".

So the first job of a visual rework is to find out **which rule the thing being
deleted was actually carrying**. It is rarely the one it looks like.

### What replaced it, and why that was available now

The ladder moved into the tower's own MATERIAL — which is the fix the elemental
roster had already made, for the same two reasons, and is written up in
`style.py` under THE PATH LADDER. What is new is that the Basic roster could
not have done it before:

- an elemental tower has a HUE to ramp, and the Basic roster gave its colour
  away to the elements on purpose (section 3)
- but a tower made of TIMBER AND STONE has two materials, a **boundary between
  them that can move**, and a tint that can ramp — so the Basic roster got a
  ladder rung the elemental one does not have and could not have

**The material boundary turned out to be the best signal in either roster.** A
shaft is authored as two stacked cylinders, masonry below and timber above, and
the join climbs the tower on every upgrade. It is readable at any distance, in
any light, needs no colour, and — unlike every other rung — it is a thing the
player watches HAPPEN to a tower they just paid for.

### What this pass cost, in order of how long it took to see

Each of these looked fine in the generator and wrong on screen. The lesson in
all of them is the same and is section 9's: **run it, at the match camera's own
pitch, before believing any of it.**

- **A ladder rung is a rule, not the part that draws it.** The 10g tower having
  no trim ring is what made the first upgrade a player ever buys the most
  visible one in the game. Delete the rings and that rung silently becomes "the
  10g tower looks like every other tower". It had to be handed to the paint.
- **Three shaders pulling the same way saturate to white.** The iron got a
  polish lift, a sheen band AND a hard rim, each defensible alone. Together,
  every barrel and every saw blade on the roster came out as a featureless pale
  blob. This is the accent-saturates-to-white trap from section 3 reached
  through a HIGHLIGHT rather than through an emission, which is why it was not
  recognised for what it was.
- **A ceiling tuned for small accents blows up a big one.** The Basic energy
  material's brightness was chosen when every lit part on the roster was a
  sight, a vent or a spark on grey stone. The reworked Sentry line carries an
  ORB that is the biggest object on the model, and at the old ceiling an
  Ultimate Defender was a white ball. Same trap as the elemental roster's, in
  the opposite direction: there a small-accent ceiling met big accents, here a
  roster that only had small accents grew a big one.
- **THINGS THAT SIT ON TOP OF A TOWER ARE LIDS.** The camera looks down, so
  anything spanning the top of a model hides everything under it. It cost three
  separate parts in one pass: the Stomper's frame head (a full disc above the
  weight — it made the whole mechanism invisible and became two crossed
  beams), the Carver's blade guard (a hood a little wider than the saw, hiding
  the one thing the branch exists to show), and the Watch Tower's roof, which
  was designed out before it was ever built for exactly this reason and became
  four corner caps around an open middle.
- **A part sized as a share of its tower gets it wrong at both ends.** Merlons
  authored at a fraction of the radius gave the widest towers the chunkiest
  battlements, so a Cannon read as a ring of boulders.
- **Verticality is not decoration when the ladder is drawn in it.** The height
  ramp had been deliberately lowered on the old roster, correctly — that one
  was squat drums, and "a top down tower wants to be a footprint with something
  on it" is right for those. This one is watchtowers, and four of its six rungs
  are drawn ABOVE the shaft. At the inherited height the first pass came out as
  a field of pancakes with the gallery, the parapet and the whole material
  boundary squashed into a few pixels.

### The second pass, and the four things it cost

The roster above was reviewed and came back with one instruction that reframed
the whole ladder: **every upgrade has to change one thing you can see, and if
it is unique to a branch it has to be big.** Four branches had their top three
tiers reported as indistinguishable. What that pass taught:

- **A LADDER MUST NOT BE MADE OF ONE KIND OF THING.** The first ladder was
  material, tint and added parts - all of them quiet, all of them the same
  kind of quiet. It now runs material, tint, METAL and parts, and the metal is
  what actually fixed it: copper, bronze, steel and polished steel are four
  different objects where four rungs of one grey are one object.
- **COUNTING IS NOT A TELL.** The anti-air branch ramped 3, 4, 5, 6 tubes and
  its top three tiers still read as the same tower. Nobody counts at match
  distance. The same budget spent on the tubes' COLOUR separated them
  instantly. Prefer a difference the eye takes in whole.
- **A TINT LADDER THAT DARKENS COMPRESSES ITS OWN CONTRAST**, twice over. The
  steeper stone ramp pulled mid, dark and light down together, so an
  Ultimate's blocks landed within a few percent of each other and the coursing
  - the thing that makes it read as masonry at all - vanished exactly at the
  top of the ladder. The light tone now moves about half as far, and the block
  scatter RISES with the tier where it used to fall.
- **AND IT COMPOUNDS WITH EVERYTHING ELSE POINTING THE SAME WAY.** The damp at
  the foot of a tower is also a mix towards the dark tone, so on an already
  dark palette it took the base to flat black. Any effect that darkens has to
  be eased off as the palette it sits on darkens.

### The lid, for the third and fourth time

Section 10 already records that things sitting on top of a tower are lids,
because the camera looks down. It happened twice more in one pass, and both
times on the part the branch exists to show:

- the Defender's 5,000g step was authored as a closed LANTERN HOUSE - wide
  piers and a cap over the top - and it did not enclose the orb, it DELETED
  it. The tower came out as a solid black drum with the one thing that whole
  branch is about nowhere on screen. It became a splayed crown with the orb
  raised clear instead.
- the Carver's blade guard was a hood a little wider than the saw, which is
  what the real machine wears, and it hid the saw completely.

**The rule is stronger than "be careful with roofs".** If a part spans the top
of a model, from the match camera that part IS the model. Author the thing that
matters as the highest thing, or leave a hole for it.

### A pattern shader must ride the model

The three surface shaders projected their pattern in WORLD space, for two real
benefits - courses ran continuously across a tower's separate meshes, and
neighbouring towers got different phases for free without a per-instance
uniform, which `gl_compatibility` does not have.

It is wrong, and the way it is wrong is invisible in every screenshot. A
world-projected pattern is nailed to the GROUND: anything that moves slides
through it. The spinning saw was the reported case - a disc turning behind a
stationary grain, like something seen through a dirty window - but it was
equally wrong on every aiming turret, every recoiling barrel and the Stomper's
falling weight.

Project in the mesh's own space. What is given up costs almost nothing: the two
halves of a shaft are different materials anyway, so there was never a course to
carry across the join.

**And test it with a POSITIVE CONTROL, because a still frame cannot show it.**
One mesh, drawn four times at four rotations: local space means every copy is
the same picture turned, world space means each copy shows a different slice of
one pattern. That is a single screenshot and it answers the question outright,
where staring at a moving saw does not.

### The third pass: three more, and the lid a third time

- **A SHAPE STEP MAY NOT LIE ABOUT THE MECHANISM.** The Cannon's 5,000g step
  was a second barrel and it was the best-looking answer on that branch. It
  still had to go: the tower fires one projectile, so two muzzles tell a player
  something untrue about a thing they just spent five thousand gold on. The
  replacement is a heavy carriage - cheek plates and a muzzle brake, both
  unmistakably parts of ONE gun.
  - the same rule caught the anti-air rack, where the recoil kicked all six
    tubes for a tower that launches a single missile. One tube moves now, and
    the missile leaves that tube.
  - the general form: **decoration may be free, but anything that reads as a
    MECHANISM is making a claim.** Check the claim against what the unit
    actually does.
- **AND A THIRD LID, in a new costume.** The replacement for those two barrels
  was first an armoured casemate - a drum around the breech - and from the
  match camera the drum was simply bigger than the barrel, so the gun became
  the smallest thing on a gun tower. A part that FRAMES a weapon is safe where
  a part that ENCLOSES it never is. That is now three separate features lost to
  the same mistake in one project (a lantern house, a blade guard, a casemate),
  so treat "does this span the top?" as a checklist item, not as judgement.
- **A ROTATED PRIMITIVE NEEDS TO SAY WHICH RAMP ITS LENGTH TAKES.** `cyl` and
  `capsule` have carried an `along` for this since the creep roster; `prism` did
  not, and the first saw teeth built out of prisms were quietly the wrong length
  at every tier and wrong by a DIFFERENT amount at each, because the width and
  height ramps are different curves. Nothing errors. If a helper can be rotated,
  it needs the parameter.

### A trajectory is authored in world units, and that is the sanity check

The projectile arc was a FLAT height applied to every shot whatever the range,
so a mortar threw the same bow at a creep one cell away as at one at the edge of
its reach. It is now a share of the distance actually flown, capped at full
range with a small floor.

The value itself was the louder half of the fault: the Cannon was authored at
3.4, in a world where **a player cell is 1.0 and no tower on the roster stands
as tall as one**. Every shell it fired arced clean over its own parapet. When
authoring anything spatial here, check it against the cell rather than against
the number that came before it - a scale mistake reads as a physics bug and
gets looked for in the wrong file.

### Two things that were checked and worth copying

- **A rule stated by omission should be stated by the thing it is about.** The
  icon baker excluded towers entirely, with a comment explaining that tower
  icons are named by DISPLAY NAME while the scan is keyed by PREFAB, and that
  baking them once wrote two hundred files under names nothing reads. The Basic
  towers needed re-baking, so that became a CHECK — bake a unit only where its
  key and its display-name slug agree — which lets the thirty Basic towers
  through, keeps the eighty elemental ones out, and says which it skipped and
  why. Same protection, applied by the thing it is actually about.
- **Grep for what you deleted, including in prose.** Removing the metal ramp
  left four comments elsewhere explaining OTHER rosters by analogy to it, and
  one of them — the creep carapace ramp — carried a claim that was now false:
  that the creep and tower ladders run in opposite directions and so can never
  be confused. The tower ladder had just been turned round to run the same way.
  Nothing errors, and the justification for a real decision quietly becomes
  untrue.


---

---

## 14. Motion: the patterns, and what each one is for

Placeholder art is mostly shapes, and everything above is about shapes. Motion
turned out to carry as much of the readability as the silhouette does, and it
has its own rules. They were learned one at a time; this is them gathered up.

### The five kinds of motion this project has

| Component | What it is for | Driven by |
| --- | --- | --- |
| `SpinAnimation3D` | something that TURNS while it works: a saw, a governor, an orbit | a target existing, or nothing at all |
| `RecoilAnimation3D` | a single weapon kicking as its shot leaves | `attacked` |
| `BarrelCycleAnimation3D` | a RACK firing its barrels in turn | `attack_started` then `attacked` |
| `SlamAnimation3D` | something raised and brought down on the beat | `attack_started`, across the windup |
| `BobAnimation3D`, `SwayAnimation3D` | idle life: a floating orb, a pennant | nothing - they never stop |

### The rules

- **MOTION IS THE LOUDEST SIGNAL A TOP DOWN CAMERA HAS.** That is why idle
  motion is reserved for the top of a ladder and why an attack animation is
  worth more than any amount of surface detail. It is also why a motion that is
  WRONG is so much more damaging than a shape that is wrong: the eye goes to it
  first.
- **AN ANIMATION IS A CLAIM.** Decoration is free, but anything that reads as a
  mechanism is telling the player how the tower works. Six tubes recoiling for
  one missile, or two muzzles on a tower that fires one shell, are both the
  model contradicting the simulation. Check the claim.
- **A MOTION NEEDS A MINIMUM DURATION.** Anything driven by "is there a target"
  will be asked to run for a single frame sooner or later, because the fastest
  towers kill in one hit. Without a floor the part twitches, and a twitch reads
  as broken rather than as fast. See `SpinAnimation3D.minimum_run_seconds`.
- **DRIVE IT OFF THE ATTACK'S OWN SIGNALS, never off a duration of your own.**
  `attack_started` carries the real windup, so a swing retimed in balance stays
  landing on the beat with no animation change. A component that counted its
  own seconds would drift the moment anything was tuned.
- **WHICH SIGNAL IS NOT INTERCHANGEABLE, and this one is genuinely subtle.**
  `AttackComponent` reads the muzzle inside its own `_fire` and only emits
  `attacked` afterwards. So anything that has to be in place BEFORE the
  projectile spawns - picking a barrel, moving the muzzle - must happen on
  `attack_started`, which precedes the shot even at zero windup. A component
  that advanced on `attacked` would fire every shot from the barrel that fired
  LAST time: right for the recoil, one step out for the projectile, and
  invisible in a code review.
  - the KICK still belongs on `attacked`, because a recoil is the consequence
    of a shot leaving.
- **A MOVING PART MUST OPT OUT OF PHYSICS INTERPOLATION.** Everything here
  animates on the render frame, and Godot's interpolator assumes a transform
  only changes on a tick, so an interpolated node moved in `_process` jitters -
  visibly on some machines and not others.
- **A CANCELLED ATTACK HAS TO PUT THINGS BACK.** Exactly one of `attacked` or
  `attack_cancelled` follows every `attack_started`, which is what lets a
  component hold state across a windup at all. A rack that advanced its barrel
  and was then cancelled must give that turn back, or the cycle drifts out of
  step with what the player is watching.
- **AND A PATTERN SHADER MUST RIDE WHAT IT IS PAINTED ON.** The motion rules
  above are useless if the surface slides through its own texture while it
  moves - see the world-space section earlier, which is the same bug class
  reached from the material side.

### How to test motion, when a screenshot cannot

A still frame cannot show a spin, a cycle or a kick, and CLAUDE.md's rule about
positive controls bites hardest here. Two things that worked:

- **For a shader or a transform, draw the same thing several times at several
  states in ONE frame.** Four copies of a mesh at four rotations answers "does
  the pattern ride the model" outright, where staring at a moving saw does not.
- **For wiring, instantiate the prefab and DO NOT ADD IT TO THE TREE.** `_ready`
  never runs, so no unit, no match session and no registry are needed, and the
  exported values are still resolved. That is how the barrel arrays were proved
  to deserialise - a typed `Array[Node3D]` written as `node_paths` plus a list
  of NodePaths comes back EMPTY if it fails, the component logs once, and every
  shot then leaves from wherever the muzzle happened to be authored, which
  looks almost right. A clean boot proves nothing about it, because a tower
  prefab is only instantiated when somebody builds one.
