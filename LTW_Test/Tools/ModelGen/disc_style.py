# The visual language of the TECHNOLOGY DISCS.
#
# Its own file rather than a fourth section of style.py, and the reason is the
# same one that keeps the three rosters apart up there: a disc cannot
# accidentally take a tower rule if it never sees one. What it DOES share is
# everything below style.py - the same stone, the same square foundation, the
# same ten element hues - and it reaches into style.ELEMENTS for those rather
# than restating them.
#
# READ style.py's header first if you are changing any of this. None of these
# rules is binding, all of them were authored by Claude rather than handed
# down, and what they buy is CONTINUITY: a disc added later should look like it
# came from the same game as the thirty-one before it. Change one when it is
# wrong, change it HERE so the whole roster moves together, and know that what
# it costs is the continuity it was buying.
#
#
# WHAT A DISC IS, VISUALLY: THREE FLAT LAYERS
#
# A disc has NO MODEL. Not a small one, none: it is a thing set into the
# ground, creeps walk straight over it, and a top down camera would see almost
# nothing of a raised shape anyway. So what a player sees is three flat layers,
# and each of them answers exactly one question.
#
#   FOUNDATION   the shared SQUARE patch every tower stands on, unchanged and
#                not generated here - tower_foundation.tscn. It says a BUILDING
#                is here and that this square is claimed
#   PLATE        a round worked disc set into that square, identical on all
#                thirty-one. It says the building is a DISC
#   GLYPH        a coloured circle in the middle. Its COLOUR says which
#                element, its SIZE says which tier
#
# ROUND ON SQUARE IS THE WHOLE TRICK, and it is what the layers are for. The
# foundation and the plate are the same stone - they have to be, because colour
# belongs to the elements - so what tells them apart is that one is a square
# patch of ground and the other is a machined circle sitting on it. That reads
# from directly overhead at any zoom, and it costs the roster nothing.
#
# It also puts a disc on the same footing as a tower where it should be: both
# claim a square and both say so with the same patch. A tower then stands up
# out of it and a disc does not, which is the one difference a player must
# never have to look twice at.
#
#
# THE THREE AXES, ANSWERED FOR SOMETHING WITH NO SILHOUETTE
#
#   WHICH KIND      it is flat, on a square foundation with a round plate. The
#                   answer arrives before colour and before size, because it is
#                   the question a maze is read for
#   WHICH ELEMENT   the glyph's COLOUR, and nothing else at all
#   WHICH TIER      the glyph's SIZE, and nothing else at all
#
# ONE SHAPE FOR ALL TEN ELEMENTS. An earlier cut gave each element the side
# count its towers are built on - a four sided Ice, a five sided Earth - so the
# roster would answer "which element" on two axes the way the towers do. It was
# dropped on review, and the reason is worth keeping: a disc is the one thing
# in the game whose whole job is to be read in peripheral vision while the
# player is looking at a creep wave, and counting sides at that size is
# something the eye will not do. Colour it reads instantly. So colour carries
# the element on its own, and the shape is a circle every time.
#
# WHAT THAT COST, and it is a real cost paid deliberately: the roster no longer
# has a second channel for a colourblind player, where the towers do. If that
# turns out to matter the answer is NOT to bring the polygons back - it is
# something the eye reads as fast as colour, like a count of pips around the
# rim.
#
# IT ALSO RETIRED THE ULTIMATE'S MOTION. style.py reserves movement for the top
# rung and the discs used to obey it by turning an Ultimate's glyph slowly - a
# rule that means nothing once the glyph is a circle, because a rotating circle
# is a still circle. It is not replaced by a pulse or anything else: the tier
# is the size, that is the single rule, and a second one laid over it would be
# fighting the first for the same pixels.

import style as ts

# Diameter of the coloured glyph at each tier, in CELLS, indexed by tier:
# inactive, element, advanced, ultimate.
#
# In cells rather than as a fraction of anything, because this number is the
# size of a MESH now rather than a radius uniform - which is what lets an
# upgrade grow the coloured part while the plate under it stays exactly where
# it was. See disc_models.py and Disc._apply_visual_height.
#
# 0 on the inactive disc is load bearing rather than tidy. A base disc has no
# element and does nothing, so it gets no glyph node at all - and it still
# reads as a disc rather than as an empty tower foundation, because the round
# plate is there under it saying so.
#
# The three that do exist are spaced to read as STEPS from directly overhead
# rather than as a smooth ramp: the eye is comparing two discs a maze apart, so
# what matters is that no two of them are ever nearly the same size.
#
# THE CEILING IS SET BY THE PLATE, not by taste. PLATE_DIAMETER is how far the
# stone reaches, and the top rung has to leave a clear ring of it showing - a
# glyph that filled its own plate would stop being a disc with a colour in it
# and become a coloured blob, which the eye cannot read a tier off at all
# because there is nothing left to read it against. glyph_headroom() checks it.
DISC_GLYPH_DIAMETER = [0.0, 0.28, 0.44, 0.60]

# How brightly a glyph gives off its own light. ONE figure for the whole
# roster: the tier is the size and the element is the colour, and letting
# brightness climb with either would be a third rule saying what two already
# say. See the header, and disc_glyph.gdshader on why it is this low.
DISC_GLYPH_EMISSION = 0.45

# How solid the glyph is. High, because it is the UNIT - the thing a player has
# to pick out of a maze - where the two stone layers under it are ground and
# sink into it.
DISC_GLYPH_OPACITY = 0.95

# Width of the lit rim around the glyph, as a share of its own radius. A share
# rather than a fixed band, so it grows with the tier instead of swallowing the
# smallest one whole.
DISC_GLYPH_RIM = 0.22

# The round mechanism plate, identical on all thirty-one discs.
#
# The SAME STONE as the tower foundation under it, near enough that neither can
# be told from the other by colour. That is deliberate: colour is spoken for by
# the elements, so the two layers are separated by SHAPE - a square patch and a
# machined circle - and by nothing else.
DISC_PLATE = {
    "plate": (0.58, 0.57, 0.54),
    "plate_dark": (0.41, 0.40, 0.38),
    "groove": (0.22, 0.21, 0.20),
    "edge": (0.28, 0.27, 0.25),
    "opacity": 0.85,
}

# Diameter of that plate, in cells, and how it is cut.
#
# Smaller than the foundation it sits on, and that is the number this whole
# design turns on: the square has to show at every corner, or the round plate
# and the square patch read as one lump and there was no point putting one on
# the other. The tower foundation covers about 1.05 cells - see
# building_foundation_material.tres - so this leaves a clear margin of stone.
PLATE_DIAMETER = 0.78

DISC_GROOVES = {
    "ring_count": 3,
    "ring_width": 0.022,
    "spoke_count": 8,
    "spoke_width": 0.045,
    "strength": 0.6,
    "edge_width": 0.07,
}


def glyph_diameter(tier):
    return DISC_GLYPH_DIAMETER[tier]


def glyph_headroom():
    """How much of the plate the biggest glyph leaves showing, in cells.

    Not read by the generator - it is here so the ceiling in the comment above
    can be CHECKED rather than trusted, and so that changing either number is
    measured against the other rather than eyeballed.
    """
    return round(PLATE_DIAMETER - DISC_GLYPH_DIAMETER[-1], 3)


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
