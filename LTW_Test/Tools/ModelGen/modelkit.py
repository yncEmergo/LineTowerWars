"""Building one placeholder model, whatever it is a model OF.

Nothing here knows about towers. It is the layer a tower, a creep and later an
elemental tower all share: a scale, three named materials, a handful of faceted
primitives, and the node helpers that place them.

THE FIVE MATERIAL ROLES are the whole convention, and they are deliberately
named for what they DO rather than for what a tower has:

    body    the bulk of the thing. A tower's plating, a creep's hide
    deep    the same material lower or heavier. Plinths, undersides, bases
    pale    the same material raised or catching light. Heads, barrels, edges
    trim    the hard accent. A tower's tier metal, a creep's claws or plates
    glow    the lit accent. A tower's crystal, a creep's eyes

body, deep and pale are ONE material at three depths rather than three
materials. That is what lets a model have parts without stopping looking like
one object - and a model built entirely out of `body` reads as a single lump
from a top down camera however good its silhouette is, because its facets have
nothing to catch against each other.

Five is still a number a 3D artist can replace in one sitting and have every
model in the game change together, which is the point of naming them at all.

FACETED, NOT SMOOTH. Every helper below defaults to a low segment count on
purpose: a six sided cylinder reads as a shape from a top down camera where a
thirty two sided one reads as a blurry pill, and the flat faces are what the
plating shader's panel lines and rim light have to catch.

WIDTH AND HEIGHT SCALE SEPARATELY, and that is not a convenience - it is the
top down camera. Height is the axis the camera sees least of and the axis that
most easily hides one model behind another, so a roster generally wants to grow
WIDER faster than it grows TALLER. Two ramps let a tier be unmistakably bigger
without anything becoming a pillar.

The cost of two ramps is that a ROTATED part no longer knows which scale it
should take: a cylinder laid on its side has its height along Z, and squashing
that by the height ramp would shorten a gun barrel every time the towers got
lower. So `cyl()` and `capsule()` take an `along` telling them which axis their
height ENDS UP on once the caller has rotated them. Get it wrong and nothing
errors - the part is just quietly the wrong length.
"""

import math

from tscn import Scene, c, t3, num

SPIN_SCRIPT = "res://Scripts/Components/SpinAnimation3D.gd"
BOB_SCRIPT = "res://Scripts/Components/BobAnimation3D.gd"

# The five material roles, in the order their ext_resources are written.
ROLES = ("body", "deep", "pale", "trim", "glow")


class Model:
    """One model under construction, and the Scene it will be written as."""

    def __init__(self, root_name, script_path, materials, scale=1.0,
                 height_scale=None):
        self.scene = Scene()
        # `s` is the width scale and is what an unqualified dimension takes.
        # `h` is the height ramp, defaulting to the same thing so a model that
        # does not care about the distinction behaves exactly as before.
        self.s = scale
        self.h = scale if height_scale is None else height_scale
        # Named by ROLE, so a builder asks for "the deep tone" and never for a
        # file. Swapping what a role points at is then one line here.
        #
        # A role may be OMITTED from the dictionary, and then it is None rather
        # than a resource - which is what keeps an elemental path tier from
        # carrying a load-time dependency on the tier metal it is forbidden to
        # draw. Reaching for a role that was not handed over fails loudly on
        # the ext_resource id being None rather than quietly drawing nothing.
        for role in ROLES:
            setattr(self, role, self.scene.ext("Material", materials[role])
                    if role in materials else None)
        self._n = 0
        self.scene.node(root_name, "Node3D", ".",
                        script=self.scene.ext("Script", script_path))

    # --- meshes -----------------------------------------------------------
    #
    # Each returns the sub_resource name to hand to put(). Meshes are NOT
    # deduplicated on purpose: two identical blades authored separately stay
    # two entries, so an artist editing one in the Godot inspector does not
    # silently edit the other.

    def _mesh(self, kind, lines, material):
        self._n += 1
        name = "%s_%d" % (kind, self._n)
        self.scene.sub(kind, name,
                       lines + ['material = ExtResource("%s")' % material])
        return name

    def cyl(self, material, top_r, bottom_r, height, segments=6, along="y"):
        """A tapered drum. The workhorse: shafts, barrels, plinths, tubes.

        `along` is which axis this cylinder's HEIGHT points down once the
        caller has rotated it. Leave it at "y" for anything standing up; pass
        "z" for a barrel or a tube laid over, so its length follows the width
        ramp instead of being squashed with the towers.
        """
        return self._mesh("CylinderMesh", [
            "top_radius = %s" % num(top_r * self.s),
            "bottom_radius = %s" % num(bottom_r * self.s),
            "height = %s" % num(height * (self.h if along == "y" else self.s)),
            "radial_segments = %d" % segments,
            "rings = 0",
        ], material)

    def box(self, material, x, y, z):
        return self._mesh("BoxMesh", [
            "size = Vector3(%s, %s, %s)" % (
                num(x * self.s), num(y * self.h), num(z * self.s)),
        ], material)

    def torus(self, material, inner, outer, rings=10, ring_segments=4):
        """A ring. Trim belts, collars, halos, orbit tracks."""
        return self._mesh("TorusMesh", [
            "inner_radius = %s" % num(inner * self.s),
            "outer_radius = %s" % num(outer * self.s),
            "rings = %d" % rings,
            "ring_segments = %d" % ring_segments,
        ], material)

    def gem(self, material, radius, height, radial=6, rings=2):
        """A faceted sphere. At radial=4, rings=2 it is an octahedron, which is
        what a crystal wants; higher counts round it off towards an eye."""
        return self._mesh("SphereMesh", [
            "radius = %s" % num(radius * self.s),
            "height = %s" % num(height * self.h),
            "radial_segments = %d" % radial,
            "rings = %d" % rings,
        ], material)

    def prism(self, material, x, y, z):
        """A wedge. Fins, shards, spikes, claws."""
        return self._mesh("PrismMesh", [
            "size = Vector3(%s, %s, %s)" % (
                num(x * self.s), num(y * self.h), num(z * self.s)),
        ], material)

    def capsule(self, material, radius, height, segments=6, rings=2, along="y"):
        """A rounded shaft. Limbs and bodies, where a hard-edged drum reads as
        machinery and the thing being built is not machinery. `along` works as
        it does on cyl()."""
        return self._mesh("CapsuleMesh", [
            "radius = %s" % num(radius * self.s),
            "height = %s" % num(height * (self.h if along == "y" else self.s)),
            "radial_segments = %d" % segments,
            "rings = %d" % rings,
        ], material)

    # --- nodes ------------------------------------------------------------

    def put(self, name, mesh, parent=".", x=0.0, y=0.0, z=0.0,
            rx=0.0, ry=0.0, rz=0.0, shadow=True, scale=1.0):
        """Places a mesh. Positions are in authored units and are scaled;
        rotations are radians and are not.

        `scale` is one number, or an (x, y, z) triple for a lopsided part. It
        is a PROPORTION rather than a size - the mesh already took the roster's
        width and height ramps on the way out of cyl()/gem()/box(), so what
        this multiplies is the shape and not the tier. It is what lets one
        sphere mesh be reused as a run of different lumps, which is the whole
        trick behind an organic tower that is not symmetrical.
        """
        props = [
            "transform = %s" % t3(x * self.s, y * self.h, z * self.s,
                                  rx, ry, rz, scale),
            'mesh = SubResource("%s")' % mesh,
        ]
        if not shadow:
            props.insert(1, "cast_shadow = 0")
        self.scene.node(name, "MeshInstance3D", parent, props=props)

    def pivot(self, name, parent=".", x=0.0, y=0.0, z=0.0,
              rx=0.0, ry=0.0, rz=0.0):
        """An empty Node3D. Aiming heads, spin hubs, muzzles, attachment
        points - anything the game code reaches for by name."""
        self.scene.node(name, "Node3D", parent, props=[
            "transform = %s" % t3(x * self.s, y * self.h, z * self.s, rx, ry, rz)])

    def ring_of(self, count, radius, place):
        """Calls place(index, x, z, angle) once per item, evenly around a ring.

        The repeated-feature helper: blades on a grinder, buttresses on a
        cannon, shards around a core, legs under a creep. Kept here because
        getting the trigonometry subtly wrong in nine separate builders is
        exactly how a roster ends up looking hand-made in the bad way.
        """
        for index in range(count):
            angle = index * math.tau / count
            place(index, math.sin(angle) * radius, math.cos(angle) * radius, angle)

    def sparks(self, name, parent, colour, count=14, radius=0.024,
               spread=0.34, lifetime=0.32, velocity=(0.7, 1.6), gravity=-1.2):
        """A quiet one-shot particle emitter, for a unit that throws something
        off itself when it acts.

        AUTHORED HERE, IN THE MODEL, and deliberately left NOT EMITTING. What a
        model owns is what the unit is made of, and it has to stay safe to hand
        to a build ghost - so the burst sits still until something with a unit
        behind it restarts the emitter. See SparkAnimation3D, which is wired in
        the PREFAB and is the only thing that ever fires this.

        It carries its OWN flat material rather than one of the five roles.
        Those are the shaders that make a tower look like worked stone lit from
        within, and every one of them reads the surface it is on; a spark is
        two pixels of pure colour and wants none of it.

        CPUParticles3D rather than GPU, because the project renders with
        gl_compatibility where GPU particles are not dependable.
        """
        material = self.scene.sub("StandardMaterial3D", "M_%s" % name, [
            "shading_mode = 0",
            "transparency = 1",
            "albedo_color = %s" % c(colour),
        ])
        self._n += 1
        mesh = "SphereMesh_%d" % self._n
        self.scene.sub("SphereMesh", mesh, [
            "radius = %s" % num(radius * self.s),
            "height = %s" % num(radius * 2.0 * self.s),
            "radial_segments = 4",
            "rings = 2",
            'material = SubResource("%s")' % material,
        ])
        self.scene.node(name, "CPUParticles3D", parent, props=[
            "transform = %s" % t3(),
            "emitting = false",
            "one_shot = true",
            "explosiveness = 1.0",
            "amount = %d" % count,
            "lifetime = %s" % num(lifetime),
            'mesh = SubResource("%s")' % mesh,
            "emission_shape = 1",
            "emission_sphere_radius = %s" % num(spread * self.s),
            "direction = Vector3(0, 1, 0)",
            "spread = 180.0",
            "initial_velocity_min = %s" % num(velocity[0]),
            "initial_velocity_max = %s" % num(velocity[1]),
            "gravity = Vector3(0, %s, 0)" % num(gravity),
            "scale_amount_min = 0.5",
            "scale_amount_max = 1.2",
            "damping_min = 1.0",
            "damping_max = 3.0",
        ])

    def aura(self, name, parent, colour, count=16, radius=0.022, spread=0.24,
             lifetime=1.8, rise=(0.16, 0.34), drift=0.06, y=0.0):
        """A slow, continuous rise of lit motes off a unit.

        The opposite of sparks() in every way that matters, and the two are
        deliberately not one helper with a flag. Sparks are an EVENT - one
        explosive burst, fired by something that just happened, and off again.
        This is a STATE: it never stops, it is a tenth of the velocity, and it
        is authored so quiet that what a player reads is that the thing is
        giving something off rather than that something is happening to it.

        It exists because motion is the loudest signal a top down camera has,
        and on the elemental ladder it is what an Ultimate has instead of the
        turning metal halo the roster started with. See style.element_has_aura.

        `local_coords` is TRUE, which is not the default and is not decoration:
        a world space emitter throws its first frame's particles at whatever
        origin the model happened to be instantiated at before it was moved
        into place, so a tower spawns with a puff of its own aura back at the
        world origin. Local coordinates also mean the motes ride the model, and
        a tower does not move, so nothing is lost.

        The gradient fades in and back out, so a mote is never seen appearing
        or being deleted - which is what stops a slow emitter reading as
        flickering. It needs `vertex_color_use_as_albedo` on the material or
        CPUParticles3D's per particle colour goes nowhere.
        """
        material = self.scene.sub("StandardMaterial3D", "M_%s" % name, [
            "shading_mode = 0",
            "transparency = 1",
            "vertex_color_use_as_albedo = true",
            "albedo_color = %s" % c(colour),
        ])
        ramp = self.scene.sub("Gradient", "G_%s" % name, [
            "offsets = PackedFloat32Array(0, 0.2, 1)",
            "colors = PackedColorArray(1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 0)",
        ])
        self._n += 1
        mesh = "SphereMesh_%d" % self._n
        self.scene.sub("SphereMesh", mesh, [
            "radius = %s" % num(radius * self.s),
            "height = %s" % num(radius * 2.0 * self.s),
            "radial_segments = 4",
            "rings = 2",
            'material = SubResource("%s")' % material,
        ])
        self.scene.node(name, "CPUParticles3D", parent, props=[
            "transform = %s" % t3(y=y * self.h),
            "emitting = true",
            "amount = %d" % count,
            "lifetime = %s" % num(lifetime),
            "local_coords = true",
            'mesh = SubResource("%s")' % mesh,
            "emission_shape = 1",
            "emission_sphere_radius = %s" % num(spread * self.s),
            "direction = Vector3(0, 1, 0)",
            "spread = 20.0",
            "initial_velocity_min = %s" % num(rise[0]),
            "initial_velocity_max = %s" % num(rise[1]),
            "gravity = Vector3(0, %s, 0)" % num(drift),
            "scale_amount_min = 0.4",
            "scale_amount_max = 1.0",
            'color_ramp = SubResource("%s")' % ramp,
        ])

    # --- motion -----------------------------------------------------------
    #
    # Both attach to their PARENT, so they are written as a child of whatever
    # should move. Both animate on the render frame and opt out of physics
    # interpolation, which is why they are components rather than raw code.

    def spinner(self, name, parent, turns_per_second, axis="Vector3(0, 1, 0)"):
        self.scene.node(name, "Node", parent,
                        node_paths=["_spinner"],
                        script=self.scene.ext("Script", SPIN_SCRIPT),
                        props=['_spinner = NodePath("..")',
                               "turns_per_second = %s" % num(turns_per_second),
                               "axis = %s" % axis])

    def bobber(self, name, parent, height, cycles_per_second, phase=0.0):
        self.scene.node(name, "Node", parent,
                        node_paths=["_floater"],
                        script=self.scene.ext("Script", BOB_SCRIPT),
                        props=['_floater = NodePath("..")',
                               "height = %s" % num(height * self.h),
                               "cycles_per_second = %s" % num(cycles_per_second),
                               "phase = %s" % num(phase)])

    # --- output -----------------------------------------------------------

    def render(self):
        return self.scene.render("[gd_scene format=3]")
