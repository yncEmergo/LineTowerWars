"""Regenerates the command card action icons.

    python Tools/IconGen/generate.py                 writes every icon
    python Tools/IconGen/generate.py --check         reports, writes nothing
    python Tools/IconGen/generate.py --sheet OUT.png plus a review sheet

RUN IT FROM THE PROJECT ROOT. The output path below is relative to it.

WHY THIS EXISTS. A command card is a wall of small white glyphs that only
works if every one of them obeys the same rules - the same stroke weight, the
same margin, the same flat silhouette that survives being tinted grey or gold
by CommandSlot. That is a consistency a person loses the third time they open
a paint program, so the rules live in glyphs.py as numbers and everything in
2DArt/UI/Icons/ability_*.png is output.

**The output is checked in and is ordinary PNG.** Nothing at runtime knows
this tool exists. Redraw one by hand whenever that is quicker - just know the
next run overwrites it, so anything worth keeping goes back into the glyph.

It writes into:
    2DArt/UI/Icons/     ability_*.png, next to the hand made stat_*.png

Godot imports them on its next filesystem scan and writes the .import files
itself. This tool does not, because a .import carries a uid and CLAUDE.md is
clear that we never invent one.

WHAT IS NOT HERE. Anything ABOUT a unit - build, upgrade, send - draws that
unit's own icon out of 2DArt/Icons/, which ModelGen bakes from its model. See
UnitAbility.icon_texture(). Creep traits and the elemental tower passives have
no icon of their own yet; they are the next batch and belong in glyphs.py
beside these when they are drawn.

Needs Python 3 and nothing else - no Godot, no packages, same as ModelGen.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import glyphs
import png

OUT_DIR = os.path.join("2DArt", "UI", "Icons")

## Loudest the tool gets about composition. Not a hard rule - a round glyph
## may overshoot a square one - but a glyph outside this wanted a reason.
MARGIN_MIN = 3.0
MARGIN_MAX = 15.0


## The panel an icon is really drawn on, so the review sheet judges it
## against that and not against whatever is behind a transparent PNG.
SHEET_BACKGROUND = (20, 23, 31)


def _write_sheet(path, alphas):
    """One wide PNG of every icon at 4x, for looking at them side by side."""
    scale, pad = 4, 8
    cell = glyphs.Mask().size * scale
    width = len(alphas) * (cell + pad) + pad
    height = cell + pad * 2
    rows = [bytearray(width) for _ in range(height)]
    for index, alpha in enumerate(alphas):
        left = pad + index * (cell + pad)
        for y in range(cell):
            source = alpha[y // scale]
            row = rows[pad + y]
            for x in range(cell):
                row[left + x] = source[x // scale]
    png.write_over(path, rows, width, SHEET_BACKGROUND)


def main(argv):
    check_only = "--check" in argv
    sheet_path = None
    if "--sheet" in argv:
        sheet_path = argv[argv.index("--sheet") + 1]

    if not check_only and not os.path.isdir(OUT_DIR):
        raise SystemExit("run me from the project root: %s is not there" % OUT_DIR)

    alphas = []
    for name in glyphs.GLYPHS:
        mask = glyphs.render(name)
        box = mask.bbox()
        if box is None:
            raise SystemExit("%s drew nothing" % name)
        margins = (box[0], box[1], 64.0 - box[2], 64.0 - box[3])
        flag = ""
        if min(margins) < MARGIN_MIN or max(margins) > MARGIN_MAX:
            flag = "  <- margins"
        print("%-24s %2.0fx%-2.0f  margins L%-4.1f T%-4.1f R%-4.1f B%-4.1f%s" % (
            name, box[2] - box[0], box[3] - box[1],
            margins[0], margins[1], margins[2], margins[3], flag))

        alpha = mask.to_alpha()
        alphas.append(alpha)
        if not check_only:
            png.write_white(os.path.join(OUT_DIR, name + ".png"), alpha)

    if sheet_path is not None:
        _write_sheet(sheet_path, alphas)
        print("sheet: %s" % sheet_path)

    if not check_only:
        print("%d icons -> %s" % (len(alphas), OUT_DIR))


if __name__ == "__main__":
    main(sys.argv[1:])
