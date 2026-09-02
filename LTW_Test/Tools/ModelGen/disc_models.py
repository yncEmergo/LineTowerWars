"""The technology discs' materials and model scenes.

The shortest models stage in the tool by a long way, and that is the design
rather than a gap: a disc has no model. It is drawn as three flat layers, and
this file writes the two of them that are not already in the game.

Read disc_style.py first. It holds the language; this holds the files that
speak it.

THE CONTRACT A DISC MODEL MEETS, which the prefab wiring depends on:

    <root>          a Node3D running UnitModel.gd, exactly like a tower model
    Base            the shared SQUARE foundation, tower_foundation.tscn
    Plate           the round mechanism plate, one material for all thirty-one
    Glyph           the element circle. ABSENT on the inactive disc

`Base` is instanced rather than rebuilt, so a disc claims its square with the
byte-identical patch a tower claims one with. It carries BuildingFoundation.gd
by being that scene, which is what turns it into a GHOST while a build order is
being aimed; the other two layers are ordinary meshes and `UnitModel` swaps
them for the flat ghost material on its own.

`Glyph` IS A SEPARATE NODE FOR A REASON, and it is not tidiness. The tier is
the SIZE of that circle, and an upgrade has to grow it while the plate under it
stays exactly where it was - so the tier is the mesh's own size and the growth
is that node's scale. A radius uniform could not do it: the material is shared
by every disc of a type, so animating it would grow all of them, and the
project renders with gl_compatibility where per-instance uniforms silently do
nothing at all. See Disc._apply_visual_height.

WHY THERE ARE ONLY ELEVEN MATERIALS and not thirty-one. Nothing about the plate
varies, so it is one file; and every tier of an element is the same circle at a
different SIZE, so the glyph is one file per element. The first cut wrote one
material per disc because the tier lived in a uniform, and moving the tier onto
the mesh took twenty of them away.

There is no Turret and no Muzzle. A tower model has both even when it has
nothing to aim, because one wiring across thirty towers beats nine special
cases - but a disc cannot attack at all, its prefab carries no AttackComponent,
and adding two nodes for something that will never be read would be inventing a
capability the roster does not have.
"""

import io
import os

import disc_roster as dr
import disc_style as ds
from tscn import Scene, c, num, t3

MAT_OUT = "Resources/Materials/Discs"
SCENE_OUT = "Scenes/Units/Models/Discs"
PLATE_SHADER = "res://Resources/Shaders/disc_plate.gdshader"
GLYPH_SHADER = "res://Resources/Shaders/disc_glyph.gdshader"
UNIT_MODEL_SCRIPT = "res://Scripts/Units/UnitModel.gd"
FOUNDATION = "res://Scenes/Units/Models/tower_foundation.tscn"

PLATE_MATERIAL = "res://%s/disc_plate.tres" % MAT_OUT

# How far off the floor each layer sits, low to high.
#
# All three are under BuildGrid.GROUND_OFFSET, so the grid lines stay readable
# across a disc - and far enough apart not to z-fight, which two transparent
# quads at one height do visibly and constantly.
#
# The foundation carries 0.01 inside its own scene and is not re-set here, so
# a disc's patch sits at exactly the height a tower's does.
PLATE_HEIGHT = 0.013
GLYPH_HEIGHT = 0.016

# Draw order. The foundation is at -1 like every tower's; these two sit above
# it and below the build grid.
PLATE_PRIORITY = 0
GLYPH_PRIORITY = 1


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    io.open(path, "w", encoding="utf-8", newline="\n").write(text)


def glyph_material_path(element):
    return "res://%s/%s_disc_glyph.tres" % (MAT_OUT, element)


def model_path(key):
    return "res://%s/%s_model.tscn" % (SCENE_OUT, key)


def pascal(key):
    return "".join(part.capitalize() for part in key.split("_"))


def _material(shader, priority, params):
    lines = [
        '[gd_resource type="ShaderMaterial" format=3]',
        "",
        '[ext_resource type="Shader" path="%s" id="1_shader"]' % shader,
        "",
        "[resource]",
        "render_priority = %d" % priority,
        'shader = ExtResource("1_shader")',
    ]
    for key, value in params:
        lines.append("shader_parameter/%s = %s" % (key, value))
    return "\n".join(lines) + "\n"


def _plate_material():
    """The one plate material, shared by every disc in the game."""
    plate = ds.DISC_PLATE
    grooves = ds.DISC_GROOVES
    return _material(PLATE_SHADER, PLATE_PRIORITY, [
        ("plate_color", c(plate["plate"])),
        ("plate_dark_color", c(plate["plate_dark"])),
        ("groove_color", c(plate["groove"])),
        ("edge_color", c(plate["edge"])),
        # The quad is cut to the plate's own diameter, so the shape fills it.
        ("radius", num(0.94)),
        ("edge_width", num(grooves["edge_width"])),
        ("ring_count", num(float(grooves["ring_count"]))),
        ("ring_width", num(grooves["ring_width"])),
        ("spoke_count", num(float(grooves["spoke_count"]))),
        ("spoke_width", num(grooves["spoke_width"])),
        ("groove_strength", num(grooves["strength"])),
        ("opacity", num(plate["opacity"])),
    ])


def _glyph_material(element):
    """One element's circle. The colour is the whole of what it says."""
    glow, rim = ds.glyph_colors(element)
    return _material(GLYPH_SHADER, GLYPH_PRIORITY, [
        ("glyph_color", c(glow)),
        ("edge_color", c(rim)),
        ("rim_width", num(ds.DISC_GLYPH_RIM)),
        ("emission_strength", num(ds.DISC_GLYPH_EMISSION)),
        ("opacity", num(ds.DISC_GLYPH_OPACITY)),
    ])


def _model(row):
    """One disc's model scene: the three layers, or two on the inactive one."""
    s = Scene()
    model_script = s.ext("Script", UNIT_MODEL_SCRIPT)
    foundation = s.ext("PackedScene", FOUNDATION)
    plate_material = s.ext("Material", PLATE_MATERIAL)

    s.sub("PlaneMesh", "Plate", [
        'material = ExtResource("%s")' % plate_material,
        "size = Vector2(%s, %s)" % (num(ds.PLATE_DIAMETER), num(ds.PLATE_DIAMETER)),
    ])

    s.node(pascal(row["key"]) + "Model", "Node3D", ".", script=model_script)
    s.node("Base", None, ".", instance=foundation)
    s.node("Plate", "MeshInstance3D", ".", props=[
        "transform = %s" % t3(y=PLATE_HEIGHT),
        # Flat decals lying on the floor have no business casting one.
        "cast_shadow = 0",
        'mesh = SubResource("Plate")',
    ])

    # The inactive disc gets NO glyph node at all rather than a zero sized one.
    # It has no element and does nothing, and an empty mesh is a thing that
    # eventually gets drawn by accident.
    diameter = ds.glyph_diameter(row["tier"])
    if row["element"] is not None and diameter > 0.0:
        glyph_material = s.ext("Material", glyph_material_path(row["element"]))
        s.sub("PlaneMesh", "Glyph", [
            'material = ExtResource("%s")' % glyph_material,
            "size = Vector2(%s, %s)" % (num(diameter), num(diameter)),
        ])
        s.node("Glyph", "MeshInstance3D", ".", props=[
            "transform = %s" % t3(y=GLYPH_HEIGHT),
            "cast_shadow = 0",
            'mesh = SubResource("Glyph")',
        ])

    return s.render("[gd_scene format=3]")


def generate():
    """Writes the plate material, the ten element materials and every disc
    model, and hands back the one number the content stage needs from here.

    A tower model reports its HEIGHT, which sizes the prefab's health bar and
    its click box. A disc is flat, so what it reports is the top layer's own
    offset - exactly right for the click box, and meaningless for the health
    bar because a disc is invulnerable and never grows one.
    """
    write(PLATE_MATERIAL.replace("res://", ""), _plate_material())
    for element in dr.ELEMENT_ORDER:
        write(glyph_material_path(element).replace("res://", ""),
              _glyph_material(element))

    heights = {}
    for row in dr.disc_rows():
        write(model_path(row["key"]).replace("res://", ""), _model(row))
        heights[row["key"]] = GLYPH_HEIGHT
    print("wrote %d disc models, 1 plate material, %d element materials"
          % (len(heights), len(dr.ELEMENT_ORDER)))
    return heights
