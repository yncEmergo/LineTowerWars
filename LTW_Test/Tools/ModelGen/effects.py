import io, math, os
from tscn import Scene, t3, c, num

OUT = "Scenes/Effects"
PROJECTILE = "res://Scripts/Combat/Projectile.gd"
BURST = "res://Scripts/Effects/ImpactBurst.gd"
SELF_FREE = "res://Scripts/Effects/FreeOnTimeout.gd"
VISUAL_EFFECT = "res://Scripts/Effects/VisualEffect3D.gd"
SPIN = "res://Scripts/Components/SpinAnimation3D.gd"
GROUND_HAZARD = "res://Scripts/Combat/GroundHazard.gd"
PIERCING = "res://Scripts/Combat/PiercingProjectile.gd"
LIGHTNING_BOLT = "res://Scripts/Effects/LightningBolt3D.gd"
BEAST_CHARGE = "res://Scripts/Combat/BeastCharge.gd"

# How big the Beastmaster's beast is DRAWN, against the size it is authored at.
#
# Visual only, and deliberately out of step with the rule: the band the beast
# actually flattens is two cells across and is BloodthirstPassive.beast_radius,
# which this does not touch. The parts below are authored at a size that reads
# as an animal from a top down camera, and then the whole model is shrunk,
# because a beast filling its own hitbox filled the lane.
#
# One node with one scale on it rather than the numbers below being retuned, so
# the shapes stay readable next to each other and this stays one knob to turn.
MODEL_SCALE = 0.7


def unshaded(scene, name, colour, alpha=1.0):
    # ALPHA transparency on every effect material, even the fully opaque ones.
    # GeometryInstance3D.transparency - which is how VisualEffect3D dials an
    # effect down - does nothing to a material whose transparency is disabled,
    # so an opaque arrow shaft would quietly ignore the opacity setting.
    return scene.sub("StandardMaterial3D", name, [
        "shading_mode = 0",
        "transparency = 1",
        "albedo_color = Color(%s, %s, %s, %s)" % (
            num(colour[0]), num(colour[1]), num(colour[2]), num(alpha)),
    ])


def lit(scene, name, colour):
    return scene.sub("StandardMaterial3D", name, [
        # See unshaded() for why every effect material is transparency-capable.
        "transparency = 1",
        "albedo_color = %s" % c(colour),
        "metallic = 0.6",
        "roughness = 0.45",
    ])


def mesh(scene, kind, name, lines, material):
    return scene.sub(kind, name, lines + ['material = SubResource("%s")' % material])


def put(scene, name, mesh_name, parent=".", **kw):
    scene.node(name, "MeshInstance3D", parent, props=[
        "transform = %s" % t3(**kw),
        "cast_shadow = 0",
        'mesh = SubResource("%s")' % mesh_name,
    ])


def write(path, scene):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    io.open(path, "w", encoding="utf-8", newline="\n").write(
        scene.render("[gd_scene format=3]"))


# --- projectiles -----------------------------------------------------------
# Every one of them points down -Z: Projectile look_at()s its own travel
# direction, and Godot's forward is -Z.

def arrow():
    """Archer and Watch Tower. A thin dart, so a fast flat shot reads as a
    streak rather than as a dot."""
    s = Scene()
    shaft_m = lit(s, "M_shaft", (0.62, 0.66, 0.72))
    head_m = unshaded(s, "M_head", (0.55, 0.95, 1.10))
    fletch_m = lit(s, "M_fletch", (0.20, 0.44, 0.56))

    shaft = mesh(s, "CylinderMesh", "Shaft", [
        "top_radius = 0.018", "bottom_radius = 0.018", "height = 0.34",
        "radial_segments = 5", "rings = 0"], shaft_m)
    head = mesh(s, "CylinderMesh", "Head", [
        "top_radius = 0.0", "bottom_radius = 0.05", "height = 0.16",
        "radial_segments = 5", "rings = 0"], head_m)
    fletch = mesh(s, "PrismMesh", "Fletch", [
        "size = Vector3(0.10, 0.09, 0.02)"], fletch_m)

    s.node("Arrow", "Node3D", ".", script=s.ext("Script", PROJECTILE))
    put(s, "Shaft", shaft, rx=1.5708)
    put(s, "Head", head, z=-0.25, rx=-1.5708)
    put(s, "FletchA", fletch, z=0.15, rx=1.5708)
    put(s, "FletchB", fletch, z=0.15, rx=1.5708, ry=1.5708)
    return s


def mortar_shell():
    """Cannon. Heavy, dark and lobbed on an arc, with a lit tail so it can be
    followed against the ground it is about to hit."""
    s = Scene()
    body_m = lit(s, "M_body", (0.20, 0.18, 0.17))
    band_m = lit(s, "M_band", (0.55, 0.38, 0.16))
    fuse_m = unshaded(s, "M_fuse", (1.00, 0.62, 0.22))

    body = mesh(s, "SphereMesh", "Body", [
        "radius = 0.085", "height = 0.17",
        "radial_segments = 7", "rings = 4"], body_m)
    band = mesh(s, "TorusMesh", "Band", [
        "inner_radius = 0.08", "outer_radius = 0.10",
        "rings = 8", "ring_segments = 4"], band_m)
    fuse = mesh(s, "SphereMesh", "Fuse", [
        "radius = 0.05", "height = 0.10",
        "radial_segments = 6", "rings = 3"], fuse_m)

    s.node("MortarShell", "Node3D", ".", script=s.ext("Script", PROJECTILE))
    put(s, "Body", body)
    put(s, "Band", band, rx=1.5708)
    put(s, "Fuse", fuse, z=0.10)
    return s


def magic_bolt():
    """Sentry and Defender. A turning shard with a glow behind it, so a magic
    shot never reads as a bullet."""
    s = Scene()
    core_m = unshaded(s, "M_core", (0.85, 0.70, 1.10))
    shell_m = unshaded(s, "M_shell", (0.55, 0.34, 0.95), 0.5)

    core = mesh(s, "SphereMesh", "Core", [
        "radius = 0.055", "height = 0.20",
        "radial_segments = 4", "rings = 2"], core_m)
    shell = mesh(s, "SphereMesh", "Shell", [
        "radius = 0.105", "height = 0.21",
        "radial_segments = 6", "rings = 3"], shell_m)

    s.node("MagicBolt", "Node3D", ".", script=s.ext("Script", PROJECTILE))
    s.node("Spin", "Node3D", ".", props=["transform = %s" % t3()])
    put(s, "Core", core, parent="Spin", rz=0.6)
    s.node("SpinDrive", "Node", "Spin", node_paths=["_spinner"],
           script=s.ext("Script", SPIN),
           props=['_spinner = NodePath("..")', "turns_per_second = 2.5",
                  "axis = Vector3(0, 0, 1)"])
    put(s, "Shell", shell)
    return s


def missile():
    """Turret. Aimed at the sky and nothing else, so it is the one projectile
    in the game with fins."""
    s = Scene()
    body_m = lit(s, "M_body", (0.58, 0.60, 0.66))
    tip_m = lit(s, "M_tip", (0.44, 0.36, 0.62))
    flame_m = unshaded(s, "M_flame", (0.80, 0.62, 1.10))

    body = mesh(s, "CylinderMesh", "Body", [
        "top_radius = 0.04", "bottom_radius = 0.045", "height = 0.26",
        "radial_segments = 6", "rings = 0"], body_m)
    tip = mesh(s, "CylinderMesh", "Tip", [
        "top_radius = 0.0", "bottom_radius = 0.042", "height = 0.11",
        "radial_segments = 6", "rings = 0"], tip_m)
    fin = mesh(s, "PrismMesh", "Fin", [
        "size = Vector3(0.09, 0.07, 0.014)"], tip_m)
    flame = mesh(s, "CylinderMesh", "Flame", [
        "top_radius = 0.0", "bottom_radius = 0.035", "height = 0.16",
        "radial_segments = 6", "rings = 0"], flame_m)

    s.node("Missile", "Node3D", ".", script=s.ext("Script", PROJECTILE))
    put(s, "Body", body, rx=1.5708)
    put(s, "Tip", tip, z=-0.185, rx=-1.5708)
    put(s, "FinA", fin, z=0.10, rx=1.5708)
    put(s, "FinB", fin, z=0.10, rx=1.5708, ry=1.5708)
    put(s, "Flame", flame, z=0.20, rx=1.5708)
    return s


# --- impacts ---------------------------------------------------------------
# Both are one ImpactBurst: a flat ring on the ground plus a core, expanding
# and fading. Flat because the camera looks down, so a ring on the floor is the
# shape that actually shows where the damage went.

def burst(name, ring_colour, core_colour, ring_radius, duration, end_scale):
    s = Scene()
    ring_m = unshaded(s, "M_ring", ring_colour, 0.85)
    core_m = unshaded(s, "M_core", core_colour, 0.9)

    ring = mesh(s, "TorusMesh", "Ring", [
        "inner_radius = %s" % num(ring_radius * 0.72),
        "outer_radius = %s" % num(ring_radius),
        "rings = 18", "ring_segments = 5"], ring_m)
    core = mesh(s, "SphereMesh", "Core", [
        "radius = %s" % num(ring_radius * 0.55),
        "height = %s" % num(ring_radius * 0.8),
        "radial_segments = 7", "rings = 4"], core_m)

    # No list of parts to wire: VisualEffect3D finds every drawable under
    # itself, so an effect that gains a mesh fades with the rest for free.
    s.node(name, "Node3D", ".",
           script=s.ext("Script", BURST),
           props=["duration = %s" % num(duration),
                  "start_scale = 0.3",
                  "end_scale = %s" % num(end_scale),
                  "scale_curve = 0.45"])
    put(s, "Ring", ring, y=0.06)
    put(s, "Core", core, y=0.12)
    return s


def shockwave():
    """The Crusher's blast, drawn on the ground it covers.

    Authored at RADIUS 1 and scaled by the tower to its own blast radius, so
    the ring a player learns to read is always exactly the ground that took
    damage - an Ultimate Crusher's is wider than a Lesser's without either
    being authored twice. See SlamAnimation3D._scale_to_blast.

    Flat and on the floor, because the camera looks down: a dome would hide
    the creeps it is telling you about.
    """
    s = Scene()
    ring_m = unshaded(s, "M_ring", (1.00, 0.72, 0.34), 0.9)
    inner_m = unshaded(s, "M_inner", (1.00, 0.88, 0.62), 0.5)
    dust_m = unshaded(s, "M_dust", (0.72, 0.62, 0.48), 0.85)

    ring = mesh(s, "TorusMesh", "Ring", [
        "inner_radius = 0.86", "outer_radius = 1.0",
        "rings = 40", "ring_segments = 5"], ring_m)
    inner = mesh(s, "TorusMesh", "Inner", [
        "inner_radius = 0.30", "outer_radius = 0.62",
        "rings = 32", "ring_segments = 5"], inner_m)
    dust = mesh(s, "SphereMesh", "Dust", [
        "radius = 0.16", "height = 0.2",
        "radial_segments = 6", "rings = 3"], dust_m)

    s.node("Shockwave", "Node3D", ".",
           script=s.ext("Script", BURST),
           props=["duration = 0.5",
                  # Snaps out over the first quarter of its life and then SITS
                  # at full size for the rest, fading. The growth is the event;
                  # the hold is what actually shows a player the radius, and a
                  # ring still creeping outwards the whole time it is on screen
                  # never gives them a size to read.
                  "start_scale = 0.12",
                  "end_scale = 1.0",
                  "grow_share = 0.26",
                  "scale_curve = 0.75"])
    put(s, "Ring", ring, y=0.05)
    put(s, "Inner", inner, y=0.04)
    # A few lumps thrown outwards, so the blast has something with volume in it
    # and does not read as a decal.
    for index, (x, z) in enumerate(((0.62, 0.24), (-0.5, 0.44), (0.1, -0.66),
                                    (-0.34, -0.44))):
        put(s, "Dust%d" % (index + 1), dust, x=x, y=0.12, z=z)
    return s


def spray(name, root_name, colour, alpha, radius, height, count, lifetime,
          offset, direction, velocity, gravity, spread, life):
    """A one-shot burst of little spheres thrown off the point a hit landed.

    Spawned at the creep and TURNED TO FACE the attacker by spawn_impact, so
    everything below is authored in "towards the attacker is -Z" space: a spray
    sits on the near edge of the creep and throws back along the line the hit
    came in on.

    CPUParticles3D rather than GPU, because the project renders with
    gl_compatibility where GPU particles are not dependable.

    One builder for every particle impact in the game. What separates a blade
    throwing blood from an arc throwing sparks is entirely in the numbers - the
    weight of what comes off, how fast, and whether it falls - so making them
    two builders would be two copies of the same forty lines drifting apart.
    """
    s = Scene()
    drop_m = unshaded(s, "M_drop", colour, alpha)
    drop = mesh(s, "SphereMesh", "Drop", [
        "radius = %s" % num(radius),
        "height = %s" % num(height),
        "radial_segments = 5", "rings = 2"], drop_m)

    # The ROOT is a plain Node3D and carries no transform of its own, because
    # spawn_impact overwrites the root's position and rotation. Everything
    # authored in place has to hang off a child of it.
    s.node(root_name, "Node3D", ".", script=s.ext("Script", VISUAL_EFFECT))
    s.node(name, "CPUParticles3D", ".", props=[
        "transform = %s" % t3(y=offset[0], z=offset[1]),
        # NOT emitting on its own. Whoever spawns the effect calls play() once
        # it is in place; emitting on the way into the tree throws the whole
        # spray at the effects root's origin, which is where every drop of
        # blood in the game used to end up.
        "emitting = false",
        "one_shot = true",
        "explosiveness = 1.0",
        "amount = %d" % count,
        "lifetime = %s" % num(lifetime),
        'mesh = SubResource("%s")' % drop,
        "direction = Vector3(%s, %s, %s)" % (
            num(direction[0]), num(direction[1]), num(direction[2])),
        "spread = %.1f" % spread,
        "initial_velocity_min = %s" % num(velocity[0]),
        "initial_velocity_max = %s" % num(velocity[1]),
        "gravity = Vector3(0, %s, 0)" % num(gravity),
        "scale_amount_min = 0.6",
        "scale_amount_max = 1.3",
        "damping_min = 0.5",
        "damping_max = 1.5",
    ])
    # CPUParticles3D does not free itself when it finishes, and an impact
    # effect that never leaves would pile one node up per swing of every
    # blade in the maze.
    s.node("Despawn", "Timer", ".", props=[
        "wait_time = %s" % num(life),
        "one_shot = true",
        "autostart = true",
    ])
    s.node("FreeOnTimeout", "Node", ".",
           script=s.ext("Script", SELF_FREE),
           props=['_timer = NodePath("../Despawn")'],
           node_paths=["_timer"])
    return s


def blood_spray():
    """What a Cutter-line blade throws off a creep it is chewing on. Heavy,
    thrown back at the tower, and pulled down hard."""
    return spray("Drops", "BloodSpray", (0.62, 0.10, 0.12), 0.95, 0.035,
                 0.055, 10, 0.42, (0.24, -0.18), (0, 0.55, -1), (1.1, 2.3),
                 -5.5, 32.0, 0.9)


def spark_burst(name, root_name, colour):
    """What an electrical attack throws off the creep it earths itself in.

    The same burst blood is, tuned the other way on every axis that matters:
    smaller and brighter, thrown FASTER and in every direction rather than back
    down the line, and barely pulled down at all - sparks do not fall, they go
    out. That difference is the whole reason both exist.
    """
    return spray(name, root_name, colour, 1.0, 0.026, 0.042, 16, 0.26,
                 (0.26, -0.06), (0, 0.4, -1), (2.2, 4.2), -1.6, 96.0, 0.7)


def arc_bolt(name, core_colour, glow_colour, segments=6, width=0.05):
    """A jagged arc strung between two points by LightningBolt3D.

    The segments are authored rather than built, one unit long down -Z, and the
    script only stretches and places them - so how kinked a bolt looks is an
    art decision here rather than a number in a script. Two boxes per segment:
    a hot thin core inside a wider, softer sheath, which is what stops a bolt
    reading as a grey stick at distance.
    """
    s = Scene()
    core_m = unshaded(s, "M_core", core_colour)
    glow_m = unshaded(s, "M_glow", glow_colour, 0.45)

    core = mesh(s, "BoxMesh", "Core", [
        "size = Vector3(%s, %s, 1)" % (num(width * 0.4), num(width * 0.4))], core_m)
    sheath = mesh(s, "BoxMesh", "Sheath", [
        "size = Vector3(%s, %s, 1)" % (num(width), num(width))], glow_m)

    s.node(name, "Node3D", ".", node_paths=["_segments"],
           script=s.ext("Script", LIGHTNING_BOLT),
           props=['_segments = NodePath("Segments")'])
    s.node("Segments", "Node3D", ".", props=["transform = %s" % t3()])
    for index in range(segments):
        s.node("Segment%d" % (index + 1), "Node3D", "Segments",
               props=["transform = %s" % t3()])
        put(s, "Sheath", sheath, parent="Segments/Segment%d" % (index + 1))
        put(s, "Core", core, parent="Segments/Segment%d" % (index + 1))
    return s


# --- elemental projectiles --------------------------------------------------
#
# Sixteen of them, and all but four are the same two shapes at different
# colours - a BOLT and a GLOB. That is deliberate rather than lazy: the element
# is read off the COLOUR, exactly as it is off the tower that fired it, and
# giving each of the ten a shape of its own would put a second signal on an
# axis that already carries one and is moving too fast to read anyway.
#
# The four that do get their own shape are the four whose ABILITY is about the
# shape: a meteor falls, a spike pierces, an orb bounces, a boulder is thrown.

def bolt(name, core_colour, shell_colour, radius=0.055, facets=4, spin=2.5):
    """A lit core inside a translucent shell, turning as it flies.

    The workhorse. `facets` is what separates a crystalline element from a
    fluid one at the only size a projectile is ever seen: 4 is a hard shard,
    8 is a droplet.
    """
    s = Scene()
    core_m = unshaded(s, "M_core", core_colour)
    shell_m = unshaded(s, "M_shell", shell_colour, 0.5)

    core = mesh(s, "SphereMesh", "Core", [
        "radius = %s" % num(radius),
        "height = %s" % num(radius * 3.6),
        "radial_segments = %d" % facets, "rings = 2"], core_m)
    shell = mesh(s, "SphereMesh", "Shell", [
        "radius = %s" % num(radius * 1.9),
        "height = %s" % num(radius * 3.8),
        "radial_segments = %d" % (facets + 2), "rings = 3"], shell_m)

    s.node(name, "Node3D", ".", script=s.ext("Script", PROJECTILE))
    s.node("Spin", "Node3D", ".", props=["transform = %s" % t3()])
    put(s, "Core", core, parent="Spin", rz=0.6)
    s.node("SpinDrive", "Node", "Spin", node_paths=["_spinner"],
           script=s.ext("Script", SPIN),
           props=['_spinner = NodePath("..")',
                  "turns_per_second = %s" % num(spin),
                  "axis = Vector3(0, 0, 1)"])
    put(s, "Shell", shell)
    return s


def glob(name, body_colour, drip_colour, radius=0.085):
    """A heavy blob with a tail of drips behind it, thrown on an arc.

    What every thrown liquid in the roster is: poison, sludge, acid. The drips
    are what make an arc readable - a plain sphere lobbed across a lane reads
    as a bug rather than as a throw.
    """
    s = Scene()
    body_m = unshaded(s, "M_body", body_colour, 0.95)
    drip_m = unshaded(s, "M_drip", drip_colour, 0.7)

    body = mesh(s, "SphereMesh", "Body", [
        "radius = %s" % num(radius),
        "height = %s" % num(radius * 1.9),
        "radial_segments = 7", "rings = 4"], body_m)
    drip = mesh(s, "SphereMesh", "Drip", [
        "radius = %s" % num(radius * 0.45),
        "height = %s" % num(radius * 0.9),
        "radial_segments = 5", "rings = 3"], drip_m)

    s.node(name, "Node3D", ".", script=s.ext("Script", PROJECTILE))
    put(s, "Body", body)
    put(s, "DripA", drip, y=0.03, z=0.11)
    put(s, "DripB", drip, x=0.04, y=-0.02, z=0.18)
    return s


def spike(name, body_colour, core_colour, length=0.42, radius=0.045,
          script=PROJECTILE):
    """A long needle pointed down -Z. Ice 2 and Earth 2 both fire one, and it
    is the one projectile shape that says PIERCES before it lands.

    `script` is which kind of flight it is: an ordinary homing Projectile, or
    the PiercingProjectile that flies straight through everything. Ice 2 is the
    only one in the game that really does pierce, and it is drawn LARGER than
    the Scorpion's thorn for it - a shot that keeps going after it hits should
    look like it has the mass to."""
    s = Scene()
    body_m = lit(s, "M_body", body_colour)
    core_m = unshaded(s, "M_core", core_colour)

    body = mesh(s, "CylinderMesh", "Body", [
        "top_radius = 0.0", "bottom_radius = %s" % num(radius),
        "height = %s" % num(length),
        "radial_segments = 4", "rings = 0"], body_m)
    core = mesh(s, "CylinderMesh", "Core", [
        "top_radius = 0.0", "bottom_radius = %s" % num(radius * 0.5),
        "height = %s" % num(length * 0.8),
        "radial_segments = 4", "rings = 0"], core_m)

    s.node(name, "Node3D", ".", script=s.ext("Script", script))
    put(s, "Body", body, z=0.05, rx=-1.5708)
    put(s, "Core", core, z=0.02, rx=-1.5708)
    return s


def disc(name, face_colour, core_colour, radius=0.14, teeth=3):
    """A flat plate flung out edge-up and spinning, seen from directly above.

    The one projectile shape authored for the CAMERA rather than for the thing
    it represents: a bolt read from overhead is a dot, where a plate lying flat
    on its own path is a disc the whole time it is in the air. Its axis is Y
    and it is never rotated onto another one, so it stays flat under the
    projectile's look_at as long as the shot is not arcing steeply.

    THE TEETH ARE WHY IT CAN SPIN AT ALL. A smooth disc turning about its own
    axis of symmetry is indistinguishable from a still one, so the spin is
    carried by points on the rim rather than by the plate.
    """
    s = Scene()
    face_m = unshaded(s, "M_face", face_colour, 0.85)
    core_m = unshaded(s, "M_core", core_colour)

    plate = mesh(s, "CylinderMesh", "Plate", [
        "top_radius = %s" % num(radius),
        "bottom_radius = %s" % num(radius * 0.86),
        "height = %s" % num(radius * 0.22),
        "radial_segments = 8", "rings = 0"], face_m)
    eye = mesh(s, "CylinderMesh", "Eye", [
        "top_radius = %s" % num(radius * 0.46),
        "bottom_radius = %s" % num(radius * 0.46),
        "height = %s" % num(radius * 0.34),
        "radial_segments = 8", "rings = 0"], core_m)
    tooth = mesh(s, "PrismMesh", "Tooth", [
        "size = Vector3(%s, %s, %s)" % (
            num(radius * 0.38), num(radius * 0.20), num(radius * 0.62))], face_m)

    s.node(name, "Node3D", ".", script=s.ext("Script", PROJECTILE))
    s.node("Spin", "Node3D", ".", props=["transform = %s" % t3()])
    put(s, "Plate", plate, parent="Spin")
    put(s, "Eye", eye, parent="Spin", y=radius * 0.1)
    for index in range(teeth):
        angle = index * math.tau / teeth
        put(s, "Tooth%d" % (index + 1), tooth, parent="Spin",
            x=radius * 0.92 * math.cos(angle), z=radius * 0.92 * math.sin(angle),
            ry=-angle)
    s.node("SpinDrive", "Node", "Spin", node_paths=["_spinner"],
           script=s.ext("Script", SPIN),
           props=['_spinner = NodePath("..")', "turns_per_second = 2.2",
                  "axis = Vector3(0, 1, 0)"])
    return s


def rock(name, body_colour, vein_colour, radius=0.10, burning=False):
    """A faceted lump. The Earth and Primal towers throw one; a meteor is the
    same lump with a fire shell over it, which is why they share a builder."""
    s = Scene()
    body_m = lit(s, "M_body", body_colour)
    vein_m = unshaded(s, "M_vein", vein_colour)

    body = mesh(s, "SphereMesh", "Body", [
        "radius = %s" % num(radius),
        "height = %s" % num(radius * 1.8),
        "radial_segments = 5", "rings = 3"], body_m)
    vein = mesh(s, "BoxMesh", "Vein", [
        "size = Vector3(%s, %s, %s)" % (
            num(radius * 1.9), num(radius * 0.18), num(radius * 0.18))], vein_m)

    s.node(name, "Node3D", ".", script=s.ext("Script", PROJECTILE))
    put(s, "Body", body)
    put(s, "VeinA", vein)
    put(s, "VeinB", vein, ry=1.5708)
    if burning:
        flame_m = unshaded(s, "M_flame", (1.00, 0.58, 0.18), 0.55)
        flame = mesh(s, "SphereMesh", "Flame", [
            "radius = %s" % num(radius * 1.7),
            "height = %s" % num(radius * 3.0),
            "radial_segments = 7", "rings = 4"], flame_m)
        put(s, "Flame", flame, z=0.09)
    return s


def orb_projectile(name, core_colour, ring_colour, radius=0.10):
    """A big lit orb inside a turning ring. The Arcane Orb line's own shot, and
    the only projectile in the game that is bigger than the creeps it hits -
    which is the point: that attack bounces, so it should be watchable."""
    s = Scene()
    core_m = unshaded(s, "M_core", core_colour)
    ring_m = unshaded(s, "M_ring", ring_colour, 0.8)

    core = mesh(s, "SphereMesh", "Core", [
        "radius = %s" % num(radius),
        "height = %s" % num(radius * 2.0),
        "radial_segments = 6", "rings = 4"], core_m)
    ring = mesh(s, "TorusMesh", "Ring", [
        "inner_radius = %s" % num(radius * 1.2),
        "outer_radius = %s" % num(radius * 1.45),
        "rings = 12", "ring_segments = 4"], ring_m)

    s.node(name, "Node3D", ".", script=s.ext("Script", PROJECTILE))
    put(s, "Core", core)
    s.node("Spin", "Node3D", ".", props=["transform = %s" % t3()])
    put(s, "Ring", ring, parent="Spin", rx=1.2)
    s.node("SpinDrive", "Node", "Spin", node_paths=["_spinner"],
           script=s.ext("Script", SPIN),
           props=['_spinner = NodePath("..")', "turns_per_second = 1.4",
                  "axis = Vector3(0, 1, 0)"])
    return s


def jet(name, colour, tail_colour, radius=0.05, length=0.34):
    """A stretched droplet. Water's own shot, and the one projectile that is
    LONGER than it is wide without being a needle."""
    s = Scene()
    body_m = unshaded(s, "M_body", colour, 0.9)
    tail_m = unshaded(s, "M_tail", tail_colour, 0.45)

    body = mesh(s, "CapsuleMesh", "Body", [
        "radius = %s" % num(radius),
        "height = %s" % num(length),
        "radial_segments = 7", "rings = 3"], body_m)
    tail = mesh(s, "CapsuleMesh", "Tail", [
        "radius = %s" % num(radius * 0.7),
        "height = %s" % num(length * 1.5),
        "radial_segments = 6", "rings = 2"], tail_m)

    s.node(name, "Node3D", ".", script=s.ext("Script", PROJECTILE))
    put(s, "Body", body, rx=1.5708)
    put(s, "Tail", tail, z=0.16, rx=1.5708)
    return s


def flask(name, glass_colour, brew_colour):
    """A bottle, tumbling. The Alchemist throws one and it should read as a
    thrown OBJECT rather than as a spell, which is the whole difference between
    the two Unholy paths."""
    s = Scene()
    glass_m = unshaded(s, "M_glass", glass_colour, 0.55)
    brew_m = unshaded(s, "M_brew", brew_colour)

    body = mesh(s, "SphereMesh", "Body", [
        "radius = 0.085", "height = 0.17",
        "radial_segments = 6", "rings = 4"], glass_m)
    brew = mesh(s, "SphereMesh", "Brew", [
        "radius = 0.06", "height = 0.10",
        "radial_segments = 6", "rings = 3"], brew_m)
    neck = mesh(s, "CylinderMesh", "Neck", [
        "top_radius = 0.028", "bottom_radius = 0.04", "height = 0.09",
        "radial_segments = 6", "rings = 0"], glass_m)

    s.node(name, "Node3D", ".", script=s.ext("Script", PROJECTILE))
    s.node("Tumble", "Node3D", ".", props=["transform = %s" % t3()])
    put(s, "Body", body, parent="Tumble")
    put(s, "Brew", brew, parent="Tumble", y=-0.02)
    put(s, "Neck", neck, parent="Tumble", y=0.10)
    s.node("TumbleDrive", "Node", "Tumble", node_paths=["_spinner"],
           script=s.ext("Script", SPIN),
           props=['_spinner = NodePath("..")', "turns_per_second = 1.8",
                  "axis = Vector3(1, 0, 0)"])
    return s


# One entry per elemental projectile: which builder draws it and with what.
# A table rather than sixteen calls, because what a reader wants from this file
# is to see the ten elements' colours next to each other.
ELEMENT_PROJECTILES = [
    ("fire_bolt", bolt, ["FireBolt", (1.00, 0.72, 0.26), (1.00, 0.34, 0.08)]),
    ("meteor", rock, ["Meteor", (0.22, 0.17, 0.16), (1.00, 0.46, 0.12), 0.13, True]),
    ("frost_bolt", bolt, ["FrostBolt", (0.80, 0.98, 1.00), (0.34, 0.72, 1.00)]),
    # Ice 2's spike is the only projectile in the game that does not home, and
    # the only one carrying the piercing script. See PierceDelivery.
    ("ice_spike", spike, ["IceSpike", (0.72, 0.92, 1.00), (0.55, 0.95, 1.00),
                          0.62, 0.075, PIERCING]),
    # Ice 1's own shot, so that a Lich is told from the base pair it grew out
    # of by what leaves it as well as by its silhouette.
    ("frost_disc", disc, ["FrostDisc", (0.74, 0.94, 1.00), (0.42, 0.80, 1.00)]),
    ("holy_mote", bolt, ["HolyMote", (1.00, 0.96, 0.76), (1.00, 0.82, 0.32),
                         0.045, 6, 1.6]),
    ("holy_bolt", bolt, ["HolyBolt", (1.00, 0.98, 0.86), (1.00, 0.78, 0.24),
                         0.05, 4, 3.2]),
    # The Divineshroom's spores. A GLOB rather than a bolt because it is lobbed
    # upwards at flyers and the trailing drips are what make an arc readable.
    ("spore_burst", glob, ["SporeBurst", (0.94, 0.96, 0.66),
                           (0.72, 0.88, 0.44), 0.09]),
    ("void_bolt", bolt, ["VoidBolt", (1.00, 0.62, 1.00), (0.52, 0.10, 0.60),
                         0.06, 6, 2.0]),
    ("poison_glob", glob, ["PoisonGlob", (0.56, 0.92, 0.24), (0.30, 0.60, 0.12)]),
    ("sludge_glob", glob, ["SludgeGlob", (0.34, 0.58, 0.34), (0.20, 0.38, 0.30),
                           0.095]),
    ("acid_flask", flask, ["AcidFlask", (0.72, 0.86, 0.70), (0.62, 1.00, 0.28)]),
    ("water_jet", jet, ["WaterJet", (0.52, 0.92, 1.00), (0.24, 0.62, 0.86)]),
    ("boulder", rock, ["Boulder", (0.40, 0.34, 0.27), (0.94, 0.72, 0.30)]),
    ("thorn", spike, ["Thorn", (0.44, 0.38, 0.26), (0.94, 0.74, 0.32), 0.34, 0.038]),
    ("arcane_shard", bolt, ["ArcaneShard", (0.86, 0.78, 1.00), (0.56, 0.36, 1.00),
                            0.05, 4, 3.0]),
    ("arcane_orb", orb_projectile, ["ArcaneOrb", (0.80, 0.62, 1.00),
                                    (0.52, 0.34, 1.00)]),
    ("nature_bolt", bolt, ["NatureBolt", (0.92, 1.00, 0.62), (0.94, 0.44, 0.28),
                           0.055, 6, 1.8]),
]

# One entry per elemental impact: the ring colour, the core colour, the radius
# it is drawn at, how long it lasts and how far it grows.
#
# Every one of them is the same flat ring on the ground the Basic roster's
# impacts are, for the same reason: the camera looks down, so a ring on the
# floor is the shape that actually shows where the damage went.
ELEMENT_IMPACTS = [
    ("flame_impact", "FlameImpact", (1.00, 0.48, 0.14), (1.00, 0.84, 0.44),
     0.40, 0.30, 1.15),
    ("frost_impact", "FrostImpact", (0.58, 0.92, 1.00), (0.88, 0.98, 1.00),
     0.36, 0.28, 1.05),
    ("spark_impact", "SparkImpact", (0.76, 0.82, 1.00), (1.00, 1.00, 1.00),
     0.32, 0.22, 1.20),
    ("holy_impact", "HolyImpact", (1.00, 0.88, 0.48), (1.00, 0.98, 0.86),
     0.36, 0.28, 1.05),
    ("void_impact", "VoidImpact", (0.92, 0.34, 1.00), (0.62, 0.16, 0.72),
     0.38, 0.32, 1.10),
    ("toxic_impact", "ToxicImpact", (0.60, 1.00, 0.28), (0.86, 1.00, 0.60),
     0.38, 0.32, 1.10),
    ("water_impact", "WaterImpact", (0.36, 0.86, 0.96), (0.80, 0.98, 1.00),
     0.38, 0.28, 1.15),
    ("nature_impact", "NatureImpact", (0.72, 1.00, 0.42), (1.00, 0.92, 0.52),
     0.36, 0.28, 1.05),
]


def ground_ring(name, ring_colour, inner_colour, dust_colour):
    """A blast ring drawn on the ground, authored at RADIUS 1.

    The same shape shockwave.tscn is and for the same reason: the tower scales
    it to its own blast radius, so the ring a player learns to read is always
    exactly the ground that took damage. See SlamAnimation3D._scale_to_blast.
    """
    s = Scene()
    ring_m = unshaded(s, "M_ring", ring_colour, 0.9)
    inner_m = unshaded(s, "M_inner", inner_colour, 0.5)
    dust_m = unshaded(s, "M_dust", dust_colour, 0.85)

    ring = mesh(s, "TorusMesh", "Ring", [
        "inner_radius = 0.86", "outer_radius = 1.0",
        "rings = 40", "ring_segments = 5"], ring_m)
    inner = mesh(s, "TorusMesh", "Inner", [
        "inner_radius = 0.30", "outer_radius = 0.62",
        "rings = 32", "ring_segments = 5"], inner_m)
    dust = mesh(s, "SphereMesh", "Dust", [
        "radius = 0.16", "height = 0.2",
        "radial_segments = 6", "rings = 3"], dust_m)

    s.node(name, "Node3D", ".",
           script=s.ext("Script", BURST),
           props=["duration = 0.5", "start_scale = 0.12", "end_scale = 1.0",
                  "grow_share = 0.26", "scale_curve = 0.75"])
    put(s, "Ring", ring, y=0.05)
    put(s, "Inner", inner, y=0.04)
    for index, (x, z) in enumerate(((0.62, 0.24), (-0.5, 0.44), (0.1, -0.66),
                                    (-0.34, -0.44))):
        put(s, "Dust%d" % (index + 1), dust, x=x, y=0.12, z=z)
    return s


def burning_ground():
    """The patch a meteor leaves behind, authored at RADIUS 1.

    Three layers, and each answers a different question a player asks of it:
    a dark scorch says the ground is RUINED, a lit floor over it says it is
    still HOT, and a rim at exactly radius 1 says how far that reaches - the
    same job the impact rings do, and the reason this is authored at 1 and
    scaled by GroundHazard rather than being drawn at some size of its own.

    The flames are a SEPARATE node because the hazard stretches them on the
    render frame while the whole patch fades. Two rings of tongues at different
    heights and offset angles, so it reads as a fire rather than as a fence.
    """
    s = Scene()
    scorch_m = unshaded(s, "M_scorch", (0.10, 0.05, 0.04), 0.80)
    floor_m = unshaded(s, "M_floor", (1.00, 0.38, 0.08), 0.50)
    rim_m = unshaded(s, "M_rim", (1.00, 0.64, 0.22), 0.85)
    flame_m = unshaded(s, "M_flame", (1.00, 0.52, 0.14), 0.70)
    core_m = unshaded(s, "M_core", (1.00, 0.86, 0.44), 0.85)

    scorch = mesh(s, "CylinderMesh", "Scorch", [
        "top_radius = 0.98", "bottom_radius = 0.98", "height = 0.02",
        "radial_segments = 20", "rings = 0"], scorch_m)
    floor_disc = mesh(s, "CylinderMesh", "Floor", [
        "top_radius = 0.86", "bottom_radius = 0.86", "height = 0.02",
        "radial_segments = 20", "rings = 0"], floor_m)
    rim = mesh(s, "TorusMesh", "Rim", [
        "inner_radius = 0.9", "outer_radius = 1.0",
        "rings = 32", "ring_segments = 5"], rim_m)
    tongue = mesh(s, "CylinderMesh", "Tongue", [
        "top_radius = 0.0", "bottom_radius = 0.075", "height = 0.26",
        "radial_segments = 5", "rings = 0"], flame_m)
    ember = mesh(s, "CylinderMesh", "Ember", [
        "top_radius = 0.0", "bottom_radius = 0.05", "height = 0.17",
        "radial_segments = 5", "rings = 0"], core_m)

    # DIALLED BACK, through the one knob every effect in the game has for it.
    # At full strength a patch this size was the brightest thing on the field
    # and drowned the tower that lit it, the creeps standing in it and the maze
    # under it. Set here rather than by editing five material alphas by hand,
    # which is exactly what VisualEffect3D.opacity exists to avoid.
    s.node("BurningGround", "Node3D", ".", node_paths=["_flames"],
           script=s.ext("Script", GROUND_HAZARD),
           props=['_flames = NodePath("Flames")', "opacity = 0.55"])
    put(s, "Scorch", scorch, y=0.015)
    put(s, "Floor", floor_disc, y=0.03)
    put(s, "Rim", rim, y=0.04)

    # Scaled from the node's own origin, so every tongue has to STAND on y=0
    # rather than be centred on it - a cone centred on the floor grows downwards
    # through it as fast as it grows up.
    s.node("Flames", "Node3D", ".", props=["transform = %s" % t3()])
    index = 0
    for radius, count, offset, height in ((0.0, 1, 0.0, 0.34),
                                          (0.45, 5, 0.0, 0.26),
                                          (0.78, 7, 0.45, 0.20)):
        for step in range(count):
            angle = offset + step * math.tau / count
            index += 1
            put(s, "Tongue%d" % index, tongue, parent="Flames",
                x=radius * math.cos(angle), y=height * 0.5,
                z=radius * math.sin(angle), scale=height / 0.26)
            put(s, "Ember%d" % index, ember, parent="Flames",
                x=radius * math.cos(angle), y=height * 0.34,
                z=radius * math.sin(angle), scale=height / 0.26)
    return s


def rift_marker(name, bar_colour, glow_colour):
    """The X the Harbinger drops where a marked creep is going back to.

    An ImpactBurst with NO growth in it - start and end scale are both 1 - so
    the only thing the burst machinery is doing here is holding the mark at
    full strength and then taking it away. `grow_share` is what buys the hold:
    the fade does not begin until that share of the life is gone, so the X
    stands for the whole delay and then goes in the last fraction of it.

    Its DURATION is set by whoever spawns it, because the delay is per tier and
    a life authored here would be right for exactly one of the three.

    Flat on the floor and drawn as two crossed bars rather than as a ring. A
    ring is what this game means by "this much ground took damage", and this is
    a point rather than an area - it is one spot, and nothing about it is a
    radius.
    """
    s = Scene()
    bar_m = unshaded(s, "M_bar", bar_colour, 0.9)
    glow_m = unshaded(s, "M_glow", glow_colour, 0.35)

    bar = mesh(s, "BoxMesh", "Bar", ["size = Vector3(0.5, 0.02, 0.09)"], bar_m)
    pool = mesh(s, "CylinderMesh", "Pool", [
        "top_radius = 0.3", "bottom_radius = 0.3", "height = 0.02",
        "radial_segments = 12", "rings = 0"], glow_m)

    s.node(name, "Node3D", ".",
           script=s.ext("Script", BURST),
           props=["duration = 3.0", "start_scale = 1.0", "end_scale = 1.0",
                  "grow_share = 0.9"])
    put(s, "Pool", pool, y=0.02)
    put(s, "BarA", bar, y=0.04, ry=0.7854)
    put(s, "BarB", bar, y=0.04, ry=-0.7854)
    return s



def beast_charge():
    """Primal 2's beast, running down a lane on its own two seconds.

    THE ONE EFFECT IN THE GAME THAT IS A CREATURE, and the only one built to be
    looked at for longer than a blink - everything else here lives under half a
    second and is read as a flash of colour. So it gets a silhouette rather than
    a shape, and it is built out of the parts that survive a top down camera:
    four stubby LEGS under a heavy body, a head slung low in front of the
    shoulders, and two tusks sweeping out past it. The legs are what do most of
    the work - from above, four of them is the difference between an animal and
    a boulder rolling along the floor, and no amount of detail on the body
    recovers that once it is missing.

    DELIBERATELY MUCH NARROWER THAN WHAT IT FLATTENS. The band it clears is two
    cells across; the model is under one, which is MODEL_SCALE's whole job. It
    is not a mistake and it is not an approximation of the hitbox - a beast
    drawn anywhere near two cells wide covers most of a lane and stops reading
    as a thing moving through one, so the band is generous on purpose and the
    model is honest about the animal rather than about the rule.

    LIT ALONG THE SPINE, which is the one place this breaks the creep rule that
    only eyes glow. It is not a creep - it is an ability arriving - and a player
    has to be able to tell at a glance which element sent it while it is halfway
    down somebody else's maze. Primal red, the same accent its tower wears.

    The spine is a ROW OF SMALL PLATES rather than one bar, and that is worth a
    line: a single lit slab along the back is the biggest surface on the model
    and it read as a brick strapped to an animal. Broken into four it reads as
    something the beast has, and it says the same thing about the element at a
    fifth of the area.
    """
    s = Scene()
    # Primal's BASE tone rather than its deep one. The deep is what its
    # towers wear in shadow under a maze, and on a loose object out in an
    # empty lane it came out near black - a silhouette with no animal in it.
    hide_m = lit(s, "M_hide", (0.54, 0.22, 0.19))
    dark_m = lit(s, "M_dark", (0.31, 0.13, 0.12))
    bone_m = lit(s, "M_bone", (0.78, 0.70, 0.57))
    glow_m = unshaded(s, "M_glow", (1.00, 0.30, 0.24))
    dust_m = unshaded(s, "M_dust", (0.54, 0.22, 0.19), 0.55)

    body = mesh(s, "CapsuleMesh", "Body", [
        "radius = 0.38", "height = 1.25",
        "radial_segments = 7", "rings = 3"], hide_m)
    haunch = mesh(s, "SphereMesh", "Haunch", [
        "radius = 0.26", "height = 0.42",
        "radial_segments = 6", "rings = 3"], hide_m)
    leg = mesh(s, "CylinderMesh", "Leg", [
        "top_radius = 0.1", "bottom_radius = 0.075", "height = 0.44",
        "radial_segments = 5", "rings = 0"], dark_m)
    head = mesh(s, "SphereMesh", "Head", [
        "radius = 0.28", "height = 0.4",
        "radial_segments = 6", "rings = 3"], hide_m)
    snout = mesh(s, "CapsuleMesh", "Snout", [
        "radius = 0.15", "height = 0.44",
        "radial_segments = 6", "rings = 2"], hide_m)
    tusk = mesh(s, "CylinderMesh", "Tusk", [
        "top_radius = 0.0", "bottom_radius = 0.085", "height = 0.62",
        "radial_segments = 5", "rings = 0"], bone_m)
    plate = mesh(s, "PrismMesh", "Plate", [
        "size = Vector3(0.16, 0.17, 0.09)"], glow_m)
    eye = mesh(s, "SphereMesh", "Eye", [
        "radius = 0.07", "height = 0.11",
        "radial_segments = 5", "rings = 2"], glow_m)
    grit = mesh(s, "SphereMesh", "Grit", [
        "radius = 0.07", "height = 0.11",
        "radial_segments = 5", "rings = 2"], dust_m)

    s.node("BeastCharge", "Node3D", ".", script=s.ext("Script", BEAST_CHARGE))
    s.node("Visual", "Node3D", ".", props=["transform = %s" % t3(scale=MODEL_SCALE)])
    put(s, "Body", body, parent="Visual", y=0.52, rx=1.5708)
    put(s, "HaunchL", haunch, parent="Visual", x=-0.3, y=0.5, z=0.3)
    put(s, "HaunchR", haunch, parent="Visual", x=0.3, y=0.5, z=0.3)
    put(s, "ShoulderL", haunch, parent="Visual", x=-0.32, y=0.5, z=-0.26)
    put(s, "ShoulderR", haunch, parent="Visual", x=0.32, y=0.5, z=-0.26)
    # Splayed outwards a little, so from above the four of them sit OUTSIDE the
    # body rather than under it. A leg hidden by the barrel it holds up is a
    # leg that was not worth putting on the model.
    for name, x, z in (("FL", -0.3, -0.3), ("FR", 0.3, -0.3),
                       ("BL", -0.28, 0.34), ("BR", 0.28, 0.34)):
        put(s, "Leg" + name, leg, parent="Visual", x=x, y=0.22, z=z, rz=-0.22 if x < 0 else 0.22)
    put(s, "Head", head, parent="Visual", y=0.44, z=-0.72)
    put(s, "Snout", snout, parent="Visual", y=0.34, z=-0.94, rx=1.5708)
    put(s, "TuskL", tusk, parent="Visual", x=-0.25, y=0.34, z=-0.98, rx=-1.35, rz=0.42)
    put(s, "TuskR", tusk, parent="Visual", x=0.25, y=0.34, z=-0.98, rx=-1.35, rz=-0.42)
    for index, at in enumerate((-0.18, 0.08, 0.34, 0.58)):
        put(s, "Plate%d" % (index + 1), plate, parent="Visual", y=0.84, z=at)
    # On the HEAD, not on the snout. Set forward they sat between the tusks
    # and read as two more lit lumps in a cluster that already had four.
    put(s, "EyeL", eye, parent="Visual", x=-0.17, y=0.56, z=-0.8)
    put(s, "EyeR", eye, parent="Visual", x=0.17, y=0.56, z=-0.8)
    # Thrown up BEHIND it, in world space, so the trail stands where the beast
    # has been rather than riding along with it. Not one-shot, unlike every
    # impact spray: this emits for the whole run and goes when the beast does.
    s.node("Dust", "CPUParticles3D", "Visual", props=[
        "transform = %s" % t3(y=0.12, z=0.62),
        "emitting = false",
        "amount = 20",
        "lifetime = 0.7",
        'mesh = SubResource("%s")' % grit,
        "direction = Vector3(0, 0.5, 1)",
        "spread = 38.0",
        "initial_velocity_min = 0.6",
        "initial_velocity_max = 1.8",
        "gravity = Vector3(0, -2.2, 0)",
        "scale_amount_min = 0.5",
        "scale_amount_max = 1.4",
        "damping_min = 1.0",
        "damping_max = 2.4",
    ])
    return s


def generate_elements():
    for file_name, builder, args in ELEMENT_PROJECTILES:
        write("%s/%s.tscn" % (OUT, file_name), builder(*args))
    for entry in ELEMENT_IMPACTS:
        file_name, node_name = entry[0], entry[1]
        write("%s/%s.tscn" % (OUT, file_name),
              burst(node_name, entry[2], entry[3], entry[4], entry[5], entry[6]))
    write("%s/dust_ring.tscn" % OUT, ground_ring(
        "DustRing", (0.84, 0.70, 0.44), (0.94, 0.86, 0.62), (0.52, 0.44, 0.32)))
    write("%s/toxic_ring.tscn" % OUT, ground_ring(
        "ToxicRing", (0.62, 1.00, 0.30), (0.84, 1.00, 0.56), (0.34, 0.52, 0.22)))
    write("%s/burning_ground.tscn" % OUT, burning_ground())
    # Lightning's own two, and the only pair in the roster that are not a ring
    # on the floor: an element whose whole idea is a discharge should throw
    # something off what it hits and draw a line to it, not flash a disc.
    write("%s/spark_burst.tscn" % OUT,
          spark_burst("Sparks", "SparkBurst", (0.82, 0.92, 1.00)))
    write("%s/annihilation_bolt.tscn" % OUT,
          arc_bolt("AnnihilationBolt", (1.00, 0.88, 0.66), (1.00, 0.26, 0.08)))
    # Void's own, and not an impact: it stands on the ground for seconds saying
    # where a creep is about to end up. A second one that rode the creep's head
    # was tried and dropped - it read as noise on a moving target rather than
    # as a warning, and the ground mark says the same thing where the player is
    # already looking.
    write("%s/rift_marker.tscn" % OUT,
          rift_marker("RiftMarker", (1.00, 0.62, 1.00), (0.52, 0.10, 0.60)))
    # Primal's own, and not a projectile either: it is a creature that runs for
    # two seconds through everything standing in a lane. See beast_charge.
    write("%s/beast_charge.tscn" % OUT, beast_charge())
    return len(ELEMENT_PROJECTILES) + len(ELEMENT_IMPACTS) + 7


def generate():
    write("%s/arrow.tscn" % OUT, arrow())
    write("%s/mortar_shell.tscn" % OUT, mortar_shell())
    write("%s/magic_bolt.tscn" % OUT, magic_bolt())
    write("%s/missile.tscn" % OUT, missile())
    write("%s/blast_impact.tscn" % OUT,
          burst("BlastImpact", (1.00, 0.66, 0.26), (1.00, 0.88, 0.62), 0.42, 0.3, 1.1))
    write("%s/arcane_impact.tscn" % OUT,
          burst("ArcaneImpact", (0.70, 0.50, 1.05), (0.90, 0.82, 1.10), 0.36, 0.26, 1.0))
    write("%s/shockwave.tscn" % OUT, shockwave())
    write("%s/blood_spray.tscn" % OUT, blood_spray())
    print("wrote %d effect scenes" % (8 + generate_elements()))
