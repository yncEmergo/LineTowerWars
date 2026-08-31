"""The technology discs' materials and model scenes.

The shortest models stage in the tool by a long way, and that is the design
rather than a gap: a disc has no model. It is a thing set into the ground, and
what a player sees is one flat quad running
Resources/Shaders/disc_ground.gdshader. So this file writes one material per
disc - which is the whole of what makes a Fire disc look different from an
Advanced Ice one - and one two-node scene to hang it on.

Read disc_style.py first. It holds the language; this holds the two files that
speak it.

THE CONTRACT A DISC MODEL MEETS, which the prefab wiring depends on:

    <root>          a Node3D running UnitModel.gd, exactly like a tower model
    Ground          a MeshInstance3D running BuildingFoundation.gd

`Ground` is the whole model, and it carries BuildingFoundation.gd for a real
reason rather than for tidiness. That script is what turns a patch into a
GHOST when a build order is being aimed - and it writes its tint into a
`preview_tint` uniform, which disc_ground.gdshader declares under exactly that
name. So a disc previews green and red like everything else in the game
without one line being written for it.

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
SHADER = "res://Resources/Shaders/disc_ground.gdshader"
UNIT_MODEL_SCRIPT = "res://Scripts/Units/UnitModel.gd"
FOUNDATION_SCRIPT = "res://Scripts/Units/BuildingFoundation.gd"

# Side of the quad the disc is drawn on, in cells. Wider than the one cell it
# occupies for the same reason the tower foundation's is: the plate's border is
# soft and slightly chewed, and a quad cut exactly to the footprint would clip
# it into a hard square.
QUAD_SIZE = 1.5

# How far off the floor the quad sits. The same height a tower foundation
# takes, because the two are the same layer of the world and neither is ever on
# the same cell as the other. See BuildGrid.GROUND_OFFSET for the three heights
# this one sits in the middle of.
QUAD_HEIGHT = 0.01

# Draw order, matching the tower foundation: under the build grid so its lines
# stay readable across a disc, over the opaque zone quads.
RENDER_PRIORITY = -1


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    io.open(path, "w", encoding="utf-8", newline="\n").write(text)


def material_path(key):
    return "res://%s/%s_ground.tres" % (MAT_OUT, key)


def model_path(key):
    return "res://%s/%s_model.tscn" % (SCENE_OUT, key)


def pascal(key):
    return "".join(part.capitalize() for part in key.split("_"))


def _material(row):
    """One disc's material: the shared plate, then its own glyph.

    The plate half is IDENTICAL on all thirty-one and is written out every time
    rather than being one shared material with the glyph overridden per disc.
    That is not a choice - the project renders with gl_compatibility, where
    per-instance shader uniforms silently do nothing at all, so a per-disc
    value has to be a per-disc material. It is the same reason there is one
    energy material per tower line and tier. See style.py.
    """
    plate = ds.DISC_PLATE
    grooves = ds.DISC_GROOVES
    tier = row["tier"]

    params = [
        ("plate_color", c(plate["plate"])),
        ("plate_dark_color", c(plate["plate_dark"])),
        ("groove_color", c(plate["groove"])),
        ("rim_color", c(plate["rim"])),
        ("radius", num(grooves["radius"])),
        ("ring_count", num(float(grooves["ring_count"]))),
        ("ring_width", num(grooves["ring_width"])),
        ("spoke_count", num(float(grooves["spoke_count"]))),
        ("spoke_width", num(grooves["spoke_width"])),
        ("groove_strength", num(grooves["strength"])),
        ("glyph_radius", num(ds.glyph_radius(tier))),
        ("glyph_emission", num(ds.glyph_emission(tier))),
        ("glyph_edge_width", num(ds.DISC_GLYPH_EDGE_WIDTH)),
        ("spin_speed", num(ds.glyph_spin(tier))),
        ("opacity", num(ds.DISC_PLATE_OPACITY)),
        ("glyph_opacity", num(ds.DISC_GLYPH_OPACITY)),
    ]

    # The inactive disc has no element, so it is written with no glyph colour
    # at all rather than with a grey one. glyph_radius is 0 on it and nothing
    # reads the colour, but authoring a colour for a thing that does not exist
    # is how a grey glyph eventually appears on somebody's screen.
    if row["element"] is not None:
        glow, rim = ds.glyph_colors(row["element"])
        params.append(("glyph_color", c(glow)))
        params.append(("glyph_edge_color", c(rim)))
        params.append(("glyph_sides", num(float(ds.glyph_sides(row["element"])))))

    lines = [
        '[gd_resource type="ShaderMaterial" format=3]',
        "",
        '[ext_resource type="Shader" path="%s" id="1_disc_ground"]' % SHADER,
        "",
        "[resource]",
        "render_priority = %d" % RENDER_PRIORITY,
        'shader = ExtResource("1_disc_ground")',
    ]
    for key, value in params:
        lines.append("shader_parameter/%s = %s" % (key, value))
    return "\n".join(lines) + "\n"


def _model(row):
    """One disc's model scene: the UnitModel root and the ground quad."""
    key = row["key"]
    s = Scene()
    model_script = s.ext("Script", UNIT_MODEL_SCRIPT)
    ground_script = s.ext("Script", FOUNDATION_SCRIPT)
    material = s.ext("Material", material_path(key))

    s.sub("PlaneMesh", "Ground", [
        'material = ExtResource("%s")' % material,
        "size = Vector2(%s, %s)" % (num(QUAD_SIZE), num(QUAD_SIZE)),
    ])

    s.node(pascal(key) + "Model", "Node3D", ".", script=model_script)
    s.node("Ground", "MeshInstance3D", ".", script=ground_script, props=[
        "transform = %s" % t3(y=QUAD_HEIGHT),
        # A flat decal lying on the floor has no business casting one.
        "cast_shadow = 0",
        'mesh = SubResource("Ground")',
    ])
    return s.render("[gd_scene format=3]")


def generate():
    """Writes every disc material and model, and hands back the one number the
    content stage needs from here.

    A tower model reports its HEIGHT, which sizes the prefab's health bar and
    its click box. A disc is flat, so the height it reports is the quad's own
    offset and nothing else - which is exactly right for the click box, and
    means nothing at all for the health bar because a disc is invulnerable and
    never grows one.
    """
    heights = {}
    for row in dr.disc_rows():
        write(material_path(row["key"]).replace("res://", ""), _material(row))
        write(model_path(row["key"]).replace("res://", ""), _model(row))
        heights[row["key"]] = QUAD_HEIGHT
    print("wrote %d disc materials and models" % len(heights))
    return heights
