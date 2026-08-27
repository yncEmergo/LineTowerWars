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

from tscn import Scene, t3, num

SPIN_SCRIPT = "res://Scripts/Components/SpinAnimation3D.gd"
BOB_SCRIPT = "res://Scripts/Components/BobAnimation3D.gd"


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
        self.body = self.scene.ext("Material", materials["body"])
        self.deep = self.scene.ext("Material", materials["deep"])
        self.pale = self.scene.ext("Material", materials["pale"])
        self.trim = self.scene.ext("Material", materials["trim"])
        self.glow = self.scene.ext("Material", materials["glow"])
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
            rx=0.0, ry=0.0, rz=0.0, shadow=True):
        """Places a mesh. Positions are in authored units and are scaled;
        rotations are radians and are not."""
        props = [
            "transform = %s" % t3(x * self.s, y * self.h, z * self.s, rx, ry, rz),
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
