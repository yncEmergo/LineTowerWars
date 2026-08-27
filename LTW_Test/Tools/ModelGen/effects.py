import io, os
from tscn import Scene, t3, c, num

OUT = "Scenes/Effects"
PROJECTILE = "res://Scripts/Combat/Projectile.gd"
BURST = "res://Scripts/Effects/ImpactBurst.gd"
SELF_FREE = "res://Scripts/Effects/FreeOnTimeout.gd"
VISUAL_EFFECT = "res://Scripts/Effects/VisualEffect3D.gd"
SPIN = "res://Scripts/Components/SpinAnimation3D.gd"


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


def blood_spray():
    """What a Cutter-line blade throws off a creep it is chewing on.

    Spawned at the creep and TURNED TO FACE the tower by spawn_impact, so
    everything below is authored in "towards the attacker is -Z" space: the
    spray sits on the near edge of the creep and throws back along the blade.

    CPUParticles3D rather than GPU, because the project renders with
    gl_compatibility where GPU particles are not dependable.
    """
    s = Scene()
    drop_m = unshaded(s, "M_drop", (0.62, 0.10, 0.12), 0.95)
    drop = mesh(s, "SphereMesh", "Drop", [
        "radius = 0.035", "height = 0.055",
        "radial_segments = 5", "rings = 2"], drop_m)

    # The ROOT is a plain Node3D and carries no transform of its own, because
    # spawn_impact overwrites the root's position and rotation. Everything
    # authored in place has to hang off a child of it.
    s.node("BloodSpray", "Node3D", ".", script=s.ext("Script", VISUAL_EFFECT))
    s.node("Drops", "CPUParticles3D", ".", props=[
        # On the near edge of the creep, facing the tower.
        "transform = %s" % t3(y=0.24, z=-0.18),
        # NOT emitting on its own. Whoever spawns the effect calls play() once
        # it is in place; emitting on the way into the tree throws the whole
        # spray at the effects root's origin, which is where every drop of
        # blood in the game used to end up.
        "emitting = false",
        "one_shot = true",
        "explosiveness = 1.0",
        "amount = 10",
        "lifetime = 0.42",
        'mesh = SubResource("%s")' % drop,
        # Thrown back towards the tower and up, then pulled down.
        "direction = Vector3(0, 0.55, -1)",
        "spread = 32.0",
        "initial_velocity_min = 1.1",
        "initial_velocity_max = 2.3",
        "gravity = Vector3(0, -5.5, 0)",
        "scale_amount_min = 0.6",
        "scale_amount_max = 1.3",
        "damping_min = 0.5",
        "damping_max = 1.5",
    ])
    # CPUParticles3D does not free itself when it finishes, and an impact
    # effect that never leaves would pile one node up per swing of every
    # blade in the maze.
    s.node("Despawn", "Timer", ".", props=[
        "wait_time = 0.9",
        "one_shot = true",
        "autostart = true",
    ])
    s.node("FreeOnTimeout", "Node", ".",
           script=s.ext("Script", SELF_FREE),
           props=['_timer = NodePath("../Despawn")'],
           node_paths=["_timer"])
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


def spike(name, body_colour, core_colour, length=0.42, radius=0.045):
    """A long needle pointed down -Z. Ice 2 and Earth 2 both fire one, and it
    is the one projectile shape that says PIERCES before it lands."""
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

    s.node(name, "Node3D", ".", script=s.ext("Script", PROJECTILE))
    put(s, "Body", body, z=0.05, rx=-1.5708)
    put(s, "Core", core, z=0.02, rx=-1.5708)
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
    ("ice_spike", spike, ["IceSpike", (0.72, 0.92, 1.00), (0.55, 0.95, 1.00)]),
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
    return len(ELEMENT_PROJECTILES) + len(ELEMENT_IMPACTS) + 2


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
