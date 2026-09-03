# ModelGen

Generates the placeholder art the game ships with: the tower and creep models,
the technology discs' ground patches, the materials they all share, the towers'
projectiles and impacts, and the `.tres` content that points at all of it.

Not part of the build. Nothing at runtime knows it exists, and `.gdignore`
keeps Godot's filesystem out of this folder entirely.

## Running it

From the **project root**, not from here:

```
python Tools/ModelGen/generate.py                 everything
python Tools/ModelGen/generate.py models          one stage
python Tools/ModelGen/generate.py --showcase      plus the review scenes
```

Stages are `materials`, `effects`, `models`, `content`. The discs are written by
the last two alongside everything else - they have no stage of their own,
because they share the `content` stage's ordering constraint: the builder's
build menu has to name the disc's build ability, and that ability is the disc
content stage's to write. It is idempotent: a run
with nothing changed rewrites every file byte for byte, so `git status` after a
run tells you exactly what your edit did.

**With one caveat that will bite you the first time.** Opening a generated
`.tres` in the Godot editor and saving it — which the editor does on its own
whenever it touches one — rewrites the file in the editor's own dialect: it
adds `uid://` lines this tool deliberately never writes, reorders properties,
and drops any property that happens to equal its script default. None of that
changes what the file MEANS and the game does not care, but it does mean that
after somebody has had the project open, the next full run comes back with a
few hundred files "changed" that you did not touch.

So `git status` is only a useful signal for the roster you are actually
working on. Check that folder, and `git checkout --` the rest.

Needs Python 3 and nothing else — no Godot, no packages.

## Why it exists

Thirty towers is past the number a person keeps consistent by hand. The tier
ladder only reads if every tower obeys the same six rules; a branch only reads
as a family if its four tiers really are one shape at four sizes. Both stop
being true the first time somebody nudges one file. So the rules live in
`style.py`, the numbers live in `roster.py`, and everything else is output.

**The rules themselves are not binding.** They were authored by Claude rather
than handed down — only placeholder visuals were ever asked for — and they buy
CONTINUITY and nothing else. Change one when it is wrong. What this tool is
for is making sure that when you do, the whole roster moves with it instead of
one unit quietly disagreeing with the other twenty-nine. See
[PLACEHOLDER_ART.md](PLACEHOLDER_ART.md) section 0.

**The output is checked in and is ordinary hand-editable Godot.** Open a
generated `.tscn` in the editor and change it whenever that is quicker. Just
know the next run overwrites it, so anything worth keeping goes back into the
generator.

## The layers

| File | What it is | Changes when |
| --- | --- | --- |
| `tscn.py` | writes Godot's `.tscn` / `.tres` text formats | never |
| `modelkit.py` | primitives, placement, motion, the five material roles | rarely |
| `style.py` | **the visual language** — both palettes, both tier ladders | the look changes |
| `roster.py` | the Basic tower table, straight from `unit_data.md` §3 | balance changes |
| `tower_models.py` | the nine Basic branch silhouettes | shapes change |
| `tower_content.py` | Basic stats, prefabs, build and upgrade abilities | rules change |
| `element_roster.py` | the elemental table, straight from `unit_data.md` §4 | balance changes |
| `element_abilities.py` | each tower's named ability and its numbers | balance changes |
| `element_models.py` | ten element base shapes and twenty path silhouettes | shapes change |
| `element_content.py` | elemental stats, prefabs, passives, morphs, upgrades | rules change |
| `creep_roster.py` | the creep table, straight from `unit_data.md` 6.2 | balance changes |
| `creep_models.py` | the creep body plans and the creep ladder | shapes change |
| `creep_content.py` | creep PREFABS. **Not** their stats, see below | wiring changes |
| `disc_style.py` | the DISC visual language, kept out of `style.py` | the look changes |
| `disc_roster.py` | the disc table and its ten effects, from `unit_data.md` §5 | balance changes |
| `disc_models.py` | the plate and element materials, and one flat scene per disc | the look changes |
| `disc_content.py` | disc stats, prefabs, effects, morphs, the build button | rules changes |
| `materials.py`, `effects.py` | the shared palette; projectiles and impacts | |
| `showcase.py` | throwaway review scenes, opt in | |

**The creep stage writes prefabs and nothing else.** Creep stats, passives and
pack entries live in `Resources/UnitStats/Creeps` and
`Resources/Abilities/Passives`, they were authored by hand, and `unit_data.md`
8.1 makes them the authority. Towers are generated because thirty of them come
out of one balance table; creeps are not, because each of them is a handful of
hand-made decisions and a generator that rewrote them would win an argument it
should lose. What the prefab stage does own is the three numbers measured off
the model: the health bar's height, the click box, and the walk's stride.

The rosters are separate files all the way up from `style.py` on purpose:
they answer the same three questions differently, and a Basic tower cannot
accidentally take an elemental rule (or a hue) if it never sees one. What they
DO share is every layer below - the same primitives, the same five material
roles, the same trim ramp, and one dictionary of model heights, because a
tower's key is unique across the whole game.

`modelkit.py` names its five materials `body`, `deep`, `pale`, `trim` and
`glow` rather than anything tower-specific, because those are the five a creep
needs too: hide, shadowed hide, lit hide, claws, eyes. It is a number a 3D
artist can replace in one sitting and have every model in the game change
together.

## Running only part of it

**`generate.py` with no stage rewrites EVERYTHING**, including the rosters you are not
working on — and if the generator source has moved on since the checked-in output was
last written, that run also applies every one of those pending changes at the same time.
That is not a bug, and it is the tool doing its job, but it means a run you thought was
"add my twelve creeps" can come back with several hundred tower files changed.

So before a full run, know whether the output is in step with the source:

```
python Tools/ModelGen/generate.py     # then read git status before doing anything else
```

If the answer is no, either bring it in step deliberately as its own change, or run the
stage you actually want. `git checkout --` on the rest is the fallback, and it is a poor
one: the reverted files can end up referencing resources a half-finished change deleted,
which is how a clean project stops booting.

## Adding a roster

**Read [PLACEHOLDER_ART.md](PLACEHOLDER_ART.md) first.** It is the method: the
design philosophy the tower roster was built to, the three axes a unit has to
answer on, why colour is reserved for the elements, the contracts a model must
meet, how to verify the result, and every trap that has already been paid for.

The short version of the shape of the work: only the top two layers are new.
Everything from `style.py` down is inherited.

- **Technology discs** were the cheapest and the strangest: they have NO MODEL.
  A disc is three flat layers - the shared square tower foundation, a round
  plate, and a coloured circle - so its whole visual roster is two shaders,
  eleven materials and a three node scene. `modelkit` is not imported at all.
  What it inherits is `style.py`'s ten element hues, read rather than restated,
  so a Fire disc and a Fire tower cannot disagree about what Fire looks like.
  Read PLACEHOLDER_ART.md section 12 before building anything else that lies
  flat.
- **Elemental towers** were the cheap case they were predicted to be: the same
  material roles and the same shape of ladder, plus a palette entry per
  element, a builder per shape, an ability table and a content file.
- **Tier 2 of the creeps** was the cheap case again, and the three new BUILDERS it needed
  are the useful part of the story. A new row is the default; a new builder is for a
  creature the existing plans would have to LIE about, and each of these three cleared
  that bar in a different way. `winged` because the wraith plan has no body, only a hood
  and rags, and a Wyvern is an animal. `shelled` because a quadruped is a barrel with a
  neck on the front, and a barrel from directly above is an oval where a dome with a hard
  rim around it reads as a shell. `machine` because a Siege Engine has wheels, and the
  leg helper derives its limb lengths from a hip height that a wagon does not have.
- **Creeps** were the bigger one. They inherited `tscn.py`, `modelkit.py` and
  the ladder machinery unchanged, and needed on top of that a shader of their
  own (`creep_hide` and `creep_vapour`), a ladder measured in GOLD rather than
  in price tiers, a builder per body plan, and one thing no tower needed: an explicit
  split between authoring in HEIGHT units and in WIDTH units. Read
  PLACEHOLDER_ART.md before touching a creep model — the width and height
  ramps are separate, and for a creature that quietly breaks every angled limb
  and flattens every round part unless each number says which space it is in.

## Reviewing the result

`--showcase` writes scenes into `Scenes/Dev` laying a line out as its own
upgrade tree. **Run them** rather than screenshotting the editor viewport — the
editor's cinematic capture renders them unlit. `Scenes/Dev` is scaffolding and
should be deleted again once the review is done.

Icons are baked separately, from the finished models, by a KEPT tool that is
not part of this one:

```
godot --path . res://Scenes/Tools/icon_gen_3d.tscn -- new
```

It has to run rather than go headless, because baking an image means rendering
one. `new` bakes only the units that have no picture yet, which is what to
reach for after adding a roster. It scans `Resources/UnitStats` rather than
carrying a list, so a unit added today is baked without editing it.
`2DArt/Icons/README.md` has the rest, including why it is pointed at the creeps
and not at the towers.
