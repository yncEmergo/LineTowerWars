import io, os
from tscn import Scene, t3, c

"""Review scenes, for looking at a whole roster in one frame.

OPT IN, and the output is THROWAWAY: `generate.py --showcase` writes into
Scenes/Dev, which CLAUDE.md says is scaffolding and gets deleted when the work
is done. The generator is kept because the review is worth repeating every time
the roster or the style changes, and rebuilding the scenes by hand each time is
how a review stops happening.

It lays a line out as the shape of its own upgrade tree - the two cheap tiers
on the back row, then one row per branch - so one frame answers both questions
at once: does a branch read as one family across its four tiers, and do the two
branches of a line read as different things.

Every tower is turned side on, because each branch's tell points down its own
-Z: a barrel, a mortar tube, a hammer, a missile rack. Head on they all hide
behind their own bodies.

To look at the result: run the scene rather than screenshotting the editor
viewport. The editor's cinematic capture renders these unlit.
"""

LINES = {
    "archer": [
        ["lesser_archer", "archer"],
        ["lesser_watch_tower", "watch_tower", "greater_watch_tower",
         "ultimate_watch_tower"],
        ["lesser_cannon", "cannon", "greater_cannon", "ultimate_cannon"],
    ],
    "cutter": [
        ["lesser_cutter", "cutter"],
        ["lesser_carver", "carver", "greater_carver", "ultimate_carver"],
        ["lesser_crusher", "crusher", "greater_crusher", "ultimate_crusher"],
    ],
    "sentry": [
        ["lesser_sentry", "sentry"],
        ["lesser_defender", "defender", "greater_defender", "ultimate_defender"],
        ["lesser_turret", "turret", "greater_turret", "ultimate_turret"],
    ],
}

STEP_X = 1.5
STEP_Z = 1.9
FACING = 1.92


def build(rows, camera, folder="Towers", facing=FACING, step=(STEP_X, STEP_Z),
          lift=None):
    s = Scene()
    s.node("TowerShowcase", "Node3D", ".")

    ground_mat = s.sub("StandardMaterial3D", "M_ground", [
        "albedo_color = %s" % c((0.30, 0.33, 0.30)),
        "roughness = 1.0",
    ])
    ground = s.sub("PlaneMesh", "Ground", [
        "size = Vector2(30, 20)",
        'material = SubResource("%s")' % ground_mat,
    ])
    s.node("Ground", "MeshInstance3D", ".", props=[
        "transform = %s" % t3(y=-0.01),
        'mesh = SubResource("%s")' % ground,
    ])

    width = max(len(r) for r in rows)
    for row, keys in enumerate(rows):
        z = (row - (len(rows) - 1) * 0.5) * step[1]
        for column, key in enumerate(keys):
            x = (column - (width - 1) * 0.5) * step[0]
            path = "res://Scenes/Units/Models/%s/%s_model.tscn" % (folder, key)
            # A flyer's model origin IS its cruising height, so a review scene
            # that puts one on the floor buries its own shadow disc.
            y = 0.0 if lift is None else lift.get(key, 0.0)
            s.node("".join(p.capitalize() for p in key.split("_")), None, ".",
                   instance=s.ext("PackedScene", path),
                   props=["transform = %s" % t3(x=x, y=y, z=z, ry=facing)])

    # A sun roughly where the match camera's is, so what this shows is what the
    # game shows rather than a studio render.
    s.node("Sun", "DirectionalLight3D", ".", props=[
        "transform = %s" % t3(y=6.0, rx=-0.95, ry=0.6),
        "light_energy = 1.35",
        "shadow_enabled = true",
    ])
    s.node("Fill", "DirectionalLight3D", ".", props=[
        "transform = %s" % t3(y=6.0, rx=-0.5, ry=3.4),
        "light_energy = 0.45",
        "light_color = %s" % c((0.6, 0.7, 0.9)),
    ])

    env = s.sub("Environment", "Env", [
        "background_mode = 1",
        "background_color = Color(0.09, 0.10, 0.12, 1)",
        "ambient_light_source = 2",
        "ambient_light_color = Color(0.42, 0.48, 0.58, 1)",
        "ambient_light_energy = 0.7",
    ])
    s.node("WorldEnvironment", "WorldEnvironment", ".",
           props=['environment = SubResource("%s")' % env])

    s.node("Camera3D", "Camera3D", ".", props=[
        "transform = %s" % t3(y=camera[0], z=camera[1], rx=camera[2]),
        "current = true",
        "fov = %s" % camera[3],
        "near = 0.05",
    ])
    return s


def element_rows(element):
    """One element as its own upgrade tree: the shared base pair on the back
    row, then one row per path."""
    import element_roster as er
    entry = er.ELEMENTS[element]
    rows = [[er.key_of(element, row[0]) for row in entry["base"]]]
    for path in entry["paths"]:
        rows.append([er.key_of(element, "%s %s" % (er.TIER_PREFIX[i], path["name"]))
                     for i in range(len(path["tiers"]))])
    return rows


def _grid(keys, per_row):
    rows = []
    for index in range(0, len(keys), per_row):
        rows.append(keys[index:index + per_row])
    return rows


def generate_elements():
    """One scene per element, plus one holding every path at 4,000g and one
    holding every Ultimate - which are the two that actually answer "can these
    be told apart"."""
    import element_roster as er
    lf = "\n"
    for element in er.ELEMENT_ORDER:
        text = build(element_rows(element),
                     (3.6, 5.4, -0.54, 46)).render("[gd_scene format=3]")
        io.open("Scenes/Dev/showcase_%s.tscn" % element, "w",
                encoding="utf-8", newline=lf).write(text)

    for prefix, name in (("Lesser", "elements"), ("Ultimate", "ultimates")):
        keys = []
        if prefix == "Lesser":
            keys.append("elemental_core")
        for element in er.ELEMENT_ORDER:
            for path in er.ELEMENTS[element]["paths"]:
                keys.append(er.key_of(element, "%s %s" % (prefix, path["name"])))
        text = build(_grid(keys, 5),
                     (7.4, 8.8, -0.68, 52)).render("[gd_scene format=3]")
        io.open("Scenes/Dev/showcase_%s.tscn" % name, "w",
                encoding="utf-8", newline=lf).write(text)
    return len(er.ELEMENT_ORDER) + 2


def generate_creeps():
    """The creep roster, twice.

    Once from the MATCH CAMERA'S OWN ANGLE, because that is the only view that
    answers the question the roster exists to answer - can a player tell these
    apart from up there - and once side on, because that is the view that shows
    whether a silhouette is doing any work at all.

    Laid out in unlock order, which is ascending cost, which is the ladder. So
    reading either scene left to right is reading the strength ladder climb.
    """
    import creep_roster as cr
    lf = chr(10)
    keys = cr.keys()
    lift = dict((k, cr.FLY_HEIGHT) for k in keys if cr.is_flying(k))
    # The match camera's own pitch, from directly over the middle of the grid.
    text = build([keys[0:5], keys[5:9], keys[9:13]],
                 (4.23, 1.54, -1.222, 40), "Creeps", 3.1416,
                 (0.82, 0.9), lift).render("[gd_scene format=3]")
    io.open("Scenes/Dev/creep_showcase.tscn", "w",
            encoding="utf-8", newline=lf).write(text)
    # Side on, for the silhouettes. Two rows so each one is big enough to
    # argue with.
    text = build([keys[0:5], keys[5:9], keys[9:13]], (1.95, 4.3, -0.36, 34),
                 "Creeps", 1.5708, (0.78, 1.45),
                 lift).render("[gd_scene format=3]")
    io.open("Scenes/Dev/creep_lineup.tscn", "w",
            encoding="utf-8", newline=lf).write(text)
    return 2


def generate():
    os.makedirs("Scenes/Dev", exist_ok=True)
    lf = "\n"
    for line, rows in LINES.items():
        text = build(rows, (3.5, 5.2, -0.52, 46)).render("[gd_scene format=3]")
        io.open("Scenes/Dev/showcase_%s.tscn" % line, "w",
                encoding="utf-8", newline=lf).write(text)

    every = []
    for line in ("archer", "cutter", "sentry"):
        every.extend(LINES[line])
    text = build(every, (6.6, 8.0, -0.66, 50)).render("[gd_scene format=3]")
    io.open("Scenes/Dev/tower_showcase.tscn", "w",
            encoding="utf-8", newline=lf).write(text)
    print("wrote %d showcase scenes"
          % (4 + generate_elements() + generate_creeps()))
