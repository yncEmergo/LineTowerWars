# The visual language of the TECHNOLOGY DISCS.
#
# Its own file rather than a fourth section of style.py, and the reason is the
# same one that keeps the three rosters apart up there: a disc cannot
# accidentally take a tower rule if it never sees one. What it DOES share is
# everything below style.py - the same stone, the same ten element hues - and
# it reaches into style.ELEMENTS for those rather than restating them.
#
# READ style.py's header first if you are changing any of this. None of these
# rules is binding, all of them were authored by Claude rather than handed
# down, and what they buy is CONTINUITY: a disc added later should look like it
# came from the same game as the thirty-one before it. Change one when it is
# wrong, change it HERE so the whole roster moves together, and know that what
# it costs is the continuity it was buying.
#
#
# WHAT A DISC IS, VISUALLY
#
# A disc has NO MODEL. Not a small one, none: it is a thing set into the
# ground, creeps walk straight over it, and a top down camera would see almost
# nothing of a raised shape anyway. So the floor patch is the whole unit, and
# one shader draws it - Resources/Shaders/disc_ground.gdshader.
#
# That is a real departure from both tower rosters and it is the point. A maze
# is read at a glance, and the one thing a player must never have to look twice
# at is which squares are WALLS and which are not. A tower stands up; a disc
# lies flat. Nothing else in the game does either.
#
#
# THE THREE AXES, ANSWERED FOR SOMETHING WITH NO SILHOUETTE
#
#   WHICH KIND      it is flat. That is the whole answer and it is answered
#                   before colour, before shape and before size, because it is
#                   the question a maze is read for
#   WHICH ELEMENT   the glyph's COLOUR first and its SIDE COUNT second - the
#                   same two answers the elemental towers give, and the same
#                   side counts, so an eight sided Holy disc sits next to an
#                   eight sided Holy tower. Colour is what carries it across a
#                   map; the count is what carries it for a player who cannot
#                   tell two hues apart
#   WHICH TIER      the glyph's RADIUS, and nothing else. A base disc has no
#                   glyph at all, which is exactly right: it has no element and
#                   does nothing. Each upgrade grows the coloured part
#
# THE TIER LADDER IS ONE RULE where the tower ladders are six, and that is
# deliberate rather than lazy. A disc has one flat circle to say everything
# with - no mass, no height, no shape change, no metal - so a second rule laid
# over the first would have to fight it for the same pixels. What the one rule
# buys is that three tiers of the same element read as three sizes of one
# thing, which is what an upgrade should look like.
#
# The ULTIMATE gets the one exception, and it is the exception the tower roster
# already makes: MOTION is reserved for the top rung. An Ultimate disc turns,
# slowly, and nothing else in the roster moves at all.

import style as ts

# Radius of the coloured glyph at each tier, as a fraction of the quad's own
# half size, indexed by tier: inactive, element, advanced, ultimate.
#
# 0 on the inactive disc is load bearing rather than tidy. A base disc has no
# element and does nothing, and drawing it a grey glyph would be drawing a
# picture of a thing that is not there.
#
# The three that do exist are spaced to read as STEPS from directly overhead
# rather than as a smooth ramp: the eye is comparing two discs a maze apart, so
# what matters is that no two of them are ever nearly the same size.
#
# THE CEILING IS SET BY THE PLATE, not by taste. DISC_GROOVES["radius"] is how
# far the stone reaches, and the top rung has to leave a clear ring of it
# showing - a glyph that fills its own plate stops being a disc with a colour
# in it and becomes a coloured blob, which is a thing the eye cannot read a
# tier off at all because there is nothing left to read it against.
DISC_GLYPH_RADIUS = [0.0, 0.22, 0.34, 0.46]

# Turns per second. Only the Ultimate moves, see the header.
DISC_SPIN = [0.0, 0.0, 0.0, 0.05]

# How brightly the glyph gives off its own light, per tier. It climbs with the
# radius, so an Ultimate is not only bigger but hotter - which is what carries
# the tier at the distance the colour has already stopped being readable at.
#
# LOW, and that is measured rather than chosen. Emission ADDS to albedo, so a
# figure near 1 pushes a saturated hue past white in its strongest channel and
# the glyph comes out a pale yellow blob whatever element it belongs to - which
# is exactly what the first cut of this roster did, and it cost the ten hues
# the whole reason they were chosen against each other. Anything above about
# 0.6 here stops reading as an element and starts reading as a light.
DISC_EMISSION = [0.0, 0.25, 0.40, 0.60]

# How solid each half of the disc is.
#
# The plate is GROUND and sinks into it, the glyph is the UNIT and has to be
# picked out of a maze - so they are two figures rather than one. Both are
# lower than they look on paper: the ground quad underneath is opaque green,
# and stone at 0.55 over it reads as a solid plate.
DISC_PLATE_OPACITY = 0.55
DISC_GLYPH_OPACITY = 0.85

# Width of the lit rim around the glyph, as a share of the glyph's own radius.
#
# A share rather than a fixed band, so it grows with the tier instead of
# swallowing the small one whole. Wide enough to be a rim rather than an
# outline, because with the emission down this is what separates the glyph from
# the stone at a glance.
DISC_GLYPH_EDGE_WIDTH = 0.20

# The stone plate, identical on all thirty-one discs.
#
# Slightly PALER and slightly less weathered than the tower foundation's, which
# is the only concession made to telling the two apart by colour. The real work
# is done by the pattern - a true circle cut with rings and spokes, against the
# tower patch's rounded square of cracked slabs - because colour is what the
# elements have been given and the ground must not take any of it back.
DISC_PLATE = {
    "plate": (0.62, 0.60, 0.56),
    "plate_dark": (0.44, 0.42, 0.39),
    "groove": (0.25, 0.24, 0.22),
    "rim": (0.30, 0.28, 0.25),
}

# How the plate is cut. One set of numbers for the whole roster: the plate says
# "disc" and nothing else, so nothing about it is allowed to vary with tier or
# element - that would be a second thing competing with the glyph to say the
# same two things it already says.
DISC_GROOVES = {
    "radius": 0.68,
    "ring_count": 3,
    "ring_width": 0.028,
    "spoke_count": 8,
    "spoke_width": 0.05,
    "strength": 0.55,
}


def glyph_radius(tier):
    return DISC_GLYPH_RADIUS[tier]


def glyph_spin(tier):
    return DISC_SPIN[tier]


def glyph_emission(tier):
    return DISC_EMISSION[tier]


def glyph_headroom():
    """How much of the plate's radius the biggest glyph leaves showing.

    Not read by the generator - it is here so the ceiling above can be checked
    rather than trusted, and so a change to either number is measured against
    the other rather than eyeballed.
    """
    return round(DISC_GROOVES["radius"] - DISC_GLYPH_RADIUS[-1], 3)


def glyph_colors(element):
    """The element's own lit colour and the brighter tone its edge lights up
    in, straight off style.ELEMENTS.

    Reached rather than restated, which is the whole reason this file imports
    style at all: a Fire disc and a Fire tower must never be able to disagree
    about what Fire looks like, and the only way to guarantee that is for there
    to be one table.
    """
    palette = ts.ELEMENTS[element]
    return palette["glow"], palette["rim"]


def glyph_sides(element):
    """The element's side count, the same one its towers are built on.

    style.py gives Void, Unholy and Primal six sides and turns their PLATING
    most of the way down instead, because a creature must not read as
    machinery. A disc is machinery, so it keeps the count and nothing else -
    there is no organic disc and there should not be one.
    """
    return ts.ELEMENTS[element]["sides"]
