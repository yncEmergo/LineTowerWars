import io, os
import roster as td
import style as ts
from tscn import Scene, t3, c, num

STATS_DIR = "Resources/UnitStats/Towers"
ABILITY_DIR = "Resources/Abilities/Towers"
PREFAB_DIR = "Scenes/Units/Towers"

S_BUILDING_STATS = "res://Scripts/Config/BuildingStats.gd"
S_UNIT_ABILITY = "res://Scripts/Abilities/UnitAbility.gd"
S_ATTACK_STATS = "res://Scripts/Config/AttackStats.gd"
S_ATTACK_EFFECT = "res://Scripts/Combat/AttackEffect.gd"
S_SPLASH = "res://Scripts/Combat/SplashEffect.gd"
S_PROJECTILE_DELIVERY = "res://Scripts/Combat/ProjectileDelivery.gd"
S_INSTANT_DELIVERY = "res://Scripts/Combat/InstantDelivery.gd"
S_BUILD_TOWER = "res://Scripts/Abilities/BuildTowerAbility.gd"
S_UPGRADE_TOWER = "res://Scripts/Abilities/UpgradeTowerAbility.gd"
S_BUILDING = "res://Scripts/Units/Building.gd"
S_ATTACK_COMPONENT = "res://Scripts/Combat/AttackComponent.gd"
S_RECOIL = "res://Scripts/Components/RecoilAnimation3D.gd"
S_SLAM = "res://Scripts/Components/SlamAnimation3D.gd"
S_SPIN = "res://Scripts/Components/SpinAnimation3D.gd"
S_SELF_SPLASH = "res://Scripts/Combat/SelfSplashEffect.gd"

A_ATTACK = "res://Resources/Abilities/attack_ability.tres"
A_SELL = "res://Resources/Abilities/sell_ability.tres"
# The one key on the builder's card that is not a square. See HotkeyAction:
# Build means the same thing on every card that has it, so it is allowed a key
# of its own that the player may rebind.
A_HOTKEY_BUILD = "res://Resources/Config/Hotkeys/build_hotkey.tres"
A_CANCEL_BUILD = "res://Resources/Abilities/cancel_build_ability.tres"
A_CANCEL_SELL = "res://Resources/Abilities/cancel_sell_ability.tres"
A_CANCEL_UPGRADE = "res://Resources/Abilities/cancel_upgrade_ability.tres"
A_PRIORITIZE = "res://Resources/Abilities/prioritize_ability.tres"
# Reading tool rather than an order: it draws what the tower reaches and
# never leaves the machine. On EVERY tower, which is why it is here rather
# than behind a condition - the same square and the same key everywhere.
A_SHOW_RANGES = "res://Resources/Abilities/show_ranges_ability.tres"

RING_MATERIAL = "res://Resources/Materials/Towers/selection_ring.tres"
# Placeholder icons, baked from the models by Scenes/Tools/icon_gen_3d.tscn.
# Named after the tower's display name, which is the key - see 2DArt/Icons.
ICONS = "res://2DArt/Icons"
# Action icons, drawn by Tools/IconGen. An ability that is not ABOUT a unit -
# Build, Move, Cancel - has no model to bake a picture from and takes one of
# these instead. Always present, so no has_icon() dance around it.
UI_ICONS = "res://2DArt/UI/Icons"

BY_KEY = td.by_key()
TYPE_IDS = td.unit_type_ids()
UPGRADE_IDS = td.upgrade_ability_ids()


def stats_path(key):
    return "res://%s/%s_stats.tres" % (STATS_DIR, key)


def prefab_path(key):
    return "res://%s/%s.tscn" % (PREFAB_DIR, key)


def model_path(key):
    return "res://Scenes/Units/Models/Towers/%s_model.tscn" % key


def icon_path(key):
    return "%s/%s.png" % (ICONS, key)


def action_icon_path(name):
    return "%s/ability_%s.png" % (UI_ICONS, name)


def upgrade_ability_path(source, target):
    return "res://%s/upgrade_%s_to_%s_ability.tres" % (ABILITY_DIR, source, target)


def build_ability_path(key):
    return "res://%s/build_%s_ability.tres" % (ABILITY_DIR, key)


def pascal(key):
    return "".join(part.capitalize() for part in key.split("_"))


def write(res_path, text):
    path = res_path.replace("res://", "")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    io.open(path, "w", encoding="utf-8", newline="\n").write(text)


# --- stats -----------------------------------------------------------------

def gen_stats(row, heights):
    (key, display, line, branch, _t, gold, total, dtype, dmin, dmax,
     cooldown, rng, splash, targets) = row
    ti = ts.PRICE_TIERS.index(gold)
    health, armor = td.TIER_BODY[gold]
    kind, projectile, speed, arc = td.DELIVERY[branch]
    impact = td.IMPACT.get(branch, "")

    s = Scene()
    stats_script = s.ext("Script", S_BUILDING_STATS)
    ability_script = s.ext("Script", S_UNIT_ABILITY)
    attack_script = s.ext("Script", S_ATTACK_STATS)

    # --- delivery
    if kind == "projectile":
        delivery_script = s.ext("Script", S_PROJECTILE_DELIVERY)
        delivery_lines = [
            'script = ExtResource("%s")' % delivery_script,
            'projectile_scene_path = "%s"' % projectile,
            "speed = %s" % num(speed),
        ]
        if arc:
            delivery_lines.append("arc_height = %s" % num(arc))
    else:
        delivery_script = s.ext("Script", S_INSTANT_DELIVERY)
        delivery_lines = ['script = ExtResource("%s")' % delivery_script]
    if impact:
        delivery_lines.append('impact_scene_path = "%s"' % impact)
    s.sub("Resource", "Delivery", delivery_lines)

    # --- effects
    effect_names = []
    if splash:
        effect_script = s.ext("Script", S_ATTACK_EFFECT)
        # Which SCRIPT the splash carries is the whole difference between a
        # blast measured from the creep and one measured from the tower, which
        # is why it is a separate effect rather than a flag - see
        # Scripts/Combat/SelfSplashEffect.gd.
        centred_on_self = branch in td.SELF_SPLASH_BRANCHES
        splash_script = s.ext(
            "Script", S_SELF_SPLASH if centred_on_self else S_SPLASH)
        s.sub("Resource", "Splash", [
            'script = ExtResource("%s")' % splash_script,
            "radius = %s" % num(td.cells(splash)),
        ])
        effect_names.append("Splash")

    # --- the attack
    attack_lines = ['script = ExtResource("%s")' % attack_script]
    attack_lines.append("damage_min = %d" % dmin)
    attack_lines.append("damage_max = %d" % dmax)
    attack_lines.append("damage_type = %d" % dtype)
    if splash:
        # Any splash is area damage by definition, and the attack says so as
        # well so the primary hit counts too. See game_rules.md.
        attack_lines.append("is_aoe_damage = true")
    attack_lines.append("attacks_per_second = %s" % num(td.aps(cooldown)))
    windup = td.WINDUP.get(branch, 0.0)
    if windup:
        attack_lines.append("windup_seconds = %s" % num(windup))
    attack_lines.append("attack_range = %s" % num(td.cells(rng)))
    attack_lines.append("target_types = %d" % targets)
    attack_lines.append('delivery = SubResource("Delivery")')
    if effect_names:
        attack_lines.append("effects = Array[ExtResource(\"%s\")]([%s])" % (
            effect_script, ", ".join('SubResource("%s")' % n for n in effect_names)))
    s.sub("Resource", "Attack", attack_lines)

    # --- the command card
    card = []
    for index, target in enumerate(td.UPGRADES.get(key, [])):
        card.append(s.ext("Resource", upgrade_ability_path(key, target)))
    card.append(s.ext("Resource", A_ATTACK))
    can_choose = targets == td.BOTH
    if can_choose:
        card.append(s.ext("Resource", A_PRIORITIZE))
    card.append(s.ext("Resource", A_SELL))
    card.append(s.ext("Resource", A_SHOW_RANGES))

    cancel_build = s.ext("Resource", A_CANCEL_BUILD)
    cancel_sell = s.ext("Resource", A_CANCEL_SELL)
    cancel_upgrade = s.ext("Resource", A_CANCEL_UPGRADE)

    icon = s.ext("Texture2D", icon_path(key))
    props = [
        "unit_type_id = %d" % TYPE_IDS[key],
        'display_name = "%s"' % display,
        'icon = ExtResource("%s")' % icon,
        "max_health = %d" % health,
        # Fortified on every tower, whatever its damage type. unit_data.md 1.4.
        "armor_type = 5",
        "armor = %d" % armor,
        'attack = SubResource("Attack")',
        "abilities = Array[ExtResource(\"%s\")]([%s])" % (
            ability_script, ", ".join('ExtResource("%s")' % r for r in card)),
        'scene_path = "%s"' % prefab_path(key),
        'model_scene_path = "%s"' % model_path(key),
        'construction_abilities = Array[ExtResource("%s")]([ExtResource("%s")])'
        % (ability_script, cancel_build),
        'selling_abilities = Array[ExtResource("%s")]([ExtResource("%s")])'
        % (ability_script, cancel_sell),
        'upgrading_abilities = Array[ExtResource("%s")]([ExtResource("%s")])'
        % (ability_script, cancel_upgrade),
        "gold_cost = %d" % gold,
        "total_gold_cost = %d" % total,
    ]

    s.node("resource", None, ".", script=stats_script, props=props)
    text = s.render('[gd_resource type="Resource" script_class="BuildingStats" format=3]')
    # Scene renders nodes as [node ...]; a resource file wants one [resource].
    text = text.replace('[node name="resource"]', "[resource]")
    write(stats_path(key), text)


# --- prefabs ---------------------------------------------------------------

def gen_prefab(row, heights):
    key, display, line, branch = row[0], row[1], row[2], row[3]
    height = heights[key]

    s = Scene()
    building = s.ext("Script", S_BUILDING)
    attack = s.ext("Script", S_ATTACK_COMPONENT)
    stats = s.ext("Resource", stats_path(key))
    model = s.ext("PackedScene", model_path(key))
    ring_mat = s.ext("Material", RING_MATERIAL)

    s.sub("TorusMesh", "SelectionRing", [
        "inner_radius = 0.40",
        "outer_radius = 0.46",
        "rings = 24",
        "ring_segments = 4",
        'material = ExtResource("%s")' % ring_mat,
    ])

    s.node(pascal(key), "Node3D", ".",
           node_paths=["_visual_root", "_selection_ring"],
           script=building,
           props=[
               '_visual_root = NodePath("Visual")',
               'stats = ExtResource("%s")' % stats,
               '_selection_ring = NodePath("SelectionRing")',
               "health_bar_height = %s" % num(round(height + 0.28, 3)),
               "select_radius = 0.5",
               "select_height = %s" % num(round(height * 0.45, 3)),
           ])
    s.node("Visual", None, ".", instance=model)
    s.node("SelectionRing", "MeshInstance3D", ".", props=[
        "transform = %s" % t3(y=0.035),
        "visible = false",
        "cast_shadow = 0",
        'mesh = SubResource("SelectionRing")',
    ])
    # Every tower model carries Turret and Turret/Muzzle, whether or not it has
    # anything to aim - it is the contract a model has to meet, so this wiring
    # is identical across the whole roster and a new tower cannot forget it.
    s.node("Attack", "Node", ".",
           node_paths=["_unit", "_muzzle", "_turret_head"],
           script=attack,
           props=[
               '_unit = NodePath("..")',
               '_muzzle = NodePath("../Visual/Turret/Muzzle")',
               '_turret_head = NodePath("../Visual/Turret")',
           ])
    _add_animations(s, branch)
    write(prefab_path(key), s.render("[gd_scene format=3]"))


## Attack animations live in the PREFAB rather than in the model, because they
## need the unit and a model does not have one - the same model scene is used
## by the build ghost, which must not recoil at anything.
def _add_animations(s, branch):
    for index, entry in enumerate(td.ANIMATION.get(branch, [])):
        kind = entry[0]
        node = 'NodePath("../Visual/%s")' % entry[1]
        if kind == "recoil":
            s.node("Recoil%d" % (index + 1), "Node", ".",
                   node_paths=["_unit", "_recoiling"],
                   script=s.ext("Script", S_RECOIL),
                   props=['_unit = NodePath("..")',
                          "_recoiling = %s" % node,
                          "distance = %s" % num(entry[2])])
        elif kind == "slam":
            s.node("Slam", "Node", ".",
                   node_paths=["_unit", "_swing"],
                   script=s.ext("Script", S_SLAM),
                   props=['_unit = NodePath("..")',
                          "_swing = %s" % node,
                          'shockwave_scene_path = "%s"' % entry[2]])
        elif kind == "spin":
            s.node("BladeSpin", "Node", ".",
                   node_paths=["_spinner", "_unit"],
                   script=s.ext("Script", S_SPIN),
                   props=["_spinner = %s" % node,
                          '_unit = NodePath("..")',
                          "turns_per_second = %s" % num(entry[2]),
                          "idle_turns_per_second = %s" % num(entry[3]),
                          "spin_change_rate = 2.5"])


# --- abilities -------------------------------------------------------------

def gen_upgrade_abilities():
    for source, targets in td.UPGRADES.items():
        for slot, target in enumerate(targets):
            row = BY_KEY[target]
            display = row[1]
            branch = row[3]
            s = Scene()
            script = s.ext("Script", S_UPGRADE_TOWER)
            stats = s.ext("Resource", stats_path(target))
            s.node("resource", None, ".", script=script, props=[
                "ability_id = %d" % UPGRADE_IDS[(source, target)],
                'tower_stats = ExtResource("%s")' % stats,
                'display_name = "Upgrade to %s"' % display,
                'description = "%s"' % td.BRANCH_TEXT[branch],
                # IMMEDIATE: the tower is already standing where the upgrade
                # will stand, so there is nothing to aim.
                "targeting = 1",
                "slot = %d" % slot,
            ])
            text = s.render(
                '[gd_resource type="Resource" script_class="UpgradeTowerAbility" format=3]')
            write(upgrade_ability_path(source, target),
                  text.replace('[node name="resource"]', "[resource]"))


def gen_build_abilities():
    for slot, key in enumerate(td.BUILDABLE):
        row = BY_KEY[key]
        s = Scene()
        script = s.ext("Script", S_BUILD_TOWER)
        stats = s.ext("Resource", stats_path(key))
        s.node("resource", None, ".", script=script, props=[
            "ability_id = %d" % (td.ABILITY_ID_BUILD + slot),
            'tower_stats = ExtResource("%s")' % stats,
            'display_name = "%s"' % row[1],
            'description = "%s"' % td.BRANCH_TEXT[row[3]],
            # PLACEMENT: choosing it arms the snapped footprint ghost.
            "targeting = 5",
            "slot = %d" % slot,
        ])
        text = s.render(
            '[gd_resource type="Resource" script_class="BuildTowerAbility" format=3]')
        write(build_ability_path(key),
              text.replace('[node name="resource"]', "[resource]"))


def gen_build_menu(extra=()):
    """The builder's card.

    `extra` is other build abilities to offer alongside the three Basic ones -
    the Elemental Core, which is placed by the builder exactly as they are and
    is generated by a different file. Passed IN rather than imported, so this
    file goes on knowing nothing about the elemental roster.
    """
    s = Scene()
    script = s.ext("Script", "res://Scripts/Abilities/BuildMenuAbility.gd")
    ability_script = s.ext("Script", S_UNIT_ABILITY)
    entries = [s.ext("Resource", build_ability_path(k)) for k in td.BUILDABLE]
    entries.extend(s.ext("Resource", path) for path in extra)
    s.node("resource", None, ".", script=script, props=[
        "ability_id = 7",
        "buildable = Array[ExtResource(\"%s\")]([%s])" % (
            ability_script, ", ".join('ExtResource("%s")' % e for e in entries)),
        'display_name = "Build"',
        'description = "Open the build menu. Every tower above these is '
        'reached by upgrading one of them."',
        "targeting = 4",
        "slot = 7",
        'hotkey_action = ExtResource("%s")' % s.ext("Resource", A_HOTKEY_BUILD),
        'icon = ExtResource("%s")' % s.ext("Texture2D", action_icon_path("build")),
    ])
    text = s.render(
        '[gd_resource type="Resource" script_class="BuildMenuAbility" format=3]')
    write("res://Resources/Abilities/build_menu_ability.tres",
          text.replace('[node name="resource"]', "[resource]"))


def gen_selection_ring_material():
    write(RING_MATERIAL, "\n".join([
        '[gd_resource type="StandardMaterial3D" format=3]',
        "",
        "[resource]",
        "shading_mode = 0",
        "albedo_color = %s" % c((0.30, 0.95, 0.35)),
        "",
    ]))


def generate(heights, extra_buildable=()):
    gen_selection_ring_material()
    for row in td.TOWERS:
        gen_stats(row, heights)
        gen_prefab(row, heights)
    gen_upgrade_abilities()
    gen_build_abilities()
    gen_build_menu(extra_buildable)
    print("wrote %d tower stats, %d prefabs, %d upgrade abilities, %d build abilities"
          % (len(td.TOWERS), len(td.TOWERS), len(UPGRADE_IDS), len(td.BUILDABLE)))
