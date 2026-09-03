"""The creep body plans, and the ladder rules laid over them.

Read style.py first: it holds the language, this file holds the shapes that
speak it. Every builder below is handed a CreepModel and answers one question -
what does this creature LOOK like - while the ladder rules (plates, spines,
crest, mass, carapace, eyes) are applied around it and are the same for every
one of them.

THE CONTRACT EVERY CREEP MODEL MEETS, which the prefab wiring depends on:

    Gait            everything that bobs and leans as the creep travels
    Leg1 .. LegN    hip pivots, at the MODEL ROOT rather than inside Gait

The legs sit outside Gait on purpose. A walk cycle is a body bobbing over feet
that stay planted, so a leg hung under the bobbing node lifts its own foot off
the floor twice a stride and the whole creature reads as swimming.

A model may also offer:

    Gait/ArmL, Gait/ArmR    limbs that counter-swing against the legs
    Gait/ArmR/Swing         [ATTACKER] what StrikeAnimation3D chops with
    Shadow                  [AIR] the disc pinned to the ground below it
    Gait/Flames             [style.CREEP_FLAMES] motes off a burning creep

None of the animation lives here. The components that drive these nodes are in
the PREFAB, because they need the unit and a model has none - the same model
scene is what the portrait and the baked icon copy their meshes out of, and
neither of those has a creep behind it.

THE THREE FAMILY RULES, restated because a builder is where they are kept
(style.py has the reasoning, and the note at the top of that file on why none
of the visual rules is a hard one - they are continuity conventions Claude
authored, not design the user handed down):

    GROUND    legs, on the floor, opaque. The Siege Engine's wheels are the
              one reading of "legs" that is not a leg, and it is a machine
    AIR       NO legs at all, and a shadow disc under it. NOT translucent by
              rule any more - that belongs to the WRAITH plan, see
              creep_roster.is_vapour
    ATTACKER  the only creep with a LIT weapon edge. Nothing else in this file
              may put the eye material on anything that is not an eye

AUTHORED UNITS ARE UNSCALED. Each builder returns the creep's height in those
units; generate() multiplies by the rung's HEIGHT ramp. Do not pre-scale
anything, and remember that width and height ramp separately - see modelkit.
"""

import io
import math
import os

import creep_roster as cr
import style as ts
from modelkit import Model
from tscn import num

OUT = "Scenes/Units/Models/Creeps"
UNIT_MODEL_SCRIPT = "res://Scripts/Units/UnitModel.gd"
# A class with no code in it, whose whole job is to tell a portrait and a baked
# icon that this mesh is not part of the creature. See GroundShadow3D.gd.
SHADOW_SCRIPT = "res://Scripts/Effects/GroundShadow3D.gd"
MAT = "res://Resources/Materials/Creeps"


class CreepModel(Model):
    """A Model that also knows which rung of the ladder it stands on, and
    whether it is a Boss - the two things every ladder rule needs."""

    def __init__(self, key, gold, plan, is_boss):
        rung = ts.creep_rung(gold)
        mass = ts.creep_mass(rung)
        height = ts.creep_height_scale(rung)
        # The rung says how far up the ladder it stands; the plan corrects for
        # a body shape that reads the wrong size whatever it costs; the tweak
        # is the one creep neither of those got right. In that order, because
        # each is narrower than the one before it - see style.creep_plan_size
        # and creep_roster.SIZE_TWEAK.
        plan_mass, plan_height = ts.creep_plan_size(plan)
        mass *= plan_mass
        height *= plan_height
        tweak = cr.size_tweak(key)
        mass *= tweak
        height *= tweak
        if is_boss:
            mass *= ts.BOSS_MASS
            height *= ts.BOSS_HEIGHT
        Model.__init__(
            self,
            "".join(part.capitalize() for part in key.split("_")) + "Model",
            UNIT_MODEL_SCRIPT,
            {
                "body": "%s/%s_hide.tres" % (MAT, key),
                "deep": "%s/%s_hide_deep.tres" % (MAT, key),
                "pale": "%s/%s_hide_pale.tres" % (MAT, key),
                "trim": "%s/carapace_r%d.tres" % (MAT, rung),
                "glow": "%s/eye_r%d.tres" % (MAT, rung),
            },
            round(mass, 4),
            round(height, 4),
        )
        self.key = key
        self.rung = rung
        self.boss = is_boss
        # Filled in by the builder and handed back to the content stage, which
        # is what wires the walk component without this file having to know
        # anything about prefabs.
        self.legs = []
        self.phases = []
        self.arms = []
        self.strike = ""
        self.hover = 0.0
        # Whether what the walk swings are WHEELS. They are handed over as hip
        # pivots so the chassis still pitches as it travels, but a wheel that
        # rocks fore and aft reads as broken rather than as rolling, so the
        # prefab turns the swing off. See build_machine.
        self.rolls = False

    # --- the two authoring spaces -----------------------------------------
    #
    # Width and height ramp separately, which for a TOWER is free - a tower is
    # a stack of axis aligned drums and squashing it just makes it squatter.
    # For a CREATURE it is not free, and it cost this roster a whole rebuild to
    # find out. Two things break:
    #
    #   ROUND PARTS  a head authored as a sphere comes out as a disc, because
    #                its radius took the width ramp and its height took the
    #                height one. Every head in the first pass was a pancake
    #   ANGLED PARTS a leg placed by trigonometry lands at the wrong angle,
    #                because its x offset and its y offset were scaled by
    #                different numbers. The spider's knees ended up above its
    #                own body
    #
    # So a creep is authored in TWO spaces on purpose, and which one a number
    # is in is a real decision the author has to make:
    #
    #   HEIGHT UNITS  the plain default. Hip height, torso length, neck, trunk.
    #                 Everything that IS the creature's height, and should be
    #                 squashed with it - which is what makes the roster stocky
    #                 rather than lanky, and stocky is what reads from above
    #   WIDTH UNITS   passed through up(). Anything that has to stay ROUND or
    #                 keep an ANGLE: heads, fists, eyes, boulders, and the
    #                 y offset of anything placed by trigonometry
    #
    # down() is the inverse, for taking a height-unit number - a hip height -
    # into the width space a limb's trigonometry is being done in.

    def up(self, value):
        """A WIDTH-space measurement, expressed in height units."""
        return value * self.s / self.h

    def down(self, value):
        """A HEIGHT-space measurement, expressed in width units."""
        return value * self.h / self.s

    def ball(self, material, radius, flatten=1.0, radial=6, rings=3):
        """A gem() that comes out round in world space."""
        return self.gem(material, radius, self.up(2.0 * radius * flatten),
                        radial, rings)


# --- the parts every creep can carry ----------------------------------------

def eyes(m, parent, y, z, spread, size=0.035, count=2, prefix="Eye"):
    """The one lit thing on an ordinary creep, and the whole of rule 3.

    Placed by the builder because an eye belongs to a head and only the head's
    author knows where that is. What the ladder fixes is the MATERIAL: every
    creep on a rung has the same amber, and it brightens as the rung climbs.

    `prefix` is only there because a spider has two ROWS of them and two nodes
    called Eye1 under one parent is not a scene Godot can load.
    """
    mesh = m.ball(m.glow, size, 1.0, 5, 2)
    for index in range(count):
        offset = (index - (count - 1) * 0.5) * spread
        m.put("%s%d" % (prefix, index + 1), mesh, parent=parent,
              x=offset, y=y, z=z, shadow=False)


def plates(m, parent, positions, size):
    """Ladder rule 4, from rung 2 up: hard plates over the shoulders or flanks.

    `positions` is a list of (x, y, z, ry) so a plan can put them wherever its
    own anatomy has shoulders - a spider wears them on its abdomen and a Priest
    wears them as a raised mantle. What the rule fixes is that they are THERE
    and that they are carapace.
    """
    if not ts.creep_has_plates(m.rung):
        return
    mesh = m.box(m.trim, size[0], size[1], size[2])
    for index, spot in enumerate(positions):
        m.put("Plate%d" % (index + 1), mesh, parent=parent,
              x=spot[0], y=spot[1], z=spot[2], ry=spot[3])


def spines(m, parent, count, start_z, step_z, y, size, rise=0.0):
    """Ladder rule 5, from rung 3 up: a row of spines down the back.

    A ROW rather than a ring, because from above a row draws a line along the
    creature's spine and a ring draws a blob. The line is also what says which
    way the thing is facing, which a top down camera otherwise has to work out
    from the head alone.
    """
    if not ts.creep_has_spines(m.rung):
        return
    mesh = m.prism(m.trim, size[0], size[1], size[2])
    for index in range(count):
        # Tallest in the middle of the run, so the back reads as arched rather
        # than as a picket fence.
        arch = math.sin((index + 1) / float(count + 1) * math.pi)
        m.put("Spine%d" % (index + 1), mesh, parent=parent,
              y=y + rise * arch, z=start_z + step_z * index)


def crest(m, parent, y, z, spread, size, tilt=0.5):
    """Ladder rule 6, from rung 4 up AND on every Boss whatever it cost.

    Horns. The last thing the ladder adds and the only one a Boss is given for
    free, because a Boss steals two lives and has to be readable as the biggest
    thing in its bracket before a player has read anything else about it.
    """
    if not ts.creep_has_crest(m.rung, m.boss):
        return
    mesh = m.prism(m.trim, size[0], size[1], size[2])
    m.put("HornL", mesh, parent=parent, x=-spread, y=y, z=z, rz=tilt, rx=-0.3)
    m.put("HornR", mesh, parent=parent, x=spread, y=y, z=z, rz=-tilt, rx=-0.3)


def flames(m, parent, y, spread, size=0.030):
    """The one thing in the creep roster that is lit and is not an eye.

    Nothing here decides whether a creep burns - style.creep_flames does, off
    the creep's own key, and answers None for all but one of them. So a builder
    may call this unconditionally and a creep that does not burn pays a
    dictionary lookup and nothing else.

    An aura() rather than sparks(), and the difference is the whole reading:
    sparks are an EVENT, thrown off by something that just happened, where this
    is a STATE that never stops. A creature made of fire is burning before it
    does anything and goes on burning afterwards.

    Deliberately QUIET for something described as being on fire. What has to
    read from a top down camera is that the silhouette is giving something off,
    and a fountain loud enough to be unmistakable in a still image is a column
    of orange that hides the creep underneath it - which is the opposite of
    what a Boss's silhouette is for.
    """
    colour = ts.creep_flames(m.key)
    if colour is None:
        return
    m.aura("Flames", parent, colour, count=20, radius=size, spread=spread,
           lifetime=1.05, rise=(0.22, 0.46), drift=0.12, y=y)


def shadow_disc(m, radius, height):
    """The AIR family's tell, and the reason a flyer reads as one at all.

    A top down camera sees almost none of the height a flyer is actually at, so
    altitude on its own is invisible: a Shade hanging at cruising height and a
    Shade standing on the floor are the same picture. The disc is pinned to the
    GROUND under the creep - which is `height` below the model's own origin,
    since a flyer's origin IS its cruising height - so what the player sees is
    a shadow with nothing standing on it.

    Unlit and shadowless, because it is standing in for a shadow rather than
    being lit like a surface.
    """
    m.scene.sub("StandardMaterial3D", "ShadowMaterial", [
        "shading_mode = 0",
        "transparency = 1",
        "albedo_color = Color(0.02, 0.03, 0.05, 0.42)",
    ])
    mesh = m.scene.sub("CylinderMesh", "ShadowDisc", [
        "top_radius = %s" % num(radius * m.s),
        "bottom_radius = %s" % num(radius * m.s),
        "height = 0.005",
        "radial_segments = 16",
        "rings = 0",
        'material = SubResource("ShadowMaterial")',
    ])
    m.scene.node("Shadow", "MeshInstance3D", ".",
                 script=m.scene.ext("Script", SHADOW_SCRIPT), props=[
                     "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, %s, 0)"
                     % num(-height * m.h),
                     "cast_shadow = 0",
                     'mesh = SubResource("%s")' % mesh,
                 ])


def leg(m, name, x, y, z, p, phase, digit="foot"):
    """One hip pivot and the limb hanging off it.

    Three segments rather than one, and it is worth the extra meshes: a leg
    made of a single cylinder swings like a pendulum and reads as a stick,
    where a thigh, a shin and a foot read as a leg even when all three are
    primitives. The foot takes the CARAPACE material, so every hoof, paw and
    boot in the roster climbs the ladder with everything else.

    THE LENGTHS ARE DERIVED FROM THE HIP HEIGHT rather than authored, so a foot
    always lands exactly on the floor. Authoring both and hoping they add up is
    how a roster ends up with one creep wading and another on stilts, and it is
    invisible in a diff - the numbers look perfectly reasonable right up until
    something is rendered.
    """
    m.pivot(name, ".", x=x, y=y, z=z)
    foot_h = p["shin_r"] * 1.3
    total = max(y - foot_h * 0.5, p["shin_r"] * 3.0)
    thigh = total * p.get("thigh_share", 0.52)
    shin = total - thigh
    # The thigh takes the BODY tone and the shin the deep one, so a leg has a
    # light half and a dark half. Both in `deep` reads as a black post from
    # above, which is what the first pass looked like.
    m.put("Thigh", m.capsule(m.body, p["thigh_r"], thigh, 5, 2),
          parent=name, y=-thigh * 0.5)
    m.put("Shin", m.capsule(m.deep, p["shin_r"], shin, 5, 2),
          parent=name, y=-thigh - shin * 0.5)
    foot_y = -total
    if digit == "hoof":
        m.put("Hoof", m.cyl(m.trim, p["shin_r"] * 1.2, p["shin_r"] * 1.45,
                            foot_h, 6),
              parent=name, y=foot_y + foot_h * 0.5)
    else:
        m.put("Foot", m.box(m.trim, p["shin_r"] * 2.0, foot_h,
                            p["shin_r"] * 2.6),
              parent=name, y=foot_y + foot_h * 0.5, z=-p["shin_r"] * 0.55)
    if digit == "claw":
        # Toes, not a slab. A PrismMesh points its apex down +Y, so rx of a
        # quarter turn BACKWARDS aims it down -Z - which is forwards, because
        # Godot's forward is -Z. Its authored height then runs along the
        # ground and has to be a width measurement; its authored depth becomes
        # the toe's thickness. Get either wrong and the foot comes out as a
        # signpost, which is what the first pass looked like.
        toe = m.prism(m.trim, p["shin_r"] * 0.6, m.up(p["shin_r"] * 1.2),
                      p["shin_r"] * 0.7)
        for index in range(3):
            m.put("Toe%d" % (index + 1), toe, parent=name,
                  x=p["shin_r"] * (index - 1) * 0.72,
                  y=foot_y + foot_h * 0.5, z=-p["shin_r"] * 1.9, rx=-1.5708)
    m.legs.append(name)
    m.phases.append(phase)
    return total


# --- the body plans ---------------------------------------------------------

def build_quadruped(m, p):
    """Four legs under a barrel: the Sheep and the Timber Wolf.

    The two are the same plan and must not read as the same animal - they
    arrive in the same pack. So everything that can differ does: the Sheep is
    round, pale, fleeced and short legged with its head DOWN, and the Wolf is
    long, dark, lean and high shouldered with its head FORWARD. Same six
    primitives, opposite silhouettes.
    """
    hip = p["hip_y"]
    span = p["leg_span"]
    reach = p["leg_reach"]
    leg(m, "LegFL", -span, hip, -reach, p, 0.0, p["digit"])
    leg(m, "LegFR", span, hip, -reach, p, 0.5, p["digit"])
    leg(m, "LegBL", -span, hip, reach, p, 0.5, p["digit"])
    leg(m, "LegBR", span, hip, reach, p, 0.0, p["digit"])

    m.pivot("Gait", ".", y=hip)
    body_r = p["body_r"]
    m.put("Barrel", m.capsule(m.body, body_r, p["body_len"], 7, 3, "z"),
          parent="Gait", rx=1.5708)
    # The chest, a size up from the barrel and set forward: it is what makes a
    # quadruped read as facing somewhere from directly above.
    m.put("Chest", m.ball(m.body, body_r * p["chest"], 1.1, 7, 3),
          parent="Gait", z=-p["body_len"] * 0.34, y=m.up(p["chest_rise"]))

    if p["fleece"]:
        # Wool. Placed as a ring of overlapping lumps rather than one big
        # sphere, so the outline is bumpy from above - which is the only thing
        # that says "fleece" at this size.
        lump = m.ball(m.pale, body_r * 0.58, 0.9, 6, 3)
        for index in range(6):
            angle = index * math.tau / 6.0
            m.put("Fleece%d" % (index + 1), lump, parent="Gait",
                  x=math.sin(angle) * body_r * 0.72,
                  y=m.up(body_r * 0.3 + math.cos(angle) * body_r * 0.24),
                  z=math.cos(angle) * p["body_len"] * 0.3)
    if p["hump"]:
        m.put("Hump", m.ball(m.pale, body_r * 0.8, 0.8, 6, 3),
              parent="Gait", y=m.up(body_r * 0.5), z=-p["body_len"] * 0.2)

    # Neck and head. The pitch of the neck is the loudest difference between
    # the two animals in this plan and is authored per creep.
    neck = p["neck"]
    # -Z is forward, so a head leaning FORWARD is a NEGATIVE tilt. The first
    # pass had it positive, which stood every neck up over the animal's own
    # back and left the Sheep's head floating behind its fleece.
    m.pivot("Neck", "Gait", y=m.up(p["neck_y"]), z=-p["body_len"] * p["neck_z"],
            rx=p["neck_tilt"])
    m.put("NeckShaft", m.cyl(m.body, body_r * 0.46, body_r * 0.62,
                             m.up(neck), 6),
          parent="Gait/Neck", y=m.up(neck * 0.5))
    m.pivot("Head", "Gait/Neck", y=m.up(neck), rx=p["head_tilt"])
    head_r = p["head_r"]
    m.put("Skull", m.ball(m.pale, head_r, 1.05, 6, 3), parent="Gait/Neck/Head")
    m.put("Snout", m.cyl(m.pale, head_r * 0.42, head_r * 0.72, p["snout"], 6, "z"),
          parent="Gait/Neck/Head", y=m.up(-head_r * 0.22),
          z=-p["snout"] * 0.5 - head_r * 0.4, rx=1.5708)
    m.put("Nose", m.ball(m.deep, head_r * 0.28, 1.0, 5, 2),
          parent="Gait/Neck/Head", y=m.up(-head_r * 0.28),
          z=-p["snout"] - head_r * 0.4)
    ear = m.prism(m.deep, head_r * 0.5, m.up(head_r * p["ear"]), head_r * 0.22)
    m.put("EarL", ear, parent="Gait/Neck/Head", x=-head_r * 0.72,
          y=m.up(head_r * 0.55), z=head_r * 0.1, rz=0.5)
    m.put("EarR", ear, parent="Gait/Neck/Head", x=head_r * 0.72,
          y=m.up(head_r * 0.55), z=head_r * 0.1, rz=-0.5)
    eyes(m, "Gait/Neck/Head", m.up(head_r * 0.2), -head_r * 0.66,
         head_r * 0.86, head_r * 0.24)
    crest(m, "Gait/Neck/Head", m.up(head_r * 0.55), head_r * 0.15,
          head_r * 0.6, (head_r * 0.42, m.up(head_r * 1.5), head_r * 0.34), 0.7)

    m.put("Tail", m.cyl(m.pale, p["tail_r"] * 0.4, p["tail_r"], p["tail"], 5, "z"),
          parent="Gait", y=m.up(body_r * 0.5), z=p["body_len"] * 0.5,
          rx=p["tail_tilt"])

    plates(m, "Gait", [
        (-body_r * 0.94, m.up(body_r * 0.3), -p["body_len"] * 0.16, 0.0),
        (body_r * 0.94, m.up(body_r * 0.3), -p["body_len"] * 0.16, 0.0),
    ], (body_r * 0.2, m.up(body_r * 0.75), p["body_len"] * 0.32))
    spines(m, "Gait", 4, -p["body_len"] * 0.26, p["body_len"] * 0.18,
           m.up(body_r * 0.9), (body_r * 0.3, m.up(body_r * 0.7), body_r * 0.24),
           m.up(body_r * 0.25))

    m.arms = []
    return hip + m.up(p["neck_y"] + neck * math.cos(p["neck_tilt"])
                      + head_r * 1.1)


def build_biped(m, p):
    """Two legs, a torso, a head and something in its hands.

    More of the roster is built on this than on any other plan, which makes it
    the one most at risk of turning a whole bracket into one silhouette at
    several sizes. Four things are authored per creep to stop that, and every
    one of them changes the OUTLINE rather than the detail:

        stoop     how far forward the torso leans. A Fel Orc is bent over its
                  own shoulders where a Priest is upright
        robe      whether the legs are replaced by a hem, which changes the
                  bottom half of the silhouette completely
        head      skull, hood, helm, bare, horned or mask
        weapon    what the right arm carries, and how far out it sticks

    Tier 3 and 4 put NINE more creeps on this plan, which is the crowding this
    docstring was already warning about. Two heads and two weapons were added
    for them rather than reusing the four that existed, on the grounds that a
    horned satyr wearing a helm and a huntress carrying a sword are both the
    plan LYING about a creature - which is the same bar a new body plan has to
    clear, one level down.
    """
    hip = p["hip_y"]
    stance = p["stance"]
    leg(m, "LegL", -stance, hip, 0.0, p, 0.0, p["digit"])
    leg(m, "LegR", stance, hip, 0.0, p, 0.5, p["digit"])

    m.pivot("Gait", ".", y=hip)
    m.put("Pelvis", m.ball(m.deep, p["waist"], 0.9, 6, 2), parent="Gait")

    torso = p["torso"]
    m.pivot("Torso", "Gait", rx=p["stoop"])
    m.put("Chest", m.capsule(m.body, p["chest_r"], torso, 7, 3),
          parent="Gait/Torso", y=torso * 0.42)
    if p["robe"]:
        # A hem instead of trousers. It swallows most of the legs, which is
        # what makes a robed silhouette a cone standing on two feet rather than
        # a person - and the feet still show, so the walk still reads.
        m.put("Hem", m.cyl(m.body, p["waist"] * 1.1, p["robe"], hip * 1.02, 8),
              parent="Gait", y=-hip * 0.5)
        m.put("HemEdge", m.torus(m.deep, p["robe"] * 0.9, p["robe"], 12, 4),
              parent="Gait", y=-hip * 0.98)
    if p["belt"]:
        m.put("Belt", m.torus(m.trim, p["waist"] * 0.95, p["waist"] * 1.2, 12, 4),
              parent="Gait", y=m.up(p["waist"] * 0.2))
    if p.get("ribs"):
        rib = m.box(m.pale, p["chest_r"] * 1.7, m.up(p["chest_r"] * 0.14),
                    p["chest_r"] * 0.9)
        for index in range(3):
            m.put("Rib%d" % (index + 1), rib, parent="Gait/Torso",
                  y=torso * (0.34 + 0.16 * index), z=-p["chest_r"] * 0.28)

    shoulder = p["shoulder"]
    shoulder_y = torso * 0.82
    m.put("Shoulders", m.box(m.pale, shoulder * 1.6, m.up(p["chest_r"] * 0.72),
                             p["chest_r"] * 1.05),
          parent="Gait/Torso", y=shoulder_y)
    if p["cloak"]:
        m.put("Cloak", m.prism(m.deep, shoulder * 1.7, torso * p["cloak"],
                               p["chest_r"] * 0.3),
              parent="Gait/Torso", y=shoulder_y - torso * p["cloak"] * 0.42,
              z=p["chest_r"] * 0.8, rz=3.1416)

    _biped_head(m, p, shoulder_y)
    _biped_arms(m, p, shoulder, shoulder_y)

    plates(m, "Gait/Torso", [
        (-shoulder * 0.86, shoulder_y + m.up(p["chest_r"] * 0.2), 0.0, 0.0),
        (shoulder * 0.86, shoulder_y + m.up(p["chest_r"] * 0.2), 0.0, 0.0),
    ], (p["chest_r"] * 0.42, m.up(p["chest_r"] * 0.34), p["chest_r"] * 1.0))
    spines(m, "Gait/Torso", 4, p["chest_r"] * 0.9, -p["chest_r"] * 0.04,
           torso * 0.5, (p["chest_r"] * 0.32, m.up(p["chest_r"] * 0.85),
                         p["chest_r"] * 0.3), m.up(p["chest_r"] * 0.35))

    return hip + torso + p["neck"] + m.up(p["head_r"] * 1.9)


def _biped_head(m, p, shoulder_y):
    head_r = p["head_r"]
    m.pivot("Head", "Gait/Torso",
            y=shoulder_y + p["neck"] + m.up(head_r * 0.55))
    if p["head"] != "hood":
        m.put("Neck", m.cyl(m.deep, head_r * 0.42, head_r * 0.5, p["neck"], 5),
              parent="Gait/Torso", y=shoulder_y + p["neck"] * 0.5)

    if p["head"] == "skull":
        m.put("Skull", m.ball(m.pale, head_r, 1.0, 6, 3),
              parent="Gait/Torso/Head")
        m.put("Jaw", m.box(m.pale, head_r * 1.1, m.up(head_r * 0.4),
                           head_r * 1.15),
              parent="Gait/Torso/Head", y=m.up(-head_r * 0.62),
              z=-head_r * 0.22)
        eyes(m, "Gait/Torso/Head", m.up(head_r * 0.1), -head_r * 0.76,
             head_r * 0.8, head_r * 0.2)
    elif p["head"] == "hood":
        # A cone with a dark hollow in it. There is no face, which is the
        # point: the eyes are the only thing in there.
        m.put("Hood", m.cyl(m.body, head_r * 0.62, head_r * 1.25,
                            m.up(head_r * 1.5), 7),
              parent="Gait/Torso/Head", y=m.up(head_r * 0.25))
        m.put("HoodPeak", m.cyl(m.body, head_r * 0.1, head_r * 0.6,
                                m.up(head_r * 0.5), 7),
              parent="Gait/Torso/Head", y=m.up(head_r * 1.2),
              z=head_r * 0.24, rx=-0.4)
        m.put("Hollow", m.ball(m.deep, head_r * 0.82, 1.0, 6, 2),
              parent="Gait/Torso/Head", y=m.up(-head_r * 0.22),
              z=-head_r * 0.42)
        eyes(m, "Gait/Torso/Head", m.up(-head_r * 0.2), -head_r * 1.08,
             head_r * 0.52, head_r * 0.19)
    elif p["head"] == "helm":
        m.put("Helm", m.ball(m.pale, head_r, 1.05, 6, 3),
              parent="Gait/Torso/Head")
        m.put("Visor", m.box(m.trim, head_r * 1.25, m.up(head_r * 0.34),
                             head_r * 0.42),
              parent="Gait/Torso/Head", y=m.up(-head_r * 0.14),
              z=-head_r * 0.76)
        m.put("Ridge", m.prism(m.trim, head_r * 0.3, m.up(head_r * 0.9),
                               head_r * 1.9),
              parent="Gait/Torso/Head", y=m.up(head_r * 0.8))
        eyes(m, "Gait/Torso/Head", m.up(-head_r * 0.1), -head_r * 0.84,
             head_r * 0.56, head_r * 0.18)
    elif p["head"] == "horned":
        # A bare skull with two long horns sweeping FORWARD past the face,
        # which is the one head in the plan whose outline reaches in front of
        # its own eyes. From directly above that is what a player reads first,
        # so it has to be the thing that says which creep this is - and the
        # horns are placed low and wide enough that the eyes still show
        # between them. See the trap about brows in PLACEHOLDER_ART.
        m.put("Head", m.ball(m.pale, head_r, 1.0, 6, 3),
              parent="Gait/Torso/Head")
        horn = m.prism(m.trim, head_r * 0.30, m.up(head_r * 1.9),
                       head_r * 0.26)
        for side, name in ((-1.0, "HornL"), (1.0, "HornR")):
            m.put(name, horn, parent="Gait/Torso/Head",
                  x=side * head_r * 0.72, y=m.up(head_r * 0.55),
                  z=head_r * 0.1, rz=side * -0.45, rx=-1.05)
        m.put("Muzzle", m.cyl(m.deep, head_r * 0.34, head_r * 0.6,
                              head_r * 0.7, 6, "z"),
              parent="Gait/Torso/Head", y=m.up(-head_r * 0.22),
              z=-head_r * 0.75, rx=1.5708)
        eyes(m, "Gait/Torso/Head", m.up(head_r * 0.12), -head_r * 0.72,
             head_r * 0.52, head_r * 0.2)
    elif p["head"] == "mask":
        # A flat plate hung in front of the face with the eyes cut into it. No
        # skull shape at all, which is the point: a masked creep has no
        # expression and no profile, and reads as a thing wearing a face
        # rather than as a person with one.
        m.put("Head", m.ball(m.deep, head_r * 0.82, 1.0, 6, 3),
              parent="Gait/Torso/Head")
        m.put("Mask", m.box(m.pale, head_r * 1.35, m.up(head_r * 1.5),
                            head_r * 0.28),
              parent="Gait/Torso/Head", z=-head_r * 0.72, rx=-0.12)
        m.put("MaskRim", m.box(m.trim, head_r * 1.5, m.up(head_r * 0.24),
                               head_r * 0.36),
              parent="Gait/Torso/Head", y=m.up(head_r * 0.7),
              z=-head_r * 0.72)
        fin = m.prism(m.trim, head_r * 0.22, m.up(head_r * 0.9),
                      head_r * 0.2)
        for side, name in ((-1.0, "PlumeL"), (1.0, "PlumeR")):
            m.put(name, fin, parent="Gait/Torso/Head",
                  x=side * head_r * 0.78, y=m.up(head_r * 0.6),
                  z=-head_r * 0.4, rz=side * 0.55)
        eyes(m, "Gait/Torso/Head", m.up(head_r * 0.05), -head_r * 0.9,
             head_r * 0.5, head_r * 0.19)
    else:  # bare
        m.put("Head", m.ball(m.pale, head_r, 1.05, 6, 3),
              parent="Gait/Torso/Head")
        m.put("Brow", m.box(m.deep, head_r * 1.35, m.up(head_r * 0.28),
                            head_r * 0.5),
              parent="Gait/Torso/Head", y=m.up(head_r * 0.32),
              z=-head_r * 0.62)
        if p["tusks"]:
            tusk = m.prism(m.trim, head_r * 0.28, m.up(head_r * 0.8),
                           head_r * 0.24)
            m.put("TuskL", tusk, parent="Gait/Torso/Head", x=-head_r * 0.58,
                  y=m.up(-head_r * 0.5), z=-head_r * 0.55, rx=0.35)
            m.put("TuskR", tusk, parent="Gait/Torso/Head", x=head_r * 0.58,
                  y=m.up(-head_r * 0.5), z=-head_r * 0.55, rx=0.35)
        eyes(m, "Gait/Torso/Head", m.up(head_r * 0.05), -head_r * 0.82,
             head_r * 0.6, head_r * 0.2)

    crest(m, "Gait/Torso/Head", m.up(head_r * 0.72), head_r * 0.1,
          head_r * 0.72, (head_r * 0.36, m.up(head_r * 1.5), head_r * 0.3),
          0.55)


def _biped_arms(m, p, shoulder, shoulder_y):
    upper = p["arm"]
    fore = p["arm"] * 0.85
    for side, name in ((-1.0, "ArmL"), (1.0, "ArmR")):
        path = "Gait/Torso/" + name
        m.pivot(name, "Gait/Torso", x=side * shoulder, y=shoulder_y,
                rz=side * p["arm_flare"])
        m.put("Upper", m.capsule(m.body, p["arm_r"], upper, 5, 2),
              parent=path, y=-upper * 0.5)
        m.put("Fore", m.capsule(m.pale, p["arm_r"] * 0.86, fore, 5, 2),
              parent=path, y=-upper - fore * 0.42)
        m.put("Hand", m.ball(m.pale, p["arm_r"] * 1.2, 1.0, 5, 2),
              parent=path, y=-upper - fore * 0.9)
        m.arms.append(path)

    _biped_weapon(m, p, "Gait/Torso/ArmR", upper + fore)
    _biped_offhand(m, p, "Gait/Torso/ArmL", upper + fore)


def _biped_weapon(m, p, path, arm_len):
    """What the right hand holds.

    EVERYTHING HANGS OFF A `Hold` PIVOT rather than being placed part by part
    on the arm, and that is not tidiness either. A weapon authored straight up
    the arm's own axis is drawn INSIDE the creature: the first pass gave the
    Skeleton and the Swordsman blades that came out of their own shoulders and
    were invisible from every angle a player ever sees. The pivot carries one
    pose - out, forward and tilted - and every weapon inherits it.

    NOTHING here may take the eye material. A lit weapon edge is the ATTACKER
    family's one tell, and half of this plan carries a sword without ever
    swinging it at a building - see style.py.
    """
    kind = p["weapon"]
    if not kind:
        return
    hold = path + "/Hold"
    m.pivot("Hold", path, x=p["arm_r"] * 2.0, y=-arm_len * 0.92,
            z=-p["arm_r"] * 1.2, rz=-0.2, rx=-0.22)

    if kind == "sword":
        blade = p["weapon_len"]
        m.put("Grip", m.cyl(m.deep, p["arm_r"] * 0.55, p["arm_r"] * 0.55,
                            blade * 0.22, 5),
              parent=hold, y=-blade * 0.06)
        m.put("Guard", m.box(m.trim, p["arm_r"] * 3.2, m.up(p["arm_r"] * 0.45),
                             p["arm_r"] * 0.9),
              parent=hold, y=blade * 0.07)
        m.put("Blade", m.box(m.trim, p["arm_r"] * 1.4, blade,
                             p["arm_r"] * 0.5),
              parent=hold, y=blade * 0.58)
        m.put("Tip", m.prism(m.trim, p["arm_r"] * 1.4, blade * 0.22,
                             p["arm_r"] * 0.5),
              parent=hold, y=blade * 1.19)
    elif kind == "axe":
        shaft = p["weapon_len"]
        m.put("Haft", m.cyl(m.deep, p["arm_r"] * 0.42, p["arm_r"] * 0.5,
                            shaft, 5),
              parent=hold, y=shaft * 0.3)
        # Rotated onto its side, so its authored HEIGHT ends up horizontal and
        # has to be a width measurement. This is exactly the trap up() exists
        # for: without it the blade gets narrower every time the roster does.
        m.put("AxeHead", m.prism(m.trim, p["arm_r"] * 3.6,
                                 m.up(p["arm_r"] * 2.6), p["arm_r"] * 0.65),
              parent=hold, y=shaft * 0.68, x=p["arm_r"] * 1.7, rz=1.5708)
        m.put("Spike", m.prism(m.trim, p["arm_r"] * 0.8, shaft * 0.24,
                               p["arm_r"] * 0.55),
              parent=hold, y=shaft * 0.9)
    elif kind == "staff":
        shaft = p["weapon_len"]
        m.put("Shaft", m.cyl(m.deep, p["arm_r"] * 0.4, p["arm_r"] * 0.46,
                             shaft, 5),
              parent=hold, y=shaft * 0.28)
        m.put("Finial", m.torus(m.trim, p["arm_r"] * 0.85, p["arm_r"] * 1.5,
                                10, 4),
              parent=hold, y=shaft * 0.8, rx=1.5708)
        # PALE, not glow. A staff head is not an eye and not an attacker's
        # weapon edge, and those are the only two lit things in the roster.
        m.put("Bead", m.ball(m.pale, p["arm_r"] * 0.75, 1.0, 5, 2),
              parent=hold, y=shaft * 0.8)
    elif kind == "spear":
        # A long shaft carried UPRIGHT with a leaf blade on top. The one
        # weapon in the plan whose outline is mostly vertical, so from above it
        # is a point beside the creep rather than a bar across it - which is
        # what lets a Huntress read as fast where a swordsman reads as heavy.
        shaft = p["weapon_len"]
        m.put("Shaft", m.cyl(m.deep, p["arm_r"] * 0.32, p["arm_r"] * 0.38,
                             shaft, 5),
              parent=hold, y=shaft * 0.26)
        m.put("Head", m.prism(m.trim, p["arm_r"] * 1.3, shaft * 0.28,
                              p["arm_r"] * 0.42),
              parent=hold, y=shaft * 0.86)
        m.put("Collar", m.torus(m.trim, p["arm_r"] * 0.5, p["arm_r"] * 0.8,
                                8, 4),
              parent=hold, y=shaft * 0.7, rx=1.5708)
        m.put("Butt", m.prism(m.trim, p["arm_r"] * 0.5, shaft * 0.14,
                              p["arm_r"] * 0.34),
              parent=hold, y=-shaft * 0.3, rx=3.1416)
    elif kind == "scythe":
        # A shaft with the blade laid ACROSS the top and swept back, so the
        # silhouette from above is an L rather than a line. Nothing else on
        # the plan reaches sideways at head height, which is the whole reason
        # it is here: it is the only weapon a player can identify from the
        # camera without seeing the creep holding it.
        shaft = p["weapon_len"]
        m.put("Haft", m.cyl(m.deep, p["arm_r"] * 0.36, p["arm_r"] * 0.42,
                            shaft, 5),
              parent=hold, y=shaft * 0.3)
        m.put("Socket", m.cyl(m.trim, p["arm_r"] * 0.55, p["arm_r"] * 0.7,
                              shaft * 0.12, 5),
              parent=hold, y=shaft * 0.8)
        # Laid on its side, so its authored height is a WIDTH and takes up().
        # The blade would get shorter every time the roster got lower without
        # it - the rotated-part trap this file has paid for twice.
        m.put("Blade", m.prism(m.trim, p["arm_r"] * 4.4,
                               m.up(p["arm_r"] * 1.5), p["arm_r"] * 0.4),
              parent=hold, y=shaft * 0.84, x=-p["arm_r"] * 2.2,
              z=-p["arm_r"] * 0.9, rz=-1.5708, rx=0.25)
        m.put("Tip", m.prism(m.trim, p["arm_r"] * 0.9,
                             m.up(p["arm_r"] * 1.4), p["arm_r"] * 0.34),
              parent=hold, y=shaft * 0.84, x=-p["arm_r"] * 4.2,
              z=-p["arm_r"] * 1.6, rz=-2.0)
    elif kind == "whip":
        # Four falling segments, each thinner and further back than the last.
        # A whip has no silhouette of its own, so what makes it read is the
        # CURVE - and a curve out of primitives is a chain of them.
        length = p["weapon_len"]
        m.put("Handle", m.cyl(m.deep, p["arm_r"] * 0.45, p["arm_r"] * 0.5,
                              length * 0.22, 5),
              parent=hold, y=length * 0.05)
        for index in range(4):
            share = index / 3.0
            m.put("Lash%d" % (index + 1),
                  m.cyl(m.trim, p["arm_r"] * (0.52 - 0.14 * share),
                        p["arm_r"] * (0.6 - 0.14 * share), length * 0.34, 4,
                        "z"),
                  parent=hold,
                  y=-m.up(length * (0.05 + 0.16 * share)),
                  z=length * (0.2 + 0.62 * share), rx=0.85 + 0.45 * share)


def _biped_offhand(m, p, path, arm_len):
    """The left hand's shield, on a pivot of its own for the same reason."""
    if not p["shield"]:
        return
    r = p["shield"]
    grip = path + "/Grip"
    m.pivot("Grip", path, x=-p["arm_r"] * 1.2, y=-arm_len * 0.86,
            z=-r * 0.5, rz=0.25, rx=-0.15)
    m.put("Shield", m.cyl(m.pale, r, r * 0.86, r * 0.2, 6, "z"),
          parent=grip, rx=1.5708)
    m.put("ShieldBoss", m.ball(m.trim, r * 0.3, 1.0, 5, 2),
          parent=grip, z=-r * 0.16)
    m.put("ShieldRim", m.torus(m.trim, r * 0.86, r, 12, 4),
          parent=grip, rx=1.5708)


def build_arachnid(m, p):
    """Eight legs around a low double body: the Forest Spider.

    The one creep in the roster that is WIDER than it is tall, and that is the
    whole silhouette. Everything else walks upright; this thing spreads. It is
    also the creep towers ignore until last, so being hard to pick out of a
    maze is not a failure of the model - it is the trait.
    """
    hip = p["hip_y"]
    for index in range(4):
        z = p["leg_first"] + p["leg_step"] * index
        # Legs alternate around the body rather than in front-to-back pairs, so
        # four feet are always down. A spider that lifts one whole side reads
        # as falling over.
        phase = 0.0 if index % 2 == 0 else 0.5
        _spider_leg(m, "LegL%d" % (index + 1), -p["leg_span"], hip, z, p,
                    phase, -1.0)
        _spider_leg(m, "LegR%d" % (index + 1), p["leg_span"], hip, z, p,
                    0.5 - phase, 1.0)

    m.pivot("Gait", ".", y=hip)
    abdomen_r = p["abdomen"]
    m.put("Abdomen", m.ball(m.body, abdomen_r, 0.86, 7, 4),
          parent="Gait", y=m.up(abdomen_r * 0.06), z=p["abdomen_z"])
    m.put("Mark", m.ball(m.pale, abdomen_r * 0.46, 0.4, 5, 2),
          parent="Gait", y=m.up(abdomen_r * 0.5), z=p["abdomen_z"])
    thorax_r = p["thorax"]
    m.put("Thorax", m.ball(m.pale, thorax_r, 0.9, 6, 3),
          parent="Gait", z=-thorax_r * 0.5)
    fang = m.prism(m.trim, thorax_r * 0.3, m.up(thorax_r * 0.85),
                   thorax_r * 0.28)
    m.put("FangL", fang, parent="Gait", x=-thorax_r * 0.38,
          y=m.up(-thorax_r * 0.2), z=-thorax_r * 1.3, rx=2.6)
    m.put("FangR", fang, parent="Gait", x=thorax_r * 0.38,
          y=m.up(-thorax_r * 0.2), z=-thorax_r * 1.3, rx=2.6)
    # Four eyes rather than two. It is the cheapest possible way to say
    # "arthropod" and it survives being three pixels across.
    eyes(m, "Gait", m.up(thorax_r * 0.3), -thorax_r * 1.1, thorax_r * 0.5,
         thorax_r * 0.16, 4)
    eyes(m, "Gait", m.up(thorax_r * 0.6), -thorax_r * 0.9, thorax_r * 0.9,
         thorax_r * 0.12, 2, "EyeTop")

    plates(m, "Gait", [
        (0.0, m.up(abdomen_r * 0.6), p["abdomen_z"] - abdomen_r * 0.4, 0.0),
        (0.0, m.up(abdomen_r * 0.54), p["abdomen_z"] + abdomen_r * 0.4, 0.0),
    ], (abdomen_r * 1.05, m.up(abdomen_r * 0.28), abdomen_r * 0.45))
    spines(m, "Gait", 3, p["abdomen_z"] - abdomen_r * 0.5, abdomen_r * 0.5,
           m.up(abdomen_r * 0.8),
           (abdomen_r * 0.28, m.up(abdomen_r * 0.6), abdomen_r * 0.24),
           m.up(abdomen_r * 0.2))
    crest(m, "Gait", m.up(thorax_r * 0.6), -thorax_r * 0.7, thorax_r * 0.7,
          (thorax_r * 0.3, m.up(thorax_r * 1.3), thorax_r * 0.26), 0.7)
    return hip + m.up(abdomen_r * 0.95)


def _spider_leg(m, name, x, y, z, p, phase, side):
    """A femur angled up and out, a tibia angled down to the floor.

    ALL OF THE TRIGONOMETRY HERE IS IN WIDTH UNITS, and the y values are handed
    to put() through up(). That is not tidiness: a leg placed with x in one
    space and y in another lands at an angle nobody authored, which is how the
    first pass ended up with the knees inside the abdomen.

    The tibia's LENGTH is derived rather than authored, for the same reason a
    walking leg's is - the claw has to land on the floor from whatever height
    the body is at, and two authored lengths plus two authored angles that
    happen to add up is not something a diff can check.

    Both segments pass along="z" even though neither runs down Z: what `along`
    really asks is whether a part should take the HEIGHT ramp or the WIDTH one,
    and a leg that mostly reaches sideways must not be shortened every time the
    roster gets lower. See modelkit.
    """
    m.pivot(name, ".", x=x, y=y, z=z)
    femur = p["femur"]
    # A capsule points down +Y; rotating it by rz maps that to
    # (-sin rz, cos rz). Up and out is a NEGATIVE rz on the right hand side.
    up_angle = p["femur_angle"]
    knee_x = math.sin(up_angle) * femur
    knee_y = math.cos(up_angle) * femur
    down = p["tibia_angle"]
    floor = m.down(y)
    # How far the tibia has to drop to put the claw on the ground.
    tibia = (knee_y + floor) / max(0.15, -math.cos(down))
    foot_x = knee_x + math.sin(down) * tibia

    m.put("Femur", m.capsule(m.body, p["leg_r"], femur, 5, 2, "z"),
          parent=name, x=side * knee_x * 0.5, y=m.up(knee_y * 0.5),
          rz=side * -up_angle)
    m.put("Tibia", m.capsule(m.deep, p["leg_r"] * 0.85, tibia, 5, 2, "z"),
          parent=name, x=side * (knee_x + foot_x) * 0.5,
          y=m.up((knee_y - floor) * 0.5), rz=side * -down)
    m.put("Claw", m.prism(m.trim, p["leg_r"] * 1.5, m.up(p["leg_r"] * 1.3),
                          p["leg_r"] * 2.4),
          parent=name, x=side * foot_x, y=m.up(-floor + p["leg_r"] * 0.6),
          rx=1.5708)
    m.legs.append(name)
    m.phases.append(phase)


def build_golem(m, p):
    """A slab of a torso on short legs, with arms that reach the ground.

    Both golems in tier 1 are built from this and they are eight rungs of
    health apart, so the plan has to survive being drawn small and mean and
    then drawn as a Boss. What carries that is PROPORTION: the Rot Golem is not
    the Mud Golem scaled up, it is the same parts with a wider chest, longer
    arms and a head sunk further into its own shoulders.
    """
    hip = p["hip_y"]
    leg(m, "LegL", -p["stance"], hip, 0.0, p, 0.0, "claw")
    leg(m, "LegR", p["stance"], hip, 0.0, p, 0.5, "claw")

    m.pivot("Gait", ".", y=hip)
    chest_w = p["chest_w"]
    chest_h = p["chest_h"]
    m.put("Torso", m.cyl(m.body, chest_w * 0.46, chest_w * 0.54, chest_h, 6),
          parent="Gait", y=chest_h * 0.45, ry=0.5236)
    m.put("Gut", m.ball(m.deep, chest_w * 0.42, 0.9, 6, 3),
          parent="Gait", y=chest_h * 0.12, z=-p["chest_d"] * 0.16)
    boulder = m.ball(m.pale, chest_w * 0.24, 0.95, 6, 3)
    m.put("ShoulderL", boulder, parent="Gait", x=-chest_w * 0.5,
          y=chest_h * 0.84)
    m.put("ShoulderR", boulder, parent="Gait", x=chest_w * 0.5,
          y=chest_h * 0.84)
    if p["ribs"]:
        # Bone showing through. The Rot Golem's own tell, and the reason the
        # two golems never read as one creature at two sizes.
        # Narrow and short, so they read as a ribcage showing through rather
        # than as a grille across the whole chest.
        for index in range(3):
            span = chest_w * (0.5 - 0.07 * index)
            m.put("Rib%d" % (index + 1),
                  m.box(m.trim, span, m.up(chest_w * 0.055),
                        p["chest_d"] * 0.16),
                  parent="Gait", y=chest_h * (0.3 + 0.17 * index),
                  z=-p["chest_d"] * 0.46)

    head_r = p["head_r"]
    m.pivot("Head", "Gait", y=chest_h * p["head_sink"], z=-p["chest_d"] * 0.18)
    m.put("Skull", m.ball(m.pale, head_r, 0.95, 6, 3), parent="Gait/Head")
    m.put("Jaw", m.box(m.deep, head_r * 1.0, m.up(head_r * 0.36),
                       head_r * 0.9),
          parent="Gait/Head", y=m.up(-head_r * 0.62), z=-head_r * 0.25)
    eyes(m, "Gait/Head", m.up(head_r * 0.08), -head_r * 0.78, head_r * 0.78,
         head_r * 0.22)
    crest(m, "Gait/Head", m.up(head_r * 0.6), head_r * 0.2, head_r * 0.76,
          (head_r * 0.42, m.up(head_r * 1.7), head_r * 0.34), 0.62)

    arm = p["arm"]
    for side, name in ((-1.0, "ArmL"), (1.0, "ArmR")):
        path = "Gait/" + name
        m.pivot(name, "Gait", x=side * chest_w * 0.6, y=chest_h * 0.78,
                rz=side * 0.16)
        m.put("Upper", m.capsule(m.body, p["arm_r"], arm * 0.55, 5, 2),
              parent=path, y=-arm * 0.28)
        m.put("Fore", m.capsule(m.body, p["arm_r"] * 1.1, arm * 0.5, 5, 2),
              parent=path, y=-arm * 0.72)
        m.put("Fist", m.ball(m.pale, p["arm_r"] * 1.35, 1.0, 6, 3),
              parent=path, y=-arm * 1.0)
        knuckle = m.prism(m.trim, p["arm_r"] * 0.5, m.up(p["arm_r"] * 0.85),
                          p["arm_r"] * 0.45)
        for index in range(3):
            m.put("Knuckle%d%s" % (index + 1, name[-1]), knuckle, parent=path,
                  x=side * p["arm_r"] * 1.5,
                  y=-arm * 1.0 + m.up(p["arm_r"] * 0.3),
                  z=p["arm_r"] * (index - 1) * 0.9, rz=side * -1.5708)
        m.arms.append(path)

    # Over the whole torso rather than out of one vent, since what burns here
    # is the creature and not a hole in it. Nothing happens on a golem that
    # style has not named - see flames().
    flames(m, "Gait", chest_h * 0.5, chest_w * 0.62)

    plates(m, "Gait", [
        (-chest_w * 0.5, chest_h * 0.94, 0.0, 0.0),
        (chest_w * 0.5, chest_h * 0.94, 0.0, 0.0),
    ], (chest_w * 0.24, m.up(chest_w * 0.1), p["chest_d"] * 0.8))
    spines(m, "Gait", 4, -p["chest_d"] * 0.1, p["chest_d"] * 0.1,
           chest_h * 0.9, (chest_w * 0.16, m.up(chest_w * 0.24),
                           chest_w * 0.14), m.up(chest_w * 0.12))
    return hip + chest_h * p["head_sink"] + m.up(head_r * 1.1)


def build_wraith(m, p):
    """A hood over a column of vapour: the Shade, and every flyer after it.

    NO LEGS, which is the family rule and half the reason a flyer reads as one.
    What the walk component swings instead are the TATTERS - the same
    component, the same wiring, driven by a hover clock rather than by distance
    travelled, so a Shade drifting on the spot still moves.

    Everything here is drawn with creep_vapour.gdshader. See style.py.
    """
    shadow_disc(m, p["shadow"], p["fly_height"])

    m.pivot("Gait", ".", y=0.0)
    body = p["body"]
    m.put("Column", m.cyl(m.body, p["waist"], p["waist"] * 0.45, body, 7),
          parent="Gait", y=-body * 0.25)
    m.put("Mantle", m.cyl(m.pale, p["waist"] * 0.5, p["shoulder"],
                          m.up(p["waist"] * 0.85), 8),
          parent="Gait", y=m.up(p["waist"] * 0.3))

    head_r = p["head_r"]
    m.pivot("Head", "Gait", y=m.up(p["waist"] * 1.0))
    m.put("Hood", m.cyl(m.body, head_r * 0.6, head_r * 1.2,
                        m.up(head_r * 1.5), 7),
          parent="Gait/Head", y=m.up(head_r * 0.25))
    m.put("HoodPeak", m.cyl(m.body, head_r * 0.1, head_r * 0.55,
                            m.up(head_r * 0.55), 7),
          parent="Gait/Head", y=m.up(head_r * 1.2), z=head_r * 0.26, rx=-0.4)
    m.put("Hollow", m.ball(m.deep, head_r * 0.82, 1.0, 6, 2),
          parent="Gait/Head", y=m.up(-head_r * 0.2), z=-head_r * 0.4)
    eyes(m, "Gait/Head", m.up(-head_r * 0.18), -head_r * 1.05, head_r * 0.54,
         head_r * 0.22)
    crest(m, "Gait/Head", m.up(head_r * 0.9), head_r * 0.1, head_r * 0.66,
          (head_r * 0.34, m.up(head_r * 1.4), head_r * 0.28), 0.6)

    # Arms. Thin, long and reaching forward, which is the one thing on a wraith
    # that says which way it is going.
    arm = p["arm"]
    for side, name in ((-1.0, "ArmL"), (1.0, "ArmR")):
        path = "Gait/" + name
        m.pivot(name, "Gait", x=side * p["shoulder"] * 0.8,
                y=m.up(p["waist"] * 0.45), rz=side * 0.3, rx=-0.5)
        m.put("Sleeve", m.capsule(m.body, p["arm_r"], arm, 5, 2, "z"),
              parent=path, y=-arm * 0.5)
        claw = m.prism(m.trim, p["arm_r"] * 0.5, m.up(p["arm_r"] * 1.6),
                       p["arm_r"] * 0.4)
        for index in range(3):
            m.put("Claw%d%s" % (index + 1, name[-1]), claw, parent=path,
                  x=p["arm_r"] * (index - 1) * 0.7,
                  y=-arm - m.up(p["arm_r"] * 0.6), rx=3.1416)
        m.arms.append(path)

    # The tatters, which are what the gait swings. Splayed around the column
    # rather than in a row, so the bottom of a wraith frays from every side.
    count = p["tatters"]
    for index in range(count):
        angle = index * math.tau / count
        name = "Tatter%d" % (index + 1)
        m.pivot(name, ".", x=math.sin(angle) * p["waist"] * 0.52,
                y=-body * 0.35, z=math.cos(angle) * p["waist"] * 0.52)
        m.put("Rag", m.cyl(m.deep, p["waist"] * 0.22, p["waist"] * 0.04,
                           p["tatter_len"], 5),
              parent=name, y=-p["tatter_len"] * 0.5)
        m.legs.append(name)
        m.phases.append(index / float(count))

    plates(m, "Gait", [
        (-p["shoulder"] * 0.78, m.up(p["waist"] * 0.42), 0.0, 0.0),
        (p["shoulder"] * 0.78, m.up(p["waist"] * 0.42), 0.0, 0.0),
    ], (p["waist"] * 0.28, m.up(p["waist"] * 0.22), p["waist"] * 0.85))
    spines(m, "Gait", 3, p["waist"] * 0.4, -p["waist"] * 0.3,
           m.up(p["waist"] * 0.8),
           (p["waist"] * 0.2, m.up(p["waist"] * 0.5), p["waist"] * 0.18))

    m.hover = p["hover"]
    return m.up(p["waist"] * 1.0 + head_r * 1.55)


def build_treant(m, p):
    """A trunk on root legs with a lit branch to swing: the Corrupted Treant.

    The only ATTACKER in tier 1, and the family rule lives on one part of it:
    the CLEAVER, whose edge takes the eye material. Nothing else in the whole
    creep roster is allowed to, so the one thing on the field with a hot edge
    is the one thing that came for your towers rather than past them.

    Its right arm carries a `Swing` pivot, which is the node
    StrikeAnimation3D chops with. That node is the model's half of the
    contract; the component that turns it lives in the prefab.
    """
    hip = p["hip_y"]
    leg(m, "LegL", -p["stance"], hip, 0.0, p, 0.0, "claw")
    leg(m, "LegR", p["stance"], hip, 0.0, p, 0.5, "claw")

    m.pivot("Gait", ".", y=hip)
    trunk = p["trunk"]
    m.put("Trunk", m.cyl(m.body, p["trunk_top"], p["trunk_r"], trunk, 7),
          parent="Gait", y=trunk * 0.42)
    # Bark. Long slabs down the sides, in the deep tone, so the trunk is
    # grooved from above instead of being a smooth post.
    slab = m.box(m.deep, p["trunk_r"] * 0.34, trunk * 0.8, p["trunk_r"] * 0.5)
    m.ring_of(5, p["trunk_r"] * 0.8, lambda i, x, z, a: m.put(
        "Bark%d" % (i + 1), slab, parent="Gait", x=x, y=trunk * 0.42, z=z,
        ry=a))
    # Buttress roots, standing still while the leg roots walk. They are what
    # keeps the base wide enough to read as a tree.
    root = m.prism(m.deep, p["trunk_r"] * 0.7, trunk * 0.3, p["trunk_r"] * 0.9)
    m.ring_of(3, p["trunk_r"] * 0.85, lambda i, x, z, a: m.put(
        "Root%d" % (i + 1), root, parent="Gait", x=x, y=trunk * 0.05, z=z,
        ry=a + 3.1416, rx=0.2))

    head_r = p["head_r"]
    m.pivot("Head", "Gait", y=trunk * 0.9)
    m.put("Knot", m.ball(m.pale, head_r, 0.95, 7, 3), parent="Gait/Head")
    m.put("Brow", m.box(m.deep, head_r * 1.4, m.up(head_r * 0.28),
                        head_r * 0.5),
          parent="Gait/Head", y=m.up(head_r * 0.34), z=-head_r * 0.6)
    eyes(m, "Gait/Head", m.up(head_r * 0.02), -head_r * 0.8, head_r * 0.64,
         head_r * 0.24)
    # The canopy: dead branches, no leaves. A tree that has been corrupted has
    # nothing left up there, and an empty crown is a sharper silhouette than a
    # full one anyway.
    branch = m.prism(m.deep, p["trunk_r"] * 0.24, p["canopy"],
                     p["trunk_r"] * 0.2)
    m.ring_of(6, p["trunk_r"] * 0.5, lambda i, x, z, a: m.put(
        "Branch%d" % (i + 1), branch, parent="Gait/Head",
        x=x, y=m.up(head_r * 0.85), z=z, ry=a, rz=math.sin(a) * -0.5,
        rx=math.cos(a) * 0.5))

    _treant_arms(m, p, trunk)

    plates(m, "Gait", [
        (-p["trunk_r"] * 0.82, trunk * 0.72, 0.0, 0.0),
        (p["trunk_r"] * 0.82, trunk * 0.72, 0.0, 0.0),
    ], (p["trunk_r"] * 0.28, trunk * 0.16, p["trunk_r"] * 0.9))
    spines(m, "Gait", 4, p["trunk_r"] * 0.5, -p["trunk_r"] * 0.05, trunk * 0.55,
           (p["trunk_r"] * 0.24, trunk * 0.16, p["trunk_r"] * 0.22),
           trunk * 0.08)
    crest(m, "Gait/Head", m.up(head_r * 0.7), head_r * 0.1, head_r * 0.78,
          (head_r * 0.38, m.up(head_r * 1.6), head_r * 0.32), 0.6)
    return hip + trunk * 0.9 + m.up(head_r) + p["canopy"]


def _treant_arms(m, p, trunk):
    """A grasping branch on the left, and the cleaver on the right.

    The two are deliberately not a mirror pair. An attacker should look ARMED
    from any angle, and a creature holding the same thing in both hands reads
    as a decoration.
    """
    arm = p["arm"]
    shoulder_y = trunk * 0.76
    m.pivot("ArmL", "Gait", x=-p["trunk_r"] * 1.0, y=shoulder_y, rz=0.42)
    m.put("Upper", m.capsule(m.body, p["arm_r"], arm * 0.6, 5, 2),
          parent="Gait/ArmL", y=-arm * 0.3)
    m.put("Fore", m.capsule(m.body, p["arm_r"] * 0.8, arm * 0.55, 5, 2),
          parent="Gait/ArmL", y=-arm * 0.78, rz=-0.5)
    twig = m.prism(m.deep, p["arm_r"] * 0.5, m.up(p["arm_r"] * 1.9),
                   p["arm_r"] * 0.4)
    for index in range(3):
        m.put("Twig%d" % (index + 1), twig, parent="Gait/ArmL",
              x=-arm * 0.16 + p["arm_r"] * (index - 1) * 0.8,
              y=-arm * 1.04, rx=3.1416, rz=-0.5)
    m.arms.append("Gait/ArmL")

    # The right arm is the one that swings, so everything below the shoulder
    # hangs off a pivot of its own. StrikeAnimation3D turns THAT and nothing
    # else, which is why the shoulder itself must stay outside it.
    m.pivot("ArmR", "Gait", x=p["trunk_r"] * 1.0, y=shoulder_y, rz=-0.34)
    m.pivot("Swing", "Gait/ArmR")
    path = "Gait/ArmR/Swing"
    m.put("Upper", m.capsule(m.body, p["arm_r"] * 1.15, arm * 0.6, 5, 2),
          parent=path, y=-arm * 0.3)
    m.put("Fore", m.capsule(m.body, p["arm_r"], arm * 0.6, 5, 2),
          parent=path, y=-arm * 0.8, rz=0.35)
    # THE CLEAVER, and the family's whole tell. A slab of dead wood in the
    # carapace material with the eye material laid along its edge - the one
    # place in the creep roster where the lit accent is not an eye.
    cleave = p["cleaver"]
    m.put("Cleaver", m.box(m.trim, p["arm_r"] * 0.7, m.up(cleave),
                           cleave * 0.75),
          parent=path, x=arm * 0.26, y=-arm * 1.18, rz=0.35)
    m.put("CleaverEdge", m.box(m.glow, p["arm_r"] * 0.78, m.up(cleave * 0.16),
                               cleave * 0.8),
          parent=path, x=arm * 0.26 + cleave * 0.16,
          y=-arm * 1.18 - m.up(cleave * 0.5), rz=0.35, shadow=False)
    m.put("CleaverSpike", m.prism(m.trim, p["arm_r"] * 0.7, m.up(cleave * 0.5),
                                  cleave * 0.3),
          parent=path, x=arm * 0.26 - cleave * 0.18,
          y=-arm * 1.18 + m.up(cleave * 0.62), rz=0.35)
    m.arms.append("Gait/ArmR")
    m.strike = path


def build_brute(m, p):
    """A shaggy hunched hulk on two heavy legs: the Ancient Wendigo.

    The plan the GOLEM one could not do the job of, and the difference is the
    part a top down camera actually sees. A golem is an upright slab that
    shows the top of its chest and sinks its head between its shoulders; a
    brute leans out over its own feet, so what fills the screen is a wide
    RAGGED BACK with the head thrust past the front of it.

    Two silhouettes, not one silhouette at two sizes - and that distinction is
    load bearing rather than tidy, because the roster is not ALLOWED to say
    "bigger" here. Every creep in the game lives inside one narrow band of
    sizes (style.CREEP_MAX_HEIGHT), so the only thing separating the roster's
    two heavyweights is their shape.

    THE PELT is what carries that. An arc of overlapping lumps across the
    shoulders, the same trick the Sheep's fleece uses, spent on the half of
    the body the camera is looking straight down at: it breaks the outline
    into fur where every other big creep in the roster ends in a clean edge.

    `hunch` is a NEGATIVE rotation about X, because Godot's forward is -Z. A
    positive one stands the creature up over its own back, which is the sign
    trap this file has already paid for once.
    """
    hip = p["hip_y"]
    leg(m, "LegL", -p["stance"], hip, 0.0, p, 0.0, "claw")
    leg(m, "LegR", p["stance"], hip, 0.0, p, 0.5, "claw")

    m.pivot("Gait", ".", y=hip)
    m.put("Haunch", m.ball(m.deep, p["waist"], 0.86, 6, 3), parent="Gait")

    m.pivot("Torso", "Gait", rx=p["hunch"])
    barrel = p["barrel"]
    chest_r = p["chest_r"]
    m.put("Barrel", m.capsule(m.body, chest_r, barrel, 7, 3),
          parent="Gait/Torso", y=barrel * 0.44)
    m.put("Gut", m.ball(m.deep, chest_r * 0.86, 0.9, 6, 3),
          parent="Gait/Torso", y=barrel * 0.22, z=-chest_r * 0.28)

    shoulder = p["shoulder"]
    shoulder_y = barrel * 0.80
    # Two shoulder masses with a GAP between them, never a bar across the top.
    # From directly above, a bar is the front of the silhouette and the head is
    # behind it; a gap leaves the head the frontmost thing, which is the only
    # place a player can read a facing from. The first pass had the bar and the
    # creature read as a slab with snow on it.
    boulder = m.ball(m.pale, p["shoulder_r"], 0.92, 6, 3)
    m.put("ShoulderL", boulder, parent="Gait/Torso", x=-shoulder * 0.84,
          y=shoulder_y, z=chest_r * 0.10)
    m.put("ShoulderR", boulder, parent="Gait/Torso", x=shoulder * 0.84,
          y=shoulder_y, z=chest_r * 0.10)

    _brute_pelt(m, p, shoulder, shoulder_y)
    _brute_head(m, p, shoulder_y)
    _brute_arms(m, p, shoulder, shoulder_y)

    plates(m, "Gait/Torso", [
        (-shoulder * 0.86, shoulder_y + m.up(chest_r * 0.24), 0.0, 0.0),
        (shoulder * 0.86, shoulder_y + m.up(chest_r * 0.24), 0.0, 0.0),
    ], (chest_r * 0.34, m.up(chest_r * 0.32), chest_r * 1.15))
    # Up the back rather than along it: the torso is still mostly upright, so
    # a long z run would leave the front half of the row standing on the
    # creature's chest. The same reading the biped plan takes.
    spines(m, "Gait/Torso", 4, chest_r * 1.02, -chest_r * 0.10, barrel * 0.56,
           (chest_r * 0.26, m.up(chest_r * 0.9), chest_r * 0.26),
           m.up(chest_r * 0.34))

    m.arms = ["Gait/Torso/ArmL", "Gait/Torso/ArmR"]
    return hip + barrel * 0.9 + m.up(p["pelt"] * 1.8)


def _brute_pelt(m, p, shoulder, shoulder_y):
    """The mane, and the whole reason this plan is not the golem one.

    An ARC across the shoulders rather than a ring around the body: from
    above, a ring reads as a collar and an arc reads as a hunched back. The
    middle lump sits highest and the outer ones drop away, so the outline over
    the shoulders is a hump rather than a straight bar.
    """
    count = p["pelt_count"]
    chest_r = p["chest_r"]
    # FLATTENED and small. A round lump at this size is a snowball, and five of
    # them are a snowbank - which is exactly what the first pass looked like.
    # What has to read is a RAGGED OUTLINE, so they are spread around the back
    # of the barrel and barely stand off it.
    lump = m.ball(m.pale, p["pelt"], 0.52, 6, 3)
    reach = chest_r * 0.92
    for index in range(count):
        share = index / float(count - 1) * 2.0 - 1.0
        # A narrow arc over the BACK, held above the shoulder line. Swung any
        # wider it meets the shoulder masses at the sides and the whole animal
        # reads as a flower seen from above, which is what the first pass did.
        angle = share * 0.85
        m.put("Pelt%d" % (index + 1), lump, parent="Gait/Torso",
              x=math.sin(angle) * reach,
              y=shoulder_y + m.up(p["pelt"] * (0.70 - 0.75 * share * share)),
              z=math.cos(angle) * reach)
    # Two more down the rump, so the fur does not stop dead at the shoulders.
    for index in range(2):
        m.put("Ruff%d" % (index + 1),
              m.ball(m.pale, p["pelt"] * (0.95 - 0.20 * index), 0.52, 6, 3),
              parent="Gait/Torso",
              y=shoulder_y - p["barrel"] * (0.30 + 0.26 * index),
              z=chest_r * 0.92)


def _brute_head(m, p, shoulder_y):
    """A broad skull thrust FORWARD out of the shoulders rather than perched
    above them. There is no neck: what a wendigo carries between its head and
    its body is more shoulder."""
    head_r = p["head_r"]
    chest_r = p["chest_r"]
    # Below the shoulder line and clear in FRONT of it. Both halves matter:
    # below is what makes the hunch read from the side, and clear in front is
    # what makes the eyes the frontmost thing from above.
    # head_tilt is measured against the HUNCHED torso and so runs the other
    # way to it: a POSITIVE one lifts the head back towards level. Left at the
    # torso's own lean the animal walks the whole match looking at the floor,
    # with its eyes pointing at ground the camera never sees.
    m.pivot("Head", "Gait/Torso", y=shoulder_y - m.up(head_r * 0.55),
            z=-chest_r * 1.18, rx=p["head_tilt"])
    path = "Gait/Torso/Head"
    m.put("Skull", m.ball(m.pale, head_r, 1.0, 6, 3), parent=path)
    # Set BACK of the eyes rather than over them. A brow between the camera
    # and the two lit dots is a creep with no face from the only angle the game
    # is ever played from.
    m.put("Brow", m.box(m.deep, head_r * 1.45, m.up(head_r * 0.34),
                        head_r * 0.55),
          parent=path, y=m.up(head_r * 0.44), z=-head_r * 0.34)
    m.put("Muzzle", m.cyl(m.pale, head_r * 0.52, head_r * 0.80, p["muzzle"],
                          6, "z"),
          parent=path, y=m.up(-head_r * 0.26),
          z=-head_r * 0.6 - p["muzzle"] * 0.5, rx=1.5708)
    m.put("Jaw", m.box(m.deep, head_r * 1.05, m.up(head_r * 0.36),
                       head_r * 1.05),
          parent=path, y=m.up(-head_r * 0.62), z=-head_r * 0.4)
    # Tusks point UP out of the lower jaw, which is the one feature that says
    # this is not another ape. A PrismMesh already points its apex at +Y, so
    # they need no rotation beyond the splay.
    tusk = m.prism(m.trim, head_r * 0.30, m.up(head_r * 1.05), head_r * 0.26)
    for side, name in ((-1.0, "TuskL"), (1.0, "TuskR")):
        m.put(name, tusk, parent=path, x=side * head_r * 0.62,
              y=m.up(-head_r * 0.42), z=-head_r * 0.86, rz=side * -0.18)
    eyes(m, path, m.up(head_r * 0.22), -head_r * 0.84, head_r * 0.62,
         head_r * 0.22)
    crest(m, path, m.up(head_r * 0.66), head_r * 0.28, head_r * 0.80,
          (head_r * 0.36, m.up(head_r * 1.5), head_r * 0.30), 0.62)


def _brute_arms(m, p, shoulder, shoulder_y):
    """Arms that hang past the knee and end in a fist, hung off the leaning
    torso so they reach forward as well as down.

    Nothing here takes the eye material UNLESS the creep is an attacker, and
    then exactly one part of it does - the edge of the slab in its right hand.
    A lit weapon edge is the ATTACKER family's one tell, and a brute that
    walks past your towers must not have one. See the `club` key.
    """
    arm = p["arm"]
    club = p.get("club", 0.0)
    for side, name in ((-1.0, "ArmL"), (1.0, "ArmR")):
        path = "Gait/Torso/" + name
        m.pivot(name, "Gait/Torso", x=side * shoulder, y=shoulder_y,
                rz=side * p["arm_flare"])
        # The right arm of an ARMED brute swings, so everything below its
        # shoulder hangs off a pivot of its own - the same contract the treant
        # meets, and the reason the shoulder itself stays outside it.
        if club and side > 0.0:
            m.pivot("Swing", path)
            path = path + "/Swing"
            m.strike = path
        m.put("Upper", m.capsule(m.body, p["arm_r"], arm * 0.52, 5, 2),
              parent=path, y=-arm * 0.26)
        m.put("Fore", m.capsule(m.body, p["arm_r"] * 0.94, arm * 0.50, 5, 2),
              parent=path, y=-arm * 0.74)
        # The BODY tone, not the pale one. A fist is the lowest thing on the
        # arm and pale is for what is raised - and this plan already spends
        # its pale on a back full of fur, so a pale fist is one more bright
        # lump in a silhouette that cannot afford another.
        m.put("Fist", m.ball(m.body, p["arm_r"] * 1.35, 1.0, 6, 3),
              parent=path, y=-arm * 1.02)
        claw = m.prism(m.trim, p["arm_r"] * 0.52, m.up(p["arm_r"] * 1.5),
                       p["arm_r"] * 0.44)
        for index in range(3):
            m.put("Claw%d%s" % (index + 1, name[-1]), claw, parent=path,
                  x=p["arm_r"] * (index - 1) * 0.80,
                  y=-arm * 1.02 - m.up(p["arm_r"] * 0.7),
                  z=-p["arm_r"] * 0.5, rx=3.1416)
        if club and side > 0.0:
            _brute_club(m, p, path, arm, club)


def _brute_club(m, p, path, arm, club):
    """A torn slab of the map held in one fist, with a hot edge along it.

    THE ATTACKER FAMILY'S ONE TELL and the only lit thing on this creature:
    the eye material laid along the leading edge of a slab that is otherwise
    the carapace material. A player looking at a lane full of heavyweights has
    to be able to pick out the one that came for their towers, and this is
    what says it.

    Held ACROSS the body rather than straight down the arm, for the reason
    every weapon in this file is: a slab authored along the arm's own axis is
    drawn inside the creature and is invisible from the only angle that
    matters.
    """
    m.put("Club", m.box(m.trim, club * 0.42, m.up(club), club * 0.5),
          parent=path, x=p["arm_r"] * 1.3, y=-arm * 1.24, rz=0.3)
    m.put("ClubEdge", m.box(m.glow, club * 0.46, m.up(club * 0.14),
                            club * 0.56),
          parent=path, x=p["arm_r"] * 1.3 + club * 0.14,
          y=-arm * 1.24 - m.up(club * 0.52), rz=0.3, shadow=False)
    for index in range(3):
        m.put("ClubSpike%d" % (index + 1),
              m.prism(m.trim, club * 0.16, m.up(club * 0.34), club * 0.14),
              parent=path, x=p["arm_r"] * 1.3 - club * 0.26,
              y=-arm * 1.24 + m.up(club * (index - 1) * 0.34),
              z=club * 0.1, rz=1.9)


def build_winged(m, p):
    """A body slung between two beating wings: the Wyvern, and the roster's
    first flyer that is an ANIMAL rather than a ghost.

    It is in the AIR family and keeps both of that family's hard tells - NO
    LEGS and a shadow disc pinned to the ground under it - and it breaks the
    third, being translucent, because a solid beast drawn as vapour reads as a
    spirit. That tell moved onto the WRAITH plan where it belongs; see
    creep_roster.is_vapour and the note in style.py.

    WHAT THE GAIT SWINGS IS THE WINGS. They are hip pivots as far as the walk
    component is concerned - same wiring the Shade's tatters use, driven by the
    hover clock rather than by distance - so a Wyvern holding station still
    beats. Which is also why they sit at the MODEL ROOT rather than inside
    Gait, the contract every plan in this file follows.

    From directly above, a flyer is a pair of wings and almost nothing else, so
    the span is the silhouette and the body is only what hangs under it.
    """
    shadow_disc(m, p["shadow"], p["fly_height"])

    m.pivot("Gait", ".", y=0.0)
    body_r = p["body_r"]
    length = p["body_len"]
    m.put("Barrel", m.capsule(m.body, body_r, length, 7, 3, "z"),
          parent="Gait", rx=1.5708)
    m.put("Chest", m.ball(m.body, body_r * p["chest"], 1.05, 7, 3),
          parent="Gait", z=-length * 0.32)
    m.put("Belly", m.ball(m.deep, body_r * 0.82, 0.7, 6, 3),
          parent="Gait", y=m.up(-body_r * 0.34))

    # Neck and head, thrust FORWARD and slightly down. A flyer seen from above
    # has to say which way it is going with its head alone, since it has no
    # feet to read a stride from.
    neck = p["neck"]
    m.pivot("Neck", "Gait", z=-length * 0.46, rx=p["neck_tilt"])
    m.put("NeckShaft", m.cyl(m.body, body_r * 0.42, body_r * 0.62,
                             m.up(neck), 6),
          parent="Gait/Neck", y=m.up(neck * 0.5))
    head_r = p["head_r"]
    m.pivot("Head", "Gait/Neck", y=m.up(neck), rx=p["head_tilt"])
    path = "Gait/Neck/Head"
    m.put("Skull", m.ball(m.pale, head_r, 1.0, 6, 3), parent=path)
    m.put("Snout", m.cyl(m.pale, head_r * 0.38, head_r * 0.74, p["snout"],
                         6, "z"),
          parent=path, y=m.up(-head_r * 0.18),
          z=-p["snout"] * 0.5 - head_r * 0.4, rx=1.5708)
    m.put("Jaw", m.box(m.deep, head_r * 0.9, m.up(head_r * 0.3), p["snout"]),
          parent=path, y=m.up(-head_r * 0.5), z=-p["snout"] * 0.5 - head_r * 0.3)
    # Swept back horns, so the head has an outline of its own against the wing
    # behind it.
    horn = m.prism(m.trim, head_r * 0.26, m.up(head_r * 1.1), head_r * 0.22)
    for side, name in ((-1.0, "HornL"), (1.0, "HornR")):
        m.put(name, horn, parent=path, x=side * head_r * 0.6,
              y=m.up(head_r * 0.5), z=head_r * 0.2, rz=side * -0.4, rx=0.5)
    eyes(m, path, m.up(head_r * 0.16), -head_r * 0.72, head_r * 0.7,
         head_r * 0.22)
    crest(m, path, m.up(head_r * 0.7), head_r * 0.24, head_r * 0.74,
          (head_r * 0.34, m.up(head_r * 1.4), head_r * 0.3), 0.6)

    _winged_wings(m, p, body_r)
    _winged_talons(m, p, body_r, length)
    # Nothing here decides whether a flyer burns - style.creep_flames does, off
    # the creep's own key, and answers None for all but one of them. The
    # Phoenix is that one, and a Phoenix giving off no light is reading as a
    # large bird. See flames().
    flames(m, "Gait", m.up(body_r * 0.4), body_r * 1.1)

    # The tail, and it is the counterweight the silhouette needs: without it a
    # wyvern from above is a head between two wings and reads as a moth.
    m.pivot("Tail", ".", y=m.up(body_r * 0.1), z=length * 0.48,
            rx=p["tail_tilt"])
    m.put("TailShaft", m.cyl(m.body, p["tail_r"] * 0.25, p["tail_r"],
                             p["tail"], 6, "z"),
          parent="Tail", z=p["tail"] * 0.5, rx=1.5708)
    m.put("TailBarb", m.prism(m.trim, p["tail_r"] * 1.5,
                              m.up(p["tail_r"] * 2.4), p["tail_r"] * 0.5),
          parent="Tail", z=p["tail"] * 1.05, rx=-1.5708)
    # The tail counter-swings against the wings, which is what the arm slot is
    # for on every other plan.
    m.arms.append("Tail")

    plates(m, "Gait", [
        (-body_r * 0.9, m.up(body_r * 0.3), -length * 0.16, 0.0),
        (body_r * 0.9, m.up(body_r * 0.3), -length * 0.16, 0.0),
    ], (body_r * 0.22, m.up(body_r * 0.7), length * 0.3))
    spines(m, "Gait", 4, -length * 0.24, length * 0.17, m.up(body_r * 0.88),
           (body_r * 0.26, m.up(body_r * 0.7), body_r * 0.22),
           m.up(body_r * 0.22))

    m.hover = p["hover"]
    return m.up(body_r + head_r * 1.6)


def _winged_talons(m, p, body_r, length):
    """A pair of hot talons folded under the body, on the pivot the strike
    animation swings.

    Only on an ATTACKER, and it is that family's one tell: the eye material on
    something that is not an eye. A Wyvern has none of this and neither does a
    Gryphon Rider - they go past your maze - and the Phoenix, which comes for
    it, is the only flyer in the game with anything lit under it.

    Under the CHEST rather than under the middle of the body, so from directly
    above the talons sit just behind the head where a player is already
    looking. Slung under the belly they would be hidden by the wings from the
    only angle the game is played from.
    """
    talon = p.get("talons", 0.0)
    if not talon:
        return

    m.pivot("Claws", "Gait", y=m.up(-body_r * 0.5), z=-length * 0.2)
    m.pivot("Swing", "Gait/Claws")
    path = "Gait/Claws/Swing"
    for side, name in ((-1.0, "L"), (1.0, "R")):
        m.put("Shank" + name, m.capsule(m.deep, p["wing_r"] * 0.9,
                                        m.up(talon * 0.9), 5, 2),
              parent=path, x=side * body_r * 0.5,
              y=m.up(-talon * 0.45), rz=side * 0.18)
        for index in range(3):
            m.put("Talon%d%s" % (index + 1, name),
                  m.prism(m.glow, talon * 0.16, m.up(talon * 0.62),
                          talon * 0.14),
                  parent=path,
                  x=side * body_r * 0.5 + talon * (index - 1) * 0.24,
                  y=m.up(-talon * 1.25), z=-talon * 0.1, rx=3.1416,
                  shadow=False)
    m.strike = path


def _winged_wings(m, p, body_r):
    """One beating wing per side, at the model root so the gait can swing it.

    Built as a SPAR and three membrane panels rather than one slab, because a
    single quad reads as a paddle from above: what says "wing" at this size is
    the fan of panels stepping back and narrowing towards the tip.
    """
    span = p["wing_span"]
    chord = p["wing_chord"]
    for side, name in ((-1.0, "WingL"), (1.0, "WingR")):
        m.pivot(name, ".", x=side * body_r * 0.7, y=m.up(body_r * 0.45),
                z=-body_r * 0.1, rz=side * -p["wing_droop"])
        m.put("Spar", m.cyl(m.trim, p["wing_r"] * 0.4, p["wing_r"], span,
                            5, "z"),
              parent=name, x=side * span * 0.5, rz=1.5708)
        # THREE PANELS THAT SWEEP AND TAPER, rather than three of one size.
        # The chord falls away hard towards the tip and each panel sits further
        # back than the last, so from directly above the wing is a swept
        # triangle. The first pass stepped them barely at all and every flyer
        # in the roster came out with a pair of rectangular planks - which
        # reads as an aeroplane, and got worse the moment there were four
        # flyers rather than one.
        #
        # The outer panel drops to the BODY tone as well. A whole wing in the
        # pale tone is the brightest object on the model by a distance, and on
        # the two near-white flyers it was the only thing a player could see.
        chords = (1.0, 0.58, 0.26)
        sweeps = (0.10, 0.30, 0.62)
        tones = (m.pale, m.pale, m.body)
        for index in range(3):
            m.put("Panel%d" % (index + 1),
                  m.box(tones[index], span * 0.34,
                        m.up(p["wing_r"] * 0.5), chord * chords[index]),
                  parent=name,
                  x=side * span * (0.2 + 0.32 * index),
                  y=m.up(-p["wing_r"] * (0.2 + 0.18 * index)),
                  z=chord * sweeps[index])
        # A finger bone along the trailing edge, so the wing has a hard rim
        # instead of fading into the hide behind it.
        # The trailing edge follows the sweep rather than running straight
        # across it, so the hard rim is on the shape the panels actually make.
        m.put("Finger", m.cyl(m.trim, p["wing_r"] * 0.22, p["wing_r"] * 0.5,
                              span * 0.8, 4, "z"),
              parent=name, x=side * span * 0.5, y=m.up(-p["wing_r"] * 0.3),
              z=chord * 0.42, rz=1.5708, ry=-side * 0.30)
        m.legs.append(name)
    m.phases.extend([0.0, 0.5])


def build_shelled(m, p):
    """A dome on four short legs: the Sea Turtle.

    The second creep in the roster that is wider than it is tall, and the only
    one that is ROOFED. That is the whole silhouette and it is worth a builder
    of its own: the quadruped plan draws a barrel with a neck on the front, and
    a barrel seen from directly above is an oval, where a dome with a rim
    around it reads as a shell from any angle without being told.

    The legs are deliberately SHORT and SPLAYED. A turtle carried high on its
    legs is a lizard; what makes this one read is the shell nearly touching
    the floor with four stumps under the corners of it.
    """
    hip = p["hip_y"]
    span = p["leg_span"]
    reach = p["leg_reach"]
    leg(m, "LegFL", -span, hip, -reach, p, 0.0, "claw")
    leg(m, "LegFR", span, hip, -reach, p, 0.5, "claw")
    leg(m, "LegBL", -span, hip, reach, p, 0.5, "claw")
    leg(m, "LegBR", span, hip, reach, p, 0.0, "claw")

    m.pivot("Gait", ".", y=hip)
    shell_r = p["shell_r"]
    shell_h = p["shell_h"]
    # The dome. FLATTENED hard, so it is a roof rather than a ball - a shell
    # that stands as tall as it is wide is a boulder, which is the mud golem's
    # job two brackets down.
    m.put("Shell", m.ball(m.body, shell_r, shell_h / max(shell_r, 0.001),
                          8, 3),
          parent="Gait", y=m.up(shell_r * 0.06))
    m.put("Plastron", m.ball(m.deep, shell_r * 0.86, 0.28, 7, 2),
          parent="Gait", y=m.up(-shell_r * 0.16))
    # The RIM, and it is what makes the dome read as a shell rather than as a
    # hump: a hard ring around the widest part, in the carapace material.
    m.put("Rim", m.torus(m.trim, shell_r * 0.94, shell_r * 1.06, 16, 4),
          parent="Gait", y=m.up(shell_r * 0.02))
    # Scutes. A ring of low pale lumps over the dome, so the roof is panelled
    # from above instead of being one smooth surface.
    scute = m.ball(m.pale, shell_r * 0.24, 0.30, 6, 2)
    m.ring_of(6, shell_r * 0.58, lambda i, x, z, a: m.put(
        "Scute%d" % (i + 1), scute, parent="Gait", x=x,
        y=m.up(shell_r * 0.16), z=z))
    m.put("ScuteTop", m.ball(m.pale, shell_r * 0.30, 0.32, 6, 2),
          parent="Gait", y=m.up(shell_r * 0.22))

    # Head, out from under the front of the shell on a short thick neck.
    neck = p["neck"]
    head_r = p["head_r"]
    m.pivot("Neck", "Gait", y=m.up(-shell_r * 0.1), z=-shell_r * 0.86,
            rx=p["neck_tilt"])
    m.put("NeckShaft", m.cyl(m.body, head_r * 0.6, head_r * 0.78, m.up(neck),
                             6),
          parent="Gait/Neck", y=m.up(neck * 0.5))
    m.pivot("Head", "Gait/Neck", y=m.up(neck))
    path = "Gait/Neck/Head"
    m.put("Skull", m.ball(m.pale, head_r, 0.95, 6, 3), parent=path)
    m.put("Beak", m.cyl(m.trim, head_r * 0.24, head_r * 0.62, p["snout"],
                        6, "z"),
          parent=path, y=m.up(-head_r * 0.12),
          z=-p["snout"] * 0.5 - head_r * 0.4, rx=1.5708)
    eyes(m, path, m.up(head_r * 0.2), -head_r * 0.68, head_r * 0.78,
         head_r * 0.22)
    crest(m, path, m.up(head_r * 0.6), head_r * 0.1, head_r * 0.7,
          (head_r * 0.3, m.up(head_r * 1.2), head_r * 0.26), 0.6)

    m.put("Tail", m.prism(m.deep, p["tail_r"] * 1.4, m.up(p["tail_r"] * 0.8),
                          p["tail"]),
          parent="Gait", y=m.up(-shell_r * 0.16), z=shell_r * 1.0, rx=-1.5708)

    plates(m, "Gait", [
        (-shell_r * 0.9, m.up(shell_r * 0.06), 0.0, 0.0),
        (shell_r * 0.9, m.up(shell_r * 0.06), 0.0, 0.0),
    ], (shell_r * 0.2, m.up(shell_r * 0.2), shell_r * 0.9))
    # Along the ridge of the shell rather than up a back, because this animal
    # has no back to speak of - it has a roof.
    spines(m, "Gait", 4, -shell_r * 0.34, shell_r * 0.24,
           m.up(shell_r * 0.26),
           (shell_r * 0.16, m.up(shell_r * 0.4), shell_r * 0.14),
           m.up(shell_r * 0.12))

    m.arms = []
    return hip + m.up(shell_h + shell_r * 0.28)


def build_machine(m, p):
    """A wheeled katapult: the Siege Engine, and the only BUILT thing that
    walks a maze.

    Two firsts, and both are deliberate rather than convenient.

    IT HAS NO LEGS AND IT IS NOT A FLYER. Every other ground creep in the
    roster stands on legs; this one rolls. The wheels are still handed to the
    walk component as hip pivots, because that component is what bobs and leans
    a body as it travels - but their SWING is turned off in the prefab, since a
    wheel that rocks fore and aft reads as broken rather than as rolling. What
    is left is a chassis that pitches slightly as it trundles, which is exactly
    what a wagon does.

    IT IS AN ATTACKER, so it carries the family's one tell: a LIT edge. Here it
    is the payload sitting in the throwing arm's bucket - the one place in the
    whole creep roster where the eye material is not an eye. The arm hangs off
    a `Swing` pivot, which is the node StrikeAnimation3D chops with, exactly as
    the Corrupted Treant's cleaver arm does.
    """
    m.rolls = True
    _machine_wheels(m, p)

    deck = p["deck_y"]
    m.pivot("Gait", ".", y=deck)
    width = p["chassis_w"]
    length = p["chassis_len"]
    m.put("Chassis", m.box(m.body, width, m.up(p["chassis_h"]), length),
          parent="Gait")
    m.put("Underside", m.box(m.deep, width * 0.92, m.up(p["chassis_h"] * 0.6),
                             length * 0.96),
          parent="Gait", y=m.up(-p["chassis_h"] * 0.7))
    # Side skirts in the deep tone, so the hull is panelled from above rather
    # than being one flat lid.
    for side, name in ((-1.0, "SkirtL"), (1.0, "SkirtR")):
        m.put(name, m.box(m.deep, width * 0.14, m.up(p["chassis_h"] * 1.3),
                          length * 0.86),
              parent="Gait", x=side * width * 0.48)

    # The plow at the front. It is what says which way a box is facing, and a
    # box with no facing is the failure this plan had to avoid.
    m.put("Plow", m.prism(m.trim, width * 1.05, m.up(p["plow"]),
                          length * 0.24),
          parent="Gait", y=m.up(-p["chassis_h"] * 0.3),
          z=-length * 0.56, rx=-1.5708)
    # View slits. A machine has no eyes, and the roster's rung ladder is read
    # off the eye material, so this is where it goes: two lit slots in the
    # front plate rather than two dots on a face.
    m.put("Hull", m.box(m.pale, width * 0.7, m.up(p["chassis_h"] * 1.1),
                        length * 0.18),
          parent="Gait", y=m.up(p["chassis_h"] * 0.6), z=-length * 0.36)
    eyes(m, "Gait", m.up(deck * 0.08 + p["chassis_h"] * 0.6),
         -length * 0.46, width * 0.34, width * 0.07)

    _machine_arm(m, p, width, length)

    plates(m, "Gait", [
        (-width * 0.52, m.up(p["chassis_h"] * 0.5), -length * 0.1, 0.0),
        (width * 0.52, m.up(p["chassis_h"] * 0.5), -length * 0.1, 0.0),
    ], (width * 0.16, m.up(p["chassis_h"] * 0.5), length * 0.4))
    spines(m, "Gait", 4, -length * 0.2, length * 0.14,
           m.up(p["chassis_h"] * 0.9),
           (width * 0.12, m.up(p["chassis_h"] * 0.8), width * 0.1),
           m.up(p["chassis_h"] * 0.3))

    return deck + m.up(p["chassis_h"] * 0.5) + p["arm_len"] * 0.9


def _machine_wheels(m, p):
    """Four wheels at the model root, offered to the walk component as legs.

    At the ROOT rather than under Gait for the same reason a leg is: the
    chassis pitches over wheels that stay on the floor, and a wheel hung off
    the pitching node would lift itself off the ground twice a stride.
    """
    radius = p["wheel_r"]
    span = p["wheel_span"]
    reach = p["wheel_reach"]
    tyre = m.cyl(m.deep, radius, radius, p["wheel_w"], 10, "z")
    hub = m.cyl(m.trim, radius * 0.34, radius * 0.34, p["wheel_w"] * 1.3,
                6, "z")
    corners = [("WheelFL", -1.0, -1.0), ("WheelFR", 1.0, -1.0),
               ("WheelBL", -1.0, 1.0), ("WheelBR", 1.0, 1.0)]
    for index, (name, side, front) in enumerate(corners):
        m.pivot(name, ".", x=side * span, y=m.up(radius),
                z=front * reach)
        m.put("Tyre", tyre, parent=name, rz=1.5708)
        m.put("Hub", hub, parent=name, rz=1.5708)
        m.legs.append(name)
        # Alternating, so the chassis rocks diagonally rather than nodding
        # straight up and down.
        m.phases.append(0.0 if index in (0, 3) else 0.5)


def _machine_arm(m, p, width, length):
    """The throwing arm, and the attacker family's lit edge.

    Everything above the trunnion hangs off `Swing`, which is the node
    StrikeAnimation3D turns. The trunnion itself stays outside it, so what
    swings is the arm and not the frame holding it.
    """
    arm = p["arm_len"]
    m.pivot("Frame", "Gait", y=m.up(p["chassis_h"] * 0.5), z=length * 0.12)
    for side, name in ((-1.0, "PostL"), (1.0, "PostR")):
        m.put(name, m.cyl(m.trim, p["arm_r"] * 0.5, p["arm_r"] * 0.7,
                          p["post"], 5),
              parent="Gait/Frame", x=side * width * 0.32, y=p["post"] * 0.5)

    m.pivot("Swing", "Gait/Frame", y=p["post"], rx=p["arm_tilt"])
    path = "Gait/Frame/Swing"
    m.put("Beam", m.cyl(m.body, p["arm_r"] * 0.6, p["arm_r"], arm, 5),
          parent=path, y=arm * 0.5)
    m.put("Brace", m.box(m.deep, p["arm_r"] * 1.6, arm * 0.5,
                         p["arm_r"] * 0.8),
          parent=path, y=arm * 0.34)
    # THE BUCKET, and the payload in it. The payload takes the eye material -
    # the attacker's one lit thing - so a Siege Engine is readable as coming
    # for your towers from the same glance that reads its shape.
    m.put("Bucket", m.cyl(m.trim, p["bucket"], p["bucket"] * 0.6,
                          m.up(p["bucket"] * 0.9), 7),
          parent=path, y=arm * 1.02)
    m.put("Payload", m.ball(m.glow, p["bucket"] * 0.72, 1.0, 7, 3),
          parent=path, y=arm * 1.02 + m.up(p["bucket"] * 0.5), shadow=False)
    m.arms.append(path)
    m.strike = path

def build_serpent(m, p):
    """A humanoid torso rising out of a coil, with a long tail behind it: the
    Naga Siren.

    The plan every other one would have had to LIE about, which is the bar a
    new builder has to clear. A naga has no legs at all, so the biped plan
    would have drawn a pair on a creature that does not have them; the wraith
    plan has no body under its hood; and the quadruped and shelled plans are
    animals lying down. What is actually there is a person from the waist up
    and a snake from the waist down.

    WHAT THE GAIT SWINGS IS THE TAIL. The segments are hip pivots as far as the
    walk component is concerned - the same wiring the Shade tatters and the
    Wyvern wings use - so a Naga travelling undulates instead of sliding. They
    sit at the MODEL ROOT rather than inside Gait for the same reason a leg
    does: a tail hung under the bobbing node would lift its own tip off the
    floor twice a cycle.

    From directly above, what says "not a person" is the COIL: a wide flat
    spiral where every other upright creep in the roster has two feet and a
    gap between them.
    """
    coil_r = p["coil"]
    coil_h = p["coil_h"]

    # The coil, drawn as three rings of falling radius rather than as one
    # cone. A cone from above is a disc and reads as a plinth; three rings
    # step, so the outline is ridged and reads as something wound up.
    for index in range(3):
        share = index / 2.0
        m.put("Coil%d" % (index + 1),
              m.torus(m.body, coil_r * (0.44 - 0.16 * share),
                      coil_r * (1.0 - 0.22 * share), 14, 5),
              parent=".", y=coil_h * (0.16 + 0.34 * index))
    m.put("Belly", m.cyl(m.deep, coil_r * 0.5, coil_r * 0.86,
                         coil_h * 0.9, 9),
          parent=".", y=coil_h * 0.45)

    m.pivot("Gait", ".", y=coil_h)
    torso = p["torso"]
    m.pivot("Torso", "Gait", rx=p["stoop"])
    m.put("Waist", m.ball(m.deep, p["waist"], 0.86, 6, 3), parent="Gait")
    m.put("Chest", m.capsule(m.body, p["chest_r"], torso, 7, 3),
          parent="Gait/Torso", y=torso * 0.42)
    m.put("Scales", m.torus(m.trim, p["waist"] * 0.9, p["waist"] * 1.25,
                            12, 4),
          parent="Gait", y=m.up(p["waist"] * 0.15))

    shoulder = p["shoulder"]
    shoulder_y = torso * 0.8
    m.put("Shoulders", m.box(m.pale, shoulder * 1.5,
                             m.up(p["chest_r"] * 0.62), p["chest_r"] * 0.95),
          parent="Gait/Torso", y=shoulder_y)

    # The head, with a fan of fins behind it. The fins are what a player sees
    # from above and they are deliberately BEHIND the eyes rather than over
    # them, which is the trap PLACEHOLDER_ART records: whatever is at the
    # front of a model is read as its face.
    head_r = p["head_r"]
    m.pivot("Head", "Gait/Torso", y=shoulder_y + p["neck"] + m.up(head_r * 0.5))
    path = "Gait/Torso/Head"
    m.put("Neck", m.cyl(m.deep, head_r * 0.4, head_r * 0.5, p["neck"], 5),
          parent="Gait/Torso", y=shoulder_y + p["neck"] * 0.5)
    m.put("Skull", m.ball(m.pale, head_r, 1.0, 6, 3), parent=path)
    m.put("Jaw", m.box(m.deep, head_r * 0.8, m.up(head_r * 0.3),
                       head_r * 0.9),
          parent=path, y=m.up(-head_r * 0.55), z=-head_r * 0.2)
    fin = m.prism(m.trim, p["fin"] * 0.3, m.up(p["fin"]), p["fin"] * 0.26)
    for index in range(3):
        share = index - 1.0
        m.put("Fin%d" % (index + 1), fin, parent=path,
              x=share * head_r * 0.62, y=m.up(head_r * 0.6),
              z=head_r * 0.5, rz=share * 0.5, rx=0.55)
    eyes(m, path, m.up(head_r * 0.06), -head_r * 0.82, head_r * 0.58,
         head_r * 0.2)

    _serpent_arms(m, p, shoulder, shoulder_y)
    _serpent_tail(m, p, coil_r, coil_h)

    plates(m, "Gait/Torso", [
        (-shoulder * 0.84, shoulder_y + m.up(p["chest_r"] * 0.2), 0.0, 0.0),
        (shoulder * 0.84, shoulder_y + m.up(p["chest_r"] * 0.2), 0.0, 0.0),
    ], (p["chest_r"] * 0.4, m.up(p["chest_r"] * 0.32), p["chest_r"] * 0.95))
    spines(m, "Gait/Torso", 4, p["chest_r"] * 0.88, -p["chest_r"] * 0.04,
           torso * 0.5, (p["chest_r"] * 0.28, m.up(p["chest_r"] * 0.8),
                         p["chest_r"] * 0.26), m.up(p["chest_r"] * 0.32))
    crest(m, path, m.up(head_r * 0.74), head_r * 0.1, head_r * 0.7,
          (head_r * 0.34, m.up(head_r * 1.4), head_r * 0.28), 0.55)

    return coil_h + torso + p["neck"] + m.up(head_r * 1.8)


def _serpent_arms(m, p, shoulder, shoulder_y):
    """Two arms held out and forward, ending in webbed hands.

    Empty on purpose. Nothing in this plan carries a weapon: a Naga Siren
    heals its pack and is not an attacker, so anything in its hands would be
    the ATTACKER family's tell being lent to a creep that never earns it.
    """
    arm = p["arm"]
    for side, name in ((-1.0, "ArmL"), (1.0, "ArmR")):
        path = "Gait/Torso/" + name
        m.pivot(name, "Gait/Torso", x=side * shoulder, y=shoulder_y,
                rz=side * p["arm_flare"], rx=-0.3)
        m.put("Upper", m.capsule(m.body, p["arm_r"], arm * 0.55, 5, 2),
              parent=path, y=-arm * 0.28)
        m.put("Fore", m.capsule(m.pale, p["arm_r"] * 0.86, arm * 0.5, 5, 2),
              parent=path, y=-arm * 0.8)
        m.put("Hand", m.box(m.pale, p["arm_r"] * 1.9, m.up(p["arm_r"] * 0.5),
                            p["arm_r"] * 1.5),
              parent=path, y=-arm * 1.08)
        m.arms.append(path)


def _serpent_tail(m, p, coil_r, coil_h):
    """The tail, laid back behind the coil in falling segments.

    Registered as LEGS, which is what makes it move: the walk component swings
    a leg fore and aft about its hip, and a chain of those with stepped phases
    reads as an undulation travelling down the tail. The Shade tatters and the
    Wyvern wings are wired the same way and for the same reason - a plan with
    no legs still has to look like it is going somewhere.
    """
    count = p["tail_segments"]
    length = p["tail"] / float(count)
    for index in range(count):
        share = index / float(count)
        name = "Tail%d" % (index + 1)
        m.pivot(name, ".", y=coil_h * (0.28 - 0.16 * share),
                z=coil_r * 0.7 + p["tail"] * share)
        m.put("Segment",
              m.cyl(m.body, p["tail_r"] * (0.8 - 0.7 * share),
                    p["tail_r"] * (1.0 - 0.7 * share), length, 6, "z"),
              parent=name, z=length * 0.5, rx=1.5708)
        m.legs.append(name)
        m.phases.append(share)
    m.put("TailFin", m.prism(m.trim, p["tail_r"] * 2.2,
                             m.up(p["tail_r"] * 2.4), p["tail_r"] * 1.2),
          parent="Tail%d" % count, z=length * 1.1, rx=-1.5708)


PLANS = {
    cr.QUADRUPED: build_quadruped,
    cr.BIPED: build_biped,
    cr.ARACHNID: build_arachnid,
    cr.GOLEM: build_golem,
    cr.WRAITH: build_wraith,
    cr.TREANT: build_treant,
    cr.BRUTE: build_brute,
    cr.WINGED: build_winged,
    cr.SHELLED: build_shelled,
    cr.MACHINE: build_machine,
    cr.SERPENT: build_serpent,
}


# ---------------------------------------------------------------------------
# THE SHAPES
# ---------------------------------------------------------------------------
#
# One entry per creep, in authored units. This is where a Sheep stops being a
# Timber Wolf: same plan, same primitives, and every number that changes the
# OUTLINE pulled the other way.
#
# `select` is the creep's authored half-width, which the prefab turns into its
# click box. It is a VISUAL number and has nothing to do with
# CreepStats.body_radius, which is the footprint the simulation walks it on -
# a Boss is a bigger model on the same footprint, per the rules.

SHAPES = {
    # --- quadrupeds
    "sheep": {
        "hip_y": 0.37, "leg_span": 0.155, "leg_reach": 0.20, "digit": "hoof",
        "thigh_r": 0.042, "shin_r": 0.032, "thigh_share": 0.5,
        "body_r": 0.24, "body_len": 0.52, "chest": 0.68, "chest_rise": 0.0,
        "fleece": True, "hump": False,
        "neck": 0.22, "neck_y": 0.02, "neck_z": 0.5, "neck_tilt": -1.2,
        "head_tilt": 0.9, "head_r": 0.115, "snout": 0.10, "ear": 1.1,
        "tail": 0.09, "tail_r": 0.042, "tail_tilt": -0.5,
        "select": 0.34,
    },
    "timber_wolf": {
        "hip_y": 0.42, "leg_span": 0.135, "leg_reach": 0.225, "digit": "claw",
        "thigh_r": 0.036, "shin_r": 0.028, "thigh_share": 0.55,
        "body_r": 0.165, "body_len": 0.60, "chest": 0.88, "chest_rise": 0.03,
        "fleece": False, "hump": True,
        "neck": 0.19, "neck_y": 0.03, "neck_z": 0.52, "neck_tilt": -0.85,
        "head_tilt": 0.55, "head_r": 0.115, "snout": 0.17, "ear": 1.7,
        "tail": 0.28, "tail_r": 0.065, "tail_tilt": -1.15,
        "select": 0.32,
    },
    # --- bipeds
    "skeleton_warrior": {
        "hip_y": 0.43, "stance": 0.075, "digit": "boot",
        "thigh_r": 0.030, "shin_r": 0.024,
        "waist": 0.075, "torso": 0.26, "chest_r": 0.105, "stoop": 0.10,
        "robe": 0.0, "belt": True, "cloak": 0.0, "ribs": True,
        "shoulder": 0.115, "neck": 0.035, "head_r": 0.085, "head": "skull",
        "tusks": False,
        "arm": 0.135, "arm_r": 0.028, "arm_flare": 0.18,
        "weapon": "sword", "weapon_len": 0.24, "shield": 0.0,
        "select": 0.24,
    },
    "acolyte": {
        "hip_y": 0.38, "stance": 0.055, "digit": "boot",
        "thigh_r": 0.030, "shin_r": 0.024, "thigh_share": 0.55,
        "waist": 0.095, "torso": 0.28, "chest_r": 0.115, "stoop": 0.16,
        "robe": 0.195, "belt": True, "cloak": 0.55,
        "shoulder": 0.115, "neck": 0.02, "head_r": 0.095, "head": "hood",
        "tusks": False,
        "arm": 0.125, "arm_r": 0.026, "arm_flare": 0.10,
        "weapon": "staff", "weapon_len": 0.30, "shield": 0.0,
        "select": 0.26,
    },
    "swordsman": {
        "hip_y": 0.44, "stance": 0.085, "digit": "boot",
        "thigh_r": 0.036, "shin_r": 0.030,
        "waist": 0.095, "torso": 0.28, "chest_r": 0.130, "stoop": 0.08,
        "robe": 0.0, "belt": True, "cloak": 0.62,
        "shoulder": 0.140, "neck": 0.03, "head_r": 0.090, "head": "helm",
        "tusks": False,
        "arm": 0.145, "arm_r": 0.032, "arm_flare": 0.22,
        "weapon": "sword", "weapon_len": 0.27, "shield": 0.098,
        "select": 0.28,
    },
    "fel_orc_grunt": {
        "hip_y": 0.40, "stance": 0.105, "digit": "claw",
        "thigh_r": 0.048, "shin_r": 0.040, "thigh_share": 0.5,
        "waist": 0.115, "torso": 0.27, "chest_r": 0.155, "stoop": 0.34,
        "robe": 0.0, "belt": True, "cloak": 0.0,
        "shoulder": 0.165, "neck": 0.015, "head_r": 0.100, "head": "bare",
        "tusks": True,
        "arm": 0.165, "arm_r": 0.042, "arm_flare": 0.34,
        "weapon": "axe", "weapon_len": 0.28, "shield": 0.0,
        "select": 0.30,
    },
    "vile_temptress": {
        "hip_y": 0.50, "stance": 0.055, "digit": "boot",
        "thigh_r": 0.028, "shin_r": 0.022, "thigh_share": 0.52,
        "waist": 0.070, "torso": 0.28, "chest_r": 0.095, "stoop": 0.06,
        "robe": 0.0, "belt": True, "cloak": 0.70,
        "shoulder": 0.105, "neck": 0.045, "head_r": 0.080, "head": "bare",
        "tusks": False,
        "arm": 0.150, "arm_r": 0.024, "arm_flare": 0.30,
        "weapon": "whip", "weapon_len": 0.34, "shield": 0.0,
        "select": 0.24,
    },
    "priest": {
        "hip_y": 0.42, "stance": 0.060, "digit": "boot",
        "thigh_r": 0.030, "shin_r": 0.024, "thigh_share": 0.55,
        "waist": 0.105, "torso": 0.31, "chest_r": 0.130, "stoop": 0.0,
        "robe": 0.215, "belt": True, "cloak": 0.68,
        "shoulder": 0.135, "neck": 0.035, "head_r": 0.095, "head": "hood",
        "tusks": False,
        "arm": 0.140, "arm_r": 0.030, "arm_flare": 0.12,
        "weapon": "staff", "weapon_len": 0.38, "shield": 0.0,
        "select": 0.28,
    },
    # --- arachnid
    "forest_spider": {
        "hip_y": 0.30, "leg_span": 0.115, "leg_first": -0.13,
        "leg_step": 0.095, "leg_r": 0.028,
        "femur": 0.235, "femur_angle": 0.95, "tibia_angle": 2.72,
        "abdomen": 0.205, "abdomen_z": 0.215, "thorax": 0.130,
        "select": 0.36,
    },
    # --- golems
    "mud_golem": {
        "hip_y": 0.35, "stance": 0.125,
        "thigh_r": 0.066, "shin_r": 0.058, "thigh_share": 0.5,
        "chest_w": 0.310, "chest_h": 0.330, "chest_d": 0.220,
        "head_r": 0.092, "head_sink": 1.06, "ribs": False,
        "arm": 0.330, "arm_r": 0.060,
        "select": 0.32,
    },
    "rot_golem": {
        "hip_y": 0.42, "stance": 0.150,
        "thigh_r": 0.078, "shin_r": 0.068, "thigh_share": 0.5,
        "chest_w": 0.365, "chest_h": 0.410, "chest_d": 0.260,
        "head_r": 0.108, "head_sink": 1.0, "ribs": True,
        "arm": 0.430, "arm_r": 0.074,
        "select": 0.34,
    },
    # --- wraith
    "shade": {
        "fly_height": cr.FLY_HEIGHT, "shadow": 0.22, "hover": 0.55,
        "body": 0.40, "waist": 0.145, "shoulder": 0.175,
        "head_r": 0.105, "arm": 0.185, "arm_r": 0.032,
        "tatters": 4, "tatter_len": 0.22,
        "select": 0.28,
    },
    # --- treant
    "corrupted_treant": {
        "hip_y": 0.34, "stance": 0.120,
        "thigh_r": 0.064, "shin_r": 0.056, "thigh_share": 0.5,
        "trunk": 0.52, "trunk_r": 0.155, "trunk_top": 0.105,
        "head_r": 0.105, "canopy": 0.185,
        "arm": 0.300, "arm_r": 0.050, "cleaver": 0.150,
        "select": 0.32,
    },
    # --- brute
    #
    # Authored a little above the Rot Golem and no more, which is the whole of
    # style.CREEP_MAX_HEIGHT in practice: the ceiling belongs to a top tier
    # Boss, this is a tier 3 creep, and between one tier and the next the size
    # difference is meant to be MINOR. The first pass had it a third larger
    # than the Rot Golem in every direction and it read as a different game.
    # What says this is a 225,000 gold creep is its carapace, its eyes and its
    # shape, never its size. Its FOOTPRINT does not move either, see
    # CreepStats.body_radius.
    "ancient_wendigo": {
        "hip_y": 0.400, "stance": 0.140,
        "thigh_r": 0.078, "shin_r": 0.068, "thigh_share": 0.48,
        "waist": 0.164, "hunch": -0.34,
        "barrel": 0.440, "chest_r": 0.220,
        "shoulder": 0.264, "shoulder_r": 0.116,
        "pelt": 0.072, "pelt_count": 5,
        "head_r": 0.128, "head_tilt": 0.24, "muzzle": 0.108,
        "arm": 0.480, "arm_r": 0.078, "arm_flare": 0.42,
        "select": 0.400,
    },
    # ------------------------------------------------------------------
    # TIER 2. The bracket climbs the SAME ladder tier 1 stands on, so what
    # separates a 100,000g Boss from a 10g Sheep here is its carapace, its
    # eyes and its added plates, spines and crest - never a size. Every entry
    # below is authored inside style.CREEP_MAX_HEIGHT with room to spare, and
    # the roster's headroom stays reserved for tier 4.
    # ------------------------------------------------------------------
    #
    # Five of the twelve are bipeds, which is the plan most at risk of turning
    # a bracket into one silhouette at five sizes. Every one of them is pulled
    # apart on the four things build_biped says change the OUTLINE - stoop,
    # robe, head and weapon - and no two share a pair of them.
    "knight": {
        "hip_y": 0.46, "stance": 0.090, "digit": "boot",
        "thigh_r": 0.040, "shin_r": 0.034,
        "waist": 0.100, "torso": 0.29, "chest_r": 0.140, "stoop": 0.04,
        "robe": 0.0, "belt": True, "cloak": 0.72,
        "shoulder": 0.150, "neck": 0.025, "head_r": 0.092, "head": "helm",
        "tusks": False,
        "arm": 0.150, "arm_r": 0.034, "arm_flare": 0.20,
        "weapon": "sword", "weapon_len": 0.30, "shield": 0.115,
        "select": 0.30,
    },
    # Upright, hooded and EMPTY HANDED, which no other biped in the roster is.
    # A spirit that carries nothing is the loudest way this plan can say
    # "not a soldier" while standing next to the Knight it unlocks after.
    "vengeful_spirit": {
        "hip_y": 0.48, "stance": 0.050, "digit": "boot",
        "thigh_r": 0.026, "shin_r": 0.021, "thigh_share": 0.55,
        "waist": 0.076, "torso": 0.30, "chest_r": 0.098, "stoop": -0.06,
        "robe": 0.190, "belt": False, "cloak": 0.80,
        "shoulder": 0.112, "neck": 0.0, "head_r": 0.094, "head": "hood",
        "tusks": False,
        "arm": 0.165, "arm_r": 0.024, "arm_flare": 0.42,
        "weapon": "", "weapon_len": 0.0, "shield": 0.0,
        "select": 0.28,
    },
    # Long limbed and stooped hard over a low waist: the lanky answer to the
    # Fel Orc's crouched one, and the only creep in the roster whose arms are
    # longer than its legs.
    "forest_troll": {
        "hip_y": 0.40, "stance": 0.100, "digit": "claw",
        "thigh_r": 0.040, "shin_r": 0.033, "thigh_share": 0.48,
        "waist": 0.104, "torso": 0.25, "chest_r": 0.140, "stoop": 0.42,
        "robe": 0.0, "belt": True, "cloak": 0.0,
        "shoulder": 0.150, "neck": 0.010, "head_r": 0.096, "head": "bare",
        "tusks": True,
        "arm": 0.210, "arm_r": 0.036, "arm_flare": 0.30,
        "weapon": "axe", "weapon_len": 0.26, "shield": 0.0,
        "select": 0.32,
    },
    # Clawed, hunched and carrying NOTHING but its own hands, with a skull for
    # a head. The one biped whose silhouette is all shoulders.
    "voidwalker": {
        "hip_y": 0.42, "stance": 0.080, "digit": "claw",
        "thigh_r": 0.038, "shin_r": 0.031, "thigh_share": 0.52,
        "waist": 0.108, "torso": 0.27, "chest_r": 0.150, "stoop": 0.26,
        "robe": 0.0, "belt": False, "cloak": 0.0, "ribs": True,
        "shoulder": 0.168, "neck": 0.020, "head_r": 0.090, "head": "skull",
        "tusks": False,
        "arm": 0.185, "arm_r": 0.040, "arm_flare": 0.36,
        "weapon": "", "weapon_len": 0.0, "shield": 0.0,
        "select": 0.32,
    },
    # Tall, armoured and upright, with the longest blade in the roster. It
    # stands where the Knight crouches and carries what the Knight carries, so
    # the two are separated by PROPORTION rather than by parts.
    "dragonspawn": {
        "hip_y": 0.50, "stance": 0.085, "digit": "claw",
        "thigh_r": 0.042, "shin_r": 0.035, "thigh_share": 0.50,
        "waist": 0.098, "torso": 0.30, "chest_r": 0.138, "stoop": 0.10,
        "robe": 0.0, "belt": True, "cloak": 0.0,
        "shoulder": 0.152, "neck": 0.045, "head_r": 0.088, "head": "helm",
        "tusks": False,
        "arm": 0.160, "arm_r": 0.032, "arm_flare": 0.24,
        "weapon": "sword", "weapon_len": 0.36, "shield": 0.0,
        "select": 0.30,
    },
    # Small, robed and hooded, leaning on a staff. Deliberately the SMALLEST
    # thing in the bracket while being one of its most expensive: the ladder
    # says how strong a creep is with its carapace and its eyes, and this is
    # the entry that proves size is not saying it.
    "kobold_geomancer": {
        "hip_y": 0.34, "stance": 0.050, "digit": "claw",
        "thigh_r": 0.028, "shin_r": 0.023, "thigh_share": 0.55,
        "waist": 0.086, "torso": 0.24, "chest_r": 0.108, "stoop": 0.20,
        "robe": 0.175, "belt": True, "cloak": 0.0,
        "shoulder": 0.110, "neck": 0.015, "head_r": 0.090, "head": "hood",
        "tusks": False,
        "arm": 0.125, "arm_r": 0.026, "arm_flare": 0.14,
        "weapon": "staff", "weapon_len": 0.36, "shield": 0.0,
        "select": 0.26,
    },
    # --- brute, the second one. Wider and lower than the Wendigo, with a
    # muzzle long enough to read as tentacles at this size and no pelt at all.
    "faceless_one": {
        "hip_y": 0.380, "stance": 0.130,
        "thigh_r": 0.070, "shin_r": 0.060, "thigh_share": 0.50,
        "waist": 0.156, "hunch": -0.44,
        "barrel": 0.400, "chest_r": 0.212,
        "shoulder": 0.256, "shoulder_r": 0.108,
        "pelt": 0.050, "pelt_count": 3,
        "head_r": 0.112, "head_tilt": 0.30, "muzzle": 0.150,
        "arm": 0.470, "arm_r": 0.072, "arm_flare": 0.46,
        "select": 0.380,
    },
    # --- golem, and the bracket's Boss. It takes the Boss ramps on top of its
    # own rung, so it is the biggest thing on the field - by a fraction, which
    # is all the size ceiling allows anything to be.
    "infernal": {
        "hip_y": 0.400, "stance": 0.155,
        "thigh_r": 0.080, "shin_r": 0.070, "thigh_share": 0.5,
        "chest_w": 0.375, "chest_h": 0.375, "chest_d": 0.270,
        "head_r": 0.100, "head_sink": 0.96, "ribs": True,
        "arm": 0.450, "arm_r": 0.078,
        "select": 0.36,
    },
    # --- wraith, the second one. Longer, thinner and more frayed than the
    # Shade: a Banshee is the same vapour drawn out.
    "banshee": {
        "fly_height": cr.FLY_HEIGHT, "shadow": 0.24, "hover": 0.72,
        "body": 0.46, "waist": 0.132, "shoulder": 0.166,
        "head_r": 0.100, "arm": 0.205, "arm_r": 0.028,
        "tatters": 6, "tatter_len": 0.28,
        "select": 0.28,
    },
    # --- winged. The span IS the silhouette, so it is the widest thing in the
    # roster and comes closest to style.CREEP_MAX_RADIUS - which is correct: a
    # flyer is read off its wings and nothing else from directly above.
    "wyvern": {
        "fly_height": cr.FLY_HEIGHT, "shadow": 0.30, "hover": 0.85,
        "body_r": 0.130, "body_len": 0.46, "chest": 1.15,
        "neck": 0.150, "neck_tilt": -0.55, "head_tilt": 0.35,
        "head_r": 0.096, "snout": 0.130,
        "wing_span": 0.400, "wing_chord": 0.230, "wing_r": 0.032,
        "wing_droop": 0.18,
        "tail": 0.300, "tail_r": 0.056, "tail_tilt": 0.30,
        "select": 0.46,
    },
    # --- shelled. Low and broad, and the only ROOFED creep in the game.
    "sea_turtle": {
        "hip_y": 0.20, "leg_span": 0.185, "leg_reach": 0.170, "digit": "claw",
        "thigh_r": 0.048, "shin_r": 0.042, "thigh_share": 0.5,
        "shell_r": 0.310, "shell_h": 0.185,
        "neck": 0.115, "neck_tilt": -0.35, "head_r": 0.086, "snout": 0.075,
        "tail": 0.110, "tail_r": 0.050,
        "select": 0.36,
    },
    # --- machine. Wheels rather than legs, and the roster's second attacker,
    # so its payload is the lit thing rather than an eye.
    "siege_engine": {
        "wheel_r": 0.115, "wheel_w": 0.062, "wheel_span": 0.165,
        "wheel_reach": 0.185,
        "deck_y": 0.255, "chassis_w": 0.290, "chassis_h": 0.130,
        "chassis_len": 0.430, "plow": 0.145,
        "post": 0.105, "arm_len": 0.310, "arm_r": 0.042, "arm_tilt": 0.85,
        "bucket": 0.080,
        "select": 0.38,
    },
    # ------------------------------------------------------------------
    # TIER 3. Every one of these stands on the ladder's top few rungs, so the
    # carapace and the eyes say almost the same thing about all twelve - which
    # means the SHAPE is doing nearly all of the work here, more than in any
    # bracket below. The size ramps say nothing at all: see
    # style.CREEP_SIZE_RUNG_CAP, which stops climbing at rung 5 on purpose.
    # ------------------------------------------------------------------
    #
    # Tall, gaunt and hooded-less: a skull over a long cloak, holding a scythe
    # laid across its own shoulder. The scythe IS the silhouette - it is the
    # only weapon in the plan that reaches sideways at head height.
    "death_revenant": {
        "hip_y": 0.50, "stance": 0.058, "digit": "boot",
        "thigh_r": 0.026, "shin_r": 0.021, "thigh_share": 0.56,
        "waist": 0.078, "torso": 0.30, "chest_r": 0.104, "stoop": -0.04,
        "robe": 0.175, "belt": True, "cloak": 0.86, "ribs": True,
        "shoulder": 0.120, "neck": 0.030, "head_r": 0.086, "head": "skull",
        "tusks": False,
        "arm": 0.160, "arm_r": 0.026, "arm_flare": 0.26,
        "weapon": "scythe", "weapon_len": 0.34, "shield": 0.0,
        "select": 0.30,
    },
    # Low, wide-stanced and horned, with an axe held out. The one biped whose
    # head reaches in FRONT of its own face, which is what the horned head was
    # added for.
    "satyr_shadowdancer": {
        "hip_y": 0.42, "stance": 0.098, "digit": "claw",
        "thigh_r": 0.036, "shin_r": 0.029, "thigh_share": 0.46,
        "waist": 0.092, "torso": 0.25, "chest_r": 0.126, "stoop": 0.30,
        "robe": 0.0, "belt": True, "cloak": 0.0,
        "shoulder": 0.138, "neck": 0.018, "head_r": 0.092, "head": "horned",
        "tusks": False,
        "arm": 0.170, "arm_r": 0.032, "arm_flare": 0.38,
        "weapon": "axe", "weapon_len": 0.24, "shield": 0.0,
        "select": 0.30,
    },
    # The second arachnid, and it has to be told apart from the first from
    # directly above: taller hips, a longer abdomen carried further back, and
    # legs that reach much further. A Forest Spider crouches, this one stands.
    "crypt_fiend": {
        "hip_y": 0.38, "leg_span": 0.130, "leg_first": -0.15,
        "leg_step": 0.105, "leg_r": 0.030,
        "femur": 0.270, "femur_angle": 1.05, "tibia_angle": 2.60,
        "abdomen": 0.215, "abdomen_z": 0.250, "thorax": 0.140,
        "select": 0.40,
    },
    # Hooded, robed and stooped over a staff. The Kobold Geomancer's shape at
    # nearly twice the size with a rib cage showing, which is deliberate: the
    # cheapest caster in the game and the most expensive one should read as the
    # same idea grown up.
    "necromancer": {
        "hip_y": 0.44, "stance": 0.058, "digit": "boot",
        "thigh_r": 0.028, "shin_r": 0.023, "thigh_share": 0.55,
        "waist": 0.096, "torso": 0.29, "chest_r": 0.116, "stoop": 0.18,
        "robe": 0.205, "belt": True, "cloak": 0.74, "ribs": True,
        "shoulder": 0.126, "neck": 0.014, "head_r": 0.094, "head": "hood",
        "tusks": False,
        "arm": 0.140, "arm_r": 0.027, "arm_flare": 0.14,
        "weapon": "staff", "weapon_len": 0.40, "shield": 0.0,
        "select": 0.28,
    },
    # Upright, masked and empty handed. Drawn as VAPOUR, which is the whole
    # point of it and which no other ground creep in the game is - see
    # creep_roster.VAPOUR_KEYS. Its outline is deliberately simple, because on
    # a translucent creep the RIM is what a player actually sees and a busy
    # silhouette turns into noise.
    "spirit_walker": {
        "hip_y": 0.46, "stance": 0.062, "digit": "boot",
        "thigh_r": 0.028, "shin_r": 0.022, "thigh_share": 0.56,
        "waist": 0.086, "torso": 0.30, "chest_r": 0.112, "stoop": -0.08,
        "robe": 0.200, "belt": False, "cloak": 0.66,
        "shoulder": 0.126, "neck": 0.040, "head_r": 0.090, "head": "mask",
        "tusks": False,
        "arm": 0.155, "arm_r": 0.026, "arm_flare": 0.34,
        "weapon": "", "weapon_len": 0.0, "shield": 0.0,
        "select": 0.28,
    },
    # Masked, belted and carrying a short heavy staff, standing squarely. The
    # other masked creep in the bracket is a robed column; this one has legs,
    # shoulders and a stance, so the mask is the only thing they share.
    "shaman": {
        "hip_y": 0.40, "stance": 0.092, "digit": "claw",
        "thigh_r": 0.034, "shin_r": 0.028, "thigh_share": 0.50,
        "waist": 0.100, "torso": 0.26, "chest_r": 0.134, "stoop": 0.14,
        "robe": 0.0, "belt": True, "cloak": 0.58,
        "shoulder": 0.142, "neck": 0.026, "head_r": 0.088, "head": "mask",
        "tusks": False,
        "arm": 0.150, "arm_r": 0.030, "arm_flare": 0.20,
        "weapon": "staff", "weapon_len": 0.30, "shield": 0.0,
        "select": 0.30,
    },
    # The third brute, and the widest. Almost no pelt, a huge gut and arms
    # longer than anything else in the roster: where the Wendigo is a hunched
    # back of fur, this is a bare slab of meat that reaches.
    "abomination": {
        "hip_y": 0.370, "stance": 0.150,
        "thigh_r": 0.082, "shin_r": 0.070, "thigh_share": 0.48,
        "waist": 0.176, "hunch": -0.30,
        "barrel": 0.420, "chest_r": 0.238,
        "shoulder": 0.268, "shoulder_r": 0.104,
        "pelt": 0.036, "pelt_count": 3,
        "head_r": 0.108, "head_tilt": 0.34, "muzzle": 0.086,
        "arm": 0.510, "arm_r": 0.082, "arm_flare": 0.50,
        "select": 0.400,
    },
    # A flyer built for BREADTH rather than length: the widest wings in the
    # game on a short body, which is what separates a bird from the Wyvern's
    # long-tailed reptile at a glance from directly above.
    "gryphon_rider": {
        "fly_height": cr.FLY_HEIGHT, "shadow": 0.30, "hover": 0.95,
        "body_r": 0.118, "body_len": 0.38, "chest": 1.22,
        "neck": 0.115, "neck_tilt": -0.35, "head_tilt": 0.30,
        "head_r": 0.090, "snout": 0.105,
        "wing_span": 0.440, "wing_chord": 0.250, "wing_r": 0.030,
        "wing_droop": 0.12,
        "tail": 0.185, "tail_r": 0.062, "tail_tilt": 0.18,
        "select": 0.48,
    },
    # The fourth brute. Squat and top heavy, standing nearly upright with a
    # shoulder span far wider than its hips - the ogre proportion, and the
    # opposite of the Abomination's forward lean.
    "ogre_magi": {
        "hip_y": 0.330, "stance": 0.155,
        "thigh_r": 0.086, "shin_r": 0.074, "thigh_share": 0.46,
        "waist": 0.180, "hunch": -0.12,
        "barrel": 0.400, "chest_r": 0.234,
        "shoulder": 0.290, "shoulder_r": 0.124,
        "pelt": 0.048, "pelt_count": 4,
        "head_r": 0.120, "head_tilt": 0.16, "muzzle": 0.092,
        "arm": 0.440, "arm_r": 0.084, "arm_flare": 0.44,
        "select": 0.420,
    },
    # Armoured, helmed and shielded: the bracket's only soldier, and it is the
    # Knight's shape three tiers on. Tall where the Knight crouches, with a
    # longer blade and a heavier shield.
    "chaos_wardens": {
        "hip_y": 0.48, "stance": 0.094, "digit": "boot",
        "thigh_r": 0.042, "shin_r": 0.035, "thigh_share": 0.50,
        "waist": 0.104, "torso": 0.30, "chest_r": 0.146, "stoop": 0.06,
        "robe": 0.0, "belt": True, "cloak": 0.78,
        "shoulder": 0.156, "neck": 0.022, "head_r": 0.094, "head": "helm",
        "tusks": False,
        "arm": 0.155, "arm_r": 0.036, "arm_flare": 0.22,
        "weapon": "sword", "weapon_len": 0.33, "shield": 0.128,
        "select": 0.32,
    },
    # The bracket's Boss, on the golem plan and taking the Boss ramps on top of
    # its own rung. Deeper and heavier than the Infernal, with the head sunk
    # right down between its shoulders - a Behemoth should read as having no
    # neck at all.
    "behemoth": {
        "hip_y": 0.400, "stance": 0.170,
        "thigh_r": 0.086, "shin_r": 0.074, "thigh_share": 0.5,
        "chest_w": 0.400, "chest_h": 0.390, "chest_d": 0.290,
        "head_r": 0.104, "head_sink": 1.14, "ribs": True,
        "arm": 0.470, "arm_r": 0.082,
        "select": 0.360,
    },
    # ------------------------------------------------------------------
    # TIER 4 - SUDDEN DEATH. Eleven creeps that arrive in the same second and
    # are only ever seen beside each other, so this bracket is spread across
    # more body plans than any other: four flyers, three heavyweights, a
    # machine, a serpent, a beast and two small ones.
    # ------------------------------------------------------------------
    #
    # Small, light and empty handed but for a purse. The only creep in the
    # roster nobody defends against, so it is authored to be SPOTTED: short,
    # bright and with nothing else in the bracket its size.
    "treasure_goblin": {
        "hip_y": 0.30, "stance": 0.052, "digit": "boot",
        "thigh_r": 0.026, "shin_r": 0.021, "thigh_share": 0.55,
        "waist": 0.082, "torso": 0.21, "chest_r": 0.104, "stoop": 0.24,
        "robe": 0.0, "belt": True, "cloak": 0.44,
        "shoulder": 0.104, "neck": 0.014, "head_r": 0.084, "head": "bare",
        "tusks": True,
        "arm": 0.120, "arm_r": 0.024, "arm_flare": 0.16,
        "weapon": "", "weapon_len": 0.0, "shield": 0.0,
        "select": 0.24,
    },
    # Long legged, lightly built and carrying a spear held upright. The only
    # creep in the game with that weapon, and the only tier 4 biped with a
    # weapon at all.
    "huntress": {
        "hip_y": 0.52, "stance": 0.062, "digit": "boot",
        "thigh_r": 0.028, "shin_r": 0.022, "thigh_share": 0.54,
        "waist": 0.076, "torso": 0.27, "chest_r": 0.100, "stoop": 0.04,
        "robe": 0.0, "belt": True, "cloak": 0.60,
        "shoulder": 0.112, "neck": 0.042, "head_r": 0.082, "head": "bare",
        "tusks": False,
        "arm": 0.150, "arm_r": 0.025, "arm_flare": 0.24,
        "weapon": "spear", "weapon_len": 0.44, "shield": 0.0,
        "select": 0.26,
    },
    # A golem with almost no legs and an enormous chest: the Obsidian Statue is
    # the squattest thing in the game, which is what a slab of rock that
    # weakens whatever it drifts past should be. It is a Boss, so it takes the
    # Boss ramps as well.
    "obsidian_statue": {
        "hip_y": 0.230, "stance": 0.160,
        "thigh_r": 0.092, "shin_r": 0.084, "thigh_share": 0.5,
        "chest_w": 0.410, "chest_h": 0.430, "chest_d": 0.270,
        "head_r": 0.096, "head_sink": 1.20, "ribs": False,
        "arm": 0.360, "arm_r": 0.076,
        "select": 0.360,
    },
    # The bracket's brute, and the roster's third ATTACKER - so it is the third
    # creep in the game allowed a lit edge, on the slab in its right fist. Wide
    # shoulders, a short pelt of moss and the longest reach of the three.
    "mountain_giant": {
        "hip_y": 0.390, "stance": 0.158,
        "thigh_r": 0.088, "shin_r": 0.076, "thigh_share": 0.48,
        "waist": 0.178, "hunch": -0.26,
        "barrel": 0.415, "chest_r": 0.232,
        "shoulder": 0.278, "shoulder_r": 0.116,
        "pelt": 0.042, "pelt_count": 4,
        "head_r": 0.110, "head_tilt": 0.22, "muzzle": 0.078,
        "arm": 0.490, "arm_r": 0.086, "arm_flare": 0.40,
        "club": 0.190,
        "select": 0.420,
    },
    # A narrow flyer with a long tail and a short span: deliberately the
    # OPPOSITE proportion to the Gryphon Rider it unlocks beside, so the two
    # air creeps of the bracket never read as one shape at two colours.
    "harpy_windwitch": {
        "fly_height": cr.FLY_HEIGHT, "shadow": 0.26, "hover": 1.05,
        "body_r": 0.104, "body_len": 0.42, "chest": 1.05,
        "neck": 0.140, "neck_tilt": -0.50, "head_tilt": 0.38,
        "head_r": 0.084, "snout": 0.090,
        "wing_span": 0.360, "wing_chord": 0.200, "wing_r": 0.026,
        "wing_droop": 0.26,
        "tail": 0.260, "tail_r": 0.048, "tail_tilt": 0.24,
        "select": 0.40,
    },
    # The serpent. A wide low coil with a person rising out of it, and the tail
    # laid back behind - the only creep in the game with no legs that is not
    # in the air.
    "naga_siren": {
        "coil": 0.230, "coil_h": 0.190,
        "waist": 0.098, "torso": 0.27, "chest_r": 0.128, "stoop": -0.06,
        "shoulder": 0.136, "neck": 0.034, "head_r": 0.090, "fin": 0.105,
        "arm": 0.155, "arm_r": 0.028, "arm_flare": 0.30,
        "tail": 0.360, "tail_r": 0.072, "tail_segments": 4,
        "select": 0.36,
    },
    # The third quadruped, and by a long way the heaviest: a barrel on four
    # short pillars with a huge horned head. The Sheep and the Timber Wolf are
    # both slight, so this needs no help telling itself apart from them.
    "kodo_beast": {
        "hip_y": 0.34, "leg_span": 0.185, "leg_reach": 0.180, "digit": "claw",
        "thigh_r": 0.070, "shin_r": 0.060, "thigh_share": 0.5,
        "body_r": 0.245, "body_len": 0.56, "chest": 1.05, "chest_rise": 0.02,
        "fleece": False, "hump": True,
        "neck": 0.130, "neck_y": 0.04, "neck_z": 0.46, "neck_tilt": -0.60,
        "head_tilt": 0.35, "head_r": 0.140, "snout": 0.150, "ear": 0.9,
        "tail": 0.170, "tail_r": 0.058, "tail_tilt": -0.70,
        "select": 0.40,
    },
    # The second machine, and it is authored AGAINST the first: taller, on
    # bigger wheels, with a short chassis and a long arm carried high. A Siege
    # Engine is a low cart, this is a walking rig.
    "goblin_shredder": {
        "wheel_r": 0.145, "wheel_w": 0.070, "wheel_span": 0.175,
        "wheel_reach": 0.150,
        "deck_y": 0.300, "chassis_w": 0.265, "chassis_h": 0.190,
        "chassis_len": 0.350, "plow": 0.110,
        "post": 0.135, "arm_len": 0.340, "arm_r": 0.048, "arm_tilt": 0.55,
        "bucket": 0.100,
        "select": 0.38,
    },
    # A skeletal flyer: long, thin and with the longest neck and tail in the
    # roster. The span is modest and the LENGTH is the silhouette, which is the
    # third distinct flyer proportion in the bracket.
    "frost_wyrm": {
        "fly_height": cr.FLY_HEIGHT, "shadow": 0.30, "hover": 0.70,
        "body_r": 0.110, "body_len": 0.50, "chest": 1.02,
        "neck": 0.210, "neck_tilt": -0.62, "head_tilt": 0.42,
        "head_r": 0.092, "snout": 0.165,
        "wing_span": 0.395, "wing_chord": 0.215, "wing_r": 0.028,
        "wing_droop": 0.20,
        "tail": 0.340, "tail_r": 0.050, "tail_tilt": 0.28,
        "select": 0.46,
    },
    # The bracket's Boss, its fourth flyer and its ATTACKER, so it carries the
    # lit talons no other flyer has - and it is one of the two creeps in the
    # game that gives off light at all (style.CREEP_FLAMES). Broad and short,
    # so a burning thing arriving over a maze fills as much of the screen as
    # the ceiling allows.
    "phoenix": {
        "fly_height": cr.FLY_HEIGHT, "shadow": 0.32, "hover": 1.15,
        "body_r": 0.122, "body_len": 0.40, "chest": 1.18,
        "neck": 0.125, "neck_tilt": -0.40, "head_tilt": 0.32,
        "head_r": 0.092, "snout": 0.120,
        "wing_span": 0.395, "wing_chord": 0.255, "wing_r": 0.032,
        "wing_droop": 0.10,
        "tail": 0.290, "tail_r": 0.054, "tail_tilt": 0.22,
        "talons": 0.130,
        # Pulled to sit just under style.CREEP_MAX_RADIUS once the Boss mass
        # ramp is applied. It is the widest click box in the game and it is
        # meant to be - the ceiling belongs to a top tier Boss, and this is
        # one - but the first pass went past it and the generator said so.
        "select": 0.42,
    },
    # The last creep in the game, and the only one that cannot be killed. A
    # golem, taking the Boss ramps, authored as the biggest silhouette the size
    # ceiling allows - what it has to say from across a lane is "nothing you
    # build will stop this".
    "demon": {
        "hip_y": 0.420, "stance": 0.168,
        "thigh_r": 0.088, "shin_r": 0.076, "thigh_share": 0.5,
        "chest_w": 0.390, "chest_h": 0.400, "chest_d": 0.280,
        "head_r": 0.106, "head_sink": 0.92, "ribs": True,
        "arm": 0.480, "arm_r": 0.084,
        "select": 0.355,
    },
    # Three of these crawl out of a dead Obsidian Statue. Hunched right over,
    # clawed, and with the lowest hips of any biped in the game - a Ghoul goes
    # on all fours as far as this plan can.
    "ghoul": {
        "hip_y": 0.32, "stance": 0.082, "digit": "claw",
        "thigh_r": 0.032, "shin_r": 0.026, "thigh_share": 0.48,
        "waist": 0.094, "torso": 0.22, "chest_r": 0.122, "stoop": 0.52,
        "robe": 0.0, "belt": False, "cloak": 0.0, "ribs": True,
        "shoulder": 0.130, "neck": 0.008, "head_r": 0.086, "head": "bare",
        "tusks": True,
        "arm": 0.185, "arm_r": 0.032, "arm_flare": 0.36,
        "weapon": "", "weapon_len": 0.0, "shield": 0.0,
        "select": 0.28,
    },
}


def generate():
    """Writes every creep model and answers what the prefab stage needs to
    know about each one: how tall it stands, and which nodes walk."""
    os.makedirs(OUT, exist_ok=True)
    built = {}
    for key, _display, plan, gold, _family, boss in cr.CREEPS:
        m = CreepModel(key, gold, plan, boss)
        shape = SHAPES[key]
        # Authored unscaled, so the rung's ramps are applied here rather than
        # inside every one of the six builders. HEIGHT, not width - this is how
        # tall the finished creep stands, and the prefab hangs its health bar
        # off it.
        height = PLANS[plan](m, shape)
        built[key] = {
            "height": round(height * m.h, 4),
            "legs": list(m.legs),
            "phases": list(m.phases),
            "arms": list(m.arms),
            "strike": m.strike,
            "hover": m.hover,
            "rolls": m.rolls,
            # A stride is measured from the leg, so a short legged Sheep takes
            # more steps to cross the same ground than a Rot Golem does. Two
            # and a bit leg lengths per cycle is roughly what stops a walk
            # looking like a skate.
            "stride": round(_stride(shape) * m.h * 2.3, 4),
            "radius": round(shape["select"] * m.s, 4),
        }
        io.open("%s/%s_model.tscn" % (OUT, key), "w", encoding="utf-8",
                newline="\n").write(m.render())
    print("wrote %d creep models" % len(built))
    _check_ceiling(built)
    return built


def _check_ceiling(built):
    """Says so when a creep has grown past style's size ceiling.

    The ceiling is a convention worth keeping - the whole roster lives inside a
    narrow band and the top of it belongs to a top tier Boss - and one that is
    only written down is one a model quietly stops obeying. REPORTED RATHER
    THAN RAISED, and that is the shape the visual rules take everywhere: it is
    not binding, the number to change is in the roster, and the person changing
    it wants to see the model before deciding. See style.py.
    """
    over = []
    for key in sorted(built):
        entry = built[key]
        if entry["height"] > ts.CREEP_MAX_HEIGHT:
            over.append("%s is %.2f tall, ceiling is %.2f"
                        % (key, entry["height"], ts.CREEP_MAX_HEIGHT))
        if entry["radius"] > ts.CREEP_MAX_RADIUS:
            over.append("%s reaches %.2f, ceiling is %.2f"
                        % (key, entry["radius"], ts.CREEP_MAX_RADIUS))
    for line in over:
        print("  OVER THE CREEP SIZE CEILING: %s" % line)


def _stride(shape):
    """How far a creep travels per full gait cycle, in authored units.

    Measured off the LEG rather than authored, so a short legged Sheep takes
    more steps to cross the same ground than a Rot Golem does and neither of
    them ever looks like it is skating.
    """
    if "hip_y" in shape and "femur" not in shape:
        return shape["hip_y"]
    if "femur" in shape:
        return shape["femur"] * 0.9
    return 0.3
