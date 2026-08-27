# The command card action icons, one function each.
#
# THE STYLE, read off the hand made stat_*.png icons next to these so the two
# sets sit in one status bar without looking like two games:
#
#   - one flat WHITE silhouette. No outline, no second tone, no interior
#     detail that is not a hole. CommandSlot tints the whole texture - grey
#     when an ability cannot be used, warm gold when a toggle is on - and a
#     silhouette is what survives being tinted
#   - chunky. Nothing thinner than STROKE, and no gap between two parts
#     narrower than GAP. These are read at a glance, in a corner, mid fight
#   - about MARGIN of air on every side, optically rather than measured: a
#     round glyph is allowed to overshoot a square one, the way the heart
#     already does
#   - objects, not diagrams. The set says coin, heart, clock, castle, bone.
#     A new entry should be a THING a player can name
#
# Anything ABOUT a unit - build, upgrade, send - is not here and never will
# be: those take the unit's own icon, see UnitAbility.icon_texture().

import math

from raster import Mask, round_rect_points

## Thinnest anything gets, and the width of every plain stroke. Measured off
## stat_gold and stat_timer, whose rings are 5 to 6 pixels.
STROKE = 6.0

## Thinnest hole. A notch between two fingers, a gap between two grid cells.
GAP = 4.0

## Air around the glyph. stat_gold sits exactly this far in on all four sides.
MARGIN = 6.0

CENTER = 32.0


# -- helpers --------------------------------------------------------------


def _rotate(points, angle_deg, about=(CENTER, CENTER)):
    """Turns a point list about a pivot, for glyphs authored square then tilted."""
    a = math.radians(angle_deg)
    ca, sa = math.cos(a), math.sin(a)
    ox, oy = about
    return [((x - ox) * ca - (y - oy) * sa + ox,
             (x - ox) * sa + (y - oy) * ca + oy) for x, y in points]


def _centered(groups):
    """Shifts point lists together so their shared bounds sit in the canvas.

    Tilting a glyph moves it off centre by an amount nobody wants to work out
    by hand, and re-tuning every coordinate after changing an angle by two
    degrees is how a set stops being consistent. So the shape is authored
    where it is easy to read and put in the middle afterwards.
    """
    points = [p for group in groups for p in group]
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    dx = CENTER - (min(xs) + max(xs)) * 0.5
    dy = CENTER - (min(ys) + max(ys)) * 0.5
    return [[(x + dx, y + dy) for x, y in group] for group in groups]


def _arrow_head(mask, tip, direction, length, half_width):
    """A solid triangle at tip, pointing along a (dx, dy) direction."""
    dx, dy = direction
    scale = math.hypot(dx, dy)
    dx, dy = dx / scale, dy / scale
    bx, by = tip[0] - dx * length, tip[1] - dy * length
    mask.polygon([
        tip,
        (bx - dy * half_width, by + dx * half_width),
        (bx + dy * half_width, by - dx * half_width),
    ])


def _sword(mask, hilt, tip):
    """One sword along a line: grip, crossguard, blade, point.

    No round pommel, and the guard kept short and low. Two swords with big
    round ends and guards that meet near the middle are a pair of SCISSORS,
    which is what the first draft of this drew.
    """
    dx, dy = tip[0] - hilt[0], tip[1] - hilt[1]
    length = math.hypot(dx, dy)
    ux, uy = dx / length, dy / length
    px, py = -uy, ux

    def along(d, side=0.0):
        return (hilt[0] + ux * d + px * side, hilt[1] + uy * d + py * side)

    mask.capsule(hilt, along(11.0), 6.0)
    mask.capsule(along(11.0, -7.5), along(11.0, 7.5), 5.0)
    mask.capsule(along(12.0), along(length - 10.0), 8.0, round_caps=False)
    _arrow_head(mask, tip, (ux, uy), 12.0, 4.0)


# -- glyphs ---------------------------------------------------------------


def move(mask):
    """A boot, seen from the side, shaft on the left and toe to the right."""
    mask.round_rect(12.0, 5.0, 17.0, 33.0, 4.0)
    mask.polygon([(12.0, 30.0), (29.0, 28.0), (41.0, 32.0),
                  (51.0, 38.0), (57.0, 46.0), (57.0, 56.0), (12.0, 56.0)])
    # Rounds the heel and the toe in one go, so the sole reads as one block
    # rather than as a wedge with two sharp corners.
    mask.round_rect(10.0, 45.0, 48.0, 11.0, 4.0)


def stop(mask):
    """A raised open palm. The RTS convention, and it is not a road sign.

    Four separate fingers standing on a palm, rather than one block with
    notches cut out of it. A notch that reaches the top edge leaves the
    fingers between it FLAT topped, and four flat prongs in a row is a fork.
    Drawn as capsules they get their round tips for free, and the gaps come
    out at GAP because the pitch was chosen to make them.
    """
    for x, tip in ((21.0, 20.0), (31.0, 15.0), (41.0, 18.0), (51.0, 25.0)):
        mask.capsule((x, tip), (x, 42.0), STROKE)
    mask.round_rect(16.0, 33.0, 40.0, 23.0, 9.0)
    mask.capsule((24.0, 46.0), (11.0, 37.0), 10.0)


def attack(mask):
    """Crossed swords. Two of them, because one alone reads as a weapon."""
    _sword(mask, (13.0, 56.0), (51.0, 10.0))
    _sword(mask, (51.0, 56.0), (13.0, 10.0))


def sell(mask):
    """A price tag, hole and all. The one object in the set that means a sale.

    Authored flat and then tilted, which is the orientation a tag is always
    drawn at - hung from its hole, wide end up.
    """
    body = [(-27.0, 0.0), (-11.0, -15.0), (21.0, -15.0),
            (26.0, -10.0), (26.0, 10.0), (21.0, 15.0), (-11.0, 15.0)]
    body, hole = _centered([_rotate(body, -45.0, about=(0.0, 0.0)),
                            _rotate([(-15.0, 0.0)], -45.0, about=(0.0, 0.0))])
    mask.polygon(body)
    mask.erase(mask.circle, hole[0][0], hole[0][1], 5.0)


def build(mask):
    """A hammer, tilted mid swing.

    Upright it is a T, which is a gavel or a signpost or nothing at all. The
    tilt and the wedge peen on one side are together what make it a hammer.
    """
    head = [(11.0, 9.0), (45.0, 9.0), (54.0, 15.5), (45.0, 22.0), (11.0, 22.0)]
    handle = round_rect_points(23.0, 20.0, 9.5, 37.0, 4.5)
    head, handle = _centered([_rotate(head, 20.0), _rotate(handle, 20.0)])
    mask.polygon(head)
    mask.polygon(handle)


def cancel(mask):
    """An X. Shared by every Cancel there is - order, build, sale, upgrade."""
    mask.capsule((14.0, 14.0), (50.0, 50.0), 10.0)
    mask.capsule((50.0, 14.0), (14.0, 50.0), 10.0)


def build_grid(mask):
    """Nine cells. A toggle, so it spends half its life tinted gold."""
    for row in range(3):
        for col in range(3):
            mask.round_rect(6.0 + col * 19.0, 6.0 + row * 19.0, 14.0, 14.0, 3.0)


def prioritize_air(mask):
    """A double chevron, pointing up at what this tower should shoot first."""
    mask.polyline([(13.0, 31.0), (32.0, 12.0), (51.0, 31.0)], 9.0)
    mask.polyline([(13.0, 51.0), (32.0, 32.0), (51.0, 51.0)], 9.0)


def alter_armor(mask):
    """A shield with a chevron cut into it: armour, and which kind of it.

    The chevron stops short of both edges on purpose. A band that reached
    them cut the shield into a box and a triangle, and the silhouette - the
    only thing a flat white glyph has - stopped being a shield at all.
    """
    right = [(53.0, 13.0), (53.0, 26.0), (51.0, 34.0),
             (45.0, 43.0), (39.0, 51.0), (32.0, 58.0)]
    left = [(64.0 - x, y) for x, y in reversed(right)]
    mask.polygon([(11.0, 7.0), (53.0, 7.0)] + right + left)
    mask.erase(mask.polyline, [(20.0, 26.0), (32.0, 37.0), (44.0, 26.0)], 5.5)


def choose_element(mask):
    """A sparkle. Ten elements and no colour to tell them apart, so: magic."""
    def star(cx, cy, outer, inner):
        pts = []
        for i in range(8):
            a = math.radians(i * 45.0 - 90.0)
            r = outer if i % 2 == 0 else inner
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
        mask.polygon(pts)

    star(27.0, 27.0, 21.0, 6.0)
    star(49.0, 48.0, 10.0, 3.0)


## Every icon this tool writes: file stem to the function that draws it.
##
## The stem is what the .tres names, so renaming one here is a content edit
## as well as a tool edit. The four Cancels deliberately share ability_cancel:
## one X is what a player already knows, and four different crosses would only
## make them look for a difference that is not there.
##
## Return to Elemental Core is NOT here, though it looks like it belongs. It
## already draws the Core itself, which is the rule every ability that turns
## into a unit follows, and showing the thing you get back is a better answer
## than a generic undo arrow would have been.
GLYPHS = {
    "ability_move": move,
    "ability_stop": stop,
    "ability_attack": attack,
    "ability_sell": sell,
    "ability_build": build,
    "ability_cancel": cancel,
    "ability_build_grid": build_grid,
    "ability_prioritize_air": prioritize_air,
    "ability_alter_armor": alter_armor,
    "ability_choose_element": choose_element,
}


def render(name):
    """Draws one glyph and hands back its finished alpha rows."""
    mask = Mask()
    GLYPHS[name](mask)
    return mask
