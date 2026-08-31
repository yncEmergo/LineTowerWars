# The visual language of the tower roster, as data.
#
# NONE OF THIS IS A HARD RULE. Every rule in this file was authored by Claude
# rather than decided by the user, who asked for placeholder visuals and not
# for a design. They exist for CONTINUITY - so a roster added later looks like
# it came from the same game as the ones before it - and where this file says
# "hard rule", "never" or "must", read it as: this is what the existing rosters
# were built to, and breaking it for one unit costs the continuity it buys.
# That is a real cost and worth arguing about; it is not a prohibition.
#
# What IS worth holding to is that a change goes HERE and is re-generated, so
# the whole roster moves together. A hand edit to one generated model is
# overwritten by the next run and leaves that unit the only one disagreeing.
# See PLACEHOLDER_ART.md section 0.
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

import colorsys
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
#   WHICH PATH      one decisive silhouette at the 4,000g split - and above
#                   that split, THREE silhouettes rather than one with parts
#                   bolted onto it. See THE PATH LADDER below
#   WHICH TIER      the ladder below, which is no longer the Basic roster's
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


# ============================================================================
# THE PATH LADDER
# ============================================================================
#
# METAL IS THE BASE PAIR'S ALONE. This is the rule the elemental roster was
# re-cut around and it is the one to read first.
#
# The roster shipped wearing the Basic ladder's metal: a trim ring on the
# plinth, a collar under the head, bolts around the shoulder, crown fins, and
# an Ultimate's turning halo - all of them the same tier metal, on every one of
# the thirty towers. Two things went wrong with that at once, and they made
# each other worse. The metal was the LOUDEST thing on every tower, so thirty
# different silhouettes read as one silhouette with its top swapped; and two
# neighbouring rungs of a six step metal ramp are nearly the same colour, so
# the thing being shouted was also the thing hardest to actually read.
#
# So metal now survives only where it is the only thing that can do the job.
# The 200g and 800g towers are deliberately one shape at two sizes, and a ring
# IS what separates them - so they keep it, and their two rungs are pulled as
# far apart as two metals get: near-black iron, then polished brass.
#
# EVERYTHING FROM 4,000g UP CARRIES NO METAL AT ALL. No ring, no collar, no
# bolts, no fins, no halo, and nothing else drawn in the trim material at all.
# What those towers read their tier off instead:
#
#   1. STONE   the element's own material darkens and dulls at Lesser, stands
#              as authored at Greater, and brightens and saturates at
#              Ultimate. This is the direct replacement for TRIM_RAMP and it
#              does the same job - one continuous value ramp that reads at any
#              distance, on any shape, in any light - with the difference that
#              it is the ELEMENT'S OWN colour rather than a second palette
#              laid over the top of it
#   2. MASS    steeper than it was, because it is carrying more now
#   3. SHAPE   every path authors THREE silhouettes rather than one silhouette
#              with parts added. That is the real work and it lives in
#              element_models.py, one comment per builder saying what its three
#              tiers are
#   4. MOTION  an Ultimate, and only an Ultimate, gives off a slow rising aura
#              in its own element's colour. Motion is still the loudest signal
#              a top down camera has and it is still reserved for the top rung.
#              It simply is not a turning metal ring any more
#
# Rules 1 and 2 are continuous so that neighbours stay apart, and rules 3 and 4
# are steps so that an Ultimate is recognisable across a whole map. That is the
# same argument the Basic ladder makes; what changed is that COLOUR does the
# work metal used to, which the elements can afford and the Basic roster cannot.


# The base pair's two rings, and the only metal in the elemental roster.
#
# Chosen to be as far apart as two metals get rather than as two rungs of one
# ramp: the 200g ring is near-black blued iron and reads as a shadow at the
# foot of the tower, the 800g ring is polished brass and reads as a bright band
# around it. A player who has just spent 800 gold should be able to see what it
# bought from across the map, and one step of TRIM_RAMP - pale iron to bronze -
# never delivered that.
ELEMENT_RING_RAMP = [
    (0.19, 0.2, 0.23),
    (0.96, 0.71, 0.24),
]


def element_ring_index(ti):
    return min(ti, len(ELEMENT_RING_RAMP) - 1)


def element_has_metal(ti):
    """Whether this tier wears any metal at all. The base pair, and nothing
    else. Everything a builder draws in the trim material asks this first."""
    return ti <= 1


def element_has_collar(ti):
    """The SECOND ring, which is the 800g tower's own tell against the 200g
    one. Two rings and the brass step are the whole of that upgrade's read, and
    they have to carry it alone - the pair is one shape at two sizes by
    design."""
    return ti == 1


# Rule 2a. Multiplies every authored WIDTH and DEPTH.
#
# A LIST rather than a formula, because the two halves of this ladder want
# different curves out of it. The base pair is one shape at two sizes and wants
# a small step; the three path tiers are carrying the tier read now that the
# metal has gone and want a bigger one.
#
# The CEILING is fixed by the grid rather than by taste - a tower has to leave
# visible ground between itself and its neighbour or a maze reads as one
# continuous wall - so what got steeper is the bottom of the path half rather
# than the top of it.
ELEMENT_MASS = [0.95, 1.0, 1.03, 1.12, 1.21]

# Rule 2b, and deliberately a SEPARATE ramp from the width. The camera looks
# down, so height is the axis it sees least of; but height also costs no
# footprint, and an Ultimate has a whole cell of empty sky over it. So this one
# climbs harder than the width does across the three path tiers - an Ultimate
# stands a quarter again as tall as its Lesser where it is only a fifth wider,
# and the SHAPE work on top of that takes the real gap to about half again.
ELEMENT_HEIGHT = [0.52, 0.57, 0.61, 0.68, 0.76]


def element_mass(ti):
    return ELEMENT_MASS[ti]


def element_height_scale(ti):
    return ELEMENT_HEIGHT[ti]


# What goes into the energy material's `tier` uniform. Starts at 0.2 rather
# than at 0, because an elemental tower is bought with a technology and none of
# them should read as the cheapest thing on the field.
def element_energy_tier(ti):
    return round((ti + 1) / float(len(ELEMENT_PRICE_TIERS)), 3)


# Rule 1: what a PATH TIER does to the element's own stone, as
# (value gain, saturation gain).
#
# Applied in HSV so the HUE NEVER MOVES. An element has to still be that
# element at every tier - the hue is the one thing this roster spends that the
# Basic one cannot - so the ramp gets the two axes that are left and not the
# one that matters.
#
# The LESSER is pulled down rather than the Ultimate being pushed up, and that
# is the lesson the accents already paid for: ramping the top of a colour is
# what saturates it towards white, and a roster whose Ultimates are all the
# same colour has lost its hue at exactly the tier a player paid most for it.
# There is far more room below an authored colour than above it.
PATH_TONE_RAMP = {
    2: (0.84, 0.9),
    3: (1.0, 1.0),
    4: (1.2, 1.3),
}


def element_path_tone(rgb, ti):
    """One authored colour, moved onto a path tier's rung of the ramp."""
    gains = PATH_TONE_RAMP.get(ti)
    if gains is None:
        return rgb
    hue, sat, val = colorsys.rgb_to_hsv(*rgb)
    shifted = colorsys.hsv_to_rgb(hue, _with_headroom(sat, gains[1]),
                                  _with_headroom(val, gains[0]))
    return tuple(round(channel, 4) for channel in shifted)


def _with_headroom(value, gain):
    """Apply a gain scaled by the room the value actually has left.

    A flat multiply is the obvious version and it is wrong at BOTH ends of the
    palette, which one rebake showed in a single frame. Fire and Void are
    near-black by design, so darkening them another fifth took their Lesser
    towers to unlit lumps with no element left in them; Holy is bright ivory,
    so brightening its Ultimate did nothing at all, because there was nothing
    above it to move into.

    So the gain gets the full effect in the middle of the range and tapers to
    nothing as the value approaches whichever end it is being pulled towards.
    An element that has already spent its darkness keeps it.
    """
    room = value if gain < 1.0 else 1.0 - value
    scaled = 1.0 + (gain - 1.0) * min(room * 2.2, 1.0)
    return max(0.0, min(1.0, value * scaled))


def element_stone_suffix(ti):
    """Which set of stone materials a tier is drawn in.

    The base pair takes the element's authored stone, unqualified, because
    those files are also what an element IS - the tones every other palette in
    the game was chosen against. Each path tier takes a rung of its own.
    """
    return "" if ti < 2 else "_t%d" % ti


def element_has_aura(ti):
    """Rule 4. The Ultimate's rising motes, and the roster's only motion."""
    return ti >= 4


# --- a path's own accent ----------------------------------------------------
#
# An element owns a hue and every tower in it carries that hue. That is the
# whole reason colour is reserved for the elements and it is not up for
# negotiation. What a PATH may claim on top of it is ONE PART of its own model,
# in a colour of its own, PER TIER - and only where the source art makes that
# part the entire point of the tower.
#
# Three do. Fire (1)'s orb, which the source draws as a bare rock, then a
# burning orb, then a green one - three different objects rather than one
# object at three brightnesses. Lightning (1)'s emitter, which the source's own
# top tier draws in red-orange with nothing blue left on it. And Primal (1)'s
# geode, which is the GOLD MAKING tower and whose gold used to be drawn in the
# tier metal - so when the metal left the path tiers, that one had to be given
# a colour of its own or lose the only thing on it that says what it does.
#
# Sampled from ReferenceFilesFromOtherProjects/TowerVisualReferences, whose
# README says which tower is which.
#
# Keyed by PATH and then by tier index, so only the three path tiers are ever
# read. Each entry is (glow, dim), exactly the pair an element's palette states,
# and it feeds the same energy shader - so a path accent pulses and surges like
# any other lit part and only its hue is its own.
PATH_ACCENTS = {
    "annihilation_glyph": {
        # RED at every tier, and it is the source game's own answer: the
        # 30,000g Glyph in the reference sheet is a bright red-orange blade
        # standing on grey stone, with nothing blue left on it. Only the
        # emitter at the top takes it, and the arc it throws is drawn in the
        # same colour - see Scenes/Effects/annihilation_bolt.tscn.
        2: ((1.0, 0.34, 0.1), (0.42, 0.07, 0.02)),
        3: ((1.0, 0.3, 0.08), (0.44, 0.06, 0.02)),
        4: ((1.0, 0.26, 0.06), (0.46, 0.05, 0.01)),
    },
    "moonbeam": {
        # 4,000g: the pale salmon meteor the source draws sitting on the plinth.
        2: ((0.94, 0.7, 0.62), (0.44, 0.26, 0.22)),
        # 10,000g: it has caught fire. The hottest of the three and the only one
        # that is the element's own colour.
        3: ((1.0, 0.42, 0.06), (0.52, 0.1, 0.0)),
        # 30,000g: green, and deliberately NOT a fire colour. It is the one
        # tower in Fire that stops being fire, which is what an Ultimate at this
        # price should be allowed to do.
        4: ((0.78, 0.96, 0.24), (0.18, 0.4, 0.08)),
    },
    "primalist": {
        # GOLD, against Primal's blood red, and it climbs from a dull seam in a
        # closed geode to a full molten cavity. It is the only warm pale thing
        # in the element and it is the whole read of the tower.
        2: ((0.86, 0.64, 0.24), (0.3, 0.19, 0.03)),
        3: ((0.98, 0.77, 0.3), (0.38, 0.25, 0.05)),
        4: ((1.0, 0.88, 0.44), (0.46, 0.33, 0.08)),
    },
}


# How many repeated features a path shows at each of its three tiers: crystal
# spikes, orbiting shards, flame plumes, spore gills.
#
# Only the last three entries are ever read, since a path starts at 4,000g. The
# first two exist so an index into it is the tier index rather than the tier
# index minus two, which is the kind of arithmetic that goes wrong once.
#
# It steps HARDER than it used to across those three, for the same reason the
# mass ramp does: counting details is one of the few tier tells left, so 3 to 5
# to 7 is worth having where 3 to 4 to 6 was not.
ELEMENT_FEATURE_COUNT = [3, 3, 3, 5, 7]

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
        # FOUR, on review. A discharge wants hard right angles rather than the
        # rounded drum every other built element sits on, and the reference
        # art's own Lightning towers are square. It shares the count with Ice,
        # which is the one place two elements do - and they are as far apart in
        # VALUE and in proportion as any pair in the table, so nothing is
        # actually being told apart by the side count here.
        "sides": 4,
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
# THE FAMILY RULES. Held firmly rather than hard - see the note at the top of
# this file - and the firmest of the visual conventions, because this is the
# one question a player has to answer in the second before a creep arrives:
#
#   GROUND    stands on legs, on the floor, opaque
#   AIR       has NO legs at all, hangs at cruising height, and is the only
#             thing in the game drawn over a shadow disc pinned to the ground
#             beneath it. From a top down camera height barely reads, so the
#             disc - not the altitude - is what says "flying"
#
#             BEING TRANSLUCENT IS NOT PART OF THIS, and it used to be. It was
#             written as an AIR rule when the only flyer in the game was a
#             ghost, and tier 2 brought a Wyvern - a solid animal that happens
#             to fly, which drawn as vapour reads as a spirit. So vapour
#             belongs to the WRAITH body plan, which is what a Shade and a
#             Banshee are, and the two tells above are what the family really
#             rests on. See creep_roster.is_vapour
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
#
# TWELVE RUNGS, and the top six arrived with tiers 3 and 4. It used to be six,
# which was enough while the roster stopped at 100,000 gold and is not now: the
# ladder is measured in HALF DECADES of cost, so a 4,200,000g creep stands
# eleven rungs above a Sheep, and a six entry ramp quietly clamped everything
# from 3,162 gold upwards onto one rung. Nine of tier 2 were already sharing
# it - the ladder had stopped saying anything about half the roster.
#
# Extending it moves those nine up the ramp, which is the ladder finally doing
# its job rather than churn. What it does NOT move is their size: see the cap
# below, which is the asymmetry this ladder was always documented to have.
CREEP_CARAPACE_RAMP = [
    ((0.72, 0.69, 0.58), 0.00, 0.88),
    ((0.86, 0.83, 0.72), 0.05, 0.78),
    ((0.62, 0.63, 0.66), 0.28, 0.60),
    ((0.52, 0.52, 0.56), 0.38, 0.48),
    ((0.44, 0.44, 0.48), 0.46, 0.38),
    ((0.38, 0.36, 0.39), 0.52, 0.32),
    ((0.34, 0.32, 0.36), 0.55, 0.29),
    ((0.31, 0.29, 0.34), 0.57, 0.26),
    ((0.28, 0.27, 0.32), 0.59, 0.24),
    ((0.26, 0.25, 0.30), 0.60, 0.22),
    ((0.24, 0.23, 0.29), 0.61, 0.20),
    ((0.22, 0.21, 0.27), 0.62, 0.18),
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
# Twelve of them, matching the carapace ramp above. The top six climb far more
# gently than the bottom six on purpose: red is already at its ceiling by rung
# 5, so the only headroom left is in green and blue - and spending it fast is
# exactly how the elemental accents saturated to white and lost their hue at
# the tier the player had paid most for it.
CREEP_EYE_RAMP = [
    (0.78, 0.38, 0.10),
    (0.86, 0.45, 0.13),
    (0.93, 0.52, 0.16),
    (0.97, 0.59, 0.20),
    (1.00, 0.66, 0.25),
    (1.00, 0.74, 0.34),
    (1.00, 0.77, 0.39),
    (1.00, 0.79, 0.44),
    (1.00, 0.81, 0.48),
    (1.00, 0.83, 0.52),
    (1.00, 0.85, 0.56),
    (1.00, 0.87, 0.60),
]


# THE SIZE CEILING. Held firmly, and not a hard rule - see the top of this
# file. What follows is the reasoning, which is what would have to be argued
# with rather than simply overridden.
#
# The whole roster - the Sheep at 10 gold and the last Boss of Sudden Death -
# lives inside a NARROW band of sizes, and the band is deliberately narrow:
#
#   - the biggest creep in the game is a TOP TIER BOSS, and it may reach these
#     numbers and no further. Nothing else may come near them
#   - between one TIER and the next the size difference is MINOR. A tier is a
#     cost bracket and carries no mechanical meaning, so a tier 4 creep that
#     towered over a tier 1 creep would be teaching a player something untrue
#     as loudly as the roster can say anything
#   - and a field of creeps two and three times each other's size is simply
#     chaotic to read, which is the practical half of the same rule
#
# So what a size ladder is FOR here is only to keep neighbours apart, never to
# say how strong something is. The eyes, the carapace and the added plates,
# spines and crest carry that, and they can climb as far as they like because
# none of them costs the player's ability to read the field.
#
# In WORLD units, measured off the finished model: how tall it stands, and how
# far its widest part reaches from its centre. creep_models.generate() checks
# every creep against these and says so when one is over, because a rule that
# is only written down is one a model quietly stops obeying.
# The numbers themselves come from looking at the roster on the field rather
# than from any formula: this is a hair above where the first tier 3 creep was
# authored before it was pulled back, which was the point at which the field
# stopped being readable. Nothing in the roster is near them today, and that is
# correct - the headroom is for the Behemoth and for Sudden Death's own Boss.
CREEP_MAX_HEIGHT = 0.88
CREEP_MAX_RADIUS = 0.55


# Rule 1a. Multiplies every authored WIDTH and DEPTH.
#
# Gentler than the tower ramp, because a creep's FOOTPRINT is a gameplay number
# it must not outgrow - the rules give a creep one free internal cell to walk
# through - so what a heavier creep really gains is bulk in its own model
# rather than reach across the floor. See CreepStats.body_radius.
#
# THE SIZE LADDER STOPS CLIMBING HERE, and the rest of the ladder does not.
# That asymmetry is the oldest thing written down about this roster - see the
# ceiling above - and it is what lets the carapace and the eyes run to twelve
# rungs without the roster growing out of the band a player can read a field
# in. Everything above this rung is the same size as it and is told apart by
# its hard parts, its eyes and its shape.
#
# It is also what kept tiers 1 and 2 still when the ramp was extended: every
# creep that moved up the carapace ramp was already at or above this rung, so
# not one model changed size.
CREEP_SIZE_RUNG_CAP = 5


def creep_mass(rung):
    return round(0.66 * pow(1.10, min(rung, CREEP_SIZE_RUNG_CAP)), 4)


# Rule 1b. Multiplies every authored HEIGHT, on the same reasoning as the tower
# ramp: the camera looks down, so height is the axis worth spending least on.
def creep_height_scale(rung):
    return round(0.40 * pow(1.115, min(rung, CREEP_SIZE_RUNG_CAP)), 4)


# A BOSS is sent one at a time and steals two lives, so it has to read as the
# biggest thing in its bracket before a player has time to read anything else.
# It takes its own rung's ramps and then these on top, and it is forced onto
# the crest whatever it costs - see creep_has_crest.
#
# This is the ONE place a creep is allowed to be noticeably bigger than its
# neighbours, and it is still a fraction rather than a multiple: the ceiling
# above belongs to a top tier Boss, so a Boss climbing much harder than this
# would put the ceiling out of the ladder's reach for everything else.
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


# THE ONE EXCEPTION TO "A CREEP'S ONLY LIT PARTS ARE ITS EYES".
#
# The rule above is what keeps a field of creeps readable next to a roster of
# towers that glow, and it is worth keeping for that and not because it is
# binding - see the top of this file. This is the single authored way past it,
# and it is deliberately a DICTIONARY of named creeps rather than a flag a hide
# can set: adding one is an edit here, in the file that owns the rule, and is
# visible as a change to the rule rather than as a property on a creep.
#
# What earns an entry: the creep IS the light. An Infernal is a burning thing -
# fire is not a decoration on it, it is what the creature is made of, and a
# player who cannot see that is reading the wrong monster. A creep that merely
# has a hot colour, a magical trait or an impressive price earns nothing.
#
# It stays affordable because it is a BOSS, and a Boss is sent one at a time.
# One burning thing on the field is a landmark; twelve would be the roster
# handing its one loud signal to whoever sent the most creeps.
#
# The colour is the flame, not the hide, so it is warmer and far brighter than
# anything in CREEPS - a mote is two pixels and reads as its own colour or as
# nothing at all.
CREEP_FLAMES = {
    "infernal": (1.00, 0.52, 0.16),
    # The second and, for now, last. A Phoenix is fire that happens to have a
    # shape, so a Phoenix that gives off no light is reading as a large bird -
    # which is exactly the mistake the Infernal entry exists to prevent. It
    # clears the same bar: it IS the light, and it is a Boss sent one at a
    # time, so there is never a field of them.
    "phoenix": (1.00, 0.68, 0.24),
}


def creep_flames(key):
    """The flame colour a creep gives off, or None for every other creep."""
    return CREEP_FLAMES.get(key)


# THE HIDES.
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
    # Snow white pelt with a cold blue shadow in it. The first tier 3 creep
    # and the first cold hide that WALKS, so it is chosen against three things
    # at once: the SHEEP, which is the roster's other near-white and is warm
    # where this is cold, and a tenth of the size; the SWORDSMAN, which is the
    # roster's other grey and is mid-value neutral steel where this is pale
    # and blue; and the ICE element, which is more saturated, glows over its
    # whole body and stands on a foundation patch. A creep landing near an
    # element is allowed - a wendigo IS a snow animal - and everything else
    # about the two says which is which.
    "ancient_wendigo": {
        "bands": 0.50,
        "tones": {
            "base": ((0.72, 0.75, 0.80), (0.50, 0.54, 0.59)),
            "deep": ((0.50, 0.54, 0.60), (0.32, 0.36, 0.42)),
            "pale": ((0.82, 0.85, 0.89), (0.60, 0.64, 0.69)),
        },
        "rim": (0.88, 0.96, 1.00),
    },
    # ---------------------------------------------------------------------
    # TIER 2. Chosen against tier 1 as well as against each other, because a
    # tier is a cost bracket and nothing else - all twenty-four of these walk
    # the same lane at the same time, and a player at 12:00 can still send
    # Sheep. Nothing here reaches an element's saturation, and nothing here
    # carries a lit part except its eyes.
    # ---------------------------------------------------------------------
    # Burnished blue steel. The Swordsman is grey steel, so the Knight is the
    # same metal with a hue in it - which is the only separation available
    # when two creeps in one roster are both "an armoured soldier".
    "knight": {
        "bands": 0.60,
        "tones": {
            "base": ((0.42, 0.48, 0.60), (0.24, 0.28, 0.38)),
            "deep": ((0.26, 0.31, 0.41), (0.14, 0.17, 0.24)),
            "pale": ((0.62, 0.68, 0.80), (0.38, 0.43, 0.54)),
        },
        "rim": (0.86, 0.93, 1.00),
    },
    # Cold green white, and the only hue in the roster that is nearly
    # colourless without being the Shade's grey. A vengeful spirit walks
    # rather than flies, so it has to read as a ghost from its COLOUR alone -
    # it gets none of the vapour or the shadow disc the flyers do.
    "vengeful_spirit": {
        "bands": 0.20,
        "tones": {
            "base": ((0.60, 0.74, 0.68), (0.37, 0.48, 0.44)),
            "deep": ((0.38, 0.50, 0.46), (0.22, 0.30, 0.28)),
            "pale": ((0.78, 0.90, 0.85), (0.54, 0.66, 0.62)),
        },
        "rim": (0.86, 1.00, 0.96),
    },
    # Moss green over grey. Skittering, like the Forest Spider two brackets
    # down, and coloured to disappear into a maze for the same reason - but
    # lighter and greyer, so the two are not one creep at two sizes.
    "forest_troll": {
        "bands": 0.50,
        "tones": {
            "base": ((0.40, 0.48, 0.36), (0.23, 0.29, 0.21)),
            "deep": ((0.25, 0.31, 0.23), (0.14, 0.18, 0.13)),
            "pale": ((0.57, 0.65, 0.51), (0.35, 0.41, 0.31)),
        },
        "rim": (0.90, 0.98, 0.82),
    },
    # Dust brown leather. A beast rather than a spirit, and the plainest hide
    # in the bracket on purpose: the Wyvern is read off its WINGSPAN, and a
    # loud colour on a shape that big would be the only thing on the screen.
    "wyvern": {
        "bands": 0.55,
        "tones": {
            "base": ((0.55, 0.44, 0.33), (0.34, 0.26, 0.19)),
            "deep": ((0.35, 0.28, 0.20), (0.20, 0.16, 0.11)),
            "pale": ((0.71, 0.60, 0.47), (0.47, 0.38, 0.29)),
        },
        "rim": (1.00, 0.92, 0.80),
    },
    # Purple, and the roster's first properly saturated hide. It is the closest
    # a creep comes to the Void element and it survives the comparison the way
    # the Mud Golem survives standing next to Earth: Void is near black,
    # magenta, and GLOWS over its whole body, where this is a mid value purple
    # with nothing lit on it but two eyes.
    #
    # It is also chosen against the two violets either side of it in the
    # roster - the Vile Temptress is paler and pinker, the Faceless One is
    # greyer - so the three separate on SATURATION, which is the axis a hide is
    # allowed to spend. See the note above on colour.
    "voidwalker": {
        "bands": 0.75,
        "tones": {
            "base": ((0.40, 0.24, 0.54), (0.24, 0.14, 0.33)),
            "deep": ((0.25, 0.14, 0.35), (0.14, 0.08, 0.20)),
            "pale": ((0.56, 0.39, 0.70), (0.36, 0.24, 0.47)),
        },
        "rim": (0.88, 0.74, 1.00),
    },
    # Grey violet, wet looking. Next to the Voidwalker it unlocks after, so it
    # is separated by VALUE - this one is mid grey where that one is nearly
    # black, which is the same separation Ice and Void use among the towers.
    "faceless_one": {
        "bands": 0.40,
        "tones": {
            "base": ((0.45, 0.41, 0.52), (0.27, 0.24, 0.32)),
            "deep": ((0.29, 0.26, 0.35), (0.16, 0.14, 0.20)),
            "pale": ((0.61, 0.57, 0.68), (0.39, 0.35, 0.45)),
        },
        "rim": (0.92, 0.86, 1.00),
    },
    # Deep teal scale. The one hue nothing else in the game owns - the Water
    # element is a lighter, bluer green and glows over its whole body, where
    # this is a dark unlit hide.
    "dragonspawn": {
        "bands": 0.90,
        "tones": {
            "base": ((0.22, 0.42, 0.42), (0.12, 0.25, 0.26)),
            "deep": ((0.13, 0.27, 0.28), (0.07, 0.15, 0.16)),
            "pale": ((0.36, 0.58, 0.57), (0.20, 0.36, 0.36)),
        },
        "rim": (0.76, 1.00, 0.98),
    },
    # Olive shell over a pale hide. Two tones far apart on purpose: the shell
    # is what the camera sees and the body under it barely shows, so the pale
    # role is doing the work the base one does on every other creep.
    "sea_turtle": {
        "bands": 0.80,
        "tones": {
            "base": ((0.36, 0.40, 0.26), (0.21, 0.24, 0.15)),
            "deep": ((0.22, 0.25, 0.16), (0.12, 0.14, 0.09)),
            "pale": ((0.62, 0.64, 0.48), (0.40, 0.42, 0.30)),
        },
        "rim": (0.96, 1.00, 0.84),
    },
    # Deep purple vapour, and the second creep drawn translucent. The Shade is
    # nearly colourless; this one has a hue, so the two flyers of the roster
    # are told apart at the size a flyer is actually drawn.
    #
    # DARKER than the Voidwalker on purpose, and getting that to read took
    # authoring it somewhere other than where it looks like it should go.
    #
    # ON A VAPOUR CREEP THE RIM IS THE COLOUR. creep_vapour.gdshader mixes the
    # body towards `rim` by the fresnel term and mixes the ALPHA the same way,
    # so the parts a player actually sees - the silhouette - are almost purely
    # rim, and the body tones only tint the near-transparent middle. The first
    # pass here set three properly dark purple tones under a pale lilac rim and
    # the creep came out pale grey. If a wraith is reading as the wrong colour,
    # its rim is the number to change.
    "banshee": {
        "bands": 0.10,
        # DENSER than the Shade, which is what actually makes it the darker
        # ghost - see the note above. It is also right on its own terms: a
        # Banshee is eight rungs of the ladder above a Shade, and the stronger
        # spirit being the more solid one is a thing a player can read.
        "face_alpha": 0.58,
        "tones": {
            "base": ((0.26, 0.13, 0.40), (0.14, 0.07, 0.22)),
            "deep": ((0.15, 0.07, 0.24), (0.08, 0.04, 0.13)),
            "pale": ((0.38, 0.22, 0.55), (0.23, 0.13, 0.34)),
        },
        "rim": (0.62, 0.34, 0.92),
    },
    # Sand and hessian. Deliberately the brightest hide in the bracket while
    # being one of its dearest, on the same reasoning as its size: the ladder
    # says how dangerous a creep is with its carapace and its eyes, and letting
    # a hide say it too would hand the roster a second, conflicting ladder.
    "kobold_geomancer": {
        "bands": 0.30,
        "tones": {
            "base": ((0.72, 0.63, 0.45), (0.48, 0.41, 0.28)),
            "deep": ((0.50, 0.43, 0.29), (0.31, 0.26, 0.17)),
            "pale": ((0.86, 0.78, 0.60), (0.62, 0.55, 0.40)),
        },
        "rim": (1.00, 0.94, 0.78),
    },
    # Iron and oiled timber. The one BUILT thing in the roster, so it is the
    # one hide with no organic tone in it at all - flat, cold and panelled,
    # which the high banding is doing.
    "siege_engine": {
        "bands": 1.00,
        "tones": {
            "base": ((0.40, 0.38, 0.35), (0.23, 0.22, 0.20)),
            "deep": ((0.25, 0.24, 0.22), (0.14, 0.13, 0.12)),
            "pale": ((0.58, 0.55, 0.50), (0.36, 0.34, 0.31)),
        },
        "rim": (0.94, 0.92, 0.88),
    },
    # Burning red rock. The bracket's Boss, and THE ONE CREEP IN THE ROSTER
    # THAT GIVES OFF LIGHT - see CREEP_FLAMES below for why that exception is
    # allowed to exist and why nothing else may take it.
    #
    # It is the one place a creep hide sits in Fire's territory rather than
    # near it, and it survives because a Fire tower glows over its whole body
    # from within while this is opaque rock with flames coming off the outside
    # of it. The two are the same hue and are not the same object.
    "infernal": {
        "bands": 0.95,
        "tones": {
            "base": ((0.46, 0.15, 0.10), (0.26, 0.08, 0.05)),
            "deep": ((0.27, 0.09, 0.06), (0.15, 0.05, 0.03)),
            "pale": ((0.64, 0.25, 0.15), (0.42, 0.15, 0.09)),
        },
        "rim": (1.00, 0.60, 0.30),
    },
    # ------------------------------------------------------------------
    # TIER 3. Twelve creeps in one cost bracket, and the hides are chosen
    # against the twenty-six above them rather than only against each other -
    # a maze at 16:00 has tier 1 creeps walking in it too, and two brackets
    # that agreed on a colour would be worse than two creeps that did.
    #
    # The bracket leans COLD and DESATURATED as a group, which is the one
    # thing it says about itself: tier 1 is farm animals and mud, tier 2 is
    # soldiers and beasts, and this is where the roster stops being alive.
    # ------------------------------------------------------------------
    #
    # Grave-bleached bone under a violet pall. It shares the Skeleton's
    # material and none of its value - a Death Revenant is what a Skeleton
    # Warrior looks like after two more tiers of the same idea, so the two are
    # separated by the cold cast rather than by hue.
    "death_revenant": {
        "bands": 0.90,
        "tones": {
            "base": ((0.55, 0.53, 0.60), (0.33, 0.32, 0.39)),
            "deep": ((0.33, 0.32, 0.40), (0.19, 0.18, 0.24)),
            "pale": ((0.74, 0.72, 0.80), (0.50, 0.49, 0.57)),
        },
        "rim": (0.86, 0.84, 1.00),
    },
    # Dusk purple hide over dark hair. The one creep in the bracket allowed a
    # real hue, because a Satyr with grey skin is a goat.
    "satyr_shadowdancer": {
        "bands": 0.55,
        "tones": {
            "base": ((0.42, 0.32, 0.46), (0.25, 0.18, 0.28)),
            "deep": ((0.26, 0.19, 0.30), (0.15, 0.10, 0.18)),
            "pale": ((0.58, 0.47, 0.62), (0.37, 0.29, 0.41)),
        },
        "rim": (0.92, 0.80, 1.00),
    },
    # Blue-black chitin. Deliberately the OTHER end of the arachnid palette
    # from the Forest Spider olive: two spiders in one game have to be told
    # apart at a glance and their silhouettes are nearly the same.
    "crypt_fiend": {
        "bands": 0.90,
        "tones": {
            "base": ((0.20, 0.24, 0.34), (0.11, 0.13, 0.20)),
            "deep": ((0.12, 0.15, 0.22), (0.06, 0.08, 0.12)),
            "pale": ((0.32, 0.38, 0.50), (0.19, 0.23, 0.32)),
        },
        "rim": (0.72, 0.84, 1.00),
    },
    # Grave linen gone green. Pale enough to read against the bracket around
    # it, since a Necromancer is a robe and a hood and has no other outline.
    "necromancer": {
        "bands": 0.25,
        "tones": {
            "base": ((0.56, 0.60, 0.50), (0.35, 0.38, 0.31)),
            "deep": ((0.34, 0.37, 0.30), (0.20, 0.22, 0.17)),
            "pale": ((0.72, 0.76, 0.66), (0.50, 0.54, 0.45)),
        },
        "rim": (0.80, 1.00, 0.84),
    },
    # Cold vapour. The one GROUND creep in the game drawn as a wraith is, and
    # that is the point: a Spirit Walker walks through your towers, so it has
    # to read as something the maze does not touch. See creep_roster.is_vapour,
    # which is why this is not on the wraith body plan.
    "spirit_walker": {
        "bands": 0.15,
        "tones": {
            "base": ((0.52, 0.66, 0.70), (0.32, 0.43, 0.47)),
            "deep": ((0.32, 0.43, 0.47), (0.19, 0.26, 0.29)),
            "pale": ((0.72, 0.86, 0.90), (0.50, 0.62, 0.66)),
        },
        "rim": (0.74, 0.98, 1.00),
    },
    # Ochre hide and red cloth. Warm on purpose, and the only warm hide in the
    # bracket until its Boss - a Shaman standing in a pack of grey and violet
    # is the thing a player has to find, because it is what is keeping the
    # pack alive.
    "shaman": {
        "bands": 0.45,
        "tones": {
            "base": ((0.60, 0.44, 0.28), (0.38, 0.27, 0.16)),
            "deep": ((0.38, 0.26, 0.16), (0.23, 0.15, 0.09)),
            "pale": ((0.78, 0.60, 0.40), (0.55, 0.41, 0.26)),
        },
        "rim": (1.00, 0.86, 0.62),
    },
    # Sallow stitched flesh. The one hide in the roster with pink in it, and it
    # is doing real work: an Abomination is meat, and a grey one would read as
    # another golem at exactly the tier the roster already has three.
    "abomination": {
        "bands": 0.35,
        "tones": {
            "base": ((0.62, 0.52, 0.48), (0.40, 0.32, 0.30)),
            "deep": ((0.40, 0.31, 0.29), (0.24, 0.18, 0.17)),
            "pale": ((0.78, 0.68, 0.62), (0.56, 0.47, 0.43)),
        },
        "rim": (1.00, 0.86, 0.82),
    },
    # Tawny feather over white. Bright, because a flyer is read off its wings
    # from directly above and a dark one is a hole in the lane - and this is
    # the bracket only flyer.
    "gryphon_rider": {
        "bands": 0.60,
        "tones": {
            "base": ((0.72, 0.66, 0.54), (0.48, 0.43, 0.34)),
            "deep": ((0.46, 0.40, 0.31), (0.28, 0.24, 0.18)),
            "pale": ((0.90, 0.87, 0.80), (0.68, 0.65, 0.58)),
        },
        "rim": (1.00, 0.96, 0.84),
    },
    # Slate blue ogre skin. Cool and heavy, and far enough from the Mud Golem
    # earth tones that two big grey-blue things are never confused.
    "ogre_magi": {
        "bands": 0.40,
        "tones": {
            "base": ((0.42, 0.50, 0.54), (0.26, 0.32, 0.35)),
            "deep": ((0.26, 0.32, 0.36), (0.15, 0.19, 0.22)),
            "pale": ((0.58, 0.66, 0.70), (0.38, 0.45, 0.49)),
        },
        "rim": (0.84, 0.94, 1.00),
    },
    # Blackened plate with a dull red under it. The bracket second warm hide
    # and the darker of the two, so a Chaos Warden and a Shaman never trade
    # places in a pack.
    "chaos_wardens": {
        "bands": 0.85,
        "tones": {
            "base": ((0.34, 0.20, 0.20), (0.19, 0.11, 0.11)),
            "deep": ((0.20, 0.11, 0.11), (0.11, 0.06, 0.06)),
            "pale": ((0.50, 0.31, 0.29), (0.31, 0.19, 0.18)),
        },
        "rim": (1.00, 0.56, 0.48),
    },
    # Abyssal near-black with a cold blue sheen. The bracket Boss, and the
    # darkest hide in the game - which is what a creep whose health bar shows a
    # tenth of what is really there ought to look like.
    "behemoth": {
        "bands": 0.80,
        "tones": {
            "base": ((0.18, 0.17, 0.24), (0.09, 0.09, 0.14)),
            "deep": ((0.10, 0.10, 0.15), (0.05, 0.05, 0.08)),
            "pale": ((0.30, 0.30, 0.40), (0.17, 0.17, 0.24)),
        },
        "rim": (0.60, 0.68, 1.00),
    },
    # ------------------------------------------------------------------
    # TIER 4 - SUDDEN DEATH. Eleven creeps that all arrive in the same second,
    # which is a problem no other bracket has: tiers 1 to 3 unlock one at a
    # time over twenty minutes and a player learns each as it appears, and this
    # whole set lands at once on a field where nothing else may be sent.
    #
    # So the bracket is SATURATED where tier 3 is drained. It is the one place
    # the roster spends real colour, it is affordable because tiers 1 to 3 are
    # gone from the field by the time any of it is walking, and it is what
    # makes Sudden Death read as a different phase of the match rather than as
    # more of the same creeps.
    # ------------------------------------------------------------------
    #
    # Moonlit teal over dark leather. Cool, bright and fast reading - a
    # Huntress is the cheapest thing in the bracket and the one a player sees
    # most of.
    "huntress": {
        "bands": 0.50,
        "tones": {
            "base": ((0.28, 0.54, 0.52), (0.16, 0.33, 0.32)),
            "deep": ((0.16, 0.33, 0.33), (0.09, 0.19, 0.20)),
            "pale": ((0.46, 0.72, 0.70), (0.29, 0.48, 0.47)),
        },
        "rim": (0.68, 1.00, 0.96),
    },
    # Polished obsidian. Nearly black and nearly smooth, which is the whole of
    # it: everything else in the bracket is loud, and the one that weakens
    # every tower it passes is a slab of glass that says nothing.
    "obsidian_statue": {
        "bands": 1.00,
        "tones": {
            "base": ((0.16, 0.15, 0.20), (0.08, 0.08, 0.11)),
            "deep": ((0.09, 0.08, 0.12), (0.04, 0.04, 0.06)),
            "pale": ((0.28, 0.27, 0.34), (0.15, 0.15, 0.20)),
        },
        "rim": (0.66, 0.62, 0.86),
    },
    # Mossed granite. The one hide in the bracket that is deliberately DULL,
    # because a Mountain Giant is an attacker sent for no income at all and
    # what it is is a walking piece of the map.
    "mountain_giant": {
        "bands": 0.85,
        "tones": {
            "base": ((0.44, 0.47, 0.40), (0.27, 0.29, 0.24)),
            "deep": ((0.27, 0.30, 0.25), (0.16, 0.18, 0.14)),
            "pale": ((0.60, 0.63, 0.55), (0.40, 0.43, 0.36)),
        },
        "rim": (0.88, 0.96, 0.80),
    },
    # Storm lilac. Pale and cold so it is legible against the ground from
    # above, which is the only view a flyer is ever read from.
    "harpy_windwitch": {
        "bands": 0.55,
        "tones": {
            "base": ((0.58, 0.52, 0.72), (0.37, 0.32, 0.48)),
            "deep": ((0.36, 0.31, 0.48), (0.21, 0.18, 0.29)),
            "pale": ((0.76, 0.72, 0.88), (0.54, 0.50, 0.66)),
        },
        "rim": (0.90, 0.84, 1.00),
    },
    # Deep sea green with a paler underside. The most saturated hide in the
    # game and it earns it: a Naga Siren is the bracket healer and the thing a
    # defender has to kill first.
    "naga_siren": {
        "bands": 0.70,
        "tones": {
            "base": ((0.20, 0.52, 0.44), (0.11, 0.31, 0.26)),
            "deep": ((0.11, 0.31, 0.27), (0.06, 0.18, 0.15)),
            "pale": ((0.40, 0.74, 0.64), (0.24, 0.50, 0.43)),
        },
        "rim": (0.62, 1.00, 0.88),
    },
    # Rust brown hide. Warm, heavy and plain, so the biggest aura carrier in
    # the game does not also have the loudest colour in it.
    "kodo_beast": {
        "bands": 0.45,
        "tones": {
            "base": ((0.54, 0.34, 0.24), (0.34, 0.21, 0.14)),
            "deep": ((0.33, 0.20, 0.13), (0.20, 0.12, 0.08)),
            "pale": ((0.70, 0.50, 0.38), (0.48, 0.33, 0.24)),
        },
        "rim": (1.00, 0.78, 0.58),
    },
    # Goblin orange over oiled steel. The second BUILT thing in the roster
    # after the Siege Engine, and it is the loud one - the Siege Engine is grey
    # iron, so the two machines never read as the same machine.
    "goblin_shredder": {
        "bands": 1.00,
        "tones": {
            "base": ((0.66, 0.40, 0.16), (0.42, 0.25, 0.09)),
            "deep": ((0.30, 0.28, 0.26), (0.17, 0.16, 0.15)),
            "pale": ((0.84, 0.58, 0.28), (0.60, 0.40, 0.19)),
        },
        "rim": (1.00, 0.82, 0.52),
    },
    # Frost bone. Almost white, and the brightest thing in the game - a Frost
    # Wyrm is a skeleton flying over a maze and it should be visible from the
    # far end of the map.
    "frost_wyrm": {
        "bands": 0.95,
        "tones": {
            "base": ((0.72, 0.82, 0.90), (0.48, 0.58, 0.68)),
            "deep": ((0.46, 0.56, 0.66), (0.28, 0.35, 0.43)),
            "pale": ((0.88, 0.94, 1.00), (0.66, 0.74, 0.84)),
        },
        "rim": (0.78, 0.94, 1.00),
    },
    # Ember. The bracket Boss and the second creep in the game that gives off
    # light - see CREEP_FLAMES. Hotter and yellower than the Infernal, which is
    # the older of the two burning creeps and is red rock rather than flame.
    "phoenix": {
        "bands": 0.60,
        "tones": {
            "base": ((0.70, 0.28, 0.08), (0.44, 0.16, 0.04)),
            "deep": ((0.42, 0.15, 0.04), (0.25, 0.08, 0.02)),
            "pale": ((0.92, 0.52, 0.14), (0.68, 0.34, 0.08)),
        },
        "rim": (1.00, 0.78, 0.34),
    },
    # Char and old blood. Darker than the Phoenix standing next to it and with
    # none of its heat, because a Demon is the one creep in the game nothing
    # can hurt and it should look inert rather than furious.
    "demon": {
        "bands": 0.75,
        "tones": {
            "base": ((0.30, 0.13, 0.14), (0.17, 0.07, 0.08)),
            "deep": ((0.16, 0.07, 0.08), (0.08, 0.03, 0.04)),
            "pale": ((0.46, 0.22, 0.22), (0.28, 0.13, 0.13)),
        },
        "rim": (1.00, 0.44, 0.36),
    },
    # Bright green and gold. The one creep in the game NOBODY defends against,
    # so it is the one hide chosen to be spotted rather than to fit in: both
    # players want it dead and the defender has one shot to notice it.
    "treasure_goblin": {
        "bands": 0.40,
        "tones": {
            "base": ((0.36, 0.62, 0.28), (0.21, 0.39, 0.16)),
            "deep": ((0.21, 0.38, 0.16), (0.12, 0.22, 0.09)),
            "pale": ((0.80, 0.68, 0.30), (0.56, 0.47, 0.19)),
        },
        "rim": (1.00, 0.94, 0.52),
    },
    # Grey-green carrion. Deliberately drab and deliberately close to nothing
    # else: a Ghoul is never sent, it only ever crawls out of a dead Obsidian
    # Statue, so what it has to say is "there are more of these now" rather
    # than anything about itself.
    "ghoul": {
        "bands": 0.40,
        "tones": {
            "base": ((0.46, 0.48, 0.40), (0.28, 0.30, 0.24)),
            "deep": ((0.28, 0.29, 0.23), (0.16, 0.17, 0.13)),
            "pale": ((0.62, 0.64, 0.55), (0.42, 0.44, 0.36)),
        },
        "rim": (0.86, 0.92, 0.78),
    },
}
