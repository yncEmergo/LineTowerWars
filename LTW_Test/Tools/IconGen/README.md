# IconGen

Draws the command card ACTION icons: Move, Stop, Attack, Sell, Build, Cancel
and the rest of the buttons that are not about a unit. Output lands in
`2DArt/UI/Icons/ability_*.png`, beside the hand made `stat_*.png`.

Not part of the build. Nothing at runtime knows it exists, and `.gdignore`
keeps Godot's filesystem out of this folder entirely.

## Running it

From the **project root**, not from here:

```
python Tools/IconGen/generate.py                      writes every icon
python Tools/IconGen/generate.py --check              reports, writes nothing
python Tools/IconGen/generate.py --sheet out.png      plus a review sheet
```

It is idempotent: a run with nothing changed rewrites every file byte for
byte, so `git status` after a run tells you exactly what your edit did.

Needs Python 3 and nothing else - no Godot, no packages, same as ModelGen.

Godot imports the PNGs on its next filesystem scan and writes the `.import`
files itself. This tool does not, because a `.import` carries a uid and
CLAUDE.md is clear that we never invent one.

`--sheet` writes every icon at 4x on the dark panel they are really drawn on,
which is the only honest way to look at a white-on-transparent glyph. Give it
a path outside the project; the sheet is for reviewing, not for shipping.

## Why it exists

A command card is a wall of small white glyphs, and it only works if all of
them obey the same rules - one stroke weight, one margin, one flat silhouette.
That is a consistency a person loses the third time they open a paint program
and eyeball it, so the rules live in `glyphs.py` as numbers, and everything in
`2DArt/UI/Icons/ability_*.png` is output.

**The output is checked in and is ordinary PNG.** Redraw one by hand whenever
that is quicker - just know the next run overwrites it, so anything worth
keeping goes back into the glyph.

## The layers

| File | What it is | Changes when |
| --- | --- | --- |
| `png.py` | writes RGBA PNGs, by hand, out of `zlib` | never |
| `raster.py` | supersampled polygons, circles, capsules, arcs | rarely |
| `glyphs.py` | **the icons** - the style rules and one function each | an icon changes |
| `generate.py` | renders them out, checks their margins | |

Glyphs are authored in a 0..64 square, which is the size they are written at,
so a number in `glyphs.py` is the pixel it comes out as. The mask underneath
is 8x that; downsampling is where the antialiasing comes from, and it is the
same soft edge the hand drawn `stat_*.png` have.

## The style

Read off `stat_*.png`, because the two sets share a HUD and must not look like
two games. `glyphs.py` says this at the top as well, in more detail:

- one flat **white silhouette**. No outline, no second tone, no interior
  detail that is not a hole. `CommandSlot` tints the whole texture - grey when
  an ability cannot be used, warm gold when a toggle is on - and a silhouette
  is what survives being tinted
- **chunky**: nothing thinner than `STROKE`, no gap narrower than `GAP`
- about `MARGIN` of air on each side, judged by eye rather than measured
- **objects, not diagrams.** The existing set says coin, heart, clock, castle,
  bone. A new entry should be a THING a player can name

`--check` prints each glyph's bounds and complains when a margin is far off
the rest. It is a smell test, not a rule: a round glyph is allowed to
overshoot a square one, exactly as `stat_life` already does.

## What is NOT here

**Anything ABOUT a unit.** Build, upgrade, send and morph all draw the unit's
own icon out of `2DArt/Icons/`, which ModelGen bakes from that unit's model -
see `UnitAbility.icon_texture()`. Return to Elemental Core looks like it
belongs here and does not, for the same reason: it already draws the Core.

**The passives.** Creep traits - Flying, Boss, Devotion Aura - and the
elemental towers' named abilities have no icon of their own yet. They are the
obvious next batch and belong in `glyphs.py` beside these, under the same
rules, when somebody draws them.

## Wiring a new one up

1. add a function to `glyphs.py` and an entry in `GLYPHS`
2. run with `--sheet` and look at it next to the others before believing it
3. point the ability at it. A hand written `.tres` gets an `ext_resource` and
   an `icon =` line; one that ModelGen owns gets `action_icon_path("<name>")`
   in `element_content.py` or `tower_content.py`, or the next ModelGen run
   quietly throws the edit away
