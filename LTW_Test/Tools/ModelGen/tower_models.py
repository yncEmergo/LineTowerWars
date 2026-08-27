"""The nine Basic tower silhouettes, and the tier rules laid over them.

Read style.py first: it holds the language, this file holds the shapes that
speak it. Every builder below is handed a TowerModel and answers one question -
what does this branch LOOK like - while the tier rules (collar, crown, halo,
mass, trim, glow) are applied around it and are the same for all nine.

THE CONTRACT EVERY TOWER MODEL MEETS, which the prefab wiring depends on:

    Base                the shared ground patch, tower_foundation.tscn
    Turret              the node that turns to face a target
    Turret/Muzzle       the node shots leave from

A model may also offer a node for the PREFAB to animate, named in
roster.ANIMATION: `Turret/Spinner` for a blade disc, `Turret/Swing` for a
hammer, `Turret/Barrel` or `Turret/Rack` for something that kicks back. Those
components live in the prefab and not here, because they need the unit and a
model does not have one - the build ghost uses this same scene and must not
recoil at anything.

Every tower has all three, including the ones with nothing to aim - a Crusher's
hammer swinging round to face a creep is fine, and one wiring that is identical
across the whole roster is worth more than nine special cases. A new tower that
forgets one of them wires up to null and silently never fires.

BASE SHAPE IS PART OF THE LINE'S IDENTITY, not a default. A roster where
every tower is a round drum on a round plinth reads as one tower at nine
sizes, so plinth() takes the number of sides and each line picks one:

    Archer   4 - square. A watchtower is a square tower, and it is the only
             line tall enough for the corners to read from above
    Cutter   6 - hexagonal. Chunky machinery, still round enough to spin on
    Sentry   8 - round. Open frames and floating cores, which want no corners
    Turret   4 - square, breaking from its own line on purpose: it is the one
             branch that shoots at nothing on the ground, and a launch pad
             reads differently from the ring it grew out of

TONE IS PART OF IT TOO. Nothing should be built entirely out of `body`: a
plinth takes `deep`, a head or a barrel takes `pale`, and the bulk between them
takes `body`. See modelkit for why.

AUTHORED UNITS ARE UNSCALED. Each builder returns the tower's height in those
units; generate() multiplies by the tier's HEIGHT ramp. Do not pre-scale
anything, and remember that width and height ramp separately - see modelkit.
"""

import io
import os

import style as ts
from modelkit import Model
from roster import TOWERS

OUT = "Scenes/Units/Models/Towers"
FOUNDATION = "res://Scenes/Units/Models/tower_foundation.tscn"
UNIT_MODEL_SCRIPT = "res://Scripts/Units/UnitModel.gd"
MAT = "res://Resources/Materials/Towers"


class TowerModel(Model):
    """A Model that also knows which rung of the price ladder it is on, which
    is the one thing every tier rule needs and nothing else does."""

    def __init__(self, key, line, tier_index):
        Model.__init__(
            self,
            "".join(part.capitalize() for part in key.split("_")) + "Model",
            UNIT_MODEL_SCRIPT,
            {
                "body": "%s/%s_plate.tres" % (MAT, line),
                "deep": "%s/%s_plate_deep.tres" % (MAT, line),
                "pale": "%s/%s_plate_pale.tres" % (MAT, line),
                "trim": "%s/trim_t%d.tres" % (MAT, tier_index),
                "glow": "%s/energy_%s_t%d.tres" % (MAT, line, tier_index),
            },
            ts.mass(tier_index),
            ts.height_scale(tier_index),
        )
        self.ti = tier_index


# --- the parts every tower carries -----------------------------------------

def plinth(m, bottom=0.32, top=0.28, height=0.16, sides=8):
    """Foundation patch, plinth, and the base trim ring from the 30g tier up.

    The ring is the tower's FIRST piece of metal, and a 10g tower deliberately
    has none. That makes the 10g -> 30g upgrade - the first one any player ever
    buys - a visible change rather than a slightly larger lump, which is worth
    more than every tower carrying the same ring.
    """
    m.scene.node("Base", None, ".", instance=m.scene.ext("PackedScene", FOUNDATION))
    # The DEEP tone: a plinth is the part carrying everything else, and
    # reading it as the same material as the head flattens the whole tower.
    m.put("Plinth", m.cyl(m.deep, top, bottom, height, sides), y=height * 0.5)
    if ts.has_base_trim(m.ti):
        m.put("BaseTrim", m.torus(m.trim, top - 0.015, top + 0.035, 14, 5),
              y=height, shadow=False)
    return height


def bolts(m, at, radius, count=6, size=0.032):
    """Tier rule: studs around the shoulder, from the 1,000g tier up.

    The quietest of the stepped rules on purpose. It sits between the collar
    and the crown fins, so the 1,000g tier gains something without stealing the
    silhouette change that belongs to 5,000g.
    """
    if not ts.has_bolts(m.ti):
        return
    stud = m.gem(m.trim, size, size * 1.6, 5, 2)
    m.ring_of(count, radius, lambda i, x, z, a: m.put(
        "Bolt%d" % (i + 1), stud, x=x, y=at, z=z, shadow=False))


def collar(m, at, inner=0.11, outer=0.17):
    """Tier rule 4. A trim ring under the head, from the 150g tier up."""
    if ts.has_collar(m.ti):
        m.put("Collar", m.torus(m.trim, inner, outer, 12, 5), y=at, shadow=False)


def crown(m, at, radius, count=4, size=(0.06, 0.16, 0.05)):
    """Tier rule 5. Fins around the shoulder, from the 5,000g tier up."""
    if not ts.has_crown(m.ti):
        return
    mesh = m.prism(m.trim, size[0], size[1], size[2])
    m.ring_of(count, radius, lambda i, x, z, a: m.put(
        "Fin%d" % (i + 1), mesh, x=x, y=at, z=z, ry=a, rx=0.28))


def halo(m, at, radius=0.26):
    """Tier rule 6. A turning ring floating above the tower, at 25,000g only.

    The one part of a tower that moves for no gameplay reason at all, which is
    exactly why it is reserved for the top of the ladder: motion is the loudest
    thing a top down camera can show, so nothing below an Ultimate gets any.

    `at` has to clear everything the tower puts above its own body - a Turret's
    rack reaches higher than its plinth does - or the ring reads as a second
    object floating alongside rather than as a crown on this one.
    """
    if not ts.has_halo(m.ti):
        return
    m.pivot("Halo", ".", y=at)
    m.put("HaloRing", m.torus(m.trim, radius - 0.05, radius, 16, 6),
          parent="Halo", rx=0.22, shadow=False)
    m.put("HaloCore", m.gem(m.glow, 0.05, 0.10, 6, 2), parent="Halo", shadow=False)
    m.spinner("HaloSpin", "Halo", 0.22)


# --- the nine branches -----------------------------------------------------

def build_archer(m):
    """The 10g/30g stub: a square post carrying a crossbow head.

    The two tiers are deliberately barely the same object. At 10g it is a
    stump: half the height, no shaft worth the name, one bare bar laid across
    it, and every part of it the raw deep tone. At 30g it grows a proper
    shaft, a pale head, limbs, a trim string and a lit sight.

    That gap is the point. This is the first upgrade a player ever buys, and it
    should be the one they can see from across the map.
    """
    if m.ti >= 1:
        base = plinth(m, 0.28, 0.24, 0.14, 4)
        m.put("Shaft", m.cyl(m.body, 0.115, 0.15, 0.50, 4), y=base + 0.25)
        m.pivot("Turret", ".", y=base + 0.52)
        m.put("Stock", m.box(m.pale, 0.07, 0.07, 0.34), parent="Turret")
        limb = m.box(m.pale, 0.22, 0.035, 0.045)
        m.put("LimbL", limb, parent="Turret", x=-0.11, z=-0.10, ry=-0.34)
        m.put("LimbR", limb, parent="Turret", x=0.11, z=-0.10, ry=0.34)
        m.put("String", m.box(m.trim, 0.34, 0.016, 0.016), parent="Turret", z=0.02)
        m.put("Sight", m.gem(m.glow, 0.045, 0.09, 6, 2), parent="Turret",
              y=0.07, z=0.04, shadow=False)
        m.pivot("Muzzle", "Turret", z=-0.20)
        return base + 0.62

    base = plinth(m, 0.26, 0.23, 0.12, 4)
    m.put("Stump", m.cyl(m.deep, 0.14, 0.19, 0.22, 4), y=base + 0.11)
    m.pivot("Turret", ".", y=base + 0.24)
    m.put("CrossBar", m.box(m.body, 0.30, 0.05, 0.06), parent="Turret", z=-0.04)
    m.pivot("Muzzle", "Turret", z=-0.18)
    return base + 0.30


def build_watch(m):
    """A tall tapered spire with one long barrel: the reach branch."""
    base = plinth(m, 0.31, 0.26, 0.16, 4)
    # Barely tapered on purpose: a 4-sided cylinder that narrows hard reads as
    # a cone from above and throws away the square the line is built on.
    m.put("Shaft", m.cyl(m.body, 0.175, 0.225, 0.72, 4), y=base + 0.36)
    collar(m, base + 0.72, 0.10, 0.16)
    bolts(m, base + 0.52, 0.17)
    crown(m, base + 0.62, 0.17)
    m.pivot("Turret", ".", y=base + 0.82)
    m.put("Housing", m.cyl(m.pale, 0.10, 0.13, 0.14, 4), parent="Turret")
    m.put("Barrel", m.cyl(m.pale, 0.045, 0.06, 0.46, 6, "z"), parent="Turret",
          y=0.02, z=-0.22, rx=1.5708)
    m.put("BarrelTip", m.torus(m.trim, 0.05, 0.075, 8, 4), parent="Turret",
          y=0.02, z=-0.42, rx=1.5708)
    m.put("Brace", m.box(m.deep, 0.16, 0.05, 0.09), parent="Turret",
          y=-0.04, z=-0.10)
    m.put("Lens", m.gem(m.glow, 0.05, 0.11, 6, 2), parent="Turret",
          y=0.11, shadow=False)
    m.pivot("Muzzle", "Turret", y=0.02, z=-0.48)
    halo(m, base + 1.48)
    return base + 0.95


def build_cannon(m):
    """A squat drum with a short mortar tube tilted at the sky."""
    base = plinth(m, 0.32, 0.30, 0.14, 8)
    m.put("Drum", m.cyl(m.body, 0.25, 0.30, 0.30, 8), y=base + 0.15)
    collar(m, base + 0.30, 0.19, 0.245)
    # Buttresses. The one place a Cannon's tier shows in its outline rather
    # than only in its metal.
    rib = m.box(m.deep, 0.055, 0.24, 0.10)
    m.ring_of(ts.FEATURE_COUNT[m.ti], 0.27, lambda i, x, z, a: m.put(
        "Rib%d" % (i + 1), rib, x=x, y=base + 0.13, z=z, ry=a))
    bolts(m, base + 0.24, 0.31)
    crown(m, base + 0.32, 0.26)
    m.pivot("Turret", ".", y=base + 0.32)
    m.put("Yoke", m.box(m.deep, 0.30, 0.10, 0.16), parent="Turret")
    tilt = -0.96
    # A pivot carrying the tilt, so a recoil along its local Z travels back
    # down the bore rather than sideways through it.
    m.pivot("Barrel", "Turret", y=0.22, z=-0.09, rx=tilt)
    m.put("Tube", m.cyl(m.pale, 0.10, 0.125, 0.30, 8, "z"), parent="Turret/Barrel")
    m.put("Mouth", m.torus(m.trim, 0.088, 0.125, 10, 5),
          parent="Turret/Barrel", z=-0.17)
    m.put("Vent", m.box(m.glow, 0.13, 0.045, 0.05), parent="Turret",
          y=0.055, z=0.10, shadow=False)
    m.pivot("Muzzle", "Turret", y=0.42, z=-0.23)
    halo(m, base + 1.15)
    return base + 0.70


def build_cutter(m):
    """The 10g/30g stub: a low block with one bar blade across it."""
    base = plinth(m, 0.28, 0.26, 0.14, 6)
    if m.ti >= 1:
        m.put("Body", m.cyl(m.body, 0.22, 0.26, 0.20, 6), y=base + 0.10)
        m.pivot("Turret", ".", y=base + 0.22)
        m.put("Hub", m.cyl(m.pale, 0.09, 0.11, 0.10, 6), parent="Turret")
        m.pivot("Spinner", "Turret")
        m.put("Blade", m.box(m.pale, 0.40, 0.028, 0.08),
              parent="Turret/Spinner", y=0.03)
        m.put("Edge", m.box(m.glow, 0.42, 0.012, 0.03), parent="Turret/Spinner",
              y=0.048, shadow=False)
        m.pivot("Muzzle", "Turret", z=-0.20)
        return base + 0.30

    # 10g: a block with a bar bolted across it. No hub, no lit edge, and the
    # whole thing in the raw deep tone.
    m.put("Body", m.cyl(m.deep, 0.19, 0.23, 0.14, 6), y=base + 0.07)
    m.pivot("Turret", ".", y=base + 0.15)
    m.pivot("Spinner", "Turret")
    m.put("Blade", m.box(m.body, 0.26, 0.03, 0.075),
          parent="Turret/Spinner", y=0.02)
    m.pivot("Muzzle", "Turret", z=-0.18)
    return base + 0.22


def build_carver(m):
    """A wide hub under a horizontal disc of blades: the speed branch."""
    base = plinth(m, 0.31, 0.28, 0.14, 6)
    m.put("Body", m.cyl(m.body, 0.21, 0.29, 0.26, 8), y=base + 0.13)
    collar(m, base + 0.26, 0.20, 0.26)
    bolts(m, base + 0.13, 0.29)
    crown(m, base + 0.24, 0.24)
    m.pivot("Turret", ".", y=base + 0.30)
    m.put("Hub", m.cyl(m.pale, 0.10, 0.14, 0.14, 6), parent="Turret", y=0.02)
    m.pivot("Spinner", "Turret", y=0.06)
    blade = m.box(m.pale, 0.05, 0.026, 0.32)
    edge = m.box(m.glow, 0.02, 0.012, 0.32)

    def place_blade(i, x, z, a):
        m.put("Blade%d" % (i + 1), blade, parent="Turret/Spinner",
              x=x, z=z, ry=a)
        m.put("BladeEdge%d" % (i + 1), edge, parent="Turret/Spinner",
              x=x, y=0.018, z=z, ry=a, shadow=False)

    m.ring_of(ts.FEATURE_COUNT[m.ti], 0.17, place_blade)
    m.pivot("Muzzle", "Turret", z=-0.30)
    halo(m, base + 0.87)
    return base + 0.42


def build_crusher(m):
    """A piston column under a hammer head: the heavy branch.

    The hammer stays over its own cell on purpose. Hung further out it looked
    better alone and split into two objects in a maze, where a row of them
    overlapped their neighbours and each Ultimate's halo read as unattached.
    """
    base = plinth(m, 0.32, 0.27, 0.16, 6)
    m.put("Column", m.cyl(m.body, 0.15, 0.21, 0.44, 6), y=base + 0.22)
    piston = m.cyl(m.deep, 0.035, 0.035, 0.34, 6)  # upright, takes the height ramp
    m.ring_of(ts.FEATURE_COUNT[m.ti], 0.20, lambda i, x, z, a: m.put(
        "Piston%d" % (i + 1), piston, x=x, y=base + 0.19, z=z))
    collar(m, base + 0.44, 0.14, 0.21)
    bolts(m, base + 0.30, 0.22)
    crown(m, base + 0.40, 0.21)
    m.pivot("Turret", ".", y=base + 0.50)
    # Everything that swings hangs off one pivot, so the prefab's slam can turn
    # the arm and the head as a single piece. The pivot sits at the shoulder,
    # not at the hammer, or the head would orbit its own centre.
    m.pivot("Swing", "Turret")
    m.put("Arm", m.box(m.deep, 0.11, 0.11, 0.18), parent="Turret/Swing", z=-0.07)
    m.put("Hammer", m.box(m.pale, 0.30, 0.26, 0.24), parent="Turret/Swing",
          y=0.03, z=-0.19)
    m.put("HammerBand", m.box(m.trim, 0.32, 0.055, 0.26), parent="Turret/Swing",
          y=-0.09, z=-0.19)
    m.put("HammerCore", m.box(m.glow, 0.09, 0.14, 0.03), parent="Turret/Swing",
          y=0.04, z=-0.32, shadow=False)
    m.pivot("Muzzle", "Turret", y=-0.12, z=-0.21)
    halo(m, base + 1.37)
    return base + 0.82


def build_sentry(m):
    """The 10g/30g stub: a ring of posts holding a floating core.

    At 10g the core sits ON two posts and does not float or wear a cage. It
    starts hovering at 30g, which is the loudest upgrade tell in the game for
    the price of one component.
    """
    if m.ti >= 1:
        base = plinth(m, 0.28, 0.24, 0.14, 8)
        post = m.box(m.body, 0.05, 0.24, 0.05)
        m.ring_of(3, 0.17, lambda i, x, z, a: m.put(
            "Post%d" % (i + 1), post, x=x, y=base + 0.12, z=z, ry=a))
        m.put("Ring", m.torus(m.pale, 0.15, 0.21, 12, 5), y=base + 0.25,
              shadow=False)
        m.pivot("Turret", ".", y=base + 0.42)
        m.put("Core", m.gem(m.glow, 0.10, 0.22, 6, 3), parent="Turret",
              shadow=False)
        m.put("Cage", m.torus(m.trim, 0.115, 0.14, 10, 4), parent="Turret",
              rx=1.5708, shadow=False)
        m.bobber("Bob", "Turret", 0.035, 0.35)
        m.pivot("Muzzle", "Turret", z=-0.14)
        return base + 0.56

    # 10g: no ring, no cage, and the core RESTING in a cradle rather than
    # floating. It starts hovering at 30g, which is the loudest upgrade tell
    # in the game for the price of one component.
    base = plinth(m, 0.25, 0.22, 0.12, 8)
    m.put("Cradle", m.cyl(m.deep, 0.15, 0.20, 0.14, 8), y=base + 0.07)
    m.pivot("Turret", ".", y=base + 0.22)
    # Sitting proud of the cradle rather than sunk into it. A 10g tower should
    # look cheap, not look broken, and the core is the only thing on it that
    # says which line it belongs to.
    m.put("Core", m.gem(m.glow, 0.105, 0.20, 5, 2), parent="Turret", shadow=False)
    m.pivot("Muzzle", "Turret", z=-0.13)
    return base + 0.28


def build_defender(m):
    """A bigger floating core with shards turning around it: splash branch."""
    base = plinth(m, 0.32, 0.26, 0.14, 8)
    post = m.box(m.body, 0.055, 0.26, 0.055)
    m.ring_of(3, 0.19, lambda i, x, z, a: m.put(
        "Post%d" % (i + 1), post, x=x, y=base + 0.13, z=z, ry=a))
    m.put("Ring", m.torus(m.pale, 0.17, 0.24, 14, 5), y=base + 0.27, shadow=False)
    collar(m, base + 0.27, 0.24, 0.29)
    bolts(m, base + 0.14, 0.28)
    crown(m, base + 0.26, 0.24)
    m.pivot("Turret", ".", y=base + 0.50)
    m.put("Core", m.gem(m.glow, 0.14, 0.30, 6, 3), parent="Turret", shadow=False)
    m.pivot("Orbit", "Turret")
    shard = m.prism(m.trim, 0.07, 0.16, 0.05)
    m.ring_of(ts.FEATURE_COUNT[m.ti], 0.25, lambda i, x, z, a: m.put(
        "Shard%d" % (i + 1), shard, parent="Turret/Orbit",
        x=x, z=z, ry=a, rz=0.35))
    m.spinner("OrbitSpin", "Turret/Orbit", 0.35)
    m.bobber("Bob", "Turret", 0.045, 0.3)
    m.pivot("Muzzle", "Turret", z=-0.18)
    halo(m, base + 1.20)
    return base + 0.70


def build_turret(m):
    """A rack of tubes aimed at the sky.

    The one tower that CANNOT hit ground, so its whole outline says so: nothing
    on it points at the floor. That is the readability job this shape exists to
    do, and it should survive real art replacing the primitives.
    """
    base = plinth(m, 0.33, 0.30, 0.14, 4)
    m.put("Body", m.cyl(m.body, 0.24, 0.30, 0.24, 4), y=base + 0.12)
    collar(m, base + 0.24, 0.22, 0.28)
    bolts(m, base + 0.12, 0.30)
    crown(m, base + 0.22, 0.25)
    m.pivot("Turret", ".", y=base + 0.30)
    m.put("Cradle", m.box(m.deep, 0.28, 0.11, 0.22), parent="Turret")
    tubes = ts.FEATURE_COUNT[m.ti]
    tube = m.cyl(m.pale, 0.042, 0.05, 0.28, 6, "z")
    cap = m.gem(m.glow, 0.035, 0.07, 6, 2)
    # Fanned across x rather than around a ring, so the rack reads as one
    # battery pointed the same way rather than as a crown of spikes.
    spread = 0.075
    first = -spread * (tubes - 1) * 0.5
    tilt = -0.87
    m.pivot("Rack", "Turret")
    for i in range(tubes):
        x = first + spread * i
        m.put("Tube%d" % (i + 1), tube, parent="Turret/Rack",
              x=x, y=0.22, z=-0.05, rx=tilt)
        m.put("TubeCap%d" % (i + 1), cap, parent="Turret/Rack",
              x=x, y=0.40, z=-0.16, shadow=False)
    m.pivot("Muzzle", "Turret", y=0.44, z=-0.18)
    halo(m, base + 1.40)
    return base + 0.84


BRANCHES = {
    "archer": build_archer, "watch": build_watch, "cannon": build_cannon,
    "cutter": build_cutter, "carver": build_carver, "crusher": build_crusher,
    "sentry": build_sentry, "defender": build_defender, "turret": build_turret,
}


def generate():
    """Writes every tower model and answers each one's height in world units,
    which the prefabs need for their health bar and their click box."""
    os.makedirs(OUT, exist_ok=True)
    heights = {}
    for row in TOWERS:
        key, branch, gold = row[0], row[3], row[5]
        tier_index = ts.PRICE_TIERS.index(gold)
        m = TowerModel(key, row[2], tier_index)
        # Authored unscaled, so the tier's ramps are applied here rather than
        # inside every one of the nine builders. HEIGHT, not width - this is
        # how tall the finished tower stands, and the prefab hangs its health
        # bar off it.
        heights[key] = round(BRANCHES[branch](m) * m.h, 3)
        io.open("%s/%s_model.tscn" % (OUT, key), "w", encoding="utf-8",
                newline="\n").write(m.render())
    return heights
