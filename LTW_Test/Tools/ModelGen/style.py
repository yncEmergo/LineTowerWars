# The visual language of the tower roster, as data.
#
# STYLE: "faceted arcane machinery". Every tower is a low segment-count solid -
# six and eight sided cylinders, boxes, prisms, low-ring spheres - standing on
# the shared stone foundation patch, lit by one plating shader and accented by
# one energy shader.
#
# Three questions the silhouette has to answer from a top down camera, and the
# axis each one is answered on:
#
#   WHICH LINE     colour and stance. Archer is tall and thin in steel blue,
#                  Cutter is squat and wide in rust, Sentry floats in violet.
#   WHICH BRANCH   one decisive shape at the 150g split, and it never changes
#                  again up the branch: a long barrel, a tilted mortar, a
#                  spinning blade disc, an overhead hammer, an orbiting core,
#                  a rack of tubes aimed at the sky.
#   WHICH TIER     six cumulative rules, below. This is the part a 3D artist
#                  should keep when the primitives are replaced.
#
# THE TIER LADDER - six rules, applied on the PRICE tier (10 / 30 / 150 /
# 1,000 / 5,000 / 25,000), not on the position in a branch. A Lesser Watch
# Tower is the third rung of six overall, and reads as one:
#
#   1. MASS     the whole tower scales up a little each tier
#   2. TRIM     the metal ramps iron -> pale iron -> bronze -> silver -> gold
#               -> white gold. This is the primary tier tell and it works at
#               any distance, in any light, on any shape
#   3. ENERGY   the accent brightens and its pulse quickens, driven by one
#               `tier` uniform on tower_energy.gdshader
#   4. COLLAR   from 150g up, a trim ring under the head
#   5. CROWN    from 5,000g up, fins around the shoulder
#   6. HALO     at 25,000g, a trim ring floating above the tower, turning
#
# Rules 1-3 are continuous and rules 4-6 are steps, on purpose: the continuous
# ones keep every tier distinguishable from its neighbour, and the stepped ones
# make the expensive ones distinguishable across a whole map.

# Price tiers, in order. The index into this list is what every rule above
# scales on.
PRICE_TIERS = [10, 30, 150, 1000, 5000, 25000]

# Rule 2. Iron to white gold.
TRIM_RAMP = [
    (0.37, 0.40, 0.44),
    (0.52, 0.55, 0.59),
    (0.66, 0.45, 0.18),
    (0.76, 0.80, 0.86),
    (0.90, 0.74, 0.33),
    (1.00, 0.94, 0.72),
]

# Line identity.
#
# One entry per LINE today. An ELEMENT gets an entry here too when elemental
# towers arrive - same roles, same tier ladder - and that is most of what
# adding one costs. A CREEP roster wants its palette here as well rather than
# in a file of its own, so the two are chosen against each other: a creep that
# happens to land on the same green as a tower line is a decision somebody
# should have to make on purpose.
#
# THE BASIC ROSTER IS DELIBERATELY COLOURLESS: stone grey through to light
# timber brown, with metal trim and a small warm accent. It has to be, because
# the ten ELEMENTS arriving later each own a hue - fire, ice, void, holy - and
# they can only read as elements if the towers a player has been looking at
# since the first minute of the match are not competing for the same signal.
#
# So a Basic line is told apart by SHAPE and by MATERIAL, never by colour:
#   Archer   pale quarried stone, steel fittings   - square, tall and thin
#   Cutter   dark timber and iron                  - round, squat and wide
#   Sentry   pale sandstone, bone-coloured         - open frames, floating
#
# THREE TONES PER LINE, not one. A tower built out of a single material reads
# as one lump from a top down camera however good its silhouette is - the
# facets have nothing to catch against each other. So every line carries a
# base, a DEEP tone for the parts that sit low or carry weight, and a PALE one
# for the parts that stick out or catch the light. They are the same material
# at three depths rather than three materials, which is what keeps a tower
# looking like one object while still having parts.
#
# Each tone is (plate, dark): the body colour, and the shade the plating shader
# streaks it with and drops its undersides towards.
LINES = {
    "archer": {
        "tones": {
            "base": ((0.58, 0.59, 0.57), (0.34, 0.35, 0.34)),
            "deep": ((0.43, 0.45, 0.48), (0.25, 0.27, 0.30)),
            "pale": ((0.71, 0.70, 0.65), (0.46, 0.45, 0.41)),
        },
        "glow": (0.92, 0.96, 1.00),
        "dim": (0.30, 0.33, 0.36),
        "rim": (1.00, 1.00, 0.98),
    },
    "cutter": {
        "tones": {
            "base": ((0.56, 0.49, 0.40), (0.33, 0.29, 0.23)),
            "deep": ((0.37, 0.33, 0.30), (0.21, 0.19, 0.17)),
            "pale": ((0.67, 0.58, 0.44), (0.43, 0.37, 0.28)),
        },
        "glow": (1.00, 0.80, 0.48),
        "dim": (0.34, 0.24, 0.14),
        "rim": (1.00, 0.94, 0.84),
    },
    "sentry": {
        "tones": {
            "base": ((0.64, 0.61, 0.54), (0.39, 0.37, 0.32)),
            "deep": ((0.47, 0.46, 0.44), (0.28, 0.27, 0.26)),
            "pale": ((0.75, 0.72, 0.63), (0.49, 0.47, 0.41)),
        },
        "glow": (1.00, 0.94, 0.74),
        "dim": (0.36, 0.33, 0.25),
        "rim": (1.00, 0.99, 0.92),
    },
}

# The tone names, in the order the materials are written.
TONES = ("base", "deep", "pale")


# Rule 1a. Multiplies every authored WIDTH and DEPTH.
#
# A tower has to leave visible ground between itself and its neighbour or a
# maze reads as one continuous wall, so even the biggest stays well inside its
# own cell.
def mass(ti):
    return round(0.82 * pow(1.0756, ti), 4)


# Rule 1b. Multiplies every authored HEIGHT, and is deliberately a SEPARATE
# ramp from the width.
#
# The camera looks down. Height is the axis it sees least of and the axis that
# most easily hides the tower behind it, so a top down tower wants to be a
# footprint with something on it rather than a tall object. The first pass got
# this wrong in both directions at once - the towers were too tall AND their
# tiers were too close together - so this ramp is both lower and steeper than
# the width one: the tallest is about half what it was, and an Ultimate is now
# a little over 1.7x its Lesser rather than 1.4x.
def height_scale(ti):
    return round(0.42 * pow(1.1144, ti), 4)


# Rule 3. What goes into the energy material's `tier` uniform.
def energy_tier(ti):
    return round(ti / (len(PRICE_TIERS) - 1.0), 3)


# Rules 4-7, the STEPPED half of the ladder.
#
# Every rung adds a piece the rung below it does not have, so a tier is
# readable by counting details and not only by reading a colour:
#
#   10g      bare. No metal on it at all
#   30g      + the base trim ring, which is its first metal
#   150g     + a collar under the head
#   1,000g   + bolts around the shoulder
#   5,000g   + crown fins
#   25,000g  + a turning halo
#
# The 10g rung having NO trim ring is what makes the first upgrade a player
# ever buys the most visible one in the game, which is worth more than the
# consistency of every tower carrying the same ring.
def has_base_trim(ti):
    return ti >= 1


def has_collar(ti):
    return ti >= 2


def has_bolts(ti):
    return ti >= 3


def has_crown(ti):
    return ti >= 4


def has_halo(ti):
    return ti >= 5


# How many repeated features a branch shows at each price tier: blades on a
# Carver, shards around a Defender, tubes on a Turret, buttresses on a Cannon.
# The 10g and 30g stubs never reach these branches, so the first two entries
# only matter to the lines that do use them.
#
# It is a LIST rather than a formula so the curve can be shaped by hand: going
# 5 -> 6 has to feel like a step up where 2 -> 3 already did, and evenly spaced
# counts do not deliver that.
FEATURE_COUNT = [2, 2, 3, 4, 5, 6]


# ============================================================================
# ELEMENTS
# ============================================================================
#
# The ten elements, and the second tier ladder they climb. Everything above
# this line is the Basic roster and is untouched by any of it.
#
# WHAT AN ELEMENTAL TOWER SPENDS THAT A BASIC ONE CANNOT: colour. The Basic
# roster is stone grey through timber brown precisely so that these ten hues
# read as elements the moment one appears in a maze, and that is the whole
# reason the constraint above exists. See game_rules.md under Presentation.
#
# The three axes are the same three, answered differently:
#
#   WHICH ELEMENT   colour first, and a base shape and side count second. An
#                   element is recognised across a map by its hue; the shape is
#                   what tells two elements of similar hue apart up close, and
#                   what carries the whole signal for a colourblind player
#   WHICH PATH      one decisive silhouette at the 4,000g split, which never
#                   changes again up that path. Exactly the Basic roster's rule
#                   at its own 150g split
#   WHICH TIER      the same cumulative rules, on the elemental ladder below
#
# THE 200g AND 800g TOWERS ARE ONE SHAPE AT TWO SIZES, on purpose and unlike
# the Basic roster's 10g/30g pair. Those two are barely the same object because
# that upgrade is the first one a player ever buys and wants shouting about; an
# element's base pair is bought seconds apart by somebody who already knows
# what they are doing, and what it should read as is a direct upgrade - which
# is also what the source game's own art does.

# The elemental price ladder. A different set of rungs from PRICE_TIERS, and
# deliberately not merged with it: a 4,000g elemental tower is the third rung
# of five here and has no equivalent among the Basic six.
ELEMENT_PRICE_TIERS = [200, 800, 4000, 10000, 30000]


# Which rung of TRIM_RAMP an elemental tier takes.
#
# Offset by one, so the cheapest elemental tower starts on pale iron rather
# than on the bare-iron rung the 10g Basic towers own. An elemental tower
# ALWAYS has metal on it: it is bought with a technology, and nothing bought
# that way should read as the cheapest thing on the field.
def element_trim_index(ti):
    return min(ti + 1, len(TRIM_RAMP) - 1)


# Rule 1a for elements. Sits deliberately just above the Basic ramp at every
# comparable price: a 200g elemental base tower is a touch wider than a 150g
# Basic one, and an Ultimate of either is within a whisker of the other.
def element_mass(ti):
    return round(0.95 * pow(1.06, ti), 4)


# Rule 1b for elements, on the same reasoning as height_scale: the camera looks
# down, so height is the axis worth spending least on.
def element_height_scale(ti):
    return round(0.52 * pow(1.088, ti), 4)


# Rule 3 for elements: what goes into the energy material's `tier` uniform.
# Starts at 0.2 rather than at 0, for the same reason the trim does.
def element_energy_tier(ti):
    return round((ti + 1) / float(len(ELEMENT_PRICE_TIERS)), 3)


# Rules 4-6 on the elemental ladder. Every rung adds a piece the one below does
# not have, exactly as on the Basic ladder, shifted onto five rungs:
#
#   200g      the base trim ring. An elemental tower is never bare
#   800g      + a collar under the head
#   4,000g    + bolts around the shoulder, and the PATH silhouette arrives
#   10,000g   + crown fins
#   30,000g   + a turning halo
def element_has_collar(ti):
    return ti >= 1


def element_has_bolts(ti):
    return ti >= 2


def element_has_crown(ti):
    return ti >= 3


def element_has_halo(ti):
    return ti >= 4


# How many repeated features a path shows at each of its three tiers: crystal
# spikes, orbiting shards, flame plumes, spore gills.
#
# Only the last three entries are ever read, since a path starts at 4,000g. The
# first two exist so an index into it is the tier index rather than the tier
# index minus two, which is the kind of arithmetic that goes wrong once.
ELEMENT_FEATURE_COUNT = [3, 3, 3, 4, 6]

# THE TEN ELEMENTS.
#
# Each is the same shape as a LINE above: three tones of one material, plus the
# lit accent. What is different is that the tones are ALLOWED to carry the
# element's hue, and the glow is that hue at its most saturated.
#
# Chosen against each other rather than one at a time, which is the whole
# reason they sit in one table. The pairs that had to be pulled apart:
#
#   ARCANE / VOID   both purple in the source game. Arcane is a COOL blue
#                   violet on pale worked stone; Void is a warm magenta purple
#                   on near-black organic hide. Different hue, different
#                   lightness, different material
#   ICE / LIGHTNING both blue-white. Ice is pale, cold and bright - nearly all
#                   of it is the light colour. Lightning is dark gunmetal with
#                   the light only in its accent, so the two are opposite in
#                   VALUE before they are ever compared in hue
#   FIRE / PRIMAL   both hot. Fire is orange on black basalt; Primal is a
#                   deeper blood red on bone and hide, and its accent is the
#                   only warm thing on it
#   HOLY / EARTH /  three WARM accents, so they are separated by the VALUE of
#   FIRE            their stone instead: Fire is near-black basalt, Earth is
#                   mid brown, Holy is bright ivory. That also fixed the first
#                   real failure of this palette - a mid-beige Holy tower was
#                   almost exactly the value of the bronze and silver trim
#                   rungs, so an Ultimate Titan Vault read as one lump of metal
#                   with no element in it at all
#
# `sides` is the base shape's side count, which is part of the element's
# identity in the same way a Basic line's is. `facets` scales the plating
# shader's panel lines: the worked-stone elements keep them and the organic
# ones - Void, Unholy, Water, Primal - turn them most of the way down, which is
# what stops a creature reading as machinery.
ELEMENTS = {
    "fire": {
        "sides": 6,
        "facets": 1.0,
        "tones": {
            "base": ((0.29, 0.20, 0.18), (0.15, 0.10, 0.09)),
            "deep": ((0.17, 0.13, 0.13), (0.08, 0.06, 0.06)),
            "pale": ((0.52, 0.30, 0.19), (0.30, 0.16, 0.10)),
        },
        "glow": (1.00, 0.52, 0.14),
        "dim": (0.42, 0.13, 0.04),
        "rim": (1.00, 0.78, 0.46),
    },
    "ice": {
        "sides": 4,
        "facets": 1.1,
        "tones": {
            "base": ((0.55, 0.72, 0.82), (0.31, 0.44, 0.54)),
            "deep": ((0.33, 0.47, 0.60), (0.18, 0.28, 0.38)),
            "pale": ((0.79, 0.90, 0.96), (0.52, 0.66, 0.76)),
        },
        "glow": (0.58, 0.92, 1.00),
        "dim": (0.14, 0.34, 0.48),
        "rim": (0.92, 1.00, 1.00),
    },
    "lightning": {
        "sides": 8,
        "facets": 1.0,
        "tones": {
            "base": ((0.28, 0.31, 0.42), (0.14, 0.16, 0.23)),
            "deep": ((0.16, 0.18, 0.26), (0.08, 0.09, 0.14)),
            "pale": ((0.50, 0.54, 0.70), (0.28, 0.31, 0.43)),
        },
        "glow": (0.74, 0.80, 1.00),
        "dim": (0.20, 0.22, 0.42),
        "rim": (0.96, 0.98, 1.00),
    },
    "holy": {
        "sides": 8,
        "facets": 0.9,
        "tones": {
            "base": ((0.86, 0.80, 0.60), (0.56, 0.51, 0.36)),
            "deep": ((0.60, 0.54, 0.38), (0.36, 0.32, 0.22)),
            "pale": ((0.98, 0.94, 0.78), (0.72, 0.68, 0.55)),
        },
        "glow": (1.00, 0.86, 0.38),
        "dim": (0.46, 0.34, 0.10),
        "rim": (1.00, 1.00, 0.92),
    },
    "void": {
        "sides": 6,
        "facets": 0.25,
        "tones": {
            "base": ((0.31, 0.16, 0.36), (0.16, 0.07, 0.19)),
            "deep": ((0.15, 0.07, 0.18), (0.07, 0.03, 0.09)),
            "pale": ((0.51, 0.27, 0.54), (0.30, 0.14, 0.32)),
        },
        "glow": (0.94, 0.36, 1.00),
        "dim": (0.28, 0.06, 0.34),
        "rim": (0.86, 0.62, 1.00),
    },
    "unholy": {
        "sides": 6,
        "facets": 0.3,
        "tones": {
            "base": ((0.34, 0.42, 0.24), (0.18, 0.24, 0.12)),
            "deep": ((0.20, 0.25, 0.15), (0.10, 0.13, 0.07)),
            "pale": ((0.57, 0.63, 0.40), (0.34, 0.39, 0.22)),
        },
        "glow": (0.62, 1.00, 0.28),
        "dim": (0.16, 0.34, 0.08),
        "rim": (0.84, 1.00, 0.68),
    },
    "water": {
        "sides": 8,
        "facets": 0.35,
        "tones": {
            "base": ((0.20, 0.42, 0.53), (0.10, 0.24, 0.32)),
            "deep": ((0.11, 0.25, 0.36), (0.05, 0.13, 0.20)),
            "pale": ((0.38, 0.63, 0.72), (0.20, 0.38, 0.46)),
        },
        "glow": (0.36, 0.86, 0.94),
        "dim": (0.06, 0.26, 0.38),
        "rim": (0.78, 0.98, 1.00),
    },
    "earth": {
        "sides": 5,
        "facets": 0.8,
        "tones": {
            "base": ((0.40, 0.32, 0.22), (0.21, 0.17, 0.12)),
            "deep": ((0.24, 0.20, 0.15), (0.12, 0.10, 0.08)),
            "pale": ((0.56, 0.48, 0.33), (0.33, 0.28, 0.19)),
        },
        "glow": (0.96, 0.70, 0.24),
        "dim": (0.30, 0.19, 0.05),
        "rim": (0.94, 0.88, 0.72),
    },
    "arcane": {
        "sides": 4,
        "facets": 1.1,
        "tones": {
            "base": ((0.40, 0.38, 0.60), (0.22, 0.21, 0.36)),
            "deep": ((0.24, 0.22, 0.40), (0.12, 0.11, 0.23)),
            "pale": ((0.60, 0.58, 0.78), (0.37, 0.36, 0.52)),
        },
        "glow": (0.66, 0.52, 1.00),
        "dim": (0.20, 0.14, 0.44),
        "rim": (0.90, 0.86, 1.00),
    },
    "primal": {
        "sides": 6,
        "facets": 0.45,
        "tones": {
            "base": ((0.54, 0.22, 0.19), (0.30, 0.11, 0.09)),
            "deep": ((0.31, 0.13, 0.12), (0.16, 0.06, 0.06)),
            "pale": ((0.78, 0.70, 0.57), (0.50, 0.44, 0.35)),
        },
        "glow": (1.00, 0.30, 0.24),
        "dim": (0.36, 0.06, 0.05),
        "rim": (1.00, 0.84, 0.74),
    },
}

# The generic 200g tower every element's base tower is morphed from.
#
# Deliberately the ONLY thing in the game with no colour of its own at all -
# it is the absence of an element, so it is bare stone with one red rune on it
# waiting to be told what it is. That is also what the source game's own art
# does with it, and it is why it is here rather than in ELEMENTS: it is not an
# element and must not be able to be iterated as one.
ELEMENTAL_CORE = {
    "sides": 8,
    "facets": 1.0,
    "tones": {
        "base": ((0.50, 0.49, 0.47), (0.29, 0.28, 0.27)),
        "deep": ((0.34, 0.33, 0.32), (0.19, 0.19, 0.18)),
        "pale": ((0.64, 0.62, 0.58), (0.41, 0.40, 0.37)),
    },
    "glow": (1.00, 0.22, 0.18),
    "dim": (0.34, 0.05, 0.04),
    "rim": (1.00, 0.90, 0.86),
}
