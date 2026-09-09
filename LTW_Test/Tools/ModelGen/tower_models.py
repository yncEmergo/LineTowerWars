"""The nine Basic tower silhouettes, and the tier rules laid over them.

Read style.py first: it holds the language, this file holds the shapes that
speak it. Every builder below is handed a TowerModel and answers one question -
what does this branch LOOK like - while the shared tier rules (material, tint,
metal, parapet, corbels, pennant) are applied around it.

THE CONTRACT EVERY TOWER MODEL MEETS, which the prefab wiring depends on:

    Base                the shared ground patch, tower_foundation.tscn
    Turret              the node that turns to face a target
    Turret/Muzzle       the node shots leave from

A model may also offer a node for the PREFAB to animate, named in
roster.ANIMATION: `Turret/Spinner` for a saw, `Turret/Swing` for a piledriver's
weight, `Turret/Stock`, `Turret/Barrel` or `Turret/Rack` for something that
kicks back. Those components live in the prefab and not here, because they need
the unit and a model does not have one - the build ghost uses this same scene
and must not recoil at anything.

Every tower has all three, including the ones with nothing to aim - a
Stomper's frame swinging round to face a creep is fine, and one wiring that is
identical across the whole roster is worth more than nine special cases. A new
tower that forgets one of them wires up to null and silently never fires.

WHAT THIS ROSTER IS. A Basic tower is TIMBER that turns to STONE as it is
bought up, with an iron working part - blade, barrel, tubes, weight - whose
METAL changes with the tier. It replaced a roster of grey plated silhouettes
wearing a six rung ramp of trim metal; style.py has the long version of why.

FOUR RULES FOLLOW, and they are worth stating before touching a builder:

  EVERY UPGRADE MUST CHANGE ONE THING YOU CAN SEE. This is the rule the second
  pass was built to and it is the user's. The shared devices carry most of it -
  the stone darkens hard, the timber retreats, the metal goes copper, bronze,
  steel - but where they are not enough, the branch spends a SHAPE step: longer
  teeth, another storey, a roof over the gallery. See the table below.

  WHAT A SHAPE STEP MAY NOT DO IS LIE. The Cannon was given a SECOND BARREL at
  5,000g and it had to come back out: that tower fires one projectile, so a
  player counting two muzzles and seeing one shell leave has been told
  something untrue about the thing they just paid for. A silhouette step is
  worth a great deal and it is not worth that. The same rule is why the
  anti-air rack recoils on ONE tube and launches from that tube, out of three
  to six.

  A BRANCH KEEPS ITS IDENTITY, NOT ITS OUTLINE. The old rule was that a
  branch's silhouette never changes above the 150g split, and it was wrong for
  the expensive half of the roster - four separate branches came back reported
  as "these three look the same". A saw is always a saw and a cannon is always
  a cannon; how many blades and how many barrels is the tier's to spend.

  NO TORUS, ANYWHERE ON THIS ROSTER. The instruction was to take the metal
  rings off, and a ring is not a shape this roster uses any more - not as a
  trim band, not as a collar, not as a barrel hoop. Where a real object would
  have a band, use a STEP: two cylinders of different radius, which is how a
  cannon's reinforce is actually shaped and reads better from above.

  THE MATERIAL BOUNDARY IS AUTHORED, not painted on. A shaft is two stacked
  cylinders - masonry below, timber above - and `TowerModel.skin` picks which
  by the height a part sits at. That is what makes the stone visibly CLIMB the
  tower over four upgrades.

BASE SHAPE IS PART OF THE LINE'S IDENTITY and is DATA, in
style.LINES[line]["sides"]. A roster where every tower is a round drum on a
round plinth reads as one tower at nine sizes:

    Archer   4 - square. A watchtower is a square tower, and it is the only
             line tall enough for the corners to read from above
    Cutter   6 - hexagonal. Chunky machinery, still round enough to spin on
    Sentry   8 - round. Open frames and a lit orb, which want no corners
    Turret   4 - square, breaking from its own line on purpose: it is the one
             branch that shoots at nothing on the ground, and a launch pad
             reads differently from the tower it grew out of

AUTHORED UNITS ARE UNSCALED. Each builder returns the tower's height in those
units; generate() multiplies by the tier's HEIGHT ramp. Do not pre-scale
anything, and remember that width and height ramp separately - see modelkit.
"""

import io
import math
import os

import style as ts
from modelkit import Model
from roster import TOWERS

OUT = "Scenes/Units/Models/Towers"
FOUNDATION = "res://Scenes/Units/Models/tower_foundation.tscn"
UNIT_MODEL_SCRIPT = "res://Scripts/Units/UnitModel.gd"
MAT = "res://Resources/Materials/Towers"

# What each branch spends its SHAPE steps on, gathered here so they can be read
# against each other rather than dug out of six builders. The builders are the
# authority; this is how you check that every branch has an answer at every
# rung, which is the whole requirement.
#
#   branch      150g              1,000g            5,000g           25,000g
#   watch       open gallery      + corner caps     SECOND STOREY    ROOFED HOARDING
#   cannon      slim barrel       FAT barrel        heavy CARRIAGE   + mantlet
#   carver      many short teeth  + braces, rim     FEW LONG TEETH   + 2nd blade
#   crusher     ONE top beam      + braces          TWO crossed      + winch
#   defender    open columns      + lintels         SPLAYED CROWN    + bigger orb
#   turret      3 tubes           4 tubes           LONG tubes       + wing
#
# Every one of them is carried by the shared devices as well: the stone darkens
# hard, the timber retreats up the tower, the metal goes copper - bronze -
# steel - polished steel, and the Sentry line's orb climbs amber to cold white.


class TowerModel(Model):
    """A Model that also knows which rung of the price ladder it is on, which
    line it belongs to, how far its masonry has climbed, and which way its body
    is turned.

    Its materials are LAZY PROPERTIES rather than a dictionary handed to Model,
    and that is deliberate. A tower is built from three surfaces at three tones
    plus paint and glow - eleven files - and almost every tower uses well under
    half of them. An `ext_resource` is a LOAD TIME DEPENDENCY, so declaring all
    eleven on every model would make a Watch Tower pull in the iron it never
    draws and the paint a 10g tower is not allowed. Reaching for one through a
    property means a file is named only where it is actually used, and
    `Scene.ext` already dedupes, so asking twice costs nothing.
    """

    def __init__(self, key, line, tier_index):
        Model.__init__(
            self,
            "".join(part.capitalize() for part in key.split("_")) + "Model",
            UNIT_MODEL_SCRIPT,
            # Only the lit accent is eager, because every tower in the roster
            # carries one.
            {"glow": "%s/energy_%s_t%d.tres" % (MAT, line, tier_index)},
            ts.mass(tier_index),
            ts.height_scale(tier_index),
        )
        self.ti = tier_index
        self.line = line
        self.sides = ts.LINES[line]["sides"]
        # How far up this tower, in AUTHORED units, the masonry reaches. Set by
        # the builder once it knows its own height; left at 0 the whole tower
        # is timber, which is what the 10g and 30g towers want.
        self.stone_top = 0.0
        # How far the BODY is turned about its own Y, in radians. Only the
        # STATIC parts take it: the Turret aims in world space, so a rotated
        # parent would put every shot off by exactly this angle.
        self.yaw = 0.0

    # --- the three surfaces, at three tones -------------------------------

    def _surface(self, surface, tone):
        suffix = "" if tone == "base" else "_" + tone
        return self.scene.ext("Material", "%s/%s_t%d%s.tres" % (
            MAT, surface, self.ti, suffix))

    @property
    def wood(self):
        return self._surface("timber", "base")

    @property
    def wood_deep(self):
        return self._surface("timber", "deep")

    @property
    def wood_pale(self):
        return self._surface("timber", "pale")

    @property
    def stone(self):
        return self._surface("masonry", "base")

    @property
    def stone_deep(self):
        return self._surface("masonry", "deep")

    @property
    def stone_pale(self):
        return self._surface("masonry", "pale")

    @property
    def iron(self):
        return self._surface("iron", "base")

    @property
    def iron_deep(self):
        return self._surface("iron", "deep")

    @property
    def iron_pale(self):
        return self._surface("iron", "pale")

    @property
    def paint(self):
        """The line's matte accent, or None below 30g.

        None is the answer rather than a fallback colour, because a 10g tower
        having NO paint is the whole of the ladder's bottom rung - see
        style.PAINT_RAMP. A caller that draws something anyway would quietly
        give the cheapest tower in the game the tell that is supposed to arrive
        with its first upgrade.
        """
        if not ts.has_paint(self.ti):
            return None
        return self.scene.ext("Material", "%s/paint_%s_t%d.tres" % (
            MAT, self.line, self.ti))

    # --- where the stone ends ---------------------------------------------

    def set_stone_top(self, total_height):
        """Works out how far the masonry climbs, from the tower's own height."""
        self.stone_top = total_height * ts.stone_share(self.ti)

    def skin(self, y, tone="base"):
        """Masonry or timber, for a part whose middle sits at height `y`.

        THE ONE FUNCTION THE WHOLE MATERIAL LADDER RUNS THROUGH. A builder
        never asks for timber or stone directly for a structural part - it asks
        what belongs at this height - so a tier that moves the boundary moves
        every tower's parts with it and none of them can disagree.
        """
        return self._surface("masonry" if y <= self.stone_top else "timber",
                             tone)


# --- the parts every tower carries -----------------------------------------

def footing(m, top, bottom, height, sides=None, stone=False):
    """The shared foundation patch, and the tower's own footing on top of it.

    The footing takes the DEEP tone: it is the part carrying everything else,
    and reading it as the same shade as the gallery flattens the whole tower.
    """
    sides = m.sides if sides is None else sides
    m.scene.node("Base", None, ".", instance=m.scene.ext("PackedScene", FOUNDATION))
    material = m.stone_deep if stone else m.skin(height * 0.5, "deep")
    m.put("Footing", m.cyl(material, top, bottom, height, sides),
          y=height * 0.5, ry=m.yaw)
    return height


def shaft(m, base, height, top_r, bottom_r, sides=None, name="Shaft"):
    """The tower's body, as TWO stacked cylinders split at the material line.

    This is the tier ladder's loudest rule made geometry. Below the line it is
    masonry, above it timber, and the join moves up the tower every time the
    player buys an upgrade. One cylinder with a blended material would have
    been easier and would have said nothing: what reads from a top down camera
    is the BOUNDARY, a hard line with a different surface either side of it.

    Returns the height of the top of the shaft.
    """
    sides = m.sides if sides is None else sides
    stone_h = max(0.0, min(height, m.stone_top - base))
    timber_h = height - stone_h

    def radius_at(y):
        return bottom_r + (top_r - bottom_r) * (y / height)

    if stone_h > 0.001:
        mid = radius_at(stone_h)
        m.put("%sStone" % name, m.cyl(m.stone, mid, bottom_r, stone_h, sides),
              y=base + stone_h * 0.5, ry=m.yaw)
    if timber_h > 0.001:
        mid = radius_at(stone_h)
        # Very slightly narrower where the timber sits on the stone, so the
        # join casts its own line rather than relying on the two surfaces to
        # differ. A tower seen against its own shadow needs the step.
        m.put("%sTimber" % name,
              m.cyl(m.wood, top_r, mid * 0.985, timber_h, sides),
              y=base + stone_h + timber_h * 0.5, ry=m.yaw)
    return base + height


def corbels(m, at, radius, count=None, name="Corbel"):
    """Tier rule 4b. The brackets carrying the gallery, from 1,000g up.

    Drawn in whatever the shaft is made of AT THAT HEIGHT rather than always in
    stone, so a mid-tier tower gets timber knee braces and a high-tier one gets
    stone corbels - both of which are how the real thing is built, and neither
    of which floats.
    """
    if not ts.has_corbels(m.ti):
        return
    count = ts.FEATURE_COUNT[m.ti] * 2 if count is None else count
    bracket = m.box(m.skin(at, "deep"), 0.055, 0.085, 0.11)
    m.ring_of(count, radius, lambda i, x, z, a: m.put(
        "%s%d" % (name, i + 1), bracket, x=x, y=at, z=z, ry=a), phase=m.yaw)


def parapet(m, at, radius, merlon_height=0.085, name=""):
    """Tier rule 4a. The projecting gallery and its battlement, from 150g up.

    A tower's most recognisable feature from directly above is the ring of
    merlons round its top - it is the shape that says "watchtower" before any
    other detail resolves - so this is the rung the branch split buys, and it
    is the one that does most of the work of making this roster read like the
    towers the user pointed at.

    Returns the height of the gallery floor, which is where a turret stands.
    """
    if not ts.has_parapet(m.ti):
        return at
    floor = m.cyl(m.skin(at, "pale"), radius * 1.20, radius * 1.14, 0.04,
                  m.sides)
    m.put("%sGallery" % name, floor, y=at + 0.02, ry=m.yaw)
    merlons = min(m.sides * 2, 8)
    merlon = m.box(m.skin(at, "base"), radius * 0.26, merlon_height,
                   radius * 0.17)
    m.ring_of(merlons, radius * 1.04, lambda i, x, z, a: m.put(
        "%sMerlon%d" % (name, i + 1), merlon, x=x,
        y=at + 0.04 + merlon_height * 0.5, z=z, ry=a), phase=m.yaw)
    return at + 0.04


def pennant(m, at, mast=0.26, name="Pennant"):
    """Tier rule 6. Painted cloth on a mast, at 25,000g only, and it MOVES.

    The one part of a tower that moves for no gameplay reason at all, which is
    exactly why it is reserved for the top of the ladder: motion is the loudest
    thing a top down camera can show, so nothing below an Ultimate gets any.

    IT IS NOT ENOUGH ON ITS OWN and was never meant to be - reported as such on
    the Defender, where it was the only thing separating a 5,000g tower from a
    25,000g one. It is the flourish ON TOP of that branch's real step, not the
    step itself. Every branch owes its Ultimate something bigger than this too.
    """
    if not ts.has_pennant(m.ti):
        return
    m.put("Mast", m.cyl(m.wood_pale, 0.011, 0.015, mast, 4),
          y=at + mast * 0.5, shadow=False)
    m.pivot(name, ".", y=at + mast * 0.78)
    m.put("PennantCloth", m.box(m.paint, 0.006, 0.10, 0.24), parent=name,
          z=0.12, shadow=False)
    m.swayer("PennantSway", name, 13.0, 0.32)


def painted_band(m, at, radius, name="Band", height=0.05, sides=None):
    """Tier rule 4's colour: a painted board banding the tower, from 30g up.

    Not a ring - a short cylinder the same shape as the tower, standing very
    slightly proud of it. The distinction matters on this roster: what came off
    was floating metal jewellery, and what a painted lintel course does instead
    is follow the building.
    """
    if m.paint is None:
        return
    sides = m.sides if sides is None else sides
    m.put(name, m.cyl(m.paint, radius, radius, height, sides), y=at, ry=m.yaw)


def sawblade(m, parent, radius, count, name="Blade", thickness=0.022,
             tooth_reach=0.30):
    """A circular saw: a plate with TRIANGULAR teeth around its rim.

    ONE SHAPE AT EVERY TIER, which is a correction. The expensive tiers were
    given three long rectangular ARMS on a hub instead, on the reasoning that a
    disc and a set of arms read as two different machines - and they do, but the
    thing they stop reading as is a SAW. The reference is a circular blade with
    a ring of triangular teeth, and every tier should be recognisably that.

    So the tier steps in the teeth rather than in the plan: many short teeth
    low down, a FEW LONG ONES at the top. `tooth_reach` is how far a tooth
    stands out as a share of the radius, and going from about a third to more
    than one whole radius is a big change in outline that never stops being a
    saw.

    THE TEETH ARE PRISMS, laid flat with their apex pointing outwards. A prism
    authored upright and rotated onto its side has its length on an axis it was
    not authored for, which is what `along="z"` on prism() is for - without it
    every tooth is silently the wrong length, and wrong by a different amount at
    each tier because the width and height ramps are different curves.
    """
    m.put(name, m.cyl(m.iron_pale, radius, radius, thickness, 14),
          parent=parent)
    reach = radius * tooth_reach
    tooth = m.prism(m.iron_pale, radius * (0.9 / count) * 2.2, reach,
                    thickness, along="z")
    m.ring_of(count, radius + reach * 0.5, lambda i, x, z, a: m.put(
        "%sTooth%d" % (name, i + 1), tooth, parent=parent, x=x, z=z,
        ry=a, rx=1.5708))
    m.put("%sHub" % name, m.cyl(m.iron_deep, radius * 0.24, radius * 0.28,
                                thickness * 2.6, 8), parent=parent)


def flywheel(m, at, radius=0.11):
    """The Cutter line's rule 6, standing in for the pennant.

    The same rung, spent on the same thing - MOTION at the top of the ladder,
    and the line's paint at its strongest - in the language this line actually
    speaks. A machine does not fly a flag; it has a governor turning on the
    side of it whether or not it is cutting anything.
    """
    if not ts.has_pennant(m.ti):
        return
    m.pivot("Flywheel", ".", x=0.24, y=at, rz=1.5708)
    m.put("FlywheelRim", m.cyl(m.paint, radius, radius, 0.022, 10),
          parent="Flywheel", shadow=False)
    m.put("FlywheelHub", m.cyl(m.iron_pale, radius * 0.3, radius * 0.34, 0.05,
                               6), parent="Flywheel", shadow=False)
    spoke = m.box(m.iron_deep, radius * 1.5, 0.03, 0.014)
    for index in range(3):
        m.put("Spoke%d" % (index + 1), spoke, parent="Flywheel",
              ry=index * 1.047, shadow=False)
    m.spinner("FlywheelSpin", "Flywheel", 0.5)


# --- the nine branches -----------------------------------------------------

def build_archer(m):
    """The 10g/30g stub: a timber post, then a boarded watchpost with a bow.

    The two tiers are deliberately barely the same object. At 10g it is a
    stump: a single post with one bar lashed across it, no platform, no paint,
    every part of it the raw deep tone. At 30g it grows legs, a boarded
    platform, a proper crossbow with limbs and a string, its first paint and a
    lit sight.

    That gap is the point. This is the first upgrade a player ever buys, and it
    should be the one they can see from across the map.
    """
    # Turned to match the Watch Tower it upgrades into, so a player who has
    # learned the shape of one is looking at the same building.
    m.yaw = math.pi * 0.25
    if m.ti >= 1:
        base = footing(m, 0.26, 0.23, 0.13)
        # A BOARDED POST, not four legs and a tabletop. The first version was
        # open-framed and read as a stool: the eye needs a solid shaft to call
        # something a tower, and four thin sticks under a plate is furniture.
        m.put("Post", m.cyl(m.wood, 0.135, 0.185, 0.44, 4), y=base + 0.22,
              ry=m.yaw)
        m.ring_of(4, 0.155, lambda i, x, z, a: m.put(
            "Rail%d" % (i + 1), m.box(m.wood_deep, 0.16, 0.05, 0.04),
            x=x, y=base + 0.50, z=z, ry=a), phase=m.yaw)
        m.put("Deck", m.cyl(m.wood_pale, 0.20, 0.175, 0.05, 4), y=base + 0.54,
              ry=m.yaw)
        painted_band(m, base + 0.58, 0.155, height=0.04, sides=4)
        m.pivot("Turret", ".", y=base + 0.65)
        m.put("Stock", m.box(m.wood_pale, 0.06, 0.06, 0.30), parent="Turret")
        limb = m.box(m.wood, 0.20, 0.032, 0.04)
        m.put("LimbL", limb, parent="Turret", x=-0.10, z=-0.09, ry=-0.34)
        m.put("LimbR", limb, parent="Turret", x=0.10, z=-0.09, ry=0.34)
        m.put("String", m.box(m.iron_pale, 0.31, 0.014, 0.014), parent="Turret",
              z=0.02, shadow=False)
        m.put("Sight", m.gem(m.glow, 0.04, 0.08, 6, 2), parent="Turret",
              y=0.06, z=0.03, shadow=False)
        m.pivot("Muzzle", "Turret", z=-0.19)
        return base + 0.74

    base = footing(m, 0.26, 0.24, 0.13)
    m.put("Post", m.cyl(m.wood_deep, 0.105, 0.14, 0.40, 4), y=base + 0.20,
          ry=m.yaw)
    m.pivot("Turret", ".", y=base + 0.42)
    # NAMED "Stock" rather than for its shape, because roster.ANIMATION names
    # one recoil node for the WHOLE BRANCH and every tier has to answer to it.
    # A bare bar is not a stock, but the node the recoil kicks is a contract
    # the branch keeps - exactly as "Turret/Muzzle" is kept by every tower in
    # the game whatever the muzzle looks like. Calling it CrossBar left the
    # 10g Archer's Recoil1 pointing at nothing, which errored once per tower
    # spawned, on the server as well as on both clients.
    m.put("Stock", m.box(m.wood, 0.30, 0.05, 0.06), parent="Turret", z=-0.03)
    m.pivot("Muzzle", "Turret", z=-0.19)
    return base + 0.50


def build_watch(m):
    """A square stone watchtower with a timber gallery: the reach branch.

    THE TOWER THE WHOLE REWORK WAS AIMED AT. The reference is the Age of
    Empires II watchtower - a square masonry shaft, a projecting timber
    hoarding near the top, battlements, corner caps on the biggest ones - and
    this is that shape assembled out of the roster's own parts.

    TURNED 45 DEGREES at the user's request, and it is a bigger change than it
    sounds. A square presented flat-on reads as a box: one panel facing the
    camera, no vertical edge, nothing to catch the light differently. The same
    box on the diagonal gives two receding faces and a corner down the middle,
    which is what a tower looks like. Only the BODY turns - see TowerModel.yaw.

    THE TOP IS OPEN AND THE ROOF IS CORNER CAPS rather than one pitched roof
    over the middle, which is where it departs from the reference. A tower with
    a roof over its centre, seen from directly above, IS a roof: the bolt
    thrower would be underneath it and invisible for most of the tower's life.

    ITS 5,000g STEP IS A SECOND STOREY. That was the answer to two tiers being
    reported as too alike, and it is worth more than another ring of detail: a
    two storey tower is a different BUILDING, not a bigger one. The main shaft
    shortens as the upper one arrives, so what changes is the shape rather than
    simply the height.
    """
    m.yaw = math.pi * 0.25
    base = footing(m, 0.29, 0.25, 0.15)
    tall = ts.has_crown(m.ti)
    top = shaft(m, base, 0.38 if tall else 0.62, 0.165, 0.215)
    corbels(m, top - 0.05, 0.20)
    floor = parapet(m, top, 0.20)
    painted_band(m, top - 0.10, 0.212, height=0.045)

    # 1,000g: capped corner turrets, the castle-scale detail that separates
    # that rung from the one below it at a glance.
    if ts.has_corbels(m.ti):
        cap = m.box(m.wood, 0.09, 0.15, 0.09)
        roof = m.cyl(m.wood_deep, 0.0, 0.085, 0.10, 4)
        m.ring_of(4, 0.20, lambda i, x, z, a: (
            m.put("Cap%d" % (i + 1), cap, x=x, y=floor + 0.075, z=z, ry=a),
            m.put("CapRoof%d" % (i + 1), roof, x=x, y=floor + 0.20, z=z,
                  ry=a)), phase=m.yaw)

    if ts.has_pennant(m.ti):
        # 25,000g: the lower gallery is ROOFED, into a covered hoarding.
        #
        # This is the rung that was reported as too close to the one below it,
        # and the two obvious answers were both bad: more height competes with
        # a size ladder that is deliberately almost flat, and a roof over the
        # middle is a lid that would hide the bolt thrower. A roofed RING
        # leaves the centre open, so the weapon is untouched and the outline
        # gains a whole storey's worth of new edge.
        panel = m.box(m.wood_deep, 0.20, 0.045, 0.20)
        m.ring_of(8, 0.255, lambda i, x, z, a: m.put(
            "Hoard%d" % (i + 1), panel, x=x, y=floor + 0.19, z=z, ry=a,
            rx=-0.55), phase=m.yaw)
        strut = m.box(m.wood, 0.04, 0.16, 0.04)
        m.ring_of(8, 0.235, lambda i, x, z, a: m.put(
            "Strut%d" % (i + 1), strut, x=x, y=floor + 0.10, z=z, ry=a),
            phase=m.yaw)

    if tall:
        # 5,000g: a second, narrower storey with its own battlement, and the
        # bolt thrower moves up onto it.
        upper = shaft(m, floor + 0.04, 0.20, 0.115, 0.155, name="Upper")
        floor = parapet(m, upper, 0.145, merlon_height=0.06, name="Upper")

    m.pivot("Turret", ".", y=floor + 0.10)
    # A bolt thrower rather than a barrel: this is the longest ranged tower in
    # the game and it shoots arrows, and a ballista says both at once.
    m.put("Stock", m.box(m.wood_pale, 0.075, 0.06, 0.38), parent="Turret")
    m.put("Trough", m.box(m.iron_pale, 0.035, 0.03, 0.42), parent="Turret",
          y=0.045, shadow=False)
    limb = m.box(m.wood, 0.24, 0.038, 0.05)
    m.put("LimbL", limb, parent="Turret", x=-0.12, z=-0.12, ry=-0.30)
    m.put("LimbR", limb, parent="Turret", x=0.12, z=-0.12, ry=0.30)
    m.put("String", m.box(m.iron_pale, 0.36, 0.016, 0.016), parent="Turret",
          y=0.03, shadow=False)
    m.put("Lens", m.gem(m.glow, 0.045, 0.09, 6, 2), parent="Turret",
          y=0.075, z=0.13, shadow=False)
    m.pivot("Muzzle", "Turret", y=0.045, z=-0.26)
    pennant(m, floor + 0.24)
    return floor + 0.20


def build_cannon(m):
    """A squat drum with a fat mortar over it: the siege branch.

    The reference is the source game's own Cannon Tower - a heavy round
    emplacement with one very fat barrel sitting on it - so this is wide and
    low where its sibling is tall and thin.

    ITS SHAPE STEPS ARE THE ORDNANCE, which is the only place a gun tower can
    honestly spend them: a slim barrel at 150g, a fat one with a shield at
    1,000g, TWO barrels at 5,000g and a full mantlet over both at 25,000g.
    Three of its four tiers were reported as indistinguishable while the barrel
    never changed, and no amount of stonework was going to fix that - a player
    looking at a cannon is looking at the cannon.

    NO BARREL HOOPS, and that is the no-torus rule earning its keep. A real gun
    is stepped rather than banded: a thick reinforce at the breech, a thinner
    chase towards the muzzle, and a swell at the mouth.
    """
    base = footing(m, 0.32, 0.30, 0.13, 8)
    top = shaft(m, base, 0.44, 0.245, 0.29, 8, name="Drum")

    # Buttresses. The one place a Cannon's tier shows in its outline as well as
    # in its ordnance.
    rib = m.box(m.skin(base + 0.16, "deep"), 0.055, 0.32, 0.09)
    m.ring_of(ts.FEATURE_COUNT[m.ti], 0.27, lambda i, x, z, a: m.put(
        "Rib%d" % (i + 1), rib, x=x, y=base + 0.16, z=z, ry=a))
    corbels(m, top - 0.05, 0.28)
    floor = parapet(m, top, 0.26, merlon_height=0.06)
    painted_band(m, top - 0.09, 0.288, height=0.04, sides=8)

    m.pivot("Turret", ".", y=floor + 0.05)
    m.put("Yoke", m.box(m.iron_deep, 0.30, 0.10, 0.16), parent="Turret")
    # A pivot carrying the tilt, so a recoil along its local Z travels back
    # down the bore rather than sideways through it. Shallower than a mortar's
    # on purpose - the reference is a cannon that fires nearly flat, and the
    # roundness of the shot is carried by the projectile's arc rather than by
    # pointing the tube at the sky.
    m.pivot("Barrel", "Turret", y=0.15, z=-0.06, rx=-0.42)

    # ONE BARREL AT EVERY TIER. The 5,000g step was a SECOND barrel, and it was
    # simply a lie: this tower fires one projectile, so a player counting two
    # muzzles and seeing one shell come out is being told something untrue
    # about the thing they just bought. A silhouette step is worth a lot and it
    # is not worth that.
    #
    # What carries 5,000g instead is the CASEMATE below - the open yoke closes
    # into an armoured housing that the barrel runs out of, which is a bigger
    # change to the outline than a second tube ever was.
    fat = ts.has_corbels(m.ti)
    bore = 0.068 if fat else 0.054
    m.put("Breech", m.cyl(m.iron_deep, bore * 1.14, bore * 1.22, 0.17, 8, "z"),
          parent="Turret/Barrel", z=0.09)
    # LONG. A barrel only reads as a barrel at something like five to one; at
    # the two-and-a-half it started with, breech, chase and mouth were three
    # stubs of the same width and the gun read as a stack of logs.
    m.put("Chase", m.cyl(m.iron, bore * 0.82, bore, 0.48, 8, "z"),
          parent="Turret/Barrel", z=-0.21)
    m.put("Mouth", m.cyl(m.iron_pale, bore * 1.08, bore * 0.88, 0.07, 8, "z"),
          parent="Turret/Barrel", z=-0.48)

    if ts.has_crown(m.ti):
        # 5,000g: a heavy CARRIAGE - cheek plates either side of the breech and
        # a muzzle brake at the mouth. Both are unmistakably parts of ONE gun,
        # which is the constraint this rung has to work inside.
        #
        # It was an armoured casemate first, a drum around the breech, and that
        # was the lid mistake again in a new costume: from the match camera the
        # drum was simply bigger than the barrel, so a 5,000g Cannon read as a
        # tower with a bump on it and the gun - the whole identity of the
        # branch - was the smallest thing up there. A part that FRAMES the
        # weapon is safe where a part that ENCLOSES it never is.
        cheek = m.box(m.iron_deep, 0.04, 0.22, 0.26)
        m.put("CheekL", cheek, parent="Turret", x=-0.135, y=0.13, z=0.01)
        m.put("CheekR", cheek, parent="Turret", x=0.135, y=0.13, z=0.01)
        m.put("Brake", m.cyl(m.iron_deep, bore * 1.5, bore * 1.5, 0.09, 8, "z"),
              parent="Turret/Barrel", z=-0.55)

    if fat:
        # A gun shield lying against the breech. It stood UPRIGHT and taller
        # than the barrel once, directly behind it, and from every angle behind
        # the tower the painted plate WAS the tower.
        m.put("Shield", m.box(m.paint, 0.30, 0.10, 0.03), parent="Turret",
              y=0.02, z=0.17, rx=0.35)
    if ts.has_pennant(m.ti):
        # 25,000g: a full mantlet across the front of the emplacement, the
        # biggest painted surface anywhere on the roster.
        m.put("Mantlet", m.box(m.paint, 0.46, 0.16, 0.04), parent="Turret",
              y=0.11, z=-0.19, rx=-0.30)
    m.put("Vent", m.box(m.glow, 0.10, 0.04, 0.045), parent="Turret",
          y=0.085, z=0.10, shadow=False)
    m.pivot("Muzzle", "Turret", y=0.36, z=-0.56)
    pennant(m, floor + 0.10)
    return floor + 0.34


def build_cutter(m):
    """The 10g/30g stub: a timber frame under a spinning saw.

    A WOODEN BASE, at the user's request, and it is the better answer than the
    stone pad this had first. It gives the Cutter line the same "stone arrives
    at 150g" step the other two lines get for free, and a timber frame under an
    iron blade is what a sawmill actually is.

    The metal is as much the tier here as the frame: a 10g blade is raw dark
    castings and a 30g one is cast iron, on the way to copper at the branch
    split. See style.METAL_RAMP.
    """
    if m.ti >= 1:
        base = footing(m, 0.24, 0.27, 0.09)
        painted_band(m, base + 0.02, 0.20, height=0.035)
        m.put("Pipe", m.cyl(m.iron_deep, 0.055, 0.075, 0.32, 8),
              y=base + 0.16)
        m.pivot("Turret", ".", y=base + 0.30)
        m.pivot("Spinner", "Turret")
        sawblade(m, "Turret/Spinner", 0.30, 9, tooth_reach=0.30)
        m.put("Spark", m.gem(m.glow, 0.032, 0.06, 5, 2), parent="Turret",
              y=-0.06, z=0.16, shadow=False)
        m.pivot("Muzzle", "Turret", z=-0.26)
        return base + 0.36

    # 10g: a bare timber pad and one blade on a short spindle. No paint, and
    # the pad in the raw deep tone.
    base = footing(m, 0.22, 0.25, 0.08)
    m.put("Pipe", m.cyl(m.iron_deep, 0.05, 0.065, 0.24, 8), y=base + 0.12)
    m.pivot("Turret", ".", y=base + 0.22)
    m.pivot("Spinner", "Turret")
    sawblade(m, "Turret/Spinner", 0.265, 8, thickness=0.018, tooth_reach=0.26)
    m.pivot("Muzzle", "Turret", z=-0.23)
    return base + 0.28


def build_carver(m):
    """A mill housing under a saw: the speed branch.

    THE BRANCH THAT NEEDED THE MOST WORK, and its four tiers now differ in the
    only place that matters on a saw - the BLADE. It goes copper, bronze, steel
    and polished steel with the metal ramp; it is a toothed disc for the two
    cheap tiers and THREE LONG BLADES for the two expensive ones; and the
    Ultimate carries a second set above the first, counter-turning.

    IT BARELY GROWS, on purpose and at the user's direction: the 150g tower is
    already tall enough for the job, and a saw that climbs out of reach reads
    worse rather than better. What changes up this branch is what is cutting,
    not how far off the ground it is.
    """
    base = footing(m, 0.27, 0.30, 0.10, stone=True)
    m.put("Pedestal", m.cyl(m.stone, 0.21, 0.25, 0.12, 6), y=base + 0.06)
    painted_band(m, base + 0.13, 0.215, height=0.04)

    if ts.has_corbels(m.ti):
        # 1,000g: braces off the pedestal.
        brace = m.box(m.iron_deep, 0.05, 0.08, 0.10)
        m.ring_of(ts.FEATURE_COUNT[m.ti], 0.235, lambda i, x, z, a: m.put(
            "Brace%d" % (i + 1), brace, x=x, y=base + 0.10, z=z, ry=a))

    # THE PIPE the blades run on. It is most of what is left of the tower: the
    # body used to be a pedestal, a housing, a ring of uprights and a mount,
    # and all of that together read as a tower with a saw on it rather than as
    # a saw. What this branch is FOR is the blade, so everything else is now a
    # pad on the ground and a spindle to hang it from.
    m.put("Pipe", m.cyl(m.iron_deep, 0.06, 0.08, 0.42, 8), y=base + 0.20)
    if ts.has_parapet(m.ti):
        m.put("Collar", m.cyl(m.iron, 0.085, 0.10, 0.055, 8), y=base + 0.33)

    m.pivot("Turret", ".", y=base + 0.40)
    m.pivot("Spinner", "Turret")
    # Few long teeth at the top of the branch, many short ones below it.
    if ts.has_crown(m.ti):
        sawblade(m, "Turret/Spinner", 0.28, 5, tooth_reach=0.52)
    else:
        sawblade(m, "Turret/Spinner", 0.315, ts.FEATURE_COUNT[m.ti] * 2 + 4,
                 tooth_reach=0.34)
    if ts.has_pennant(m.ti):
        # 25,000g: a SECOND blade lower down the same pipe, counter-turning.
        # WIDER than the blade above it, and short-toothed where that one
        # is long. Hung directly underneath at the same size it was simply
        # invisible from the match camera, which is the only angle that
        # counts - so the Ultimate's whole step over the Greater was a
        # change of metal. Sticking out past the top blade, it reads from
        # above as a second ring of teeth.
        m.pivot("LowerSpinner", "Turret", y=-0.19)
        sawblade(m, "Turret/LowerSpinner", 0.30, 9, name="LowerBlade",
                 tooth_reach=0.30)
        m.spinner("LowerSpin", "Turret/LowerSpinner", -1.9)
    m.put("Spark", m.gem(m.glow, 0.035, 0.07, 5, 2), parent="Turret",
          y=-0.08, z=0.18, shadow=False)
    m.pivot("Muzzle", "Turret", z=-0.30)
    flywheel(m, base + 0.11)
    return base + 0.46


def build_crusher(m):
    """A piledriver: an iron weight in a frame, dropped onto a stone anvil.

    THE USER'S OWN BRIEF, chosen from three. The source game's version is an
    ogre playing a stomp animation, which primitives cannot do, so what has to
    carry "one heavy blow over a wide area" instead is a machine that visibly
    winds up and lets go. The weight rises over the whole windup and falls on
    the beat - see SlamAnimation3D, whose DROP mode exists for this - and the
    blast ring and its dust are thrown on the landing.

    ITS SHAPE STEP IS THE HEADGEAR, also the user's suggestion: ONE beam across
    the frame for the two cheap tiers, TWO crossed beams for the two expensive
    ones, and a winch on top of the Ultimate. The weight's own metal ramps
    alongside it, so the thing that falls changes as well as the thing holding
    it up.

    THE FRAME IS DELIBERATELY MODEST IN HEIGHT. A taller one reads better in
    isolation and is worse in a maze: this branch has the widest blast in the
    game so its towers stand in rows, and a tall frame turns that row into a
    fence that hides everything behind it.
    """
    base = footing(m, 0.32, 0.30, 0.15)
    top = shaft(m, base, 0.40, 0.24, 0.285, name="Drum")
    # The face the weight lands on, in the pale tone so the impact point is the
    # brightest thing on the tower and a player's eye is already there when the
    # blow arrives.
    m.put("AnvilFace", m.cyl(m.stone_pale, 0.235, 0.25, 0.05, m.sides),
          y=top + 0.02)
    corbels(m, top - 0.06, 0.275)
    painted_band(m, top - 0.10, 0.283, height=0.045)

    # The frame the weight runs in. Four posts and a head, in iron, because
    # nothing else on a stone tower would plausibly take that load - and
    # because the posts are what tell a player at rest that this thing drops.
    post = m.box(m.iron_deep, 0.05, 0.34, 0.05)
    m.ring_of(4, 0.245, lambda i, x, z, a: m.put(
        "Post%d" % (i + 1), post, x=x, y=top + 0.21, z=z, ry=a))
    beam = m.box(m.iron, 0.55, 0.055, 0.075)
    m.put("FrameBeamA", beam, y=top + 0.40)
    if ts.has_crown(m.ti):
        m.put("FrameBeamB", beam, y=top + 0.40, ry=1.5708)
    if ts.has_pennant(m.ti):
        # 25,000g: a winch drum across the head, painted at its ends.
        m.put("Winch", m.cyl(m.iron_pale, 0.065, 0.065, 0.26, 6, "z"),
              y=top + 0.47, rx=1.5708)
        m.put("WinchCap", m.cyl(m.paint, 0.078, 0.078, 0.03, 6, "z"),
              y=top + 0.47, z=0.13, rx=1.5708)

    m.pivot("Turret", ".", y=top + 0.06)
    # Everything that falls hangs off one pivot, so the prefab's slam moves the
    # weight as a single piece. It sits at the weight's RESTING height, and the
    # animation lifts it from there - see SlamAnimation3D, which captures this
    # node's authored y as the height a blow returns to.
    m.pivot("Swing", "Turret")
    m.put("Weight", m.cyl(m.iron_pale, 0.15, 0.165, 0.21, m.sides),
          parent="Turret/Swing", y=0.11)
    m.put("WeightFace", m.cyl(m.iron_deep, 0.17, 0.155, 0.045, m.sides),
          parent="Turret/Swing", y=0.015)
    m.put("WeightCore", m.gem(m.glow, 0.05, 0.10, 5, 2),
          parent="Turret/Swing", y=0.20, shadow=False)
    m.pivot("Muzzle", "Turret", y=0.02, z=-0.20)
    pennant(m, top + 0.44, mast=0.22)
    return top + 0.46


def build_sentry(m):
    """The 10g/30g stub: a round timber tower holding a lit orb.

    The user asked for this one specifically: the pair used to be a half
    capsule sitting on the ground, and what they wanted was an actual TOWER.
    So both tiers are a proper round shaft with the orb on top, and what
    separates them is what the orb sits IN - and its colour, which starts at a
    deep amber here and climbs to a cold white by the Ultimate.

    At 10g it rests in a plain timber cap and does not move. At 30g the tower
    is half again as tall, the cap opens into a three post crown, and the orb
    starts to FLOAT inside it.
    """
    if m.ti >= 1:
        base = footing(m, 0.25, 0.23, 0.13)
        m.put("Shaft", m.cyl(m.wood, 0.115, 0.155, 0.46, m.sides),
              y=base + 0.23)
        painted_band(m, base + 0.40, 0.126, height=0.04)
        m.put("Cap", m.cyl(m.wood_pale, 0.155, 0.13, 0.05, m.sides),
              y=base + 0.48)
        upright = m.box(m.wood, 0.035, 0.20, 0.035)
        m.ring_of(3, 0.115, lambda i, x, z, a: m.put(
            "Upright%d" % (i + 1), upright, x=x, y=base + 0.60, z=z, ry=a))
        m.pivot("Turret", ".", y=base + 0.63)
        m.put("Core", m.gem(m.glow, 0.095, 0.20, 6, 3), parent="Turret",
              shadow=False)
        m.bobber("Bob", "Turret", 0.03, 0.35)
        m.pivot("Muzzle", "Turret", z=-0.13)
        return base + 0.75

    # 10g: shorter, no crown, and the orb RESTING on the cap rather than
    # floating in anything. It starts hovering at 30g.
    base = footing(m, 0.23, 0.21, 0.12)
    m.put("Shaft", m.cyl(m.wood_deep, 0.10, 0.135, 0.32, m.sides),
          y=base + 0.16)
    m.put("Cap", m.cyl(m.wood, 0.135, 0.115, 0.045, m.sides), y=base + 0.34)
    m.pivot("Turret", ".", y=base + 0.43)
    # Sitting proud of the cap rather than sunk into it. A 10g tower should
    # look cheap, not look broken, and the orb is the only thing on it that
    # says which line it belongs to.
    m.put("Core", m.gem(m.glow, 0.085, 0.17, 5, 2), parent="Turret",
          shadow=False)
    m.pivot("Muzzle", "Turret", z=-0.12)
    return base + 0.52


def build_defender(m):
    """A round tower carrying a big orb in a crown: the splash branch.

    A round tower with an orb at the top that the shot leaves from. What makes
    it read as the BRANCH rather than as a large Sentry is the crown, and what
    makes its four tiers read as four towers is what the crown DOES: open
    columns at 150g, lintels across them at 1,000g, and at 5,000g the whole
    thing closing into a LANTERN HOUSE - wide piers with light showing between
    them - which is a different building rather than a taller one.

    The orb's own colour climbs with the tier as well, deep amber to cold
    white. On this line the accent is the biggest object on the model, which
    makes it the strongest tell available and the cheapest to read - and it is
    why a pennant alone was never going to separate the top two rungs.
    """
    base = footing(m, 0.30, 0.28, 0.14)
    top = shaft(m, base, 0.44, 0.165, 0.225)
    corbels(m, top - 0.05, 0.21)
    floor = parapet(m, top, 0.21, merlon_height=0.055)
    painted_band(m, top - 0.09, 0.222, height=0.045)

    columns = ts.FEATURE_COUNT[m.ti] + 1
    if ts.has_crown(m.ti):
        # 5,000g: the crown SPLAYS. The arms lean outwards and the orb rises
        # clear of them, so the tower goes from something holding a light in a
        # cage to something presenting one.
        #
        # IT WAS A CLOSED LANTERN HOUSE FIRST - wide piers and a cap over the
        # top - and that was flatly wrong for the same reason a roof over a
        # watchtower is: the camera looks down, so a cap does not enclose the
        # orb, it DELETES it. A 5,000g Defender came out as a solid black drum
        # with the one thing the whole branch is about nowhere on screen. Any
        # part that spans the top of a model is a lid.
        arm = m.box(m.skin(floor, "pale"), 0.055, 0.30, 0.055)
        m.ring_of(columns, 0.175, lambda i, x, z, a: m.put(
            "Arm%d" % (i + 1), arm, x=x, y=floor + 0.15, z=z, ry=a, rx=-0.30))
        brace = m.box(m.skin(floor, "base"), 0.09, 0.045, 0.07)
        m.ring_of(columns, 0.20, lambda i, x, z, a: m.put(
            "Brace%d" % (i + 1), brace, x=x, y=floor + 0.06, z=z, ry=a))
    else:
        column = m.box(m.skin(floor, "pale"), 0.05, 0.24, 0.05)
        m.ring_of(columns, 0.20, lambda i, x, z, a: m.put(
            "Column%d" % (i + 1), column, x=x, y=floor + 0.13, z=z, ry=a))
        if ts.has_corbels(m.ti):
            # 1,000g: lintels across the arcade.
            lintel = m.box(m.skin(floor, "base"), 0.11, 0.05, 0.09)
            m.ring_of(columns, 0.20, lambda i, x, z, a: m.put(
                "Lintel%d" % (i + 1), lintel, x=x, y=floor + 0.27, z=z, ry=a))

    m.pivot("Turret", ".", y=floor + (0.30 if ts.has_crown(m.ti) else 0.15))
    orb = 0.17 if ts.has_pennant(m.ti) else 0.135
    m.put("Core", m.gem(m.glow, orb, orb * 2.05, 6, 3), parent="Turret",
          shadow=False)
    m.bobber("Bob", "Turret", 0.035, 0.3)
    m.pivot("Muzzle", "Turret", z=-0.16)
    pennant(m, floor + 0.40)
    return floor + (0.50 if ts.has_crown(m.ti) else 0.34)


def build_turret(m):
    """A rack of tubes aimed at the sky.

    The one tower that CANNOT hit ground, so its whole outline says so: nothing
    on it points at the floor. That is the readability job this shape exists to
    do, and it should survive real art replacing the primitives.

    ITS TIER IS THE METAL, which is the user's own idea and the fix for three
    of its four tiers reading alike. Counting tubes was the only thing telling
    them apart, and counting is exactly the tell that does not work at match
    distance - three, four, five and six of anything are one thing. Copper,
    bronze, steel and polished steel are four different objects.
    """
    base = footing(m, 0.33, 0.30, 0.13, 4)
    top = shaft(m, base, 0.36, 0.235, 0.29, 4, name="Body")
    corbels(m, top - 0.05, 0.28, count=4)
    floor = parapet(m, top, 0.26, merlon_height=0.055)
    painted_band(m, top - 0.09, 0.288, height=0.04, sides=4)

    m.pivot("Turret", ".", y=floor + 0.05)
    m.put("Cradle", m.box(m.iron_deep, 0.28, 0.11, 0.22), parent="Turret")
    tubes = ts.FEATURE_COUNT[m.ti]
    long_tube = ts.has_crown(m.ti)
    length = 0.34 if long_tube else 0.30
    tube = m.cyl(m.iron_pale, 0.042, 0.05, length, 6)
    # Fanned across x rather than around a ring, so the rack reads as one
    # battery pointed the same way rather than as a crown of spikes. WIDE
    # enough that six of them still read as six: at 0.075 the long tubes of the
    # top two tiers touched and the rack became one slab.
    spread = 0.098
    first = -spread * (tubes - 1) * 0.5
    tilt = -0.87
    # EVERY TUBE IS ITS OWN PIVOT and they fire IN TURN - see
    # BarrelCycleAnimation3D, which kicks one per shot and moves the muzzle
    # onto it. The rack used to recoil as a single node, so all six tubes
    # kicked for one missile; that reads as a salvo, and this tower fires one.
    #
    # Each tube carries a TIP, which is where its shot leaves. It is a real
    # node rather than a number worked out in the component because the tube
    # length changes with the tier, and a muzzle derived from a guessed offset
    # is how the lit caps ended up floating a good way off the end of the tubes
    # they were supposed to be plugging.
    for i in range(tubes):
        x = first + spread * i
        name = "Tube%d" % (i + 1)
        m.pivot(name, "Turret", x=x, y=0.22, z=-0.05, rx=tilt)
        path = "Turret/%s" % name
        m.put("%sBody" % name, tube, parent=path)
        m.put("%sCap" % name, m.gem(m.glow, 0.036, 0.07, 6, 2), parent=path,
              y=length * 0.5, shadow=False)
        m.pivot("Tip", path, y=length * 0.62)
    if long_tube:
        # 5,000g: longer tubes, and a painted blast deflector behind the rack.
        m.put("Deflector", m.box(m.paint, 0.34, 0.22, 0.03), parent="Turret",
              y=0.18, z=0.16, rx=0.4)
    if ts.has_pennant(m.ti):
        m.put("DeflectorWing", m.box(m.paint, 0.48, 0.14, 0.03),
              parent="Turret", y=0.31, z=0.20, rx=0.55)
    # Authored on the FIRST tube and moved onto whichever one is firing by
    # BarrelCycleAnimation3D. The path is the contract every tower in the game
    # keeps, so it stays a plain child of the Turret however many tubes there
    # are - see that component for why the muzzle moves rather than the attack
    # being taught about several of them.
    m.pivot("Muzzle", "Turret", x=first, y=0.22 + math.cos(tilt) * length * 0.62,
            z=-0.05 - math.sin(-tilt) * length * 0.62 * (m.h / m.s))
    pennant(m, floor + 0.10)
    return floor + 0.46


BRANCHES = {
    "archer": build_archer, "watch": build_watch, "cannon": build_cannon,
    "cutter": build_cutter, "carver": build_carver, "crusher": build_crusher,
    "sentry": build_sentry, "defender": build_defender, "turret": build_turret,
}

# Roughly how tall each branch stands in AUTHORED units, used only to work out
# where its masonry stops before the builder runs.
#
# It has to be a table rather than the builder's own return value, because the
# material of a part is decided while the tower is being built and the height
# is not known until it has been. Being approximate costs nothing: it moves the
# stone line by a few percent of a tower's height, which is invisible, and the
# alternative - building every tower twice - would be real complexity for it.
#
# The six PATH branches are the only ones it decides anything for: the three
# 10g/30g stubs sit at tiers where `stone_share` is zero, so they are pure
# timber and the number below them is never read.
NOMINAL_HEIGHT = {
    "archer": 0.87, "watch": 1.05, "cannon": 0.95,
    "cutter": 0.45, "carver": 0.56, "crusher": 1.01,
    "sentry": 0.88, "defender": 0.97, "turret": 1.00,
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
        m.set_stone_top(NOMINAL_HEIGHT[branch])
        # Authored unscaled, so the tier's ramps are applied here rather than
        # inside every one of the nine builders. HEIGHT, not width - this is
        # how tall the finished tower stands, and the prefab hangs its health
        # bar off it.
        heights[key] = round(BRANCHES[branch](m) * m.h, 3)
        io.open("%s/%s_model.tscn" % (OUT, key), "w", encoding="utf-8",
                newline="\n").write(m.render())
    return heights
