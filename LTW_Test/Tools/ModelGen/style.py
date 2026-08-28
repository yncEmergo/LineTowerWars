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

import math

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


# ============================================================================
# CREEPS
# ============================================================================
#
# The third roster, and the first one that is ALIVE. Everything above this line
# is built; everything below it walks.
#
# The three axes again, answered for a thing that is coming AT the player
# rather than standing on their grid:
#
#   WHICH FAMILY  what the creep DOES to the maze, which is the only question a
#                 player has to answer in the second before it arrives: does it
#                 walk, does it fly, does it attack back. NOT the tier - a tier
#                 is a cost bracket and carries no mechanical meaning, so
#                 making it the loudest signal would teach a player something
#                 untrue. See game_rules.md
#   WHICH KIND    the individual creep, told by its body plan and its hide
#                 colour. This is where the silhouette work goes
#   HOW STRONG    a stepped ladder on the creep's own gold cost, below. Worth
#                 more here than on towers, because a creep cannot be upgraded
#                 and a player has no other way to learn the ordering
#
# THE FAMILY RULES, and each is a hard one rather than a tendency:
#
#   GROUND    stands on legs, on the floor, opaque
#   AIR       has NO legs at all, hangs at cruising height, is translucent, and
#             is the only thing in the game drawn over a shadow disc pinned to
#             the ground beneath it. From a top down camera height barely
#             reads, so the disc - not the altitude - is what says "flying"
#   ATTACKER  the only creep whose WEAPON is lit. Every other hard part in the
#             roster - bone, claw, iron, a Swordsman's sword - is unlit, so the
#             one thing on the field with a hot edge is the one thing coming
#             for your towers
#
# The Swordsman is why the attacker rule is about the LIT edge and not about
# carrying a weapon: half the roster carries one and only two of them ever
# swing it at a building.
#
# COLOUR, which is the constraint this roster inherits. The ten elements own
# the saturated hues and the Basic towers gave up colour entirely so they can
# read. A creep needs its own hue anyway - a Sheep and a Skeleton have to be
# told apart at a glance - so the separation is on a SECOND axis instead, and
# there are three of them at once:
#
#   VALUE       creep hides are muted. Nothing here is as saturated as an
#               element's stone, so a Fel Orc's red is never a Primal tower's
#   LIGHT       an elemental tower glows over its whole body. A creep's ONLY
#               lit parts are its eyes and, on an attacker, its weapon edge
#   MATERIAL    a creep is drawn with creep_hide.gdshader, which bands across
#               the body like ribs and hide rather than stacking panel seams
#               like plating, and it has no ground patch under it
#
# So a mud brown Golem next to an Earth tower is a deliberate outcome and not a
# collision: mud IS earth coloured, and everything else about the two says
# which is which.
#
# OWNERSHIP is deliberately NOT carried by any of this. A creep belongs to its
# sender, the minimap already colours it by owner, and tinting a creep's hide
# would cost the roster the one axis that tells a Sheep from a Skeleton. If an
# in-world owner tell is ever wanted it has to be a SEPARATE device - a ring on
# the ground, a banner - and not the hide.

# Rule 2, and the creep equivalent of TRIM_RAMP: what every hard part is made
# of - claws, horns, shoulder plates, weapons, the spines down a back.
#
# Bone through blackened steel, so it gets DARKER and harder as it climbs where
# the tower ramp gets brighter. That is on purpose and it is what stops a
# creep's carapace being read as a tower's tier metal: the two ladders run in
# opposite directions and can never be confused halfway up.
#
# (albedo, metallic, roughness). Chalky bone has no metal in it at all; the top
# rung is polished and nearly black.
# METALLIC IS KEPT LOW ON PURPOSE, and that cost a rebake to learn. Under
# gl_compatibility a metallic surface takes nearly all its colour from
# reflections, and this project has no reflection probes and no sky - so a
# metallic 0.9 carapace renders BLACK whatever its albedo says. Tower trim gets
# away with it because the top two rungs emit; a creep's hard parts must not,
# since the eyes are the only thing in the roster allowed to be lit.
CREEP_CARAPACE_RAMP = [
    ((0.72, 0.69, 0.58), 0.00, 0.88),
    ((0.86, 0.83, 0.72), 0.05, 0.78),
    ((0.62, 0.63, 0.66), 0.28, 0.60),
    ((0.52, 0.52, 0.56), 0.38, 0.48),
    ((0.44, 0.44, 0.48), 0.46, 0.38),
    ((0.38, 0.36, 0.39), 0.52, 0.32),
]

# The creep ladder's rungs, in gold. One rung per half decade of cost, which is
# what keeps the whole roster on one ladder: tier 1 spans 10g to 1,000g and
# lands on rungs 0 to 4, and everything above it goes on climbing rather than
# starting again. A tier is a cost bracket, so a ladder measured in cost is the
# same ladder in every bracket.
CREEP_RUNG_DECADES = 0.5
CREEP_CHEAPEST = 10.0


def creep_rung(gold):
    """Which rung of the ladder a creep of this price stands on."""
    if gold <= CREEP_CHEAPEST:
        return 0
    steps = math.log10(gold / CREEP_CHEAPEST) / CREEP_RUNG_DECADES
    # The epsilon is not decoration: log10(100) comes back a hair under 2.0 on
    # some builds, which would put a 1,000g Boss one rung below itself.
    return min(int(steps + 1e-9), len(CREEP_CARAPACE_RAMP) - 1)


# Rule 3. THE EYES, and they are one colour for the whole roster on purpose.
#
# A player learns "brighter eyes, tougher creep" exactly once and it holds for
# every creep in the game, which is worth far more than a per-creep eye hue
# would be at the size an eye is actually drawn.
#
# Amber, because it is the one warm hue no tower carries as a small lit point -
# Fire's orange arrives on a whole black basalt tower and never as two dots -
# and because eyeshine is amber in every animal a player has ever seen.
#
# It brightens rather than saturating: the top rung is still clearly amber and
# not white, which is the failure the elemental accents were retuned to avoid.
CREEP_EYE_RAMP = [
    (0.78, 0.38, 0.10),
    (0.86, 0.45, 0.13),
    (0.93, 0.52, 0.16),
    (0.97, 0.59, 0.20),
    (1.00, 0.66, 0.25),
    (1.00, 0.74, 0.34),
]


# Rule 1a. Multiplies every authored WIDTH and DEPTH.
#
# Gentler than the tower ramp, because a creep's FOOTPRINT is a gameplay number
# it must not outgrow - the rules give a creep one free internal cell to walk
# through - so what a heavier creep really gains is bulk in its own model
# rather than reach across the floor. See CreepStats.body_radius.
def creep_mass(rung):
    return round(0.66 * pow(1.10, rung), 4)


# Rule 1b. Multiplies every authored HEIGHT, on the same reasoning as the tower
# ramp: the camera looks down, so height is the axis worth spending least on.
def creep_height_scale(rung):
    return round(0.40 * pow(1.115, rung), 4)


# A BOSS is sent one at a time and steals two lives, so it has to read as the
# biggest thing in its bracket before a player has time to read anything else.
# It takes its own rung's ramps and then these on top, and it is forced onto
# the crest whatever it costs - see creep_has_crest.
BOSS_MASS = 1.22
BOSS_HEIGHT = 1.18


# Rules 4-6, the STEPPED half of the ladder. Every rung adds a hard part the
# rung below does not have, so danger can be read by counting details and not
# only by reading a size:
#
#   10g       bare hide. Eyes and nothing else
#   32g       (nothing new - the continuous ramps carry this rung)
#   100g      + plates over the shoulders or flanks
#   316g      + a row of spines down the back
#   1,000g    + a crest of horns, and every Boss regardless of price
#
# WHERE a rung's feature goes is the body plan's business, not this file's: a
# robed Priest wears its spines as a raised mantle and a Golem wears them as
# slabs of rock. What the ladder fixes is that the feature is THERE.
def creep_has_plates(rung):
    return rung >= 2


def creep_has_spines(rung):
    return rung >= 3


def creep_has_crest(rung, is_boss=False):
    return is_boss or rung >= 4


# THE THIRTEEN HIDES.
#
# Same shape as a LINE or an ELEMENT above - three depths of one material plus
# the rim - and chosen against each other first, because what a player has to
# do in a maze is tell one creep from another. Each is (plate, dark).
#
# `glow` and `dim` are absent on purpose: a creep's lit accent is the roster's
# one amber, from CREEP_EYE_RAMP, and letting a hide name its own would hand
# back the axis the eye ladder is spending.
#
# `bands` scales the hide shader's banding the way `facets` scales an element's
# panel seams: high on anything scaled, plated or bony, near zero on wool,
# cloth and vapour.
CREEPS = {
    # Dirty wool. The cheapest thing in the game and it should look it: no
    # colour, no hard parts, and the only creep in the roster with a bounty of
    # nothing.
    "sheep": {
        "bands": 0.15,
        "tones": {
            "base": ((0.87, 0.86, 0.81), (0.62, 0.61, 0.57)),
            "deep": ((0.63, 0.61, 0.56), (0.42, 0.41, 0.37)),
            "pale": ((0.96, 0.95, 0.91), (0.74, 0.73, 0.69)),
        },
        "rim": (1.00, 0.99, 0.94),
    },
    # Grey brown fur, and deliberately the darker half of the Sheep's own pack:
    # the two arrive together and the wolf is the one that matters.
    "timber_wolf": {
        "bands": 0.30,
        "tones": {
            "base": ((0.46, 0.42, 0.37), (0.27, 0.25, 0.21)),
            "deep": ((0.29, 0.27, 0.23), (0.16, 0.15, 0.13)),
            "pale": ((0.64, 0.59, 0.52), (0.40, 0.37, 0.32)),
        },
        "rim": (0.96, 0.92, 0.84),
    },
    # Bone, which is also rung 0 of the carapace ramp - so a Skeleton is the
    # one creep whose hard parts and whose body are the same colour, and it
    # reads as being made entirely of the cheapest material there is.
    "skeleton_warrior": {
        "bands": 1.00,
        "tones": {
            "base": ((0.79, 0.77, 0.67), (0.52, 0.50, 0.42)),
            "deep": ((0.56, 0.54, 0.45), (0.35, 0.34, 0.28)),
            "pale": ((0.91, 0.89, 0.80), (0.66, 0.64, 0.56)),
        },
        "rim": (1.00, 0.98, 0.90),
    },
    # Charcoal cloth. Nearly the darkest hide in the roster, so the hood reads
    # as a hole rather than as a head.
    "acolyte": {
        "bands": 0.20,
        "tones": {
            "base": ((0.31, 0.32, 0.38), (0.17, 0.18, 0.23)),
            "deep": ((0.19, 0.20, 0.25), (0.10, 0.11, 0.14)),
            "pale": ((0.48, 0.49, 0.56), (0.29, 0.30, 0.36)),
        },
        "rim": (0.78, 0.82, 0.94),
    },
    # Olive black chitin. Kept dark and green so the one creep towers ignore
    # until last is also the one that disappears into a maze.
    "forest_spider": {
        "bands": 0.85,
        "tones": {
            "base": ((0.27, 0.30, 0.21), (0.14, 0.16, 0.11)),
            "deep": ((0.16, 0.18, 0.12), (0.08, 0.09, 0.06)),
            "pale": ((0.43, 0.46, 0.32), (0.25, 0.27, 0.18)),
        },
        "rim": (0.82, 0.90, 0.68),
    },
    # Steel and leather, and the only cold grey in the roster. It is the
    # Skeleton's opposite number - same plan, same weapon, a real soldier.
    "swordsman": {
        "bands": 0.65,
        "tones": {
            "base": ((0.51, 0.54, 0.58), (0.31, 0.33, 0.37)),
            "deep": ((0.33, 0.35, 0.39), (0.19, 0.20, 0.23)),
            "pale": ((0.70, 0.73, 0.77), (0.46, 0.48, 0.52)),
        },
        "rim": (0.92, 0.96, 1.00),
    },
    # Red brown hide. Fel orcs are red skinned in the source game, which is
    # lucky: green would have landed on Unholy and there was nowhere else for
    # a brute to go.
    "fel_orc_grunt": {
        "bands": 0.45,
        "tones": {
            "base": ((0.52, 0.33, 0.27), (0.31, 0.18, 0.15)),
            "deep": ((0.33, 0.20, 0.17), (0.18, 0.11, 0.09)),
            "pale": ((0.67, 0.46, 0.38), (0.44, 0.28, 0.23)),
        },
        "rim": (1.00, 0.86, 0.76),
    },
    # Pale lilac. Separated from Void's magenta by VALUE rather than by hue,
    # exactly the way Ice and Lightning are separated from each other: Void is
    # near black and this is the palest coloured thing on the field.
    "vile_temptress": {
        "bands": 0.25,
        "tones": {
            "base": ((0.63, 0.45, 0.58), (0.41, 0.27, 0.37)),
            "deep": ((0.42, 0.28, 0.39), (0.25, 0.16, 0.23)),
            "pale": ((0.79, 0.62, 0.72), (0.55, 0.41, 0.50)),
        },
        "rim": (1.00, 0.90, 0.98),
    },
    # Vapour. Nearly colourless on purpose - it is the one creep that is drawn
    # translucent, and a hue underneath that would only muddy it.
    "shade": {
        "bands": 0.10,
        "tones": {
            "base": ((0.57, 0.61, 0.69), (0.36, 0.40, 0.47)),
            "deep": ((0.39, 0.43, 0.51), (0.23, 0.26, 0.32)),
            "pale": ((0.77, 0.81, 0.89), (0.54, 0.58, 0.66)),
        },
        "rim": (0.90, 0.95, 1.00),
    },
    # Wet earth. Lands near the Earth element and that is the right answer:
    # mud is earth coloured, and nothing else about a four legged lump of it
    # reads as a tower.
    "mud_golem": {
        "bands": 0.70,
        "tones": {
            "base": ((0.43, 0.35, 0.26), (0.25, 0.20, 0.14)),
            "deep": ((0.27, 0.22, 0.16), (0.14, 0.11, 0.08)),
            "pale": ((0.58, 0.49, 0.37), (0.36, 0.30, 0.22)),
        },
        "rim": (0.94, 0.88, 0.76),
    },
    # Warm ivory vestments. Held apart from the Shade - the other pale robed
    # figure - by being WARM where the Shade is cold, and by standing on legs.
    "priest": {
        "bands": 0.20,
        "tones": {
            "base": ((0.81, 0.78, 0.71), (0.56, 0.53, 0.47)),
            "deep": ((0.57, 0.54, 0.48), (0.37, 0.35, 0.30)),
            "pale": ((0.93, 0.91, 0.86), (0.70, 0.68, 0.62)),
        },
        "rim": (1.00, 0.98, 0.92),
    },
    # Dead bark over sick green heartwood. The corruption is in the VALUE - it
    # is the darkest thing that walks - and the only bright thing on it is the
    # lit edge that says it is an attacker.
    "corrupted_treant": {
        "bands": 1.00,
        "tones": {
            "base": ((0.33, 0.31, 0.22), (0.18, 0.17, 0.12)),
            "deep": ((0.21, 0.20, 0.15), (0.11, 0.10, 0.07)),
            "pale": ((0.44, 0.47, 0.30), (0.26, 0.29, 0.18)),
        },
        "rim": (0.86, 0.94, 0.70),
    },
    # Rotting grey green flesh over bone. The Boss of the bracket, and the one
    # hide in the roster that is deliberately unpleasant to look at.
    "rot_golem": {
        "bands": 0.55,
        "tones": {
            "base": ((0.44, 0.47, 0.38), (0.25, 0.28, 0.22)),
            "deep": ((0.28, 0.31, 0.24), (0.15, 0.17, 0.13)),
            "pale": ((0.61, 0.63, 0.51), (0.38, 0.40, 0.32)),
        },
        "rim": (0.94, 1.00, 0.84),
    },
}
