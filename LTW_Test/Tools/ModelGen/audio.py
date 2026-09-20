# Which sound each tower fires with and each hit lands with. The audio half of
# style.py, and the whole mapping in one file for the same reason the visual
# rules are: thirty basic towers and eighty elemental ones is past the number
# anybody keeps consistent by hand, and a roster only sounds like one game if
# something says so in one place.
#
# WHAT THE SOUNDS ARE is not decided here. Tools/SfxGen/sounds.py is the sound
# language - it decides what a bow or a powder charge is made of - and this file
# only says which tower gets which. The two tools are deliberately separate:
# SfxGen writes .wav files and knows nothing about a roster, and this knows the
# roster and renders no audio.
#
# NONE OF IT IS BINDING, on the same terms as style.py: it was authored by
# Claude rather than handed down, and what it buys is continuity. Change a row
# when it is wrong, here rather than in a generated .tres - the next run
# overwrites a hand edit and leaves that one tower the only thing disagreeing.
#
# THE THREE AXES ARE SfxGen's, read onto this roster:
#
#   LINE     picks the timbre. The archer line is a physical release, the
#            cutter line does not announce itself at all, the sentry line and
#            every element line are arcane.
#   BRANCH   changes one ingredient. Inside the archer line a bow becomes a
#            mechanism becomes a powder charge, which is the same single step
#            the silhouette takes.
#   TIER     is not here at all, and that is the one place this disagrees with
#            PLACEHOLDER_ART.md. SfxGen carries a TIER table and no tower uses
#            it yet: four fire sounds cover thirty basic towers and eighty
#            elemental ones, so a tier ladder would mean rendering the ladder
#            first. See "What is missing" below.
#
# WHAT IS MISSING, stated plainly because the mapping below reads richer than
# it is. There is ONE arcane fire sound, so nine of the ten element lines share
# it - fire, ice, holy, void and the rest are distinguishable by their
# projectile and their impact and not at all by what leaving the tower sounds
# like. That is a gap in SfxGen rather than a mistake here, and the fix is more
# sounds in sounds.py, not a mis-mapping in this file to manufacture variety.

FIRE_DIR = "res://Audio/Generated/Towers"
IMPACT_DIR = "res://Audio/Generated/Impacts"

# Releases. What leaving the tower sounds like.
ARROW = FIRE_DIR + "/arrow_release.wav"
BOLT = FIRE_DIR + "/bolt_release.wav"
CANNON = FIRE_DIR + "/cannon_fire.wav"
MAGIC = FIRE_DIR + "/magic_cast.wav"

# Arrivals. What being hit sounds like, told apart by how much the thing struck
# rings back: flesh not at all, stone a little, armour a lot.
FLESH = IMPACT_DIR + "/impact_flesh.wav"
ARMOR = IMPACT_DIR + "/impact_armor.wav"
STONE = IMPACT_DIR + "/impact_stone.wav"
EXPLOSION = IMPACT_DIR + "/explosion.wav"

# SILENCE IS AN ANSWER, not a hole. An empty path is how a sound is turned off,
# and the game reads it as "this makes no noise" rather than as a missing file
# - see AttackStats.fire_sound_path and AttackDelivery.impact_sound_path.
NONE = ""


# --- the basic roster, by branch --------------------------------------------

# What each branch of the three basic lines fires with.
#
# THE CUTTER LINE FIRES SILENTLY, which is the only entry here worth arguing
# about. A grinder attacks three times a second and a slam is the slowest
# attack in the game, and neither of them launches anything - what a player
# hears from that line is the landing. A release sound on the Cutter would be
# nine machines in a maze each asking twenty times a second for a noise that
# describes nothing, and the dedupe would then make the whole line sound like
# one saw. The Crusher is silent on the way out for the opposite reason: its
# blow IS the impact, and announcing it twice would read as two attacks.
TOWER_FIRE = {
    "archer": ARROW,
    # The one branch change inside the archer line, and it matches the
    # silhouette's: a bow becomes a mechanism.
    "watch": BOLT,
    "cannon": CANNON,
    "cutter": NONE,
    "carver": NONE,
    "crusher": NONE,
    "sentry": MAGIC,
    "defender": MAGIC,
    # The one branch that does not follow its LINE, and deliberately: the
    # Turret is the only thing in the sentry line that is not magic at all. It
    # deals Siege damage out of a rack of barrels, so it follows its damage
    # type instead, and a player who hears powder where the rest of the line
    # rings has been told something true about it.
    "turret": CANNON,
}

# What a hit from each branch sounds like landing.
#
# EXPLOSION IS RESERVED for the two branches whose shot is a shell. It is the
# one long sound in SfxGen's set - most of a second, against every other impact
# being under three tenths - and it earns that by being rare. Spending it on
# anything that fires quickly turns a maze into a drone; see sounds.py.
#
# An impact sound is INDEPENDENT of an impact visual: the archer branches have
# no impact scene at all in roster.IMPACT and are still audible when they hit,
# because AttackDelivery plays the sound outside the early return that skips
# the visual. Either half may exist without the other.
TOWER_IMPACT = {
    "archer": FLESH,
    "watch": FLESH,
    "cannon": EXPLOSION,
    "cutter": FLESH,
    "carver": FLESH,
    # Stone rather than flesh: what a Crusher hits is the ground, and the
    # blast comes off the floor rather than off the creep standing on it.
    "crusher": STONE,
    "sentry": ARMOR,
    "defender": ARMOR,
    "turret": EXPLOSION,
}


# --- the elemental roster, by element then by shape -------------------------

# What an element line fires with, keyed as element_roster names its elements.
#
# Nine of the ten are the same sound, which is honest rather than lazy - see
# "What is missing" at the top. Earth is the exception because an Earth tower
# throws a rock: nothing about that is arcane, and the boulder leaving is the
# one thing in the set a powder charge already describes.
ELEMENT_FIRE = {
    "core": NONE,
    "fire": MAGIC,
    "ice": MAGIC,
    "lightning": MAGIC,
    "holy": MAGIC,
    "void": MAGIC,
    "unholy": MAGIC,
    "water": MAGIC,
    "earth": CANNON,
    "arcane": MAGIC,
    "primal": MAGIC,
}

# What an element's hits sound like landing, on the axis SfxGen's three
# impacts are separated by: how much the thing struck rings back.
ELEMENT_IMPACT = {
    "core": NONE,
    # A burst with no ring to it.
    "fire": FLESH,
    # Brittle, and it cracks rather than rings.
    "ice": STONE,
    # Metal, because an inharmonic ring is what electricity earthing itself
    # into something sounds like.
    "lightning": ARMOR,
    "holy": ARMOR,
    # Dull and swallowing, which is the whole character of the element.
    "void": FLESH,
    "unholy": FLESH,
    "water": FLESH,
    "earth": STONE,
    "arcane": ARMOR,
    "primal": FLESH,
}

# Where ONE elemental tower disagrees with its own line, keyed by shape.
#
# Kept as a short list of exceptions rather than folded into the tables above,
# so the line's answer stays readable and every departure from it has to be
# written down. A shape not named here takes its element's answer.
SHAPE_FIRE = {
    # The Moonbeam's shot is CALLED DOWN rather than fired - the projectile is
    # spawned in the sky and the tower is not on the line at all, see
    # element_roster.SKY_LAUNCH. A muzzle report from a tower that launched
    # nothing would be heard coming from the wrong place.
    "moonbeam": NONE,
    # Thrown rocks, wherever they appear. Primal is an arcane line and the
    # Ancient Warden still lobs a boulder.
    "ancient_warden": CANNON,
    "primal_base": CANNON,
    # A mortar in everything but name: a lobbed flask, the slowest shot in the
    # game.
    "alchemist": CANNON,
    # A dart. The fastest small projectile in the roster, and the only thing
    # outside the archer line that a bowstring describes.
    "scorpion": ARROW,
    # The one PIERCE in the game, fired flat and fast through a whole column -
    # a mechanism rather than a spell.
    "crystal": BOLT,
}

SHAPE_IMPACT = {
    # An Alchemist's flask is a blast, and it is slow enough to afford the one
    # long sound in the set.
    "alchemist": EXPLOSION,
    # A thorn in a body, whatever the line it came from.
    "scorpion": FLESH,
}


# --- asking -----------------------------------------------------------------

def tower_fire(branch):
    """What a basic tower of this branch fires with, or "" for silence."""
    return TOWER_FIRE.get(branch, NONE)


def tower_impact(branch):
    """What a basic tower of this branch sounds like landing a hit."""
    return TOWER_IMPACT.get(branch, NONE)


def element_fire(element, shape):
    """What an elemental tower fires with: its shape's exception if it has
    one, otherwise its element's answer."""
    if shape in SHAPE_FIRE:
        return SHAPE_FIRE[shape]
    return ELEMENT_FIRE.get(element, MAGIC)


def element_impact(element, shape):
    """The same for the hit landing."""
    if shape in SHAPE_IMPACT:
        return SHAPE_IMPACT[shape]
    return ELEMENT_IMPACT.get(element, NONE)
