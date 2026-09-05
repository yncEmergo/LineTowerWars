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
  and they are the SAME builder, growing rather than changing. They are also
  the only two towers here that carry any METAL, and the two rings on them are
  the whole of what separates them - see plinth() and collar().

  A PATH IS THREE SHAPES, not one with parts added. The 4,000g split brings a
  silhouette and every tier above it re-cuts that silhouette rather than
  bolting another ring onto it, because with the metal gone the shape is what
  says which tier this is. Read style.py, THE PATH LADDER, before touching any
  builder below the base ten.

MOTION, and a deliberate exception to the Basic roster's rule.

The Basic rule is that nothing below an Ultimate has a moving part that is not
its own attack, because motion is the loudest thing a top down camera can show.
That rule is kept: the ULTIMATE'S AURA - a slow rise of motes in the element's
own colour, from aura() - is an Ultimate's alone, at every tier of every
element, and it is what the turning metal halo used to be.

What is allowed here and is not allowed there is a SMALL, SLOW idle breath on
the elements that are alive rather than built - Void, Unholy, Water and Primal.
A creature that is perfectly still reads as dead, which is a worse lie than the
motion is a distraction. It is authored an order of magnitude smaller and
slower than the aura and sits at the middle of the model rather than at its
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

    def __init__(self, key, element, tier_index, shape=""):
        palette = ts.ELEMENTAL_CORE if element == "core" else ts.ELEMENTS[element]
        # Which rung of the element's own stone this tier is drawn in. The base
        # pair takes the authored tones; each path tier takes a rung of its
        # own, and that ramp is what replaced the tier metal - see style,
        # THE PATH LADDER.
        stone = ts.element_stone_suffix(tier_index)
        materials = {
            "body": "%s/%s_stone%s.tres" % (MAT, element, stone),
            "deep": "%s/%s_stone%s_deep.tres" % (MAT, element, stone),
            "pale": "%s/%s_stone%s_pale.tres" % (MAT, element, stone),
            "glow": "%s/energy_%s_t%d.tres" % (MAT, element, tier_index),
        }
        # The trim role is OMITTED above 800g rather than left unused, so a
        # path tier carries no load-time dependency on a metal it is forbidden
        # to draw - and so that a builder reaching for m.trim by mistake fails
        # instead of quietly putting a ring back on.
        if ts.element_has_metal(tier_index):
            materials["trim"] = "%s/element_ring_t%d.tres" % (
                MAT, ts.element_ring_index(tier_index))
        Model.__init__(
            self,
            "".join(part.capitalize() for part in key.split("_")) + "Model",
            UNIT_MODEL_SCRIPT,
            materials,
            ts.element_mass(tier_index),
            ts.element_height_scale(tier_index),
        )
        self.ti = tier_index
        self.element = element
        self.sides = palette["sides"]
        self.alive = element in LIVING

        # A sixth material role, and the ONLY one that is not the element's.
        # A path may claim one part of its own model in a colour of its own -
        # see style.PATH_ACCENTS. It falls back to `glow`, so a builder may
        # reach for it unconditionally and a path that claims nothing draws
        # exactly what it drew before.
        self.accent = self.glow
        # The raw colour behind it too, for the parts that are not a material
        # on a mesh - a particle emitter carries its own flat colour and cannot
        # take one of the five roles. See modelkit.sparks.
        self.accent_rgb = palette["glow"]
        tiers = ts.PATH_ACCENTS.get(shape, {})
        if tier_index in tiers:
            self.accent = self.scene.ext(
                "Material", "%s/energy_path_%s_t%d.tres" % (MAT, shape, tier_index))
            self.accent_rgb = tiers[tier_index][0]

    def features(self):
        """How many repeated parts this tier shows: spikes, plumes, shards."""
        return ts.ELEMENT_FEATURE_COUNT[self.ti]

    @property
    def rung(self):
        """Which of a PATH's own three tiers this is: 0, 1 or 2.

        A base tower answers 0, which is never read - the base builders branch
        on `ti` because their two tiers are 0 and 1 of the whole ladder, not of
        a path.
        """
        return max(self.ti - 2, 0)

    def step(self, lesser, greater, ultimate):
        """Pick one of a path's three values.

        The authoring idiom of the whole path section, and it exists so that a
        builder's three tiers sit on ONE LINE. Written as an `if` per part they
        drift: somebody tunes the Greater's radius, forgets the Ultimate's, and
        nothing errors because both numbers are perfectly reasonable. Written
        like this the three are read together or not at all, and a diff shows
        which tier moved.
        """
        return (lesser, greater, ultimate)[self.rung]


# --- the parts every elemental tower carries --------------------------------

def pad(m):
    """The shared ground patch, and nothing else.

    EVERY tower stands on one, including the ones with no plinth at all. The
    patch is what says a cell has been built on; a tower floating over bare
    ground reads as something passing over the maze rather than as part of it.
    See build_arcane_orb, which is the tower this was split out for.
    """
    m.scene.node("Base", None, ".", instance=m.scene.ext("PackedScene", FOUNDATION))


def plinth(m, bottom=0.34, top=0.30, height=0.16, sides=None):
    """Foundation patch, plinth, and - on the BASE PAIR only - the ring.

    The ring is the whole of what separates a 200g tower from its 800g
    upgrade, since those two are deliberately one shape at two sizes, and it
    is the only metal left in the elemental roster. Every tower from 4,000g up
    stands on the same plinth with nothing around it. See style, THE PATH
    LADDER.
    """
    pad(m)
    faces = m.sides if sides is None else sides
    m.put("Plinth", m.cyl(m.deep, top, bottom, height, faces), y=height * 0.5)
    if ts.element_has_metal(m.ti):
        m.put("BaseTrim", m.torus(m.trim, top - 0.015, top + 0.035, 14, 5),
              y=height, shadow=False)
    return height


def collar(m, at, inner=0.12, outer=0.19):
    """The SECOND ring, and the 800g tower's own tell against the 200g one.

    Two rings where there was one, in a metal two whole steps brighter. That
    pair has to carry the entire upgrade on its own, because the shape either
    side of it is the same shape - which is why the two metals are as far apart
    as style.ELEMENT_RING_RAMP puts them.
    """
    if not ts.element_has_collar(m.ti):
        return
    m.put("Collar", m.torus(m.trim, inner, outer, 12, 5), y=at, shadow=False)


def aura(m, spread, at=0.0, colour=None, count=16, lifetime=1.8,
         rise=(0.16, 0.34), drift=0.06):
    """The ULTIMATE's own tell, and the roster's one moving part.

    Motion is the loudest signal a top down camera has, so it is reserved for
    the top rung exactly as it was when that rung wore a turning metal halo
    instead. What changed is that this is the element's OWN colour rising off
    the tower rather than a ring of somebody else's metal turning above it -
    so it says which element as well as how expensive, where the halo said
    only the second and said it in a material the roster no longer uses.

    `spread` is how wide the motes come off, and it should be roughly the
    tower's own footprint: a column of motes narrower than the thing under it
    reads as a chimney. A NEGATIVE `drift` makes them fall instead, which is
    the difference between an ember and a drip.
    """
    if not ts.element_has_aura(m.ti):
        return
    m.aura("Aura", ".", colour or m.accent_rgb, count, 0.032, spread,
           lifetime, rise, drift, at)


def breathe(m, node, height=0.018, rate=0.22, phase=0.0):
    """The living elements' idle breath.

    Deliberately tiny and slow next to the Ultimate's aura - a twentieth of the
    travel at a fifth of the rate - and attached to the middle of the model
    rather than to its outline. It is there to say the thing is alive, not to
    say it is expensive. Only the four elements in LIVING carry it.
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


def lumps(m, name, mesh, count, radius, at, rise, wobble=0.35, seed=0.0,
          parent="."):
    """A stack of the same primitive walked up a spiral and jittered.

    What an ORGANIC tower is built out of. A creature made of concentric
    symmetrical parts reads as machinery however round the parts are - the
    symmetry is the tell, not the curve - so this turns one mesh into a run of
    lopsided ones by moving each copy off the axis, turning it, and squashing
    it on a different pair of axes.

    Deterministic, and deliberately not random: the jitter comes off the index
    through a sine, so the same tower comes out the same shape every run and a
    diff of this file still says what changed.
    """
    for index in range(count):
        # The golden angle, so a run of any length spreads rather than lining
        # up, and `seed` walks one whole run off another's angles.
        angle = (index + seed) * 2.399963
        drift = radius * (0.6 + 0.4 * math.sin(angle * 1.7))
        squash = 1.0 + wobble * math.sin(angle * 2.3)
        m.put("%s%d" % (name, index + 1), mesh, parent=parent,
              x=math.sin(angle) * drift, y=at + rise * index,
              z=math.cos(angle) * drift, ry=angle,
              scale=(squash, 1.0 + wobble * 0.4 * math.cos(angle),
                     2.0 - squash))


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
    base pair has to be told apart from the Moonbeam's orb at a glance.
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
    """Shock Particle / Power Generator: four posts holding a floating orb.

    SQUARE, on review, and the element's side count went with it: a discharge
    wants hard right angles rather than the rounded drum every other built
    element sits on, and the source art's own Lightning towers are square. Four
    posts rather than three for the same reason - three around a square plinth
    reads as a mistake.

    Dark stone with the only bright thing on the whole model hanging in the
    middle of it, which is straight from the reference. What is new is that the
    orb is WIRED to its posts by lit arcs, so the tower reads as something under
    load rather than as a rock with a bulb over it.
    """
    base = plinth(m, 0.32, 0.29, 0.15, 4)
    m.put("Drum", m.cyl(m.body, 0.24, 0.29, 0.20, 4), y=base + 0.10)
    post = m.box(m.pale, 0.075, 0.30, 0.075)
    m.ring_of(4, 0.20, lambda i, x, z, a: m.put(
        "Post%d" % (i + 1), post, x=x, y=base + 0.35, z=z, ry=a))
    tip = m.gem(m.glow, 0.035, 0.07, 4, 2)
    m.ring_of(4, 0.20, lambda i, x, z, a: m.put(
        "Tip%d" % (i + 1), tip, x=x, y=base + 0.50, z=z, shadow=False))
    collar(m, base + 0.20, 0.23, 0.29)
    m.pivot("Turret", ".", y=base + 0.52)
    m.put("Orb", m.gem(m.glow, 0.115 if m.ti >= 1 else 0.095, 0.22, 6, 3),
          parent="Turret", shadow=False)
    m.put("OrbCage", m.torus(m.trim, 0.13, 0.155, 10, 4), parent="Turret",
          rx=1.5708, shadow=False)
    if m.ti >= 1:
        m.put("OrbCage2", m.torus(m.trim, 0.13, 0.155, 10, 4), parent="Turret",
              rx=1.5708, ry=1.5708, shadow=False)
    # The arcs from the post tips in towards the orb. Tilted inwards and
    # stopping short of it, so they read as a discharge crossing a gap rather
    # than as spokes bolted on.
    arc = m.box(m.glow, 0.018, 0.018, 0.13)
    m.ring_of(4, 0.14, lambda i, x, z, a: m.put(
        "Arc%d" % (i + 1), arc, parent="Turret", x=x, y=-0.02, z=z,
        ry=a, rx=0.5, shadow=False))
    m.bobber("Bob", "Turret", 0.03, 0.4)
    m.sparks("Sparks", "Turret", m.accent_rgb)
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


# ============================================================================
# THE TWENTY PATHS
# ============================================================================
#
# THREE SILHOUETTES, NOT ONE WITH PARTS ADDED. That is the rule every builder
# below is written to, and it is the whole reason this section is as long as it
# is. The roster used to draw one shape per path and let the tier metal say
# which of the three it was; with the metal gone (style, THE PATH LADDER) the
# shape has to say it, so each builder makes its three tiers three related but
# distinct objects.
#
# Each one opens with a three line table of what its Lesser, Greater and
# Ultimate ARE. Read that before the numbers - the numbers are only how.
#
# `m.step(a, b, c)` is the authoring idiom: one call picks the tier's value,
# so a builder's three tiers sit on the same line and the difference between
# them is readable in a diff rather than buried in an if.


# --- Fire ------------------------------------------------------------------

def build_moonbeam(m):
    """Fire 1: a basalt cradle holding a rock that catches fire and lifts off.

        Lesser     a dull rock SITTING in a shallow cradle, claws lying flat
        Greater    the rock has caught and LIFTED clear of the cradle, bobbing
                   inside a crown of flame, claws risen to grip it
        Ultimate   a big green orb hanging high over a cradle that has cracked
                   open beneath it, embers turning around it, ember aura

    Three objects rather than one at three brightnesses, which is the source
    art's own answer: it draws a bare rock, then a burning orb, then a green
    one. The orb takes the PATH's accent rather than the element's and so is a
    different colour at every tier - see style.PATH_ACCENTS.

    Nothing on it points at the ground at any tier. Same trick the anti-air
    branches use: a tower whose damage falls out of the SKY should not look
    like it is aiming along the floor.
    """
    base = plinth(m, 0.34, 0.3, 0.15, 6)
    bowl = m.step(0.31, 0.29, 0.33)
    m.put("Cradle", m.cyl(m.deep, bowl, bowl - 0.05, 0.16, 6), y=base + 0.08)
    m.put("Basin", m.cyl(m.body, bowl - 0.07, bowl - 0.04, 0.07, 6),
          y=base + 0.15)
    # The cradle only cracks at the top tier, under what is hanging over it.
    if m.rung >= 2:
        seam = m.box(m.glow, 0.06, 0.03, 0.34)
        m.ring_of(3, 0.1, lambda i, x, z, a: m.put(
            "Seam%d" % (i + 1), seam, x=x, y=base + 0.18, z=z, ry=a,
            shadow=False))
    claw = m.prism(m.body, 0.12, m.step(0.2, 0.3, 0.4), 0.1)
    m.ring_of(3, m.step(0.25, 0.22, 0.24), lambda i, x, z, a: m.put(
        "Claw%d" % (i + 1), claw, x=x, y=base + m.step(0.16, 0.24, 0.32), z=z,
        ry=a, rx=m.step(-0.85, -0.4, -0.16)))
    m.pivot("Turret", ".", y=base + m.step(0.26, 0.36, 0.48))
    m.pivot("Orb", "Turret")
    # A LOW FACET COUNT at the cheap tier and a round one above it, because the
    # first of the three is a rock and the other two are not.
    radius = m.step(0.13, 0.17, 0.22)
    m.put("Core", m.gem(m.accent, radius, radius * m.step(1.7, 2.0, 2.0),
                        m.step(5, 8, 8), m.step(2, 4, 4)),
          parent="Turret/Orb", shadow=False)
    if m.rung >= 1:
        # A CROWN OF FLAME rather than a band around the orb. A ring reads as
        # something bolted on; separate tongues read as the thing burning.
        tongue = m.prism(m.accent, 0.07, m.step(0.0, 0.2, 0.3), 0.05)
        m.ring_of(m.features(), radius + 0.03, lambda i, x, z, a: m.put(
            "Flame%d" % (i + 1), tongue, parent="Turret/Orb", x=x, z=z, ry=a,
            rx=-0.35, shadow=False))
        m.bobber("Bob", "Turret/Orb", 0.03, 0.3)
    ember = m.gem(m.accent, 0.04, 0.08, 5, 2)
    m.pivot("Embers", "Turret")
    m.ring_of(m.features(), m.step(0.26, 0.3, 0.36), lambda i, x, z, a: m.put(
        "Ember%d" % (i + 1), ember, parent="Turret/Embers", x=x,
        y=0.04 * math.sin(a * 3.0), z=z, shadow=False))
    m.spinner("EmberSpin", "Turret/Embers", m.step(0.1, 0.16, 0.24))
    m.pivot("Muzzle", "Turret", y=0.2)
    aura(m, 0.3, base + 0.2, count=20, rise=(0.2, 0.42))
    return base + m.step(0.55, 0.65, 0.77)


def build_firelord(m):
    """Fire 2: a burning thing that stands further up out of its own fire each
    tier.

        Lesser     a molten STUMP - no head, no arms, a lump with flame in it
        Greater    it has stood up: a torso, a head, plume arms thrown out
        Ultimate   a tall figure with horns and a full crown of plumes, its
                   whole body lit, standing in a wide molten pool, ember aura

    The user's brief was to keep the Firelord reading as a LIVING thing on a
    base a tower can stand on, so the plinth is a proper one and everything
    above it is flame. Against the Moonbeam's floating orb it is the element's
    upright, and nothing about it is symmetrical the way the Moonbeam is.
    """
    base = plinth(m, 0.32, 0.3, 0.15, 6)
    pool = m.step(0.2, 0.25, 0.32)
    # SHADOWED STONE rather than the lit accent, and it is the one place this
    # line deliberately spends less light than its own description asks for.
    # Everything else on a Firelord is lit - a heart, six plumes and an ember
    # aura - and the pool is a wide flat disc, so from the top down camera the
    # game is actually played from it was the biggest emitting surface on the
    # model and it drowned the parts that say WHICH tower this is. Dark, it
    # reads as the crust the fire is standing in, which is the same idea told
    # by the thing around the light instead of by more light.
    m.put("Pool", m.cyl(m.deep, pool, pool + 0.02, 0.04, 6), y=base + 0.02,
          shadow=False)
    m.put("Legs", m.cyl(m.deep, m.step(0.19, 0.17, 0.16), 0.26,
                        m.step(0.18, 0.22, 0.26), 6),
          y=base + m.step(0.09, 0.11, 0.13))
    m.pivot("Turret", ".", y=base + m.step(0.22, 0.32, 0.4))
    m.put("Torso", m.capsule(m.pale, m.step(0.17, 0.16, 0.17),
                             m.step(0.24, 0.32, 0.4), 6, 3),
          parent="Turret", y=m.step(0.06, 0.13, 0.17))
    m.pivot("Core", "Turret", y=m.step(0.08, 0.18, 0.24))
    m.put("Heart", m.gem(m.glow, m.step(0.1, 0.12, 0.15),
                         m.step(0.22, 0.27, 0.34), 6, 3),
          parent="Turret/Core", z=-0.05, shadow=False)
    plume = m.prism(m.glow, 0.055, m.step(0.24, 0.34, 0.44), 0.04)
    m.ring_of(m.features(), m.step(0.16, 0.19, 0.23), lambda i, x, z, a: m.put(
        "Plume%d" % (i + 1), plume, parent="Turret", x=x,
        y=m.step(0.14, 0.26, 0.34), z=z, ry=a, rx=-0.5, shadow=False))
    # No head at all on the cheap one. A stump with fire coming out of it is a
    # different object from a figure standing in fire, and that is the step.
    if m.rung >= 1:
        m.put("Head", m.gem(m.pale, m.step(0.0, 0.09, 0.11),
                            m.step(0.0, 0.17, 0.21), 6, 3),
              parent="Turret", y=m.step(0.0, 0.36, 0.46))
    if m.rung >= 2:
        horn = m.capsule(m.pale, 0.035, 0.26, 5, 2)
        m.put("HornL", horn, parent="Turret", x=-0.1, y=0.52, z=0.02,
              rx=-0.35, rz=0.7)
        m.put("HornR", horn, parent="Turret", x=0.1, y=0.52, z=0.02,
              rx=-0.35, rz=-0.7)
    m.pivot("Muzzle", "Turret", y=0.2, z=-0.18)
    aura(m, 0.26, base + 0.24, count=20, rise=(0.22, 0.46))
    return base + m.step(0.57, 0.67, 0.79)


# --- Ice -------------------------------------------------------------------

def build_lich(m):
    """Ice 1: the base obelisk cracking further open at every tier.

        Lesser     the spire SHUT, one thin lit seam down the middle of it
        Greater    it has split: the two halves lean apart around a bright
                   core, with shards turning in the gap
        Ultimate   the spire has SHATTERED - two low stumps and a thicket of
                   shards standing around a core the size of the old tower,
                   frost aura

    A direct continuation of the base pair rather than a new object, which is
    the reference art's own progression: the spire is still there, it has just
    cracked and something has got out.
    """
    base = plinth(m, 0.3, 0.27, 0.15, 4)
    split = m.step(0.09, 0.17, 0.26)
    half = m.cyl(m.body, m.step(0.1, 0.09, 0.15), m.step(0.16, 0.17, 0.24),
                 m.step(0.58, 0.62, 0.34), 4)
    lean = m.step(0.09, 0.2, 0.5)
    high = m.step(0.31, 0.3, 0.15)
    m.put("SpireL", half, x=-split, y=base + high, rz=lean)
    m.put("SpireR", half, x=split, y=base + high, rz=-lean)
    m.put("Cradle", m.cyl(m.deep, m.step(0.2, 0.22, 0.28),
                          m.step(0.24, 0.26, 0.31), 0.14, 4), y=base + 0.07)
    m.pivot("Turret", ".", y=base + m.step(0.52, 0.54, 0.46))
    m.put("Core", m.gem(m.glow, m.step(0.09, 0.145, 0.2),
                        m.step(0.26, 0.36, 0.46), 4, 3),
          parent="Turret", shadow=False)
    # The shards only exist once the spire has opened. Below that the whole
    # tower is one closed object and the seam is all there is to see.
    if m.rung >= 1:
        shard = m.gem(m.pale, m.step(0.0, 0.05, 0.07),
                      m.step(0.0, 0.26, 0.42), 4, 2)
        m.pivot("Shards", "Turret")
        m.ring_of(m.features(), m.step(0.0, 0.27, 0.34),
                  lambda i, x, z, a: m.put(
                      "Shard%d" % (i + 1), shard, parent="Turret/Shards",
                      x=x, z=z, rz=0.28 * math.sin(a), rx=-0.28 * math.cos(a)))
        m.spinner("ShardSpin", "Turret/Shards", m.step(0.0, 0.12, 0.2))
    else:
        m.put("Seam", m.box(m.glow, 0.05, 0.5, 0.05), y=base + 0.3,
              shadow=False)
    m.bobber("Bob", "Turret", 0.026, 0.3)
    m.pivot("Muzzle", "Turret", z=-0.2)
    aura(m, 0.28, base + 0.3, count=18, rise=(0.1, 0.24))
    return base + m.step(0.75, 0.85, 0.95)


def build_crystal(m):
    """Ice 2: one crystal, then a cluster, then a monolith.

        Lesser     ONE thin lance out of a low bed, two small spikes beside it
        Greater    a fistful of spikes, the lance heavier and taller
        Ultimate   a single monolith twice the height of the Lesser's lance,
                   in a thicket, frost aura

    The clearest tier read of any path in the roster and it is straight out of
    the reference sheet, which draws exactly this: one spike, three, then a
    crystal bigger than the tower it grew out of.
    """
    base = plinth(m, 0.31, 0.28, 0.14, 4)
    m.put("Bed", m.cyl(m.deep, 0.22, 0.28, 0.16, 4), y=base + 0.08)
    spike = m.gem(m.body, m.step(0.06, 0.08, 0.1),
                  m.step(0.36, 0.46, 0.58), 4, 2)
    m.ring_of(m.features(), m.step(0.16, 0.2, 0.24), lambda i, x, z, a: m.put(
        "Crystal%d" % (i + 1), spike, x=x, y=base + m.step(0.26, 0.32, 0.4),
        z=z, rx=0.24 * math.cos(a), rz=-0.24 * math.sin(a)))
    m.pivot("Turret", ".", y=base + 0.28)
    m.pivot("Spike", "Turret")
    lance = m.step(0.56, 0.68, 0.86)
    m.put("Lance", m.gem(m.pale, m.step(0.07, 0.095, 0.13), lance, 4, 2),
          parent="Turret/Spike", y=lance * 0.42, z=-0.06)
    m.put("LanceCore", m.gem(m.glow, m.step(0.04, 0.055, 0.08), lance * 0.66,
                             4, 2),
          parent="Turret/Spike", y=lance * 0.45, z=-0.06, shadow=False)
    m.pivot("Muzzle", "Turret", y=lance * 0.8, z=-0.1)
    aura(m, 0.26, base + 0.3, count=16, rise=(0.08, 0.2))
    return base + m.step(0.76, 0.86, 1.0)


# --- Lightning --------------------------------------------------------------

def build_annihilation_glyph(m):
    """Lightning 1: a square pylon that grows into a blade.

        Lesser     a short dark post with a small red head on it
        Greater    twice as tall, the head drawn out into a blade, arcs
                   climbing the shaft
        Ultimate   a thin red BLADE the height of the cell, on a shaft that has
                   nearly vanished under it, spark aura

    It is the one tower in the roster that stopped being what the reference's
    middle tier is and became what its TOP tier is: the 30,000g Glyph in the
    source sheet is a narrow red-orange blade standing on grey stone, and that
    is a far better tower than the dark drum below it.

    It does not turn. A spinning ring is the loudest thing a top-down camera
    can show and this tower's loudest thing should be the arc coming off its
    head, so what used to be a turning plate ring is a low static skirt.

    THE HEAD IS RED at every tier, and so is the lightning it throws. That is
    the path's own accent rather than the element's - see style.PATH_ACCENTS.
    """
    base = plinth(m, 0.28, 0.24, 0.16, 4)
    shaft = m.step(0.52, 0.6, 0.68)
    width = m.step(0.21, 0.18, 0.15)
    m.put("Shaft", m.box(m.body, width, shaft, width), y=base + shaft * 0.5)
    face = m.box(m.accent, width * 0.5, shaft * 0.7, 0.02)
    m.put("ShaftFaceF", face, y=base + shaft * 0.52, z=-width * 0.51,
          shadow=False)
    m.put("ShaftFaceB", face, y=base + shaft * 0.52, z=width * 0.51,
          shadow=False)
    side = m.box(m.accent, 0.02, shaft * 0.7, width * 0.5)
    m.put("ShaftFaceL", side, x=-width * 0.51, y=base + shaft * 0.52,
          shadow=False)
    m.put("ShaftFaceR", side, x=width * 0.51, y=base + shaft * 0.52,
          shadow=False)
    # The skirt: what the spinning ring became. Low, at the foot, square, and
    # gaining plates by tier exactly as the ring did - but in the tower's own
    # stone rather than in a metal, and standing still.
    plate = m.box(m.pale, 0.06, m.step(0.12, 0.18, 0.24), 0.04)
    m.ring_of(m.features() + 2, 0.24, lambda i, x, z, a: m.put(
        "Plate%d" % (i + 1), plate, x=x, y=base + 0.08, z=z, ry=a))

    # THE EMITTER. Everything above the shaft, and the point the arc is drawn
    # from - which is why the Muzzle sits inside it rather than out in front.
    m.pivot("Turret", ".", y=base + shaft)
    m.put("Yoke", m.cyl(m.pale, 0.05, width * 0.8, 0.1, 4), parent="Turret",
          y=0.03)
    # A GEM at the cheap tier and a BLADE above it. The reference's top Glyph
    # is a flat edge standing on end, and that is what the money buys.
    if m.rung < 1:
        m.put("Head", m.gem(m.accent, 0.085, 0.24, 4, 2), parent="Turret",
              y=0.15, shadow=False)
    else:
        blade = m.step(0.0, 0.28, 0.4)
        wide = m.step(0.0, 0.17, 0.24)
        m.put("Head", m.box(m.accent, wide, blade, 0.045),
              parent="Turret", y=0.08 + blade * 0.5, shadow=False)
        m.put("HeadTip", m.prism(m.accent, wide, blade * 0.5, 0.045),
              parent="Turret", y=0.08 + blade * 1.25, shadow=False)
        m.put("HeadFoot", m.prism(m.accent, wide, blade * 0.34, 0.045),
              parent="Turret", y=0.08 - blade * 0.17, rz=3.1416,
              shadow=False)
    prong = m.box(m.pale, 0.022, m.step(0.14, 0.18, 0.22), 0.022)
    m.ring_of(4, m.step(0.08, 0.1, 0.13), lambda i, x, z, a: m.put(
        "Prong%d" % (i + 1), prong, parent="Turret", x=x, y=0.16, z=z,
        ry=a, rx=0.32))
    m.sparks("Sparks", "Turret", m.accent_rgb, 12, 0.022, 0.16, 0.28,
             (1.0, 2.2), -0.8)
    m.pivot("Muzzle", "Turret", y=0.17)
    aura(m, 0.2, base + 0.4, count=14, rise=(0.3, 0.6), lifetime=1.2)
    return base + shaft + m.step(0.28, 0.34, 0.4)


def build_orb_keeper(m):
    """Lightning 2: an orb under load, in a square frame that closes around it.

        Lesser     a small orb on a squat pylon, two posts beside it
        Greater    a bigger orb, four posts, a lintel over the top of them
        Ultimate   a huge orb inside a closed square frame - posts, lintels
                   and a floor plate - crackling, spark aura

    Short range and a very fast attack, so it is the SQUATTEST thing in the
    element and stays that way: a player should be able to tell an Orb Keeper
    from an Annihilation Glyph across a maze without reading either, and the
    Glyph is a thin spike.

    The frame is SQUARE and it is made of the tower's own stone. The three
    metal cage rings this used to wear were three of the worst offenders in the
    roster - they read as machinery idling and they were the same colour as
    every other tower's rings.
    """
    base = plinth(m, 0.34, 0.31, 0.15, 4)
    m.put("Pylon", m.cyl(m.body, 0.19, 0.28, m.step(0.2, 0.24, 0.28), 4),
          y=base + m.step(0.1, 0.12, 0.14))
    m.put("Shoulder", m.cyl(m.pale, 0.23, 0.18, 0.08, 4),
          y=base + m.step(0.24, 0.28, 0.32))
    m.pivot("Turret", ".", y=base + m.step(0.44, 0.5, 0.58))
    m.put("Orb", m.gem(m.glow, m.step(0.13, 0.17, 0.22),
                       m.step(0.26, 0.34, 0.44), 8, 4),
          parent="Turret", shadow=False)
    posts = m.step(2, 4, 4)
    stand = m.step(0.3, 0.38, 0.46)
    # Where the top of a post is, so the lintels land ON them.
    top = stand * 0.5 - 0.03
    post = m.box(m.pale, 0.07, stand, 0.07)
    reach = m.step(0.2, 0.23, 0.26)
    m.ring_of(posts, reach, lambda i, x, z, a: m.put(
        "Post%d" % (i + 1), post, parent="Turret", x=x, y=0.0, z=z, ry=a))
    if m.rung >= 1:
        # The lintel arrives with the second pair of posts and closes the
        # frame. It is the tier step a player sees from directly above, which
        # is the angle this tower is actually looked at from.
        lintel = m.box(m.pale, reach * 2.3, 0.055, 0.09)
        m.put("LintelF", lintel, parent="Turret", y=top, z=-reach)
        m.put("LintelB", lintel, parent="Turret", y=top, z=reach)
    if m.rung >= 2:
        m.put("Floor", m.box(m.deep, reach * 2.3, 0.05, reach * 2.3),
              parent="Turret", y=-0.24)
        lintel = m.box(m.pale, 0.09, 0.055, reach * 2.3)
        m.put("LintelL", lintel, parent="Turret", x=-reach, y=top)
        m.put("LintelR", lintel, parent="Turret", x=reach, y=top)
    arc = m.box(m.glow, 0.02, m.step(0.14, 0.18, 0.24), 0.02)
    m.ring_of(m.features(), m.step(0.18, 0.22, 0.26), lambda i, x, z, a: m.put(
        "Arc%d" % (i + 1), arc, parent="Turret", x=x, y=-0.16, z=z,
        shadow=False))
    spark = m.gem(m.glow, 0.03, 0.06, 4, 2)
    m.ring_of(posts, reach, lambda i, x, z, a: m.put(
        "Node%d" % (i + 1), spark, parent="Turret",
        x=x, y=top - 0.04, z=z, shadow=False))
    m.sparks("Sparks", "Turret", m.accent_rgb, 16, 0.026, 0.26, 0.3,
             (1.2, 2.6), -1.4)
    m.pivot("Muzzle", "Turret", z=-0.2)
    aura(m, 0.28, base + 0.3, count=14, rise=(0.24, 0.5), lifetime=1.2)
    return base + m.step(0.62, 0.72, 0.84)


# --- Holy ------------------------------------------------------------------

def build_divineshroom(m):
    """Holy 1: one mushroom, then three, then a whole ring of them.

        Lesser     ONE small cap on a thin stalk
        Greater    a bigger cap with two sprouting beside it
        Ultimate   a broad cap over a ring of four, spore aura

    The anti-air path, and it says so the way every anti-air branch in the game
    does: NOTHING on it points at the ground. The cap is angled upwards and the
    spores go with it, so a player reads what it can shoot before paying for
    one. The user asked for shrooms and the source art has them.

    The COUNT is the tier here rather than the size, because a mushroom that
    only grows reads as the same mushroom nearer the camera.
    """
    base = plinth(m, 0.31, 0.28, 0.14, 8)
    m.put("Bulb", m.capsule(m.deep, 0.13, 0.26, 6, 3), y=base + 0.13)
    stalk = m.step(0.34, 0.38, 0.44)
    m.put("Stalk", m.cyl(m.body, 0.1, 0.15, stalk, 8), y=base + 0.1 + stalk * 0.5)
    m.put("Skirt", m.cyl(m.pale, 0.2, 0.11, 0.05, 8), y=base + 0.06 + stalk)
    # The sprouts. Small caps on their own short stalks around the foot, and
    # the whole tier read of the path - one, three, five.
    sprouts = m.step(0, 2, 4)
    if sprouts:
        neck = m.cyl(m.body, 0.045, 0.06, 0.16, 6)
        hood = m.gem(m.deep, m.step(0.0, 0.12, 0.14), m.step(0.0, 0.13, 0.15),
                     8, 3)
        lit = m.torus(m.glow, m.step(0.0, 0.09, 0.11),
                      m.step(0.0, 0.12, 0.14), 12, 4)
        m.ring_of(sprouts, m.step(0.0, 0.25, 0.29), lambda i, x, z, a: (
            m.put("Neck%d" % (i + 1), neck, x=x, y=base + 0.09, z=z),
            m.put("Hood%d" % (i + 1), hood, x=x, y=base + 0.2, z=z),
            m.put("HoodRim%d" % (i + 1), lit, x=x, y=base + 0.17, z=z,
                  shadow=False)))
    m.pivot("Turret", ".", y=base + 0.16 + stalk)
    # The cap is a pivot so the prefab's recoil rocks the whole head rather
    # than sliding the mesh out of its own stalk.
    m.pivot("Cap", "Turret", rx=-0.42)
    # The cap takes the DEEP tone. Ivory with a gold rim on ivory stone read as
    # one pale disc; a dark cap with a lit rim under it reads as a mushroom.
    crown = m.step(0.26, 0.3, 0.34)
    m.put("Head", m.gem(m.deep, crown, crown * 1.05, 8, 3),
          parent="Turret/Cap", y=0.1)
    m.put("Rim", m.torus(m.glow, crown - 0.05, crown, 16, 5),
          parent="Turret/Cap", y=0.03, shadow=False)
    m.put("Crest", m.gem(m.glow, 0.11, 0.16, 6, 2), parent="Turret/Cap", y=0.21,
          shadow=False)
    gill = m.prism(m.glow, 0.06, 0.16, 0.03)
    m.ring_of(m.features() + 2, crown * 0.66, lambda i, x, z, a: m.put(
        "Gill%d" % (i + 1), gill, parent="Turret/Cap", x=x, y=0.02, z=z, ry=a,
        rx=3.1416, shadow=False))
    m.pivot("Muzzle", "Turret", y=0.32, z=-0.22)
    aura(m, 0.32, base + 0.4, count=18, rise=(0.14, 0.3), lifetime=2.2)
    return base + m.step(0.74, 0.84, 0.94)


def build_titan_vault(m):
    """Holy 2: a strongbox that opens further at every tier.

        Lesser     a SHUT stone box with a slit of light across its face
        Greater    the lid has lifted at one end and light is coming out of the
                   gap, the lens on its face is open
        Ultimate   the lid is thrown wide, the box is full of light, and it is
                   spilling upward - gold aura

    The reference art's top tier is a golden chest and the tiers below it are a
    beam tower, so this is both. It is the support tower of the whole game, so
    what it wants to read as is something VALUABLE standing behind the maze
    rather than in it.

    The gold is drawn in the element's own LIGHT rather than in a metal, which
    is what it should always have been: Holy's accent is gold, and a gold
    coloured metal on top of it was two shades of the same thing.
    """
    base = plinth(m, 0.32, 0.29, 0.16, 8)
    m.put("Column", m.cyl(m.body, 0.19, 0.26, m.step(0.3, 0.36, 0.42), 8),
          y=base + m.step(0.15, 0.18, 0.21))
    m.pivot("Turret", ".", y=base + m.step(0.42, 0.5, 0.6))
    # The vault body takes the DEEP tone rather than the pale one: a bright
    # box on bright ivory stone is two shades of the same thing.
    box = m.step(0.32, 0.37, 0.43)
    m.put("Vault", m.box(m.deep, box, box * 0.82, box * 0.84),
          parent="Turret", y=0.12)
    # The lid. Shut, cracked, thrown wide - the whole tier read of the path.
    m.pivot("Hinge", "Turret", y=0.12 + box * 0.42, z=box * 0.42,
            rx=m.step(0.0, -0.5, -1.15))
    m.put("VaultLid", m.box(m.pale, box * 1.04, 0.045, box * 0.88),
          parent="Turret/Hinge", z=-box * 0.42)
    m.put("Hoard", m.gem(m.glow, box * m.step(0.2, 0.34, 0.46),
                         box * m.step(0.2, 0.4, 0.62), 8, 3),
          parent="Turret", y=0.12 + box * m.step(0.1, 0.24, 0.38),
          shadow=False)
    band = m.box(m.pale, 0.05, box * 0.86, box * 0.88)
    m.put("BandL", band, parent="Turret", x=-box * 0.38, y=0.12)
    m.put("BandR", band, parent="Turret", x=box * 0.38, y=0.12)
    m.pivot("Lens", "Turret", y=0.12, z=-box * 0.5)
    m.put("Eye", m.gem(m.glow, m.step(0.07, 0.1, 0.13),
                       m.step(0.1, 0.14, 0.18), 8, 3),
          parent="Turret/Lens", shadow=False)
    beam = m.box(m.glow, 0.025, m.step(0.06, 0.12, 0.2), 0.025)
    m.ring_of(m.features(), box * 0.42, lambda i, x, z, a: m.put(
        "Beam%d" % (i + 1), beam, parent="Turret", x=x,
        y=0.12 + box * m.step(0.44, 0.52, 0.62), z=z, shadow=False))
    m.pivot("Muzzle", "Turret", y=0.12, z=-box * 0.72)
    aura(m, 0.26, base + 0.5, count=16, rise=(0.18, 0.4), lifetime=2.0)
    return base + m.step(0.72, 0.82, 0.94)


# --- Void -------------------------------------------------------------------

def build_harbinger(m):
    """Void 1: a hide spire with a rift in it, growing lopsided.

        Lesser     a short thick stump, one small rift near the top
        Greater    it has drawn itself up: taller, narrower, a wide rift, horns
        Ultimate   a writhing spire with a rift the width of the tower and lit
                   sockets opening down its flank, void aura

    The Void towers are the ones the user asked to make structural without
    stopping being alive, so this is a SPIRE - upright, with a footprint, and a
    silhouette a maze can be built out of - and every part of it is a capsule
    walked off the axis by lumps(), because what tells a creature from a
    machine is the asymmetry rather than the curve.
    """
    base = plinth(m, 0.28, 0.26, 0.14, 6)
    body = m.step(0.54, 0.64, 0.74)
    m.put("Body", m.capsule(m.body, m.step(0.17, 0.14, 0.155), body, 8, 3),
          y=base + body * 0.5)
    # The flank lumps. Deterministic jitter, so the tower is lopsided in the
    # same way every run - see lumps().
    lumps(m, "Sac", m.capsule(m.deep, m.step(0.075, 0.07, 0.08),
                              m.step(0.14, 0.16, 0.2), 6, 2),
          m.step(3, 4, 6), m.step(0.15, 0.14, 0.16), base + 0.16,
          body * m.step(0.16, 0.14, 0.12), 0.4)
    rib = m.prism(m.deep, 0.07, m.step(0.3, 0.4, 0.5), 0.055)
    m.ring_of(m.features(), m.step(0.16, 0.14, 0.15), lambda i, x, z, a: m.put(
        "Rib%d" % (i + 1), rib, x=x, y=base + m.step(0.2, 0.26, 0.3), z=z,
        ry=a, rx=-0.14))
    m.pivot("Turret", ".", y=base + body + m.step(0.02, 0.04, 0.06))
    m.pivot("Eye", "Turret")
    eye = m.step(0.095, 0.12, 0.15)
    # The socket sits BEHIND the rift rather than around it, so the lit part is
    # the part facing whatever the tower is shooting.
    m.put("Socket", m.gem(m.deep, eye + 0.045, (eye + 0.045) * 1.9, 6, 3),
          parent="Turret/Eye", z=0.06, scale=(1.15, 1.05, 0.72))
    m.put("Rift", m.gem(m.glow, eye, eye * 2.0, 6, 3), parent="Turret/Eye",
          z=-0.06, shadow=False)
    # The lesser has one eye. The others open more of them down the flank,
    # which is what makes the top tier read as a thing looking at you rather
    # than a thing with a light on it.
    if m.rung >= 1:
        spare = m.gem(m.glow, m.step(0.0, 0.045, 0.06),
                      m.step(0.0, 0.08, 0.11), 5, 2)
        lumps(m, "Ocellus", spare, m.step(0, 3, 5), 0.16,
              base + body * 0.5, body * 0.12, 0.3, seed=1.5)
    horn = m.capsule(m.pale, 0.035, m.step(0.22, 0.32, 0.42), 5, 2)
    m.ring_of(3, m.step(0.11, 0.13, 0.15), lambda i, x, z, a: m.put(
        "Horn%d" % (i + 1), horn, parent="Turret", x=x, y=0.14, z=z, ry=a,
        rx=-0.7))
    breathe(m, "Turret", 0.022, 0.2)
    m.pivot("Muzzle", "Turret", z=-0.2)
    aura(m, 0.22, base + body * 0.6, count=16, rise=(0.14, 0.32),
         lifetime=2.2)
    return base + body + m.step(0.24, 0.28, 0.32)


def build_leviathan(m):
    """Void 2: a mound that opens into a mouth.

        Lesser     a closed lopsided mound with one lit slit across it
        Greater    the slit has become a maw ringed with teeth, lashes turning
        Ultimate   a gullet the width of the plinth, a second mouth beside it,
                   and a skirt of long lashes, void aura

    The armour-eating path, so what it reads as is a MOUTH. It is the one tower
    in the roster whose moving part IS its attack, which is what lets the
    motion be as loud as it is - see element_roster.ANIMATION's spin entry.
    """
    base = plinth(m, 0.34, 0.32, 0.13, 6)
    m.put("Mound", m.capsule(m.body, m.step(0.22, 0.25, 0.28),
                             m.step(0.24, 0.3, 0.36), 8, 3),
          y=base + m.step(0.14, 0.16, 0.18), scale=(1.12, 1.0, 0.88))
    lumps(m, "Wart", m.capsule(m.deep, 0.06, 0.1, 6, 2),
          m.step(3, 4, 6), m.step(0.18, 0.2, 0.23), base + 0.1,
          m.step(0.03, 0.035, 0.04), 0.45)
    m.pivot("Turret", ".", y=base + m.step(0.24, 0.29, 0.34))
    maw = m.step(0.11, 0.15, 0.2)
    m.put("Maw", m.cyl(m.deep, maw + 0.05, maw, 0.14, 8), parent="Turret",
          y=0.05)
    m.put("Gullet", m.gem(m.glow, maw * 0.92, maw * 2.4, 8, 3),
          parent="Turret", y=0.12, shadow=False)
    tooth = m.prism(m.pale, 0.05, m.step(0.1, 0.15, 0.2), 0.04)
    m.ring_of(m.features() + 2, maw + 0.05, lambda i, x, z, a: m.put(
        "Tooth%d" % (i + 1), tooth, parent="Turret", x=x, y=0.1, z=z, ry=a,
        rx=-0.5))
    if m.rung >= 2:
        # A SECOND mouth, off centre and smaller. The one thing on the tower
        # that is not radially symmetrical, and the top tier's own tell.
        m.put("MawB", m.cyl(m.deep, 0.11, 0.08, 0.1, 6), parent="Turret",
              x=0.2, y=0.06, z=-0.14, rz=-0.4)
        m.put("GulletB", m.gem(m.glow, 0.075, 0.12, 6, 3), parent="Turret",
              x=0.21, y=0.11, z=-0.15, shadow=False)
    m.pivot("Lashes", "Turret", y=0.06)
    lash = m.capsule(m.pale, 0.045, m.step(0.3, 0.42, 0.56), 5, 2)
    m.ring_of(m.features() + 1, m.step(0.22, 0.26, 0.3),
              lambda i, x, z, a: m.put(
                  "Lash%d" % (i + 1), lash, parent="Turret/Lashes", x=x, y=0.06,
                  z=z, ry=a, rx=0.85))
    breathe(m, "Turret", 0.018, 0.26)
    m.pivot("Muzzle", "Turret", y=0.14, z=-0.14)
    aura(m, 0.3, base + 0.2, count=16, rise=(0.12, 0.28), lifetime=2.2)
    return base + m.step(0.44, 0.52, 0.62)


# --- Unholy -----------------------------------------------------------------

def build_gravedigger(m):
    """Unholy 1: an open grave with something growing out of it.

        Lesser     a small pit with a closed bud sitting in it
        Greater    a wider pit, the bud open into a bloom, ribs standing round
        Ultimate   a pit the width of the cell with THREE blooms in it, spore
                   aura

    Stays LOW, the way the base pair is low, and grows SIDEWAYS rather than
    upwards: a wider pit, more ribs, more blooms. That is what keeps the two
    Unholy paths apart at a glance, because the Alchemist goes straight up.
    """
    base = plinth(m, 0.35, 0.33, 0.13, 6)
    pit = m.step(0.29, 0.32, 0.36)
    m.put("Pit", m.cyl(m.body, pit, pit - 0.03, 0.18, 6), y=base + 0.09)
    m.put("Sludge", m.cyl(m.glow, pit - 0.05, pit - 0.05, 0.03, 6),
          y=base + 0.17, shadow=False)
    rib = m.capsule(m.pale, 0.04, m.step(0.24, 0.32, 0.4), 5, 2)
    m.ring_of(m.features() + 2, pit, lambda i, x, z, a: m.put(
        "Rib%d" % (i + 1), rib, x=x, y=base + 0.17, z=z, ry=a, rx=0.45))
    m.pivot("Turret", ".", y=base + 0.22)

    def bloom(tag, parent, x, z, size, open_petals):
        m.put("Bloom" + tag, m.capsule(m.deep, 0.11 * size, 0.22 * size, 6, 3),
              parent=parent, x=x, y=0.1 * size, z=z)
        petal = m.prism(m.pale, 0.11 * size, 0.2 * size, 0.06 * size)
        m.ring_of(m.features(), 0.11 * size, lambda i, px, pz, a: m.put(
            "Petal%s%d" % (tag, i + 1), petal, parent=parent, x=x + px,
            y=0.19 * size, z=z + pz, ry=a, rx=-0.2 - 0.5 * open_petals))
        m.put("Sac" + tag, m.gem(m.glow, 0.09 * size, 0.18 * size, 6, 3),
              parent=parent, x=x, y=0.23 * size, z=z, shadow=False)

    bloom("", "Turret", 0.0, 0.0, m.step(0.85, 1.05, 1.25), m.step(0.0, 0.7, 1.0))
    if m.rung >= 2:
        # Two more, off centre and smaller. A grave with three things growing
        # out of it, which is a different object from a grave with one.
        bloom("B", "Turret", -0.2, 0.14, 0.62, 1.0)
        bloom("C", "Turret", 0.21, -0.12, 0.55, 1.0)
    breathe(m, "Turret", 0.02, 0.22)
    m.pivot("Muzzle", "Turret", y=0.28, z=-0.1)
    aura(m, 0.34, base + 0.16, count=18, rise=(0.1, 0.24), lifetime=2.4)
    return base + m.step(0.42, 0.5, 0.6)


def build_alchemist(m):
    """Unholy 2: a still, growing a taller stack and more flasks.

        Lesser     a small vat with one flask swinging off a short boom
        Greater    a taller vat with a condenser stack of drums over it
        Ultimate   a tall still, three flasks on the boom, the stack venting -
                   spore aura

    Tall and narrow against the Gravedigger's low pit, and the only Unholy
    tower with a hard silhouette: the frame is bone rather than plating, but it
    IS a frame, which is what says this one was made on purpose.
    """
    base = plinth(m, 0.3, 0.28, 0.15, 6)
    vat = m.step(0.24, 0.28, 0.32)
    m.put("Vat", m.cyl(m.body, 0.2, 0.25, vat, 6), y=base + vat * 0.5)
    m.put("VatTop", m.cyl(m.pale, 0.16, 0.2, 0.06, 6), y=base + vat + 0.03)
    m.put("Brew", m.cyl(m.glow, 0.14, 0.14, 0.03, 6), y=base + vat + 0.06,
          shadow=False)
    leg = m.capsule(m.deep, 0.035, m.step(0.34, 0.42, 0.5), 5, 2)
    m.ring_of(m.features(), 0.22, lambda i, x, z, a: m.put(
        "Leg%d" % (i + 1), leg, x=x, y=base + m.step(0.34, 0.4, 0.46), z=z,
        ry=a, rx=0.2))
    # The condenser stack. Short drums rather than a stack of rings, because
    # rings are exactly what this roster spent the review getting rid of.
    drums = m.step(0, 2, 3)
    for index in range(drums):
        wide = 0.15 - index * 0.018
        m.put("Drum%d" % (index + 1), m.cyl(m.pale, wide, wide + 0.02, 0.09, 6),
              y=base + vat + 0.12 + index * 0.1, ry=index * 0.5)
        m.put("DrumVent%d" % (index + 1), m.gem(m.glow, 0.045, 0.06, 5, 2),
              x=wide + 0.03, y=base + vat + 0.14 + index * 0.1, shadow=False)
    m.pivot("Turret", ".", y=base + vat + m.step(0.24, 0.3, 0.36))
    m.pivot("Arm", "Turret")
    m.put("Boom", m.box(m.deep, 0.07, 0.07, m.step(0.26, 0.3, 0.36)),
          parent="Turret/Arm", z=m.step(-0.1, -0.12, -0.15))
    flasks = m.step(1, 1, 3)
    for index in range(flasks):
        offset = (index - (flasks - 1) * 0.5) * 0.26
        size = 1.0 if index == 0 else 0.62
        m.put("Flask%d" % (index + 1),
              m.gem(m.pale, m.step(0.11, 0.13, 0.15) * size,
                    m.step(0.2, 0.24, 0.28) * size, 6, 3),
              parent="Turret/Arm", x=offset, z=m.step(-0.24, -0.28, -0.34))
        m.put("FlaskCore%d" % (index + 1),
              m.gem(m.glow, m.step(0.075, 0.09, 0.1) * size,
                    m.step(0.14, 0.16, 0.19) * size, 6, 3),
              parent="Turret/Arm", x=offset, z=m.step(-0.24, -0.28, -0.34),
              shadow=False)
    m.put("Neck", m.cyl(m.pale, 0.04, 0.06, 0.1, 6), parent="Turret/Arm",
          y=0.14, z=m.step(-0.24, -0.28, -0.34))
    breathe(m, "Turret", 0.014, 0.18)
    m.pivot("Muzzle", "Turret", z=m.step(-0.34, -0.4, -0.46))
    aura(m, 0.24, base + vat + 0.2, count=16, rise=(0.16, 0.34), lifetime=2.0)
    return base + m.step(0.7, 0.8, 0.93)


# --- Water ------------------------------------------------------------------

def build_hurricane_elemental(m):
    """Water 1: a column of water that climbs out of its basin.

        Lesser     a low churn in the basin, barely off the ground
        Greater    a waist-high spiral with arms of water thrown out of it
        Ultimate   a full column the height of the cell with a head on top of
                   it, spray aura

    Built out of lopsided lumps walked up a spiral rather than out of stacked
    rings, which is both what water does and what keeps the tower off the one
    shape this roster is trying to stop using. Nothing about it is plated and
    the only hard edges on it are its basin.
    """
    base = plinth(m, 0.33, 0.31, 0.14, 8)
    m.put("Basin", m.cyl(m.body, 0.31, 0.29, 0.14, 8), y=base + 0.07)
    m.put("Lip", m.torus(m.pale, 0.27, 0.32, 16, 5), y=base + 0.14)
    m.pivot("Turret", ".", y=base + 0.2)
    m.pivot("Vortex", "Turret")
    column = m.step(0.34, 0.46, 0.62)
    coils = m.step(4, 6, 8)
    lumps(m, "Coil", m.capsule(m.pale, m.step(0.115, 0.11, 0.105),
                               m.step(0.14, 0.16, 0.18), 6, 2),
          coils, m.step(0.17, 0.19, 0.21), 0.04, column / coils, 0.55,
          parent="Turret/Vortex")
    m.put("Core", m.gem(m.glow, m.step(0.07, 0.085, 0.1), column * 0.86, 8, 4),
          parent="Turret", y=column * 0.5, shadow=False)
    arm = m.capsule(m.pale, 0.05, m.step(0.2, 0.28, 0.36), 6, 2)
    m.ring_of(m.features(), m.step(0.19, 0.23, 0.27), lambda i, x, z, a: m.put(
        "Arm%d" % (i + 1), arm, parent="Turret", x=x, y=column * 0.62, z=z,
        ry=a, rx=1.0))
    if m.rung >= 1:
        m.put("Head", m.gem(m.glow, m.step(0.0, 0.09, 0.12),
                            m.step(0.0, 0.16, 0.22), 6, 3),
              parent="Turret", y=column + 0.06, shadow=False)
    breathe(m, "Turret", 0.024, 0.3)
    m.pivot("Muzzle", "Turret", y=column * 0.7, z=-0.18)
    aura(m, 0.28, base + 0.2, count=18, rise=(0.2, 0.44), lifetime=1.8)
    return base + m.step(0.62, 0.74, 0.88)


def build_sludge_monstrosity(m):
    """Water 2: one slumped mass of sludge, sitting in its own spreading pool.

        Lesser     a low lopsided blob with one lit eye and a single vent
        Greater    heavier, humps growing off one shoulder, a wider pool
        Ultimate   a sprawl of a body over a pool the width of the cell, the
                   eye the size of the Lesser's whole head - dripping aura

    The one tower in the roster whose ABILITY is a radius on the floor and
    nothing else, so it is built around a pool deliberately WIDER than the mass
    standing in it: the eye is taught to read the ground around this tower
    before the tower itself. The pool is drawn, not measured - the real radius
    is on the passive.

    THE MOST ASYMMETRICAL THING IN THE ROSTER, on purpose. It is the biological
    tower the user asked to be lopsided, so nothing on it is centred and every
    lump is placed by lumps().

    Its first pass was a cluster of same-sized round parts and came out as a
    plate of ice cubes - the bunch-of-grapes failure PLACEHOLDER_ART warns
    about. The fix is a HIERARCHY of sizes: one mass that is unmistakably the
    body, humps that are plainly smaller than it, and one vent. Not eight
    things the same size.
    """
    base = plinth(m, 0.36, 0.34, 0.11, 8)
    pool = m.step(0.29, 0.33, 0.38)
    # The pool is the sludge's OWN dark tone with lit patches in it. Drawn in
    # the energy material it was a white disc the width of the cell at the top
    # tier, with the tower invisible inside its own aura.
    m.put("Pool", m.cyl(m.deep, pool, pool + 0.02, 0.03, 10), y=base + 0.015)
    lumps(m, "Patch", m.cyl(m.glow, 0.075, 0.06, 0.018, 6), m.step(3, 4, 5),
          pool * 0.66, base + 0.04, 0.0, 0.55, seed=0.4)
    m.put("Mass", m.capsule(m.body, m.step(0.22, 0.25, 0.29),
                            m.step(0.32, 0.4, 0.48), 8, 3),
          y=base + m.step(0.17, 0.21, 0.25), ry=0.4, scale=(1.18, 1.0, 0.84))
    lumps(m, "Hump", m.capsule(m.pale, m.step(0.095, 0.11, 0.125),
                               m.step(0.1, 0.13, 0.16), 6, 3),
          m.step(2, 3, 4), m.step(0.16, 0.19, 0.22),
          base + m.step(0.26, 0.32, 0.38), m.step(0.04, 0.05, 0.06), 0.5,
          seed=2.2)
    m.pivot("Turret", ".", y=base + m.step(0.28, 0.35, 0.42))
    # ONE vent, off to one side. A ring of them made the tower symmetrical
    # again, which is the one thing this shape must not be.
    m.put("Vent", m.cyl(m.pale, 0.075, 0.11, m.step(0.12, 0.15, 0.18), 6),
          parent="Turret", x=0.15, y=0.02, z=0.11)
    m.put("Bubble", m.gem(m.glow, m.step(0.06, 0.07, 0.08),
                          m.step(0.11, 0.13, 0.15), 6, 2),
          parent="Turret", x=0.15, y=m.step(0.1, 0.12, 0.14), z=0.11,
          shadow=False)
    # THE EYE, and it is the only deliberate thing on the whole tower - so it
    # is big, low and at the front, under a hood of the dark tone that stops it
    # reading as another bubble.
    eye = m.step(0.08, 0.1, 0.125)
    m.put("Hood", m.capsule(m.deep, eye + 0.05, eye * 1.2, 6, 3),
          parent="Turret", y=0.06, z=-m.step(0.18, 0.21, 0.24),
          scale=(1.2, 0.9, 1.0))
    m.put("Eye", m.gem(m.glow, eye, eye * 1.6, 6, 3), parent="Turret",
          y=0.0, z=-m.step(0.22, 0.25, 0.28), shadow=False)
    breathe(m, "Turret", 0.02, 0.16)
    m.pivot("Muzzle", "Turret", y=0.06, z=-0.3)
    # Falling rather than rising, and slower than anything else in the roster.
    # Sludge does not give off motes, it drips.
    aura(m, 0.32, base + 0.42, count=14, rise=(0.02, 0.08), lifetime=2.6,
         drift=-0.14)
    return base + m.step(0.42, 0.5, 0.6)


# --- Earth ------------------------------------------------------------------

def build_ancient_warden(m):
    """Earth 1: a tree that thickens rather than a tower that gains parts.

        Lesser     a stump with a thin canopy over it and one throwing bough
        Greater    a proper trunk, bark plates, roots gripping the plinth, a
                   canopy twice the spread
        Ultimate   an ancient - a wide buttressed trunk with a face lit in it
                   and a canopy that fills the cell, leaf aura

    This is the tower a player puts at the FRONT of a maze to be chewed on, so
    it is the widest and heaviest thing in the roster. The arm is what makes it
    a tower rather than scenery, and it is there at every tier.
    """
    base = plinth(m, 0.36, 0.33, 0.16, 5)
    trunk = m.step(0.36, 0.42, 0.5)
    m.put("Trunk", m.cyl(m.body, m.step(0.16, 0.2, 0.25),
                         m.step(0.22, 0.28, 0.34), trunk, 5),
          y=base + trunk * 0.5)
    root = m.prism(m.deep, 0.1, m.step(0.14, 0.2, 0.26), 0.09)
    m.ring_of(m.features() + 2, m.step(0.25, 0.28, 0.32),
              lambda i, x, z, a: m.put(
                  "Root%d" % (i + 1), root, x=x, y=base + 0.07, z=z, ry=a,
                  rx=-0.7))
    bark = m.box(m.deep, 0.06, trunk * 0.78, 0.05)
    m.ring_of(m.features() + 1, m.step(0.2, 0.24, 0.29),
              lambda i, x, z, a: m.put(
                  "Bark%d" % (i + 1), bark, x=x, y=base + trunk * 0.55, z=z,
                  ry=a))
    m.pivot("Turret", ".", y=base + trunk + m.step(0.08, 0.12, 0.16))
    leaf = m.prism(m.pale, m.step(0.18, 0.24, 0.3), m.step(0.16, 0.2, 0.24),
                   m.step(0.12, 0.15, 0.19))
    m.ring_of(m.features() + 1, m.step(0.17, 0.21, 0.26),
              lambda i, x, z, a: m.put(
                  "Leaf%d" % (i + 1), leaf, parent="Turret", x=x,
                  y=m.step(0.1, 0.14, 0.18), z=z, ry=a, rx=-0.3))
    m.put("Heart", m.gem(m.glow, m.step(0.07, 0.09, 0.11),
                         m.step(0.14, 0.18, 0.22), 6, 3),
          parent="Turret", y=0.1, shadow=False)
    if m.rung >= 2:
        # A FACE in the trunk, and only at the top tier. It is the one thing
        # that says this stopped being a tree and started being an Ancient.
        m.put("Eyes", m.box(m.glow, 0.19, 0.035, 0.02), y=base + trunk * 0.72,
              z=-m.step(0.0, 0.0, 0.27), shadow=False)
        m.put("Brow", m.box(m.deep, 0.24, 0.06, 0.06), y=base + trunk * 0.8,
              z=-0.25)
    m.pivot("Arm", "Turret", y=-0.02)
    m.put("Bough", m.box(m.deep, 0.1, 0.1, m.step(0.24, 0.3, 0.36)),
          parent="Turret/Arm", z=m.step(-0.11, -0.13, -0.16))
    m.put("Rock", m.gem(m.pale, m.step(0.11, 0.13, 0.16),
                        m.step(0.18, 0.22, 0.27), 5, 3),
          parent="Turret/Arm", z=m.step(-0.24, -0.28, -0.34))
    m.pivot("Muzzle", "Turret", z=m.step(-0.34, -0.38, -0.44))
    aura(m, 0.34, base + trunk * 0.8, count=18, rise=(0.08, 0.2),
         lifetime=2.6, drift=-0.02)
    return base + trunk + m.step(0.3, 0.36, 0.42)


def build_scorpion(m):
    """Earth 2: a thorn plant, and the count of its spines is the tier.

        Lesser     a thin stalk with a small closed pod on it, three spines
        Greater    a taller stalk, a heavier pod, five spines and side buds
        Ultimate   a long stalk under a pod ringed by seven spines the length
                   of the pod itself, pollen aura

    The user asked for spiky plants rather than the source's scorpion, and the
    path is pure single target - so it is one narrow stalk with one bulb, and
    every tier adds thorns to that bulb rather than mass to the tower. It is
    the THINNEST thing in the roster, which is the read it wants next to the
    Ancient Warden it shares an element with.
    """
    base = plinth(m, 0.28, 0.25, 0.14, 5)
    m.put("Root", m.capsule(m.deep, 0.16, 0.2, 6, 3), y=base + 0.1)
    stalk = m.step(0.46, 0.54, 0.64)
    m.put("Stalk", m.cyl(m.body, 0.075, 0.13, stalk, 5),
          y=base + 0.1 + stalk * 0.5)
    thorn = m.prism(m.pale, 0.05, m.step(0.14, 0.18, 0.22), 0.04)
    m.ring_of(m.features() + 1, 0.13, lambda i, x, z, a: m.put(
        "Thorn%d" % (i + 1), thorn, x=x, y=base + 0.24, z=z, ry=a, rx=-1.0))
    if m.rung >= 1:
        # Side buds: small pods on their own short stalks, so the plant reads
        # as having grown rather than as having been scaled up.
        bud = m.gem(m.body, 0.07, 0.13, 6, 3)
        core = m.gem(m.glow, 0.045, 0.09, 5, 2)
        m.ring_of(m.step(0, 2, 3), 0.19, lambda i, x, z, a: (
            m.put("Bud%d" % (i + 1), bud, x=x, y=base + 0.1 + stalk * 0.55,
                  z=z),
            m.put("BudCore%d" % (i + 1), core, x=x,
                  y=base + 0.1 + stalk * 0.55, z=z - 0.05, shadow=False)))
    m.pivot("Turret", ".", y=base + 0.16 + stalk)
    m.pivot("Bulb", "Turret")
    pod = m.step(0.1, 0.125, 0.155)
    m.put("Pod", m.gem(m.deep, pod, pod * 3.0, 6, 3), parent="Turret/Bulb")
    m.put("PodCore", m.gem(m.glow, pod * 0.8, pod * 2.3, 6, 3),
          parent="Turret/Bulb", z=-pod * 0.55, shadow=False)
    spine = m.prism(m.pale, 0.04, m.step(0.3, 0.4, 0.52), 0.032)
    m.ring_of(m.features(), pod * 0.8, lambda i, x, z, a: m.put(
        "Spine%d" % (i + 1), spine, parent="Turret/Bulb", x=x, z=z - 0.1,
        ry=a, rx=-1.45))
    m.pivot("Muzzle", "Turret", z=-0.24)
    aura(m, 0.2, base + stalk * 0.8, count=14, rise=(0.1, 0.24), lifetime=2.4)
    return base + m.step(0.72, 0.82, 0.94)


# --- Arcane -----------------------------------------------------------------

def build_spellslinger(m):
    """Arcane 1: floating slabs, and the tier is how many are in the air.

        Lesser     ONE rune slab hanging over a dais, a short staff behind it
        Greater    TWO slabs, one over the other, the sigil ring turning
        Ultimate   THREE slabs stacked clear of the ground with a wide ring of
                   sigils around them, arcane aura

    The caster path, so everything on it is floating and nothing on it is a
    weapon: a slab, a ring of marks, and a staff spire behind. The tower has no
    barrel at all, which is the point - it does its damage with spells and its
    silhouette should not promise otherwise.

    The sigils are LIT rather than metal now, which is what they always wanted
    to be: a rune drawn in tier metal was the one part of an Arcane tower that
    was not Arcane coloured.
    """
    base = plinth(m, 0.3, 0.27, 0.15, 4)
    m.put("Dais", m.cyl(m.body, 0.22, 0.26, m.step(0.16, 0.2, 0.24), 4),
          y=base + m.step(0.08, 0.1, 0.12))
    spire = m.step(0.54, 0.62, 0.72)
    m.put("Spire", m.cyl(m.pale, 0.045, 0.075, spire, 4),
          y=base + 0.12 + spire * 0.5, z=0.16)
    m.put("SpireTip", m.gem(m.glow, 0.07, 0.16, 4, 2),
          y=base + 0.16 + spire, z=0.16, shadow=False)
    runes(m, 4, 0.21, base + 0.12, (0.035, 0.14, 0.02))
    m.pivot("Turret", ".", y=base + m.step(0.4, 0.5, 0.62))
    slabs = m.step(1, 2, 3)
    for index in range(slabs):
        wide = m.step(0.2, 0.19, 0.19) - index * 0.035
        m.put("Slab%d" % (index + 1), m.cyl(m.pale, wide, wide, 0.055, 4),
              parent="Turret", y=index * 0.15, ry=0.785 + index * 0.5)
    m.put("SlabCore", m.gem(m.glow, m.step(0.1, 0.12, 0.14),
                            m.step(0.22, 0.28, 0.34), 4, 2),
          parent="Turret", y=m.step(0.0, 0.07, 0.15), shadow=False)
    m.pivot("Sigils", "Turret")
    sigil = m.box(m.glow, 0.045, m.step(0.11, 0.14, 0.17), 0.02)
    m.ring_of(m.features() + 2, m.step(0.24, 0.28, 0.33),
              lambda i, x, z, a: m.put(
                  "Sigil%d" % (i + 1), sigil, parent="Turret/Sigils", x=x, z=z,
                  ry=a, shadow=False))
    m.bobber("Bob", "Turret", 0.032, 0.26)
    m.pivot("Muzzle", "Turret", z=-0.22)
    aura(m, 0.26, base + 0.3, count=16, rise=(0.16, 0.34), lifetime=2.0)
    return base + m.step(0.78, 0.88, 1.0)


def build_arcane_orb(m):
    """Arcane 2: a pylon that gives up its own tower.

        Lesser     a squat crystalline pylon with a small orb sitting on it
        Greater    a taller pylon, a bigger orb clear of the top of it, shards
        Ultimate   NO PYLON AT ALL - a portal orb hanging over a bare pad,
                   ringed by turning shards, arcane aura

    The one tower in the roster with no structure under it at the top tier, and
    it is the user's own suggestion: not everything has to be a tower, some of
    them can just be a floating thing that turns. It has to be THIS path,
    because the reference art's own 30,000g Arcane tower is a glowing hole in
    the air with nothing holding it up.

    The pad stays. Every tower stands on one, however little of it touches the
    ground - see pad().
    """
    if m.rung >= 2:
        pad(m)
        base = 0.0
        # A low collar of shards on the floor instead of a plinth, so the cell
        # still reads as built on from directly above.
        stone = m.gem(m.deep, 0.09, 0.16, 4, 2)
        m.ring_of(6, 0.28, lambda i, x, z, a: m.put(
            "Stone%d" % (i + 1), stone, x=x, y=0.05, z=z, rz=0.3 * math.sin(a),
            rx=-0.3 * math.cos(a)))
    else:
        base = plinth(m, 0.32, 0.29, 0.16, 4)
        pylon = m.step(0.36, 0.5, 0.0)
        m.put("Pylon", m.cyl(m.body, 0.14, 0.26, pylon, 4),
              y=base + pylon * 0.5)
        buttress = m.prism(m.deep, 0.09, pylon * 0.7, 0.07)
        m.ring_of(4, 0.22, lambda i, x, z, a: m.put(
            "Buttress%d" % (i + 1), buttress, x=x, y=base + pylon * 0.36, z=z,
            ry=a))
        base += pylon
    m.pivot("Turret", ".", y=base + m.step(0.16, 0.2, 0.62))
    orb = m.step(0.14, 0.18, 0.24)
    m.put("Orb", m.gem(m.glow, orb, orb * 2.0, 6, 4), parent="Turret",
          shadow=False)
    if m.rung >= 2:
        # A dark eye inside the light. What makes the top tier read as a HOLE
        # rather than as a bigger lamp.
        m.put("Void", m.gem(m.deep, orb * 0.6, orb * 1.3, 6, 3),
              parent="Turret", z=-orb * 0.5)
    m.pivot("Shards", "Turret")
    shard = m.gem(m.pale, m.step(0.045, 0.055, 0.07),
                  m.step(0.22, 0.28, 0.38), 4, 2)
    m.ring_of(m.features() + 1, m.step(0.24, 0.28, 0.34),
              lambda i, x, z, a: m.put(
                  "Shard%d" % (i + 1), shard, parent="Turret/Shards", x=x, z=z,
                  rz=0.32 * math.sin(a), rx=-0.32 * math.cos(a)))
    if m.rung >= 2:
        m.bobber("Bob", "Turret", 0.04, 0.22)
    m.pivot("Muzzle", "Turret", z=-0.24)
    aura(m, 0.3, 0.2, count=18, rise=(0.14, 0.3), lifetime=2.2)
    return base + m.step(0.4, 0.46, 1.02)


# --- Primal -----------------------------------------------------------------

def build_primalist(m):
    """Primal 1: a geode on an altar, opening further at every tier.

        Lesser     a SHUT geode, one dull gold seam across it
        Greater    it has split: a gold cavity showing, veins running out of it
        Ultimate   the geode is a cracked shell around a mass of molten gold,
                   gold aura

    The gold making tower, so it says GOLD - and it is the one place a path is
    allowed a colour the element does not own, because Primal is blood red and
    a red gold mine says nothing at all. See style.PATH_ACCENTS.

    It is also the only tower with a reason to be spread out rather than packed
    together, so it wants to be recognisable one at a time.
    """
    base = plinth(m, 0.33, 0.3, 0.15, 6)
    m.put("Altar", m.cyl(m.body, 0.24, 0.29, 0.24, 6), y=base + 0.12)
    m.put("Table", m.cyl(m.pale, 0.26, 0.23, 0.06, 6), y=base + 0.26)
    vine = m.capsule(m.deep, 0.035, 0.3, 5, 2)
    m.ring_of(m.features() + 1, 0.27, lambda i, x, z, a: m.put(
        "Vine%d" % (i + 1), vine, x=x, y=base + 0.14, z=z, ry=a, rx=0.35))
    m.pivot("Turret", ".", y=base + 0.36)
    m.pivot("Geode", "Turret")
    shell = m.step(0.2, 0.23, 0.27)
    # The shell is one closed lump at the Lesser and two halves pulled apart
    # above it, which is the whole tier read of the path.
    if m.rung < 1:
        m.put("Shell", m.gem(m.pale, shell, shell * 1.7, 6, 3),
              parent="Turret/Geode", y=0.14)
        m.put("Seam", m.box(m.accent, shell * 1.6, 0.03, 0.05),
              parent="Turret/Geode", y=0.2, rz=0.2, shadow=False)
    else:
        half = m.gem(m.pale, shell, shell * 1.7, 6, 3)
        gap = m.step(0.0, 0.09, 0.15)
        m.put("ShellL", half, parent="Turret/Geode", x=-gap, y=0.14,
              rz=m.step(0.0, 0.22, 0.42), scale=(0.72, 1.0, 1.0))
        m.put("ShellR", half, parent="Turret/Geode", x=gap, y=0.14,
              rz=m.step(0.0, -0.22, -0.42), scale=(0.72, 1.0, 1.0))
    m.put("Cavity", m.gem(m.accent, shell * m.step(0.5, 0.72, 0.92),
                          shell * m.step(0.9, 1.3, 1.7), 6, 3),
          parent="Turret/Geode", y=0.16, z=-0.04, shadow=False)
    nugget = m.gem(m.accent, 0.045, 0.08, 5, 2)
    m.ring_of(m.features(), m.step(0.16, 0.2, 0.25), lambda i, x, z, a: m.put(
        "Nugget%d" % (i + 1), nugget, parent="Turret/Geode", x=x,
        y=m.step(0.02, 0.03, 0.04), z=z, shadow=False))
    breathe(m, "Turret", 0.014, 0.18)
    m.pivot("Muzzle", "Turret", y=0.14, z=-0.2)
    aura(m, 0.26, base + 0.34, count=16, rise=(0.14, 0.3), lifetime=2.0)
    return base + m.step(0.58, 0.68, 0.8)


def build_beastmaster(m):
    """Primal 2: a totem, and the horns are the tier.

        Lesser     a short post with a low brow and two stubby horns
        Greater    a taller totem, horns swept up and out, skulls round it
        Ultimate   a heavy totem under horns wider than the cell, eyes lit,
                   blood aura

    The horns are what the beast comes out of, so they are the whole
    silhouette: forward facing, on a pivot, and swung on the windup. Against
    the Primalist's round altar it is all verticals, which is the read the two
    Primal paths need from each other.
    """
    base = plinth(m, 0.32, 0.29, 0.15, 6)
    post = m.step(0.34, 0.4, 0.48)
    m.put("Post", m.cyl(m.body, 0.16, 0.24, post, 6), y=base + post * 0.5)
    m.put("Drum", m.cyl(m.deep, 0.22, 0.22, 0.16, 8), y=base + 0.14, ry=0.3)
    m.put("DrumSkin", m.cyl(m.pale, 0.2, 0.2, 0.03, 8), y=base + 0.22)
    skull = m.prism(m.pale, 0.09, 0.16, 0.07)
    m.ring_of(m.features(), 0.19, lambda i, x, z, a: m.put(
        "Skull%d" % (i + 1), skull, x=x, y=base + post * 0.85, z=z, ry=a))
    m.pivot("Turret", ".", y=base + post + m.step(0.1, 0.14, 0.18))
    m.pivot("Horns", "Turret")
    m.put("Brow", m.box(m.pale, m.step(0.22, 0.26, 0.32), 0.1,
                        m.step(0.12, 0.14, 0.16)),
          parent="Turret/Horns", z=-0.06)
    # Swept UP and out rather than forward. Pointed along the tower's facing
    # they were hidden behind the brow from every angle a maze is seen at.
    horn = m.capsule(m.pale, m.step(0.04, 0.05, 0.06),
                     m.step(0.26, 0.38, 0.52), 5, 2)
    reach = m.step(0.13, 0.17, 0.22)
    m.put("HornL", horn, parent="Turret/Horns", x=-reach, y=0.16, z=-0.1,
          rx=0.5, rz=m.step(0.6, 0.8, 1.0))
    m.put("HornR", horn, parent="Turret/Horns", x=reach, y=0.16, z=-0.1,
          rx=0.5, rz=m.step(-0.6, -0.8, -1.0))
    m.put("Eyes", m.box(m.glow, m.step(0.13, 0.16, 0.2), 0.03, 0.02),
          parent="Turret/Horns", y=0.02, z=-0.13, shadow=False)
    breathe(m, "Turret", 0.016, 0.2)
    m.pivot("Muzzle", "Turret", z=-0.28)
    aura(m, 0.24, base + post * 0.7, count=16, rise=(0.16, 0.34), lifetime=2.0)
    return base + post + m.step(0.32, 0.38, 0.46)


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

    "moonbeam": build_moonbeam,
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
        m = ElementModel(row["key"], row["element"], row["ti"], row["shape"])
        heights[row["key"]] = round(BUILDERS[row["shape"]](m) * m.h, 3)
        io.open("%s/%s_model.tscn" % (OUT, row["key"]), "w", encoding="utf-8",
                newline="\n").write(m.render())
    return heights
