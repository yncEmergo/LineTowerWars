"""The thirty elemental silhouettes: ten element base shapes and twenty paths.

Read style.py first, then tower_models.py. This is the same job the Basic
roster's model file does, on the second ladder, and everything structural about
it is the same:

    Base                the shared ground patch, tower_foundation.tscn
    Turret              the node that turns to face a target
    Turret/Muzzle       the node shots leave from

plus whatever node element_roster.ANIMATION names for that path - `Turret/Orb`,
`Turret/Cap`, `Turret/Lashes` - which the PREFAB animates, because those
components need the unit and a model has none.

WHAT IS DIFFERENT FROM THE BASIC ROSTER, and it is only two things:

  COLOUR IS SPENT. An element owns a hue and every part of its tower carries
  it. That is the whole thing the Basic roster gave up (style.py says why), so
  a builder here should not be shy with it - what a player reads across a map
  is the colour, and the shape is what tells two similar hues apart up close.

  THE BASE PAIR IS ONE SHAPE. tier 0 and tier 1 are the 200g and 800g towers
  and they are the SAME builder, growing rather than changing. The path
  silhouette arrives at 4,000g and never changes again, exactly as a Basic
  branch's does at 150g.

MOTION, and a deliberate exception to the Basic roster's rule.

The Basic rule is that nothing below an Ultimate has a moving part that is not
its own attack, because motion is the loudest thing a top down camera can show.
That rule is kept for everything LARGE: the turning halo is still an Ultimate's
alone, at every tier of every element.

What is allowed here and is not allowed there is a SMALL, SLOW idle breath on
the elements that are alive rather than built - Void, Unholy, Water and Primal.
A creature that is perfectly still reads as dead, which is a worse lie than the
motion is a distraction. It is authored an order of magnitude smaller and
slower than a halo and sits at the middle of the model rather than at its
outline, so the two cannot be confused at a glance. See game_rules.md.

AUTHORED UNITS ARE UNSCALED, exactly as in tower_models: each builder returns
the tower's height in those units and generate() multiplies by the tier's own
ramp. Width and height ramp separately, so a rotated cylinder must pass
`along="z"` or it is shortened every time the roster gets lower.
"""

import io
import math
import os

import style as ts
from element_roster import ELEMENT_ORDER, ELEMENTS, tower_rows
from modelkit import Model

OUT = "Scenes/Units/Models/Towers"
FOUNDATION = "res://Scenes/Units/Models/tower_foundation.tscn"
UNIT_MODEL_SCRIPT = "res://Scripts/Units/UnitModel.gd"
MAT = "res://Resources/Materials/Towers"

# Elements whose towers are CREATURES rather than structures, and so carry the
# small idle breath the module docstring describes. Named here rather than in
# style.py because it is a fact about the models, not about the palette.
LIVING = ("void", "unholy", "water", "primal")


class ElementModel(Model):
    """A Model that knows which element it belongs to and which rung of the
    ELEMENTAL price ladder it is on - the two things every rule here needs."""

    def __init__(self, key, element, tier_index):
        palette = ts.ELEMENTAL_CORE if element == "core" else ts.ELEMENTS[element]
        Model.__init__(
            self,
            "".join(part.capitalize() for part in key.split("_")) + "Model",
            UNIT_MODEL_SCRIPT,
            {
                "body": "%s/%s_stone.tres" % (MAT, element),
                "deep": "%s/%s_stone_deep.tres" % (MAT, element),
                "pale": "%s/%s_stone_pale.tres" % (MAT, element),
                "trim": "%s/trim_t%d.tres" % (MAT, ts.element_trim_index(tier_index)),
                "glow": "%s/energy_%s_t%d.tres" % (MAT, element, tier_index),
            },
            ts.element_mass(tier_index),
            ts.element_height_scale(tier_index),
        )
        self.ti = tier_index
        self.element = element
        self.sides = palette["sides"]
        self.alive = element in LIVING

    def features(self):
        """How many repeated parts this tier shows: spikes, plumes, shards."""
        return ts.ELEMENT_FEATURE_COUNT[self.ti]


# --- the parts every elemental tower carries --------------------------------

def plinth(m, bottom=0.34, top=0.30, height=0.16, sides=None):
    """Foundation patch, plinth, and the base trim ring.

    Unlike the Basic roster's, the ring is here at EVERY tier: an elemental
    tower is bought with a technology and none of them should read as the
    cheapest thing on the field. See style.element_trim_index.
    """
    m.scene.node("Base", None, ".", instance=m.scene.ext("PackedScene", FOUNDATION))
    faces = m.sides if sides is None else sides
    m.put("Plinth", m.cyl(m.deep, top, bottom, height, faces), y=height * 0.5)
    m.put("BaseTrim", m.torus(m.trim, top - 0.015, top + 0.035, 14, 5),
          y=height, shadow=False)
    return height


def collar(m, at, inner=0.12, outer=0.19):
    """Tier rule: a trim ring under the head, from the 800g tier up."""
    if ts.element_has_collar(m.ti):
        m.put("Collar", m.torus(m.trim, inner, outer, 12, 5), y=at, shadow=False)


def bolts(m, at, radius, count=6, size=0.034):
    """Tier rule: studs around the shoulder, from 4,000g up."""
    if not ts.element_has_bolts(m.ti):
        return
    stud = m.gem(m.trim, size, size * 1.6, 5, 2)
    m.ring_of(count, radius, lambda i, x, z, a: m.put(
        "Bolt%d" % (i + 1), stud, x=x, y=at, z=z, shadow=False))


def crown(m, at, radius, count=4, size=(0.06, 0.17, 0.05)):
    """Tier rule: fins around the shoulder, from 10,000g up."""
    if not ts.element_has_crown(m.ti):
        return
    mesh = m.prism(m.trim, size[0], size[1], size[2])
    m.ring_of(count, radius, lambda i, x, z, a: m.put(
        "Fin%d" % (i + 1), mesh, x=x, y=at, z=z, ry=a, rx=0.28))


def halo(m, at, radius=0.28):
    """Tier rule: a turning ring above the tower, at 30,000g only.

    Still the one large moving part in the game and still an Ultimate's alone,
    however alive the element below it is. `at` has to clear everything the
    tower puts above its own body, or it reads as a second object floating
    alongside rather than as a crown on this one.
    """
    if not ts.element_has_halo(m.ti):
        return
    m.pivot("Halo", ".", y=at)
    m.put("HaloRing", m.torus(m.trim, radius - 0.05, radius, 16, 6),
          parent="Halo", rx=0.22, shadow=False)
    m.put("HaloCore", m.gem(m.glow, 0.055, 0.11, 6, 2), parent="Halo", shadow=False)
    m.spinner("HaloSpin", "Halo", 0.22)


def breathe(m, node, height=0.018, rate=0.22, phase=0.0):
    """The living elements' idle breath.

    Deliberately tiny and slow next to a halo - a twentieth of the travel at a
    fifth of the rate - and attached to the middle of the model rather than to
    its outline. It is there to say the thing is alive, not to say it is
    expensive. Only the four elements in LIVING carry it.
    """
    if not m.alive:
        return
    m.bobber("Breathe", node, height, rate, phase)


def runes(m, count, radius, at, size=(0.05, 0.14, 0.02), parent="."):
    """A ring of small glowing marks around a shaft. The cheapest way to make a
    plain drum read as an element rather than as a rock, and used by most of
    the worked-stone builders."""
    mesh = m.box(m.glow, size[0], size[1], size[2])
    m.ring_of(count, radius, lambda i, x, z, a: m.put(
        "Rune%d" % (i + 1), mesh, parent=parent, x=x, y=at, z=z, ry=a, shadow=False))


# --- the elemental core -----------------------------------------------------

def build_core(m):
    """The generic 200g tower, before it is any element at all.

    A flat worked pad with one red rune turning slowly on it, which is what the
    source game's own art is. Deliberately the LOWEST thing in the game and the
    only one with no colour of its own: it is a socket waiting to be filled,
    and it should look unfinished next to everything it can become.
    """
    base = plinth(m, 0.36, 0.34, 0.10, 8)
    m.put("Slab", m.cyl(m.body, 0.30, 0.32, 0.10, 8), y=base + 0.05)
    m.pivot("Turret", ".", y=base + 0.10)
    m.pivot("Rune", "Turret")
    bar = m.box(m.glow, 0.30, 0.02, 0.05)
    m.put("RuneA", bar, parent="Turret/Rune", y=0.02, shadow=False)
    m.put("RuneB", bar, parent="Turret/Rune", y=0.02, ry=1.5708, shadow=False)
    m.put("RuneCore", m.gem(m.glow, 0.06, 0.06, 6, 2), parent="Turret/Rune",
          y=0.03, shadow=False)
    m.spinner("RuneSpin", "Turret/Rune", 0.12)
    m.pivot("Muzzle", "Turret", y=0.06, z=-0.14)
    return base + 0.14


# --- the ten element base shapes --------------------------------------------

def build_fire_base(m):
    """Fire Pit / Magma Well: a cracked basalt crater with lava in the seams.

    Squat and wide, because everything else in Fire is tall and thin and the
    base pair has to be told apart from the Doom Guard's orb at a glance.
    """
    base = plinth(m, 0.34, 0.31, 0.15, 6)
    m.put("Cone", m.cyl(m.body, 0.24, 0.31, 0.24, 6), y=base + 0.12)
    m.put("Mouth", m.torus(m.pale, 0.17, 0.25, 10, 5), y=base + 0.24)
    m.put("Lava", m.cyl(m.glow, 0.19, 0.19, 0.03, 6), y=base + 0.25, shadow=False)
    seam = m.box(m.glow, 0.045, 0.16, 0.02)
    m.ring_of(m.features(), 0.27, lambda i, x, z, a: m.put(
        "Seam%d" % (i + 1), seam, x=x, y=base + 0.13, z=z, ry=a, shadow=False))
    collar(m, base + 0.24, 0.25, 0.30)
    m.pivot("Turret", ".", y=base + 0.28)
    if m.ti >= 1:
        # The 800g tower is the same crater with a spout on it, which is the
        # base pair's whole upgrade tell.
        m.put("Spout", m.cyl(m.pale, 0.07, 0.11, 0.20, 6), parent="Turret", y=0.10)
        m.put("SpoutCore", m.gem(m.glow, 0.055, 0.11, 6, 2), parent="Turret",
              y=0.22, shadow=False)
    m.pivot("Muzzle", "Turret", y=0.20 if m.ti >= 1 else 0.06, z=-0.10)
    return base + (0.50 if m.ti >= 1 else 0.30)


def build_ice_base(m):
    """Obelisk / Runic Monolith: a four sided tapered spire with lit runes.

    The tallest and thinnest of the ten, and squarely the source game's own
    shape - it is the one element whose reference art is already a tower.
    """
    base = plinth(m, 0.28, 0.25, 0.14, 4)
    m.put("Spire", m.cyl(m.body, 0.13, 0.22, 0.62, 4), y=base + 0.31)
    m.put("Cap", m.cyl(m.pale, 0.0, 0.14, 0.20, 4), y=base + 0.70)
    runes(m, 4, 0.16, base + 0.36, (0.04, 0.22, 0.02))
    collar(m, base + 0.60, 0.115, 0.175)
    m.pivot("Turret", ".", y=base + 0.66)
    m.put("Core", m.gem(m.glow, 0.075, 0.20, 4, 2), parent="Turret", shadow=False)
    if m.ti >= 1:
        shard = m.gem(m.pale, 0.05, 0.20, 4, 2)
        m.ring_of(3, 0.20, lambda i, x, z, a: m.put(
            "Shard%d" % (i + 1), shard, parent="Turret", x=x, y=-0.06, z=z, rz=0.3))
    m.pivot("Muzzle", "Turret", z=-0.14)
    return base + 0.86


def build_lightning_base(m):
    """Shock Particle / Power Generator: three posts holding a floating orb.

    Straight from the reference art, which is already a tower and already the
    clearest thing in the element: dark stone with the only bright thing on the
    whole model hanging in the middle of it.
    """
    base = plinth(m, 0.32, 0.29, 0.15, 8)
    m.put("Drum", m.cyl(m.body, 0.24, 0.29, 0.20, 8), y=base + 0.10)
    post = m.box(m.pale, 0.075, 0.28, 0.075)
    m.ring_of(3, 0.19, lambda i, x, z, a: m.put(
        "Post%d" % (i + 1), post, x=x, y=base + 0.34, z=z, ry=a))
    collar(m, base + 0.20, 0.23, 0.29)
    m.pivot("Turret", ".", y=base + 0.52)
    m.put("Orb", m.gem(m.glow, 0.115 if m.ti >= 1 else 0.095, 0.22, 6, 3),
          parent="Turret", shadow=False)
    m.put("OrbCage", m.torus(m.trim, 0.13, 0.155, 10, 4), parent="Turret",
          rx=1.5708, shadow=False)
    if m.ti >= 1:
        m.put("OrbCage2", m.torus(m.trim, 0.13, 0.155, 10, 4), parent="Turret",
              rx=1.5708, ry=1.5708, shadow=False)
    m.bobber("Bob", "Turret", 0.03, 0.4)
    m.pivot("Muzzle", "Turret", z=-0.15)
    return base + 0.66


def build_holy_base(m):
    """Light Flies / Holy Lantern: a fluted column carrying an open lantern.

    Round and upright, in warm ivory and gold. The lantern is a CAGE rather
    than a solid head, so the light inside it is what reads at distance - which
    is the whole of the element's identity.
    """
    base = plinth(m, 0.31, 0.28, 0.15, 8)
    m.put("Column", m.cyl(m.body, 0.15, 0.20, 0.40, 8), y=base + 0.20)
    flute = m.box(m.deep, 0.035, 0.36, 0.035)
    m.ring_of(m.features() + 1, 0.17, lambda i, x, z, a: m.put(
        "Flute%d" % (i + 1), flute, x=x, y=base + 0.20, z=z, ry=a))
    collar(m, base + 0.40, 0.13, 0.20)
    m.pivot("Turret", ".", y=base + 0.54)
    m.put("Cap", m.cyl(m.pale, 0.05, 0.16, 0.10, 8), parent="Turret", y=0.18)
    m.put("Dish", m.cyl(m.pale, 0.17, 0.10, 0.05, 8), parent="Turret", y=-0.14)
    # Bigger than the cage around it, so the lantern reads as LIGHT rather than
    # as a beige column with something inside it.
    m.put("Flame", m.gem(m.glow, 0.125, 0.30, 6, 3), parent="Turret",
          shadow=False)
    bar = m.box(m.trim, 0.02, 0.24, 0.02)
    m.ring_of(4 if m.ti >= 1 else 3, 0.12, lambda i, x, z, a: m.put(
        "Bar%d" % (i + 1), bar, parent="Turret", x=x, z=z, ry=a, shadow=False))
    m.pivot("Muzzle", "Turret", z=-0.14)
    return base + 0.74


def build_void_base(m):
    """Voidling / Voidalisk: a hide mound with a pod that has opened.

    The one element whose towers are grown rather than built, so it is all
    capsules and no flat faces, and the eye inside the pod is the only thing on
    it that reads as deliberate. It breathes - see the module docstring.
    """
    base = plinth(m, 0.32, 0.30, 0.13, 6)
    m.put("Mound", m.capsule(m.body, 0.24, 0.34, 8, 3), y=base + 0.14)
    frond = m.capsule(m.deep, 0.045, 0.26, 5, 2)
    m.ring_of(m.features() + 1, 0.24, lambda i, x, z, a: m.put(
        "Frond%d" % (i + 1), frond, x=x, y=base + 0.10, z=z, ry=a, rx=0.6))
    collar(m, base + 0.24, 0.20, 0.26)
    m.pivot("Turret", ".", y=base + 0.34)
    petal = m.prism(m.pale, 0.12, 0.24, 0.07)
    m.ring_of(3 if m.ti < 1 else 4, 0.11, lambda i, x, z, a: m.put(
        "Petal%d" % (i + 1), petal, parent="Turret", x=x, z=z, ry=a, rx=-0.45))
    m.put("Eye", m.gem(m.glow, 0.085, 0.17, 6, 3), parent="Turret", y=0.04,
          shadow=False)
    breathe(m, "Turret", 0.02, 0.24)
    m.pivot("Muzzle", "Turret", y=0.06, z=-0.12)
    return base + 0.52


def build_unholy_base(m):
    """Plague Well / Defiled Fountain: a bone ribbed pit of something green.

    A hole in the ground rather than a thing standing on it, which is what
    keeps the whole element low and lets the Gravedigger above it stay low too
    while the Alchemist goes tall.
    """
    base = plinth(m, 0.34, 0.32, 0.13, 6)
    m.put("Rim", m.cyl(m.body, 0.30, 0.27, 0.24, 6), y=base + 0.12)
    m.put("Pool", m.cyl(m.glow, 0.19, 0.19, 0.03, 6), y=base + 0.23, shadow=False)
    # Standing PROUD of the rim rather than lying against it. Sunk in, the pit
    # read as a flat green disc with nothing around it.
    rib = m.capsule(m.pale, 0.04, 0.34, 5, 2)
    m.ring_of(m.features() + 2, 0.27, lambda i, x, z, a: m.put(
        "Rib%d" % (i + 1), rib, x=x, y=base + 0.22, z=z, ry=a, rx=0.5))
    collar(m, base + 0.18, 0.26, 0.32)
    m.pivot("Turret", ".", y=base + 0.20)
    if m.ti >= 1:
        m.put("Spout", m.capsule(m.pale, 0.07, 0.26, 6, 2), parent="Turret", y=0.13)
        m.put("SpoutMouth", m.gem(m.glow, 0.06, 0.10, 6, 2), parent="Turret",
              y=0.26, shadow=False)
    breathe(m, "Turret", 0.014, 0.2)
    m.pivot("Muzzle", "Turret", y=0.24 if m.ti >= 1 else 0.04, z=-0.10)
    return base + (0.50 if m.ti >= 1 else 0.24)


def build_water_base(m):
    """Splasher / Tidecaller: a round basin with a spout standing in it.

    Everything about Water is a ring on the floor and something rising out of
    the middle of it, which is what makes the Sludge line's aura read later:
    the shape has already taught a player to look at the ground around it.
    """
    base = plinth(m, 0.33, 0.31, 0.13, 8)
    m.put("Basin", m.cyl(m.body, 0.30, 0.28, 0.14, 8), y=base + 0.07)
    m.put("Water", m.cyl(m.glow, 0.25, 0.25, 0.03, 8), y=base + 0.13, shadow=False)
    m.put("Lip", m.torus(m.pale, 0.26, 0.31, 14, 5), y=base + 0.14)
    collar(m, base + 0.14, 0.27, 0.33)
    m.pivot("Turret", ".", y=base + 0.20)
    m.put("Spout", m.capsule(m.pale, 0.085, 0.30, 8, 3), parent="Turret", y=0.13)
    m.put("Drop", m.gem(m.glow, 0.075, 0.17, 6, 3), parent="Turret",
          y=0.32 if m.ti >= 1 else 0.28, shadow=False)
    if m.ti >= 1:
        m.put("Collar2", m.torus(m.trim, 0.09, 0.125, 10, 4), parent="Turret",
              y=0.22, shadow=False)
    breathe(m, "Turret", 0.016, 0.3)
    m.pivot("Muzzle", "Turret", y=0.30, z=-0.10)
    return base + 0.56


def build_earth_base(m):
    """Rockfall / Avalanche: a stack of boulders with a throwing arm on it.

    Five sided and deliberately irregular - every boulder is turned a different
    way - because a regular Earth tower reads as masonry and Earth is the one
    element that should read as something nobody built.
    """
    base = plinth(m, 0.35, 0.32, 0.14, 5)
    m.put("RockA", m.cyl(m.body, 0.24, 0.29, 0.22, 5), y=base + 0.11, ry=0.4)
    m.put("RockB", m.cyl(m.body, 0.17, 0.22, 0.18, 5), y=base + 0.30, ry=-0.7)
    m.put("RockC", m.cyl(m.pale, 0.13, 0.16, 0.13, 5), y=base + 0.44, ry=1.1)
    vein = m.box(m.glow, 0.03, 0.13, 0.02)
    m.ring_of(m.features(), 0.26, lambda i, x, z, a: m.put(
        "Vein%d" % (i + 1), vein, x=x, y=base + 0.12, z=z, ry=a, shadow=False))
    collar(m, base + 0.28, 0.19, 0.25)
    m.pivot("Turret", ".", y=base + 0.56)
    # The arm is a PIVOT so a recoil along its local Z travels back down its
    # own line rather than sideways through it. It sits ABOVE the boulder stack
    # rather than beside it, or the only part that says "tower" is hidden.
    m.pivot("Arm", "Turret")
    m.put("Sling", m.box(m.deep, 0.09, 0.09, 0.26), parent="Turret/Arm", z=-0.10)
    m.put("Boulder", m.gem(m.pale, 0.10, 0.18, 5, 3), parent="Turret/Arm", z=-0.22)
    m.put("BoulderGlow", m.gem(m.glow, 0.05, 0.09, 5, 2), parent="Turret/Arm",
          y=0.05, z=-0.22, shadow=False)
    m.pivot("Muzzle", "Turret", z=-0.30)
    return base + 0.64


def build_arcane_base(m):
    """Apprentice / Sorcerer: a worked pedestal under a floating rune slab.

    Four sided and precise, which is the opposite of Void's organic mound - the
    two elements are the closest in hue in the whole roster, so they are pulled
    as far apart as possible in everything else.
    """
    base = plinth(m, 0.28, 0.25, 0.15, 4)
    m.put("Pedestal", m.cyl(m.body, 0.16, 0.23, 0.34, 4), y=base + 0.17)
    runes(m, 4, 0.18, base + 0.20, (0.035, 0.18, 0.02))
    collar(m, base + 0.34, 0.13, 0.20)
    m.pivot("Turret", ".", y=base + 0.54)
    m.put("Slab", m.cyl(m.pale, 0.16, 0.16, 0.06, 4), parent="Turret", ry=0.785)
    m.put("SlabCore", m.gem(m.glow, 0.09, 0.20, 4, 2), parent="Turret",
          shadow=False)
    mote = m.gem(m.glow, 0.03, 0.06, 4, 2)
    m.pivot("Motes", "Turret")
    m.ring_of(3 if m.ti < 1 else 5, 0.21, lambda i, x, z, a: m.put(
        "Mote%d" % (i + 1), mote, parent="Turret/Motes", x=x, z=z, shadow=False))
    m.spinner("MoteSpin", "Turret/Motes", 0.3)
    m.bobber("Bob", "Turret", 0.03, 0.28)
    m.pivot("Muzzle", "Turret", z=-0.16)
    return base + 0.70


def build_primal_base(m):
    """Quarry / Coreway: a cut block of stone in a frame of bone and hide.

    The economy element, so the read is a WORKING thing rather than a weapon: a
    quarried block with a sling arm, and one warm vein in it that says there is
    something worth digging out.
    """
    base = plinth(m, 0.33, 0.30, 0.14, 6)
    m.put("Block", m.box(m.body, 0.40, 0.26, 0.40), y=base + 0.13)
    m.put("Cut", m.box(m.pale, 0.30, 0.06, 0.30), y=base + 0.27)
    m.put("Vein", m.box(m.glow, 0.26, 0.02, 0.05), y=base + 0.30, shadow=False)
    frame = m.capsule(m.deep, 0.04, 0.30, 5, 2)
    m.ring_of(m.features() + 1, 0.24, lambda i, x, z, a: m.put(
        "Frame%d" % (i + 1), frame, x=x, y=base + 0.16, z=z, ry=a, rx=0.4))
    collar(m, base + 0.28, 0.20, 0.26)
    m.pivot("Turret", ".", y=base + 0.34)
    m.pivot("Arm", "Turret")
    m.put("Beam", m.box(m.deep, 0.07, 0.07, 0.30), parent="Turret/Arm", z=-0.12)
    m.put("Basket", m.cyl(m.pale, 0.11, 0.07, 0.10, 6), parent="Turret/Arm",
          y=0.05, z=-0.25)
    breathe(m, "Turret", 0.012, 0.18)
    m.pivot("Muzzle", "Turret", y=0.06, z=-0.30)
    return base + 0.52


# --- Fire ------------------------------------------------------------------

def build_doom_guard(m):
    """Fire 1: three basalt claws holding a burning orb that calls meteors.

    Nothing on it points at the ground. That is the same trick the anti-air
    Turret branch uses in the Basic roster: a tower whose damage comes from the
    SKY should not look like it is aiming along one.
    """
    base = plinth(m, 0.33, 0.29, 0.16, 6)
    m.put("Stem", m.cyl(m.body, 0.16, 0.26, 0.34, 6), y=base + 0.17)
    claw = m.prism(m.deep, 0.10, 0.42, 0.09)
    m.ring_of(3, 0.17, lambda i, x, z, a: m.put(
        "Claw%d" % (i + 1), claw, x=x, y=base + 0.42, z=z, ry=a, rx=-0.22))
    collar(m, base + 0.34, 0.17, 0.24)
    bolts(m, base + 0.24, 0.25)
    crown(m, base + 0.36, 0.24)
    m.pivot("Turret", ".", y=base + 0.72)
    m.pivot("Orb", "Turret")
    m.put("Core", m.gem(m.glow, 0.19, 0.38, 8, 4), parent="Turret/Orb",
          shadow=False)
    m.put("Shell", m.torus(m.pale, 0.19, 0.235, 12, 5), parent="Turret/Orb",
          rx=1.5708, shadow=False)
    ember = m.gem(m.glow, 0.04, 0.08, 5, 2)
    m.pivot("Embers", "Turret")
    m.ring_of(m.features(), 0.29, lambda i, x, z, a: m.put(
        "Ember%d" % (i + 1), ember, parent="Turret/Embers", x=x, z=z, shadow=False))
    m.spinner("EmberSpin", "Turret/Embers", 0.18)
    m.pivot("Muzzle", "Turret", y=0.20)
    halo(m, base + 1.44)
    return base + 0.96


def build_firelord(m):
    """Fire 2: a burning body with plume arms, standing on a molten base.

    The user's brief for the reference art was to keep the Firelord reading as
    a LIVING thing while giving it a base a tower can stand on. So the plinth
    is a proper one and everything above it is flame - and nothing about it is
    symmetrical the way the Doom Guard's claws are.
    """
    base = plinth(m, 0.32, 0.30, 0.15, 6)
    m.put("Pool", m.cyl(m.glow, 0.24, 0.26, 0.04, 6), y=base + 0.02, shadow=False)
    m.put("Legs", m.cyl(m.deep, 0.17, 0.25, 0.22, 6), y=base + 0.11)
    collar(m, base + 0.22, 0.18, 0.25)
    bolts(m, base + 0.12, 0.26)
    crown(m, base + 0.24, 0.23)
    m.pivot("Turret", ".", y=base + 0.34)
    m.put("Torso", m.capsule(m.pale, 0.15, 0.36, 6, 3), parent="Turret", y=0.14)
    m.pivot("Core", "Turret", y=0.18)
    m.put("Heart", m.gem(m.glow, 0.115, 0.26, 6, 3), parent="Turret/Core",
          z=-0.05, shadow=False)
    plume = m.prism(m.glow, 0.09, 0.34, 0.06)
    m.ring_of(m.features(), 0.20, lambda i, x, z, a: m.put(
        "Plume%d" % (i + 1), plume, parent="Turret", x=x, y=0.24, z=z, ry=a,
        rx=-0.3, shadow=False))
    m.put("Head", m.gem(m.pale, 0.09, 0.17, 6, 3), parent="Turret", y=0.40)
    m.pivot("Muzzle", "Turret", y=0.20, z=-0.18)
    halo(m, base + 1.26)
    return base + 0.80


# --- Ice -------------------------------------------------------------------

def build_lich(m):
    """Ice 1: the base obelisk split open around a frozen core.

    A direct continuation of the base pair rather than a new object, which is
    the reference art's own progression: the spire is still there, it has just
    cracked and something has got out.
    """
    base = plinth(m, 0.30, 0.27, 0.15, 4)
    half = m.cyl(m.body, 0.09, 0.16, 0.60, 4)
    m.put("SpireL", half, x=-0.13, y=base + 0.30, rz=0.12)
    m.put("SpireR", half, x=0.13, y=base + 0.30, rz=-0.12)
    m.put("Cradle", m.cyl(m.deep, 0.20, 0.24, 0.14, 4), y=base + 0.07)
    collar(m, base + 0.14, 0.20, 0.26)
    bolts(m, base + 0.08, 0.26)
    crown(m, base + 0.20, 0.25)
    m.pivot("Turret", ".", y=base + 0.48)
    m.put("Core", m.gem(m.glow, 0.16, 0.40, 4, 3), parent="Turret", shadow=False)
    m.put("Cage", m.torus(m.trim, 0.155, 0.185, 10, 4), parent="Turret",
          rx=1.5708, shadow=False)
    shard = m.gem(m.pale, 0.05, 0.26, 4, 2)
    m.pivot("Shards", "Turret")
    m.ring_of(m.features(), 0.26, lambda i, x, z, a: m.put(
        "Shard%d" % (i + 1), shard, parent="Turret/Shards", x=x, z=z, rz=0.28))
    m.spinner("ShardSpin", "Turret/Shards", 0.16)
    m.bobber("Bob", "Turret", 0.026, 0.3)
    m.pivot("Muzzle", "Turret", z=-0.20)
    halo(m, base + 1.26)
    return base + 0.84


def build_crystal(m):
    """Ice 2: a cluster of spikes, one of which is aimed at whatever it shoots.

    The whole path is one shape at three counts - one spike, three, then a
    thicket - which is exactly what the reference art does and is the clearest
    tier read of any path in the roster.
    """
    base = plinth(m, 0.31, 0.28, 0.14, 4)
    m.put("Bed", m.cyl(m.deep, 0.22, 0.28, 0.16, 4), y=base + 0.08)
    collar(m, base + 0.16, 0.21, 0.27)
    bolts(m, base + 0.08, 0.28)
    crown(m, base + 0.18, 0.26)
    spike = m.gem(m.body, 0.075, 0.52, 4, 2)
    m.ring_of(m.features(), 0.19, lambda i, x, z, a: m.put(
        "Crystal%d" % (i + 1), spike, x=x, y=base + 0.36, z=z,
        rx=0.24 * math.cos(a), rz=-0.24 * math.sin(a)))
    m.pivot("Turret", ".", y=base + 0.28)
    m.pivot("Spike", "Turret")
    m.put("Lance", m.gem(m.pale, 0.085, 0.70, 4, 2), parent="Turret/Spike",
          y=0.30, z=-0.06)
    m.put("LanceCore", m.gem(m.glow, 0.05, 0.46, 4, 2), parent="Turret/Spike",
          y=0.32, z=-0.06, shadow=False)
    m.pivot("Muzzle", "Turret", y=0.60, z=-0.10)
    halo(m, base + 1.24)
    return base + 0.82


# --- Lightning --------------------------------------------------------------

def build_annihilation_glyph(m):
    """Lightning 1: a monolith slab inside a ring of runic plates that turns.

    The reference art's 30,000g tower is a spinning monolith and the user
    picked it out as the best of the three, so the whole path is built to it -
    the ring is there from the first tier and only gains plates.
    """
    base = plinth(m, 0.32, 0.29, 0.16, 8)
    m.put("Slab", m.box(m.body, 0.26, 0.76, 0.16), y=base + 0.38)
    # A glyph on EVERY face rather than one. With a single lit face the tower
    # was a dark grey box from three quarters of the angles a maze is seen at,
    # which is the whole reason it was hard to tell from an Orb Keeper.
    face = m.box(m.glow, 0.14, 0.50, 0.02)
    m.put("SlabFaceF", face, y=base + 0.40, z=-0.09, shadow=False)
    m.put("SlabFaceB", face, y=base + 0.40, z=0.09, shadow=False)
    side = m.box(m.glow, 0.02, 0.50, 0.08)
    m.put("SlabFaceL", side, x=-0.14, y=base + 0.40, shadow=False)
    m.put("SlabFaceR", side, x=0.14, y=base + 0.40, shadow=False)
    m.put("Cap", m.cyl(m.pale, 0.06, 0.16, 0.10, 8), y=base + 0.80)
    m.put("CapCore", m.gem(m.glow, 0.075, 0.16, 6, 3), y=base + 0.86,
          shadow=False)
    collar(m, base + 0.16, 0.22, 0.29)
    bolts(m, base + 0.08, 0.29)
    crown(m, base + 0.20, 0.27)
    m.pivot("Turret", ".", y=base + 0.34)
    m.pivot("Spinner", "Turret")
    plate = m.box(m.trim, 0.05, 0.20, 0.03)
    m.ring_of(m.features() + 2, 0.26, lambda i, x, z, a: m.put(
        "Plate%d" % (i + 1), plate, parent="Turret/Spinner", x=x, z=z, ry=a,
        shadow=False))
    m.put("Ring", m.torus(m.trim, 0.24, 0.27, 18, 5), parent="Turret/Spinner",
          shadow=False)
    m.pivot("Muzzle", "Turret", y=0.50, z=-0.12)
    halo(m, base + 1.32)
    return base + 0.92


def build_orb_keeper(m):
    """Lightning 2: a caged orb on a short pylon.

    Short range and a very fast attack, so it is the SQUATTEST thing in the
    element - a player should be able to tell an Orb Keeper from an
    Annihilation Glyph across a maze without reading either.
    """
    base = plinth(m, 0.34, 0.31, 0.15, 8)
    m.put("Pylon", m.cyl(m.body, 0.19, 0.28, 0.26, 8), y=base + 0.13)
    m.put("Shoulder", m.cyl(m.pale, 0.21, 0.17, 0.08, 8), y=base + 0.30)
    collar(m, base + 0.26, 0.19, 0.26)
    bolts(m, base + 0.13, 0.28)
    crown(m, base + 0.28, 0.25)
    m.pivot("Turret", ".", y=base + 0.52)
    m.put("Orb", m.gem(m.glow, 0.155, 0.32, 8, 4), parent="Turret", shadow=False)
    m.pivot("Cage", "Turret")
    m.put("CageA", m.torus(m.trim, 0.165, 0.195, 12, 4), parent="Turret/Cage",
          rx=1.5708, shadow=False)
    m.put("CageB", m.torus(m.trim, 0.165, 0.195, 12, 4), parent="Turret/Cage",
          rx=1.5708, ry=1.0472, shadow=False)
    m.put("CageC", m.torus(m.trim, 0.165, 0.195, 12, 4), parent="Turret/Cage",
          rx=1.5708, ry=2.0944, shadow=False)
    arc = m.box(m.glow, 0.02, 0.20, 0.02)
    m.ring_of(m.features(), 0.24, lambda i, x, z, a: m.put(
        "Arc%d" % (i + 1), arc, parent="Turret", x=x, y=-0.16, z=z, shadow=False))
    m.pivot("Muzzle", "Turret", z=-0.20)
    halo(m, base + 1.18)
    return base + 0.76


# --- Holy ------------------------------------------------------------------

def build_divineshroom(m):
    """Holy 1: a mushroom whose cap is tilted at the sky.

    The anti-air path, and it says so the way the Basic roster's anti-air
    branch does: NOTHING on it points at the ground. The cap is angled upwards
    and the spores go with it, so a player reads what it can shoot before
    paying for one. The user asked for shrooms and the source art has them.
    """
    base = plinth(m, 0.31, 0.28, 0.14, 8)
    m.put("Bulb", m.capsule(m.deep, 0.13, 0.26, 6, 3), y=base + 0.13)
    m.put("Stalk", m.cyl(m.body, 0.10, 0.15, 0.40, 8), y=base + 0.30)
    m.put("Skirt", m.cyl(m.pale, 0.20, 0.11, 0.05, 8), y=base + 0.40)
    collar(m, base + 0.44, 0.10, 0.16)
    bolts(m, base + 0.24, 0.17)
    crown(m, base + 0.36, 0.19)
    m.pivot("Turret", ".", y=base + 0.62)
    # The cap is a pivot so the prefab's recoil rocks the whole head rather
    # than sliding the mesh out of its own stalk.
    m.pivot("Cap", "Turret", rx=-0.42)
    # The cap takes the DEEP tone. Ivory with a gold rim on ivory stone read as
    # one pale disc; a dark cap with a lit rim under it reads as a mushroom.
    m.put("Head", m.gem(m.deep, 0.30, 0.32, 8, 3), parent="Turret/Cap", y=0.10)
    m.put("Rim", m.torus(m.glow, 0.25, 0.30, 16, 5), parent="Turret/Cap",
          y=0.03, shadow=False)
    m.put("Crest", m.gem(m.glow, 0.11, 0.16, 6, 2), parent="Turret/Cap", y=0.21,
          shadow=False)
    gill = m.prism(m.glow, 0.06, 0.16, 0.03)
    m.ring_of(m.features() + 2, 0.20, lambda i, x, z, a: m.put(
        "Gill%d" % (i + 1), gill, parent="Turret/Cap", x=x, y=0.02, z=z, ry=a,
        rx=3.1416, shadow=False))
    m.pivot("Muzzle", "Turret", y=0.32, z=-0.22)
    halo(m, base + 1.30)
    return base + 0.90


def build_titan_vault(m):
    """Holy 2: a gold plated vault on a column, with a lens on its face.

    The reference art's top tier is a golden chest and the tiers below it are a
    beam tower, so this is both: a vault that has opened just far enough to
    aim. It is the support tower of the whole game, so what it wants to read as
    is something VALUABLE standing behind the maze rather than in it.
    """
    base = plinth(m, 0.32, 0.29, 0.16, 8)
    m.put("Column", m.cyl(m.body, 0.19, 0.26, 0.36, 8), y=base + 0.18)
    collar(m, base + 0.36, 0.17, 0.24)
    bolts(m, base + 0.20, 0.26)
    crown(m, base + 0.34, 0.24)
    m.pivot("Turret", ".", y=base + 0.52)
    # The vault body takes the DEEP tone rather than the pale one: gold bands
    # and a gold lens on bright ivory was two shades of the same thing, and the
    # tower read as a lump of metal with no element in it.
    m.put("Vault", m.box(m.deep, 0.36, 0.30, 0.30), parent="Turret", y=0.12)
    m.put("VaultLid", m.box(m.trim, 0.38, 0.05, 0.32), parent="Turret", y=0.28,
          shadow=False)
    band = m.box(m.trim, 0.05, 0.32, 0.32)
    m.put("BandL", band, parent="Turret", x=-0.13, y=0.12, shadow=False)
    m.put("BandR", band, parent="Turret", x=0.13, y=0.12, shadow=False)
    m.pivot("Lens", "Turret", y=0.12, z=-0.15)
    m.put("Eye", m.gem(m.glow, 0.10, 0.14, 8, 3), parent="Turret/Lens",
          shadow=False)
    m.put("EyeRing", m.torus(m.trim, 0.10, 0.13, 10, 4), parent="Turret/Lens",
          rx=1.5708, shadow=False)
    beam = m.box(m.glow, 0.02, 0.20, 0.02)
    m.ring_of(m.features(), 0.23, lambda i, x, z, a: m.put(
        "Beam%d" % (i + 1), beam, parent="Turret", x=x, y=0.34, z=z, shadow=False))
    m.pivot("Muzzle", "Turret", y=0.12, z=-0.24)
    halo(m, base + 1.24)
    return base + 0.84


# --- Void -------------------------------------------------------------------

def build_harbinger(m):
    """Void 1: a hide spire with a rift eye in it.

    The Void towers are the ones the user asked to make structural without
    stopping being alive, so this is a SPIRE - upright, with a footprint, and a
    silhouette a maze can be built out of - made entirely of capsules and
    carapace ribs, and breathing.
    """
    base = plinth(m, 0.28, 0.26, 0.14, 6)
    # Narrow and TALL. A wide mound read as a bigger Voidalisk, which is the
    # one thing a path silhouette must never do - the base pair is what it has
    # to be told apart from.
    m.put("Body", m.capsule(m.body, 0.135, 0.84, 8, 3), y=base + 0.42)
    rib = m.prism(m.deep, 0.07, 0.40, 0.055)
    m.ring_of(m.features() + 1, 0.14, lambda i, x, z, a: m.put(
        "Rib%d" % (i + 1), rib, x=x, y=base + 0.26, z=z, ry=a, rx=-0.14))
    collar(m, base + 0.56, 0.115, 0.175)
    bolts(m, base + 0.30, 0.19)
    crown(m, base + 0.54, 0.18)
    m.pivot("Turret", ".", y=base + 0.86)
    m.pivot("Eye", "Turret")
    # The socket sits BEHIND the rift rather than around it, so the lit part is
    # the part facing whatever the tower is shooting.
    m.put("Socket", m.gem(m.pale, 0.135, 0.24, 6, 3), parent="Turret/Eye",
          z=0.04)
    m.put("Rift", m.gem(m.glow, 0.115, 0.24, 6, 3), parent="Turret/Eye",
          z=-0.06, shadow=False)
    m.put("RiftRing", m.torus(m.trim, 0.115, 0.145, 12, 4), parent="Turret/Eye",
          rx=1.5708, z=-0.08, shadow=False)
    horn = m.capsule(m.pale, 0.035, 0.32, 5, 2)
    m.ring_of(3, 0.13, lambda i, x, z, a: m.put(
        "Horn%d" % (i + 1), horn, parent="Turret", x=x, y=0.14, z=z, ry=a,
        rx=-0.7))
    breathe(m, "Turret", 0.022, 0.2)
    m.pivot("Muzzle", "Turret", z=-0.20)
    halo(m, base + 1.54)
    return base + 1.06


def build_leviathan(m):
    """Void 2: a maw ringed with lashes that turn.

    The armour-eating path, so what it reads as is a MOUTH: a low gullet with a
    ring of tentacles around it that never stops moving. It is the one tower in
    the roster whose moving part IS its attack, which is what lets the motion
    be as loud as it is - see roster.ANIMATION's spin entry.
    """
    base = plinth(m, 0.34, 0.32, 0.13, 6)
    m.put("Mound", m.capsule(m.body, 0.27, 0.24, 8, 3), y=base + 0.11)
    collar(m, base + 0.20, 0.24, 0.30)
    bolts(m, base + 0.10, 0.31)
    crown(m, base + 0.22, 0.27)
    m.pivot("Turret", ".", y=base + 0.26)
    m.put("Maw", m.cyl(m.deep, 0.20, 0.14, 0.14, 8), parent="Turret", y=0.05)
    m.put("Gullet", m.gem(m.glow, 0.14, 0.20, 8, 3), parent="Turret", y=0.10,
          shadow=False)
    tooth = m.prism(m.pale, 0.05, 0.16, 0.04)
    m.ring_of(m.features() + 2, 0.19, lambda i, x, z, a: m.put(
        "Tooth%d" % (i + 1), tooth, parent="Turret", x=x, y=0.10, z=z, ry=a,
        rx=-0.5))
    m.pivot("Lashes", "Turret", y=0.06)
    lash = m.capsule(m.pale, 0.045, 0.40, 5, 2)
    m.ring_of(m.features() + 1, 0.26, lambda i, x, z, a: m.put(
        "Lash%d" % (i + 1), lash, parent="Turret/Lashes", x=x, y=0.06, z=z,
        ry=a, rx=0.85))
    breathe(m, "Turret", 0.018, 0.26)
    m.pivot("Muzzle", "Turret", y=0.14, z=-0.14)
    halo(m, base + 1.10)
    return base + 0.62


# --- Unholy -----------------------------------------------------------------

def build_gravedigger(m):
    """Unholy 1: an open grave with something breathing in it.

    Stays LOW, the way the base pair is low, and grows sideways instead of
    upwards: a wider pit, more ribs, more spouts. That is what keeps the two
    Unholy paths apart at a glance, because the Alchemist goes straight up.
    """
    base = plinth(m, 0.35, 0.33, 0.13, 6)
    m.put("Pit", m.cyl(m.body, 0.31, 0.28, 0.18, 6), y=base + 0.09)
    m.put("Sludge", m.cyl(m.glow, 0.26, 0.26, 0.03, 6), y=base + 0.17,
          shadow=False)
    rib = m.capsule(m.pale, 0.04, 0.34, 5, 2)
    m.ring_of(m.features() + 2, 0.29, lambda i, x, z, a: m.put(
        "Rib%d" % (i + 1), rib, x=x, y=base + 0.17, z=z, ry=a, rx=0.45))
    collar(m, base + 0.18, 0.27, 0.33)
    bolts(m, base + 0.09, 0.33)
    crown(m, base + 0.20, 0.29)
    m.pivot("Turret", ".", y=base + 0.22)
    m.put("Bloom", m.capsule(m.deep, 0.13, 0.24, 6, 3), parent="Turret", y=0.10)
    petal = m.prism(m.pale, 0.11, 0.22, 0.06)
    m.ring_of(m.features(), 0.12, lambda i, x, z, a: m.put(
        "Petal%d" % (i + 1), petal, parent="Turret", x=x, y=0.20, z=z, ry=a,
        rx=-0.55))
    m.put("Sac", m.gem(m.glow, 0.10, 0.20, 6, 3), parent="Turret", y=0.24,
          shadow=False)
    breathe(m, "Turret", 0.02, 0.22)
    m.pivot("Muzzle", "Turret", y=0.28, z=-0.10)
    # Lower than everything else in the roster, so its halo has to clear the
    # tower by more than the tower is tall or it sits inside the bloom.
    halo(m, base + 1.02)
    return base + 0.58


def build_alchemist(m):
    """Unholy 2: a still - a bone frame carrying a flask it swings.

    Tall and narrow against the Gravedigger's low pit, and the only Unholy
    tower with a hard silhouette: the frame is bone rather than plating, but it
    is a FRAME, which is what says this one was made on purpose.
    """
    base = plinth(m, 0.30, 0.28, 0.15, 6)
    m.put("Vat", m.cyl(m.body, 0.20, 0.25, 0.28, 6), y=base + 0.14)
    m.put("VatTop", m.cyl(m.pale, 0.16, 0.20, 0.06, 6), y=base + 0.30)
    m.put("Brew", m.cyl(m.glow, 0.14, 0.14, 0.03, 6), y=base + 0.33, shadow=False)
    leg = m.capsule(m.deep, 0.035, 0.40, 5, 2)
    m.ring_of(m.features(), 0.22, lambda i, x, z, a: m.put(
        "Leg%d" % (i + 1), leg, x=x, y=base + 0.38, z=z, ry=a, rx=0.2))
    collar(m, base + 0.34, 0.16, 0.23)
    bolts(m, base + 0.18, 0.25)
    crown(m, base + 0.36, 0.23)
    m.pivot("Turret", ".", y=base + 0.58)
    m.pivot("Arm", "Turret")
    m.put("Boom", m.box(m.deep, 0.07, 0.07, 0.30), parent="Turret/Arm", z=-0.12)
    m.put("Flask", m.gem(m.pale, 0.13, 0.24, 6, 3), parent="Turret/Arm", z=-0.26)
    m.put("FlaskCore", m.gem(m.glow, 0.085, 0.16, 6, 3), parent="Turret/Arm",
          z=-0.26, shadow=False)
    m.put("Neck", m.cyl(m.pale, 0.04, 0.06, 0.10, 6), parent="Turret/Arm",
          y=0.14, z=-0.26)
    breathe(m, "Turret", 0.014, 0.18)
    m.pivot("Muzzle", "Turret", z=-0.36)
    halo(m, base + 1.22)
    return base + 0.80


# --- Water ------------------------------------------------------------------

def build_hurricane_elemental(m):
    """Water 1: a turning column of water standing in a basin.

    The user's brief was to keep the water elemental reading as a living thing
    on a base a tower can stand on, so it is a vortex - stacked rings that turn
    - with a core in it and arms of water thrown out. Nothing about it is
    plated, and the only hard edges on it are its basin.
    """
    base = plinth(m, 0.33, 0.31, 0.14, 8)
    m.put("Basin", m.cyl(m.body, 0.31, 0.29, 0.14, 8), y=base + 0.07)
    m.put("Lip", m.torus(m.pale, 0.27, 0.32, 16, 5), y=base + 0.14)
    collar(m, base + 0.14, 0.28, 0.34)
    bolts(m, base + 0.07, 0.32)
    crown(m, base + 0.16, 0.29)
    m.pivot("Turret", ".", y=base + 0.20)
    m.pivot("Vortex", "Turret")
    for index in range(4):
        radius = 0.24 - index * 0.045
        m.put("Coil%d" % (index + 1),
              m.torus(m.pale, radius - 0.05, radius, 14, 5),
              parent="Turret/Vortex", y=0.06 + index * 0.13,
              ry=index * 0.5, shadow=False)
    m.put("Core", m.gem(m.glow, 0.115, 0.44, 8, 4), parent="Turret", y=0.28,
          shadow=False)
    arm = m.capsule(m.pale, 0.05, 0.30, 6, 2)
    m.ring_of(m.features(), 0.25, lambda i, x, z, a: m.put(
        "Arm%d" % (i + 1), arm, parent="Turret", x=x, y=0.24, z=z, ry=a,
        rx=1.0))
    m.put("Head", m.gem(m.glow, 0.09, 0.16, 6, 3), parent="Turret", y=0.58,
          shadow=False)
    breathe(m, "Turret", 0.024, 0.3)
    m.pivot("Muzzle", "Turret", y=0.34, z=-0.18)
    halo(m, base + 1.36)
    return base + 0.92


def build_sludge_monstrosity(m):
    """Water 2: a slumped mound of sludge sitting in its own spreading pool.

    The one tower in the roster whose ABILITY is a radius on the floor and
    nothing else, so it is built around a pool that is deliberately WIDER than
    the mound standing in it - the eye is taught to read the ground around this
    tower before the tower itself. The pool is drawn, not measured: the real
    radius is on the passive.
    """
    base = plinth(m, 0.36, 0.34, 0.11, 8)
    m.put("Pool", m.cyl(m.glow, 0.36, 0.38, 0.025, 10), y=base + 0.01,
          shadow=False)
    m.put("PoolRim", m.torus(m.deep, 0.34, 0.40, 18, 5), y=base + 0.02)
    m.put("Mound", m.capsule(m.body, 0.26, 0.26, 8, 3), y=base + 0.14)
    m.put("Hump", m.capsule(m.pale, 0.15, 0.18, 6, 3), y=base + 0.26, z=-0.06)
    collar(m, base + 0.20, 0.25, 0.31)
    bolts(m, base + 0.10, 0.33)
    crown(m, base + 0.24, 0.28)
    m.pivot("Turret", ".", y=base + 0.30)
    vent = m.cyl(m.pale, 0.055, 0.085, 0.14, 6)
    m.ring_of(m.features() + 1, 0.16, lambda i, x, z, a: m.put(
        "Vent%d" % (i + 1), vent, parent="Turret", x=x, y=0.05, z=z))
    bubble = m.gem(m.glow, 0.05, 0.10, 6, 2)
    m.ring_of(m.features() + 1, 0.16, lambda i, x, z, a: m.put(
        "Bubble%d" % (i + 1), bubble, parent="Turret", x=x, y=0.14, z=z,
        shadow=False))
    m.put("Eye", m.gem(m.glow, 0.075, 0.14, 6, 3), parent="Turret", y=0.10,
          z=-0.16, shadow=False)
    breathe(m, "Turret", 0.02, 0.16)
    m.pivot("Muzzle", "Turret", y=0.14, z=-0.20)
    halo(m, base + 1.06)
    return base + 0.58


# --- Earth ------------------------------------------------------------------

def build_ancient_warden(m):
    """Earth 1: a fortified trunk with a canopy and one arm that throws.

    This is the tower a player puts at the FRONT of a maze to be chewed on, so
    it is the widest and heaviest thing in the roster - a trunk with bark
    plates, roots gripping the plinth, and a canopy over it. The arm is what
    makes it a tower rather than scenery.
    """
    base = plinth(m, 0.36, 0.33, 0.16, 5)
    m.put("Trunk", m.cyl(m.body, 0.20, 0.28, 0.44, 5), y=base + 0.22)
    root = m.prism(m.deep, 0.10, 0.20, 0.09)
    m.ring_of(m.features() + 2, 0.28, lambda i, x, z, a: m.put(
        "Root%d" % (i + 1), root, x=x, y=base + 0.08, z=z, ry=a, rx=-0.7))
    bark = m.box(m.deep, 0.06, 0.34, 0.05)
    m.ring_of(m.features() + 1, 0.24, lambda i, x, z, a: m.put(
        "Bark%d" % (i + 1), bark, x=x, y=base + 0.24, z=z, ry=a))
    collar(m, base + 0.44, 0.18, 0.26)
    bolts(m, base + 0.28, 0.27)
    crown(m, base + 0.46, 0.25)
    m.pivot("Turret", ".", y=base + 0.56)
    leaf = m.prism(m.pale, 0.22, 0.20, 0.14)
    m.ring_of(m.features() + 1, 0.20, lambda i, x, z, a: m.put(
        "Leaf%d" % (i + 1), leaf, parent="Turret", x=x, y=0.14, z=z, ry=a,
        rx=-0.3))
    m.put("Heart", m.gem(m.glow, 0.09, 0.18, 6, 3), parent="Turret", y=0.10,
          shadow=False)
    m.pivot("Arm", "Turret", y=-0.02)
    m.put("Bough", m.box(m.deep, 0.10, 0.10, 0.30), parent="Turret/Arm", z=-0.13)
    m.put("Rock", m.gem(m.pale, 0.13, 0.22, 5, 3), parent="Turret/Arm", z=-0.28)
    m.pivot("Muzzle", "Turret", z=-0.38)
    halo(m, base + 1.34)
    return base + 0.86


def build_scorpion(m):
    """Earth 2: a thorn bulb on a stalk, firing spines.

    The user asked for spiky plants rather than the source's scorpion, and the
    path is pure single target - so it is one narrow stalk with one bulb, and
    every tier adds thorns to that bulb rather than mass to the tower. It is
    the THINNEST thing in the roster, which is the read it wants next to the
    Ancient Warden it shares an element with.
    """
    base = plinth(m, 0.28, 0.25, 0.14, 5)
    m.put("Root", m.capsule(m.deep, 0.16, 0.20, 6, 3), y=base + 0.10)
    m.put("Stalk", m.cyl(m.body, 0.075, 0.13, 0.52, 5), y=base + 0.36)
    thorn = m.prism(m.pale, 0.05, 0.18, 0.04)
    m.ring_of(m.features() + 1, 0.13, lambda i, x, z, a: m.put(
        "Thorn%d" % (i + 1), thorn, x=x, y=base + 0.30, z=z, ry=a, rx=-1.0))
    collar(m, base + 0.56, 0.09, 0.15)
    bolts(m, base + 0.30, 0.15)
    crown(m, base + 0.52, 0.16)
    m.pivot("Turret", ".", y=base + 0.68)
    m.pivot("Bulb", "Turret")
    # Narrow on purpose. The two Earth paths share a palette, so the only thing
    # separating a Scorpion from an Ancient Warden across a maze is that one is
    # a wide canopy and the other is a thin stalk with spines coming off it.
    m.put("Pod", m.gem(m.body, 0.115, 0.34, 6, 3), parent="Turret/Bulb")
    m.put("PodCore", m.gem(m.glow, 0.085, 0.24, 6, 3), parent="Turret/Bulb",
          z=-0.05, shadow=False)
    spine = m.prism(m.pale, 0.035, 0.34, 0.03)
    m.ring_of(m.features(), 0.09, lambda i, x, z, a: m.put(
        "Spine%d" % (i + 1), spine, parent="Turret/Bulb", x=x, z=z - 0.10,
        ry=a, rx=-1.45))
    m.pivot("Muzzle", "Turret", z=-0.24)
    halo(m, base + 1.32)
    return base + 0.88


# --- Arcane -----------------------------------------------------------------

def build_spellslinger(m):
    """Arcane 1: a floating rune slab with a ring of sigils turning around it.

    The caster path, so everything on it is floating and nothing on it is a
    weapon: a slab, a ring of marks, and a staff spire behind. The tower has no
    barrel at all, which is the point - it does its damage with spells and its
    silhouette should not promise otherwise.
    """
    base = plinth(m, 0.30, 0.27, 0.15, 4)
    m.put("Dais", m.cyl(m.body, 0.22, 0.26, 0.20, 4), y=base + 0.10)
    m.put("Spire", m.cyl(m.pale, 0.045, 0.075, 0.66, 4), y=base + 0.46, z=0.16)
    m.put("SpireTip", m.gem(m.glow, 0.07, 0.16, 4, 2), y=base + 0.82, z=0.16,
          shadow=False)
    runes(m, 4, 0.21, base + 0.12, (0.035, 0.14, 0.02))
    collar(m, base + 0.20, 0.23, 0.29)
    bolts(m, base + 0.10, 0.28)
    crown(m, base + 0.22, 0.26)
    m.pivot("Turret", ".", y=base + 0.48)
    m.put("Slab", m.cyl(m.pale, 0.20, 0.20, 0.055, 4), parent="Turret", ry=0.785)
    m.put("SlabCore", m.gem(m.glow, 0.115, 0.26, 4, 2), parent="Turret",
          shadow=False)
    m.pivot("Sigils", "Turret")
    sigil = m.box(m.trim, 0.045, 0.13, 0.02)
    m.ring_of(m.features() + 2, 0.26, lambda i, x, z, a: m.put(
        "Sigil%d" % (i + 1), sigil, parent="Turret/Sigils", x=x, z=z, ry=a,
        shadow=False))
    m.bobber("Bob", "Turret", 0.032, 0.26)
    m.pivot("Muzzle", "Turret", z=-0.22)
    halo(m, base + 1.30)
    return base + 0.92


def build_arcane_orb(m):
    """Arcane 2: a crystalline pylon holding an orb with shards around it.

    The reference art's own progression - a pylon, then a runeforged sentry,
    then a glowing rock - so the orb is there from the first tier and the pylon
    around it is what grows. Squarer and heavier than the Spellslinger, which
    floats.
    """
    base = plinth(m, 0.32, 0.29, 0.16, 4)
    m.put("Pylon", m.cyl(m.body, 0.14, 0.26, 0.46, 4), y=base + 0.23)
    buttress = m.prism(m.deep, 0.09, 0.30, 0.07)
    m.ring_of(4, 0.22, lambda i, x, z, a: m.put(
        "Buttress%d" % (i + 1), buttress, x=x, y=base + 0.16, z=z, ry=a))
    collar(m, base + 0.46, 0.13, 0.20)
    bolts(m, base + 0.28, 0.22)
    crown(m, base + 0.44, 0.21)
    m.pivot("Turret", ".", y=base + 0.62)
    m.put("Orb", m.gem(m.glow, 0.175, 0.36, 6, 4), parent="Turret", shadow=False)
    m.put("OrbBand", m.torus(m.trim, 0.175, 0.21, 12, 5), parent="Turret",
          rx=1.5708, shadow=False)
    m.pivot("Shards", "Turret")
    shard = m.gem(m.pale, 0.055, 0.28, 4, 2)
    m.ring_of(m.features() + 1, 0.27, lambda i, x, z, a: m.put(
        "Shard%d" % (i + 1), shard, parent="Turret/Shards", x=x, z=z, rz=0.32))
    m.pivot("Muzzle", "Turret", z=-0.24)
    halo(m, base + 1.30)
    return base + 0.86


# --- Primal -----------------------------------------------------------------

def build_primalist(m):
    """Primal 1: an altar with a gold veined geode standing open on it.

    The gold making tower, so it says GOLD: the geode is the only thing in the
    element that is not red, and the trim veins over it are the tier metal
    itself. It is also the only tower with a reason to be spread out rather
    than packed together, so it wants to be recognisable one at a time.
    """
    base = plinth(m, 0.33, 0.30, 0.15, 6)
    m.put("Altar", m.cyl(m.body, 0.24, 0.29, 0.24, 6), y=base + 0.12)
    m.put("Table", m.cyl(m.pale, 0.26, 0.23, 0.06, 6), y=base + 0.26)
    vine = m.capsule(m.deep, 0.035, 0.30, 5, 2)
    m.ring_of(m.features() + 1, 0.27, lambda i, x, z, a: m.put(
        "Vine%d" % (i + 1), vine, x=x, y=base + 0.14, z=z, ry=a, rx=0.35))
    collar(m, base + 0.28, 0.22, 0.29)
    bolts(m, base + 0.14, 0.29)
    crown(m, base + 0.30, 0.27)
    m.pivot("Turret", ".", y=base + 0.36)
    m.pivot("Geode", "Turret")
    # Deliberately oversized. The gold is the whole point of this tower and it
    # is the only thing telling it from a Beastmaster at a glance.
    m.put("Shell", m.gem(m.pale, 0.24, 0.40, 6, 3), parent="Turret/Geode",
          y=0.14)
    m.put("Cavity", m.gem(m.glow, 0.175, 0.32, 6, 3), parent="Turret/Geode",
          y=0.16, z=-0.08, shadow=False)
    vein = m.box(m.trim, 0.02, 0.22, 0.02)
    m.ring_of(m.features() + 2, 0.17, lambda i, x, z, a: m.put(
        "Vein%d" % (i + 1), vein, parent="Turret/Geode", x=x, y=0.10, z=z,
        ry=a, shadow=False))
    breathe(m, "Turret", 0.014, 0.18)
    m.pivot("Muzzle", "Turret", y=0.14, z=-0.20)
    halo(m, base + 1.20)
    return base + 0.68


def build_beastmaster(m):
    """Primal 2: a bone totem with a pair of horns it swings forward.

    The horns are what the beast comes out of, so they are the whole
    silhouette: forward facing, on a pivot, and swung on the windup. Against
    the Primalist's round altar it is all verticals, which is the read the two
    Primal paths need from each other.
    """
    base = plinth(m, 0.32, 0.29, 0.15, 6)
    m.put("Post", m.cyl(m.body, 0.16, 0.24, 0.40, 6), y=base + 0.20)
    m.put("Drum", m.cyl(m.deep, 0.22, 0.22, 0.16, 8), y=base + 0.14, ry=0.3)
    m.put("DrumSkin", m.cyl(m.pale, 0.20, 0.20, 0.03, 8), y=base + 0.22)
    skull = m.prism(m.pale, 0.09, 0.16, 0.07)
    m.ring_of(m.features(), 0.19, lambda i, x, z, a: m.put(
        "Skull%d" % (i + 1), skull, x=x, y=base + 0.36, z=z, ry=a))
    collar(m, base + 0.40, 0.15, 0.22)
    bolts(m, base + 0.24, 0.23)
    crown(m, base + 0.42, 0.22)
    m.pivot("Turret", ".", y=base + 0.54)
    m.pivot("Horns", "Turret")
    m.put("Brow", m.box(m.pale, 0.26, 0.10, 0.14), parent="Turret/Horns",
          z=-0.06)
    # Swept UP and out rather than forward. Pointed along the tower's facing
    # they were hidden behind the brow from every angle a maze is seen at.
    horn = m.capsule(m.pale, 0.05, 0.40, 5, 2)
    m.put("HornL", horn, parent="Turret/Horns", x=-0.17, y=0.16, z=-0.10,
          rx=0.5, rz=0.8)
    m.put("HornR", horn, parent="Turret/Horns", x=0.17, y=0.16, z=-0.10,
          rx=0.5, rz=-0.8)
    m.put("Eyes", m.box(m.glow, 0.16, 0.03, 0.02), parent="Turret/Horns",
          y=0.02, z=-0.13, shadow=False)
    breathe(m, "Turret", 0.016, 0.2)
    m.pivot("Muzzle", "Turret", z=-0.28)
    halo(m, base + 1.24)
    return base + 0.78


BUILDERS = {
    "core": build_core,
    "fire_base": build_fire_base,
    "ice_base": build_ice_base,
    "lightning_base": build_lightning_base,
    "holy_base": build_holy_base,
    "void_base": build_void_base,
    "unholy_base": build_unholy_base,
    "water_base": build_water_base,
    "earth_base": build_earth_base,
    "arcane_base": build_arcane_base,
    "primal_base": build_primal_base,

    "doom_guard": build_doom_guard,
    "firelord": build_firelord,
    "lich": build_lich,
    "crystal": build_crystal,
    "annihilation_glyph": build_annihilation_glyph,
    "orb_keeper": build_orb_keeper,
    "divineshroom": build_divineshroom,
    "titan_vault": build_titan_vault,
    "harbinger": build_harbinger,
    "leviathan": build_leviathan,
    "gravedigger": build_gravedigger,
    "alchemist": build_alchemist,
    "hurricane_elemental": build_hurricane_elemental,
    "sludge_monstrosity": build_sludge_monstrosity,
    "ancient_warden": build_ancient_warden,
    "scorpion": build_scorpion,
    "spellslinger": build_spellslinger,
    "arcane_orb": build_arcane_orb,
    "primalist": build_primalist,
    "beastmaster": build_beastmaster,
}


def generate():
    """Writes every elemental tower model and answers each one's height in
    world units, which the prefabs need for their health bar and click box."""
    os.makedirs(OUT, exist_ok=True)
    heights = {}
    for row in tower_rows():
        m = ElementModel(row["key"], row["element"], row["ti"])
        heights[row["key"]] = round(BUILDERS[row["shape"]](m) * m.h, 3)
        io.open("%s/%s_model.tscn" % (OUT, row["key"]), "w", encoding="utf-8",
                newline="\n").write(m.render())
    return heights
