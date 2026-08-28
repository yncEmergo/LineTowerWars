"""The creep PREFABS, and nothing else.

Deliberately a much smaller stage than tower_content.py, and the difference is
worth stating because it is the thing most likely to be "fixed" by somebody
later: this file does NOT write creep stats, abilities or passives.

Those live in `Resources/UnitStats/Creeps/*.tres` and
`Resources/Abilities/Passives/*.tres`, they were authored by hand when tier 1
was implemented, and unit_data.md 8.1 makes them the authority. A generator
that rewrote them would have to hold every number in 6.2 as well as every
passive, every pack entry and every unlock time - and the first time the two
disagreed, the file a human edited would lose. Towers are generated because
thirty of them come out of one balance table; creeps are not because thirteen
of them come out of thirteen hand-made decisions.

So what a prefab does here is assemble what already exists:

    the stats resource, by path, exactly as it is
    the MODEL, from creep_models
    the walk, which needs the unit and so cannot live in the model
    the strike, on the one creep in tier 1 that attacks

The one thing this stage DOES decide is the three numbers a prefab carries that
are measured off the model rather than authored - the health bar's height, the
click box's radius and its centre - which is exactly why it runs after the
models and takes their dimensions as an argument.
"""

import io
import os

import creep_roster as cr
from tscn import Scene, t3, num

PREFAB_DIR = "Scenes/Units/Creeps"
STATS_DIR = "Resources/UnitStats/Creeps"
MODEL_DIR = "Scenes/Units/Models/Creeps"

S_CREEP = "res://Scripts/Units/Creep.gd"
S_ATTACK_COMPONENT = "res://Scripts/Combat/AttackComponent.gd"
S_WALK = "res://Scripts/Components/WalkAnimation3D.gd"
S_STRIKE = "res://Scripts/Components/StrikeAnimation3D.gd"

# The same ring every selectable thing in the game wears. Shared rather than
# copied, so the one colour a player learns to read has one home - it lives
# under Materials/Towers because that is where the tower stage wrote it first,
# and moving it would be churn for nothing.
RING_MATERIAL = "res://Resources/Materials/Towers/selection_ring.tres"

# How far above the top of the model its health bar floats, in world units.
# Smaller than a tower's, because a creep is smaller and a bar hung as high as
# a tower's would read as belonging to whatever is behind it.
BAR_CLEARANCE = 0.18

# How much wider than the model the selection ring is drawn, and how thick.
RING_MARGIN = 1.12
RING_THICKNESS = 0.055


def pascal(key):
    return "".join(part.capitalize() for part in key.split("_"))


def stats_path(key):
    return "res://%s/%s_stats.tres" % (STATS_DIR, key)


def prefab_path(key):
    return "res://%s/%s.tscn" % (PREFAB_DIR, key)


def model_path(key):
    return "res://%s/%s_model.tscn" % (MODEL_DIR, key)


def write(res_path, text):
    path = res_path.replace("res://", "")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    io.open(path, "w", encoding="utf-8", newline="\n").write(text)


def _paths(names):
    """An exported Array[Node3D], as Godot stores one."""
    return "[%s]" % ", ".join('NodePath("../Visual/%s")' % n for n in names)


def gen_prefab(key, display, family, built):
    height = built["height"]
    radius = built["radius"]

    s = Scene()
    creep = s.ext("Script", S_CREEP)
    stats = s.ext("Resource", stats_path(key))
    model = s.ext("PackedScene", model_path(key))
    ring_mat = s.ext("Material", RING_MATERIAL)

    inner = round(radius * RING_MARGIN, 4)
    s.sub("TorusMesh", "SelectionRing", [
        "inner_radius = %s" % num(inner),
        "outer_radius = %s" % num(round(inner + RING_THICKNESS, 4)),
        "rings = 20",
        "ring_segments = 4",
        'material = ExtResource("%s")' % ring_mat,
    ])

    s.node(pascal(key), "Node3D", ".",
           node_paths=["_selection_ring"],
           script=creep,
           props=[
               'stats = ExtResource("%s")' % stats,
               '_selection_ring = NodePath("SelectionRing")',
               "health_bar_height = %s" % num(round(height + BAR_CLEARANCE, 3)),
               "select_radius = %s" % num(round(radius * RING_MARGIN, 3)),
               "select_height = %s" % num(round(height * 0.5, 3)),
           ])
    s.node("Visual", None, ".", instance=model)

    # A flyer's ring sits on the GROUND rather than around the creep, which is
    # where the creep itself is not. That is the same answer the shadow disc
    # gives and for the same reason: what a player needs to point at is the
    # spot on the floor the thing is over.
    ring_y = 0.035
    if family == cr.AIR:
        ring_y = -cr.FLY_HEIGHT + 0.035
    s.node("SelectionRing", "MeshInstance3D", ".", props=[
        "transform = %s" % t3(y=ring_y),
        "visible = false",
        "cast_shadow = 0",
        'mesh = SubResource("SelectionRing")',
    ])

    if family == cr.ATTACKER:
        # An attacker creep is an ordinary attacker: the same component every
        # tower uses, wired the same way. It aims nothing and fires nothing
        # visible, so it has neither a muzzle nor a turret head.
        s.node("Attack", "Node", ".", node_paths=["_unit"],
               script=s.ext("Script", S_ATTACK_COMPONENT),
               props=['_unit = NodePath("..")'])

    _add_walk(s, built)
    if built["strike"]:
        s.node("Strike", "Node", ".", node_paths=["_unit", "_swing"],
               script=s.ext("Script", S_STRIKE),
               props=['_unit = NodePath("..")',
                      '_swing = NodePath("../Visual/%s")' % built["strike"]])

    write(prefab_path(key), s.render("[gd_scene format=3]"))


## The walk lives in the PREFAB rather than in the model, for the reason every
## other animation component does: it needs the unit, and a model has none -
## the same model scene is what a portrait and a baked icon copy their meshes
## out of, and neither of those is walking anywhere.
def _add_walk(s, built):
    if not built["legs"]:
        return
    props = ['_unit = NodePath("..")',
             '_body = NodePath("../Visual/Gait")',
             "_legs = %s" % _paths(built["legs"]),
             "_arms = %s" % _paths(built["arms"]),
             "leg_phases = PackedFloat32Array(%s)"
             % ", ".join(num(p) for p in built["phases"]),
             "stride_length = %s" % num(built["stride"])]
    if built["hover"] > 0.0:
        props.append("hover_cycles_per_second = %s" % num(built["hover"]))
        # A hovering creep has no footfalls, so the parts of the gait that
        # stand for one are turned off rather than left to run on a clock they
        # have nothing to do with.
        props.append("bob_height = %s" % num(built["height"] * 0.09))
        props.append("swing_degrees = 9")
        props.append("arm_swing_degrees = 5")
        props.append("lean_degrees = 0")
        props.append("roll_degrees = 3")
    else:
        props.append("bob_height = %s" % num(round(built["height"] * 0.035, 4)))
    s.node("Walk", "Node", ".",
           node_paths=["_unit", "_body", "_legs", "_arms"],
           script=s.ext("Script", S_WALK),
           props=props)


def generate(built):
    for key, display, _plan, _gold, family, _boss in cr.CREEPS:
        gen_prefab(key, display, family, built[key])
    print("wrote %d creep prefabs" % len(cr.CREEPS))
