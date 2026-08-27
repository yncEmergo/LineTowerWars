# ModelGen

Generates the placeholder art the game ships with: the tower models, the
materials they share, their projectiles and impacts, and the `.tres` content
that points at all of it.

Not part of the build. Nothing at runtime knows it exists, and `.gdignore`
keeps Godot's filesystem out of this folder entirely.

## Running it

From the **project root**, not from here:

```
python Tools/ModelGen/generate.py                 everything
python Tools/ModelGen/generate.py models          one stage
python Tools/ModelGen/generate.py --showcase      plus the review scenes
```

Stages are `materials`, `effects`, `models`, `content`. It is idempotent: a run
with nothing changed rewrites every file byte for byte, so `git status` after a
run tells you exactly what your edit did.

Needs Python 3 and nothing else — no Godot, no packages.

## Why it exists

Thirty towers is past the number a person keeps consistent by hand. The tier
ladder only reads if every tower obeys the same six rules; a branch only reads
as a family if its four tiers really are one shape at four sizes. Both stop
being true the first time somebody nudges one file. So the rules live in
`style.py`, the numbers live in `roster.py`, and everything else is output.

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
| `materials.py`, `effects.py` | the shared palette; projectiles and impacts | |
| `showcase.py` | throwaway review scenes, opt in | |

The two rosters are separate files all the way up from `style.py` on purpose:
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

## Adding a roster

**Read [PLACEHOLDER_ART.md](PLACEHOLDER_ART.md) first.** It is the method: the
design philosophy the tower roster was built to, the three axes a unit has to
answer on, why colour is reserved for the elements, the contracts a model must
meet, how to verify the result, and every trap that has already been paid for.

The short version of the shape of the work: only the top two layers are new.
Everything from `style.py` down is inherited.

- **Elemental towers** are DONE, and were the cheap case they were predicted to
  be: the same material roles and the same shape of ladder, plus a palette entry
  per element, a builder per shape, an ability table and a content file.
- **Creeps** need their own model file and their own content file, but inherit
  `tscn.py`, `modelkit.py` and the ladder machinery unchanged.

## Reviewing the result

`--showcase` writes scenes into `Scenes/Dev` laying a line out as its own
upgrade tree. **Run them** rather than screenshotting the editor viewport — the
editor's cinematic capture renders them unlit. `Scenes/Dev` is scaffolding and
should be deleted again once the review is done.

Icons are baked separately, from the finished models: run
`Scenes/Dev/icon_renderer.tscn` from the editor. It has to run rather than be a
headless script, because baking an image means rendering one.
