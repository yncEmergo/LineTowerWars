"""Stats, prefabs, upgrade abilities and named abilities for the elemental
roster.

The mirror of tower_content.py, and everything structural about it is the same:
a BuildingStats per tower naming its own prefab and model by path, a prefab per
tower wiring the shared Building / AttackComponent pair, and one upgrade ability
per rung naming only the tower ABOVE it.

Three things are here that the Basic roster has no need of:

  A TECHNOLOGY GATE. Every elemental upgrade authors `required_tech_id`, which
  TowerOrderAbility checks against the ORDERING PLAYER through TechManager - the
  same call the Research Center makes, so there is no second copy of the rule

  A NAMED ABILITY. Each tower carries one TowerPassive .tres of its own,
  authored from element_abilities.ABILITIES. It sits FIRST on the card, before
  the upgrades, because it is what the tower IS

  MANA. Authored on the stats where unit_data.md gives a tower any, along with
  the share it is built holding - which is 0 for everything except the Doom
  Guard line, whose whole design is starting full and decaying

THE ICON IS OPTIONAL HERE, and that is a real dependency rather than a
convenience: an `ext_resource` that does not resolve takes the WHOLE .tres down
with it (see CLAUDE.md), and the icons are baked FROM the finished models by a
renderer that has to run in the editor. So a tower whose PNG is not there yet is
written without one and picks it up on the next run. Bake, then run again.
"""

import io
import os

import element_abilities as ea
import element_roster as er
import roster as td
import style as ts
from tscn import Scene, t3, num

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
S_ARMOR_CHOICE = "res://Scripts/Abilities/ArmorTypeChoiceAbility.gd"
S_MORPH_MENU = "res://Scripts/Abilities/MorphMenuAbility.gd"
S_RETURN_TO_CORE = "res://Scripts/Abilities/ReturnToCoreAbility.gd"
S_BUILDING = "res://Scripts/Units/Building.gd"
S_ATTACK_COMPONENT = "res://Scripts/Combat/AttackComponent.gd"
S_RECOIL = "res://Scripts/Components/RecoilAnimation3D.gd"
S_SLAM = "res://Scripts/Components/SlamAnimation3D.gd"
S_SPIN = "res://Scripts/Components/SpinAnimation3D.gd"

A_ATTACK = "res://Resources/Abilities/attack_ability.tres"
A_SELL = "res://Resources/Abilities/sell_ability.tres"
A_CANCEL_BUILD = "res://Resources/Abilities/cancel_build_ability.tres"
A_CANCEL_SELL = "res://Resources/Abilities/cancel_sell_ability.tres"
A_CANCEL_UPGRADE = "res://Resources/Abilities/cancel_upgrade_ability.tres"
A_PRIORITIZE = "res://Resources/Abilities/prioritize_ability.tres"
A_ARMOR_CHOICE = "res://Resources/Abilities/Towers/alchemist_armor_choice_ability.tres"
A_MORPH_MENU = "res://Resources/Abilities/Towers/elemental_morph_menu_ability.tres"
A_RETURN_TO_CORE = ("res://Resources/Abilities/Towers/return_to_elemental_core_ability.tres")

RING_MATERIAL = "res://Resources/Materials/Towers/selection_ring.tres"
ICONS = "res://2DArt/Icons"
# Action icons, drawn by Tools/IconGen rather than baked from a model. The two
# abilities here that are not ABOUT a tower - the armour choice and the element
# list - take one of these, and unlike a baked icon it is always there.
UI_ICONS = "res://2DArt/UI/Icons"

# The one tower whose named ability needs a BUTTON as well as a passive: the
# Ultimate Alchemist picks which armour type it applies. See
# Scripts/Abilities/ArmorTypeChoiceAbility.gd.
ARMOR_CHOICE_TOWER = "unholy_ultimate_alchemist"

# The squares a tower's upgrades take, in order: the first two of the top row,
# so a branch reads left to right with no gap - see _upgrade_slot.
BRANCH_SLOTS = (0, 1)

# Where a tower's named ability sits: the bottom RIGHT square, the furthest
# one on the card from the keys worth pressing.
#
# A passive draws no hotkey letter, but it still OCCUPIES the square that
# letter is bound to, so one sitting at the front of the card spends the best
# key in the game on something that can never be pressed. It is read, not
# pressed, so it gets the square nothing else wants - and its icon is the tower
# itself, which is what makes it findable there.
#
# It was the bottom LEFT until Return to Core claimed that square, which is a
# button and needs the key. See RETURN_SLOT.
PASSIVE_SLOT = 11

# Where Return to Core sits: the bottom left square, which is Y on the
# "qwer"/"asdf"/"yxcv" command card. One square for the whole roster, so the
# key that takes a tower back down to a Core is the same key at every tier and
# in every element.
RETURN_SLOT = 8

# What a tower has to be WORTH before it carries Return to Core, counting
# everything sunk into it rather than the rung it last climbed.
#
# 800 leaves out the Elemental Core itself and each element's 200g base tower,
# and there is nothing for either of them to return: the base tower cost
# exactly what the Core cost and is one free morph away from being one again.
RETURN_MIN_VALUE = 800

BY_KEY = er.by_key()
TYPE_IDS = er.unit_type_ids()

# Ability ids, handed out in one pass so nothing can collide: the tower
# passives first, then the upgrades, then the two loose ones.
_PASSIVE_IDS = {}
_UPGRADE_IDS = {}
_BUILD_CORE_ID = 0
_ARMOR_CHOICE_ID = 0
_MORPH_MENU_ID = 0
_RETURN_TO_CORE_ID = 0


def _assign_ids():
    """Hands out every ability id this roster claims, in one fixed order.

    PERMANENT once run and never re-sorted: an ability_id is authored, not
    derived, and re-ordering anything here would renumber the rest. See
    CLAUDE.md - the number carries no meaning, it only has to be unique and
    never move.
    """
    global _BUILD_CORE_ID, _ARMOR_CHOICE_ID, _MORPH_MENU_ID, _RETURN_TO_CORE_ID
    next_id = er.FIRST_ABILITY_ID

    for row in er.tower_rows():
        if row["key"] in ea.ABILITIES:
            _PASSIVE_IDS[row["key"]] = next_id
            next_id += 1

    for source, target in er.upgrade_pairs():
        _UPGRADE_IDS[(source, target)] = next_id
        next_id += 1

    _BUILD_CORE_ID = next_id
    _ARMOR_CHOICE_ID = next_id + 1
    _MORPH_MENU_ID = next_id + 2
    # APPENDED, never inserted. Everything above already shipped its number.
    _RETURN_TO_CORE_ID = next_id + 3
    return next_id + 4


LAST_ABILITY_ID = _assign_ids()


def stats_path(key):
    return "res://%s/%s_stats.tres" % (STATS_DIR, key)


def prefab_path(key):
    return "res://%s/%s.tscn" % (PREFAB_DIR, key)


def model_path(key):
    return "res://Scenes/Units/Models/Towers/%s_model.tscn" % key


def icon_name(display):
    """The file the icon renderer writes for a tower, which is named after its
    DISPLAY NAME rather than its key.

    That is Scenes/Dev/icon_renderer.tscn's convention and it is kept rather
    than changed, because it is already what every Basic tower and every creep
    icon in 2DArt/Icons is called. It works because a display name is unique
    across the whole game - "Lesser Doom Guard" belongs to Fire and to nothing
    else - which is a thing worth knowing before adding a roster that reuses
    one.
    """
    return display.lower().replace(" ", "_").replace("'", "")


def icon_path(display):
    return "%s/%s.png" % (ICONS, icon_name(display))


def has_icon(display):
    return os.path.exists("2DArt/Icons/%s.png" % icon_name(display))


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


def as_resource(scene, header):
    """Renders a Scene as a .tres. Scene writes `[node name="resource"]`; a
    resource file wants one `[resource]`."""
    return scene.render(header).replace('[node name="resource"]', "[resource]")


# --- the named abilities ----------------------------------------------------

def gen_passives():
    """One TowerPassive .tres per elemental tower, from element_abilities.

    The DESCRIPTION is left empty on purpose. Every one of these passives
    builds its own line out of its own @exports through effect_text(), and an
    authored description would be a second copy of numbers that are already
    here - the same rule CreepPassive follows.
    """
    for key, entry in ea.ABILITIES.items():
        s = Scene()
        script = s.ext("Script", entry["script"])
        props = [
            "ability_id = %d" % _PASSIVE_IDS[key],
            'display_name = "%s"' % entry["name"],
            # PASSIVE: it is read, never pressed, and its square carries no
            # hotkey letter.
            "targeting = 0",
            # Out of the way of the keys that are worth pressing. See
            # PASSIVE_SLOT.
            "slot = %d" % PASSIVE_SLOT,
        ]
        # The TOWER's own picture. A passive has no art of its own and never
        # will have - it is a rule rather than a thing - and an iconless square
        # sitting first on all eighty cards is a hole a player learns to skip
        # over. Its own tower is the truest picture available and costs
        # nothing, since the icon is already baked.
        display = BY_KEY[key]["display"]
        if has_icon(display):
            props.append('icon = ExtResource("%s")'
                         % s.ext("Texture2D", icon_path(display)))
        for field, value in entry["fields"].items():
            props.append("%s = %s" % (field, _value(value)))

        s.node("resource", None, ".", script=script, props=props)
        write(ea.ability_path(key),
              as_resource(s, '[gd_resource type="Resource" format=3]'))


def _value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return '"%s"' % value
    return num(value)


def gen_armor_choice():
    """The Ultimate Alchemist's armour-type button, which is the one ACTIVE
    ability in the whole elemental roster."""
    s = Scene()
    script = s.ext("Script", S_ARMOR_CHOICE)
    s.node("resource", None, ".", script=script, props=[
        "ability_id = %d" % _ARMOR_CHOICE_ID,
        'display_name = "Alter Armor"',
        'description = "Which armor type this tower alters the creeps it hits '
        'into. A creep can only ever be altered into a given type once."',
        # IMMEDIATE: pressing it cycles the choice, there is nothing to aim at.
        "targeting = 1",
        "slot = 6",
        'icon = ExtResource("%s")'
        % s.ext("Texture2D", action_icon_path("alter_armor")),
    ])
    write(A_ARMOR_CHOICE,
          as_resource(s, '[gd_resource type="Resource" format=3]'))


# --- stats ------------------------------------------------------------------

def gen_stats(row, heights):
    key = row["key"]
    shape = row["shape"]
    health, armor = er.TIER_BODY[er_price(row)]
    kind, projectile, speed, arc = er.DELIVERY[shape]
    impact = er.IMPACT.get(shape, "")

    s = Scene()
    stats_script = s.ext("Script", S_BUILDING_STATS)
    ability_script = s.ext("Script", S_UNIT_ABILITY)
    attack_script = s.ext("Script", S_ATTACK_STATS)

    _delivery(s, kind, projectile, speed, arc, impact)
    effect_script = _splash(s, row)
    _attack(s, row, attack_script, effect_script)

    card = _card(s, row)
    cancel_build = s.ext("Resource", A_CANCEL_BUILD)
    cancel_sell = s.ext("Resource", A_CANCEL_SELL)
    cancel_upgrade = s.ext("Resource", A_CANCEL_UPGRADE)

    props = ["unit_type_id = %d" % TYPE_IDS[key],
             'display_name = "%s"' % row["display"]]
    if has_icon(row["display"]):
        props.append('icon = ExtResource("%s")'
                     % s.ext("Texture2D", icon_path(row["display"])))
    props.extend([
        "max_health = %d" % health,
        # Fortified on every tower, whatever it deals. unit_data.md 1.4.
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
    ])
    if row["mana"] > 0:
        props.append("max_mana = %d" % row["mana"])
        if row["start_mana"] > 0.0:
            props.append("starting_mana_ratio = %s" % num(row["start_mana"]))
    props.append("gold_cost = %d" % row["gold"])
    props.append("total_gold_cost = %d" % row["total"])

    s.node("resource", None, ".", script=stats_script, props=props)
    write(stats_path(key), as_resource(
        s, '[gd_resource type="Resource" script_class="BuildingStats" format=3]'))


def er_price(row):
    """The price TIER this tower's body comes from, which is its own price
    except for a base tower reached by a free morph - a Fire Pit costs 0 to
    step into and still has a 200g tower's health."""
    return ts.ELEMENT_PRICE_TIERS[row["ti"]]


def _delivery(s, kind, projectile, speed, arc, impact):
    if kind == "projectile":
        script = s.ext("Script", S_PROJECTILE_DELIVERY)
        lines = ['script = ExtResource("%s")' % script,
                 'projectile_scene_path = "%s"' % projectile,
                 "speed = %s" % num(speed)]
        if arc:
            lines.append("arc_height = %s" % num(arc))
    else:
        script = s.ext("Script", S_INSTANT_DELIVERY)
        lines = ['script = ExtResource("%s")' % script]
    if impact:
        lines.append('impact_scene_path = "%s"' % impact)
    s.sub("Resource", "Delivery", lines)


def _splash(s, row):
    if not row["splash"]:
        return None
    effect_script = s.ext("Script", S_ATTACK_EFFECT)
    # Every elemental splash is measured from the IMPACT. Nothing in this
    # roster is the Crusher, whose reach is shorter than its own blast - see
    # SelfSplashEffect for the one exception in the game.
    s.sub("Resource", "Splash", [
        'script = ExtResource("%s")' % s.ext("Script", S_SPLASH),
        "radius = %s" % num(td.cells(row["splash"])),
    ])
    return effect_script


def _attack(s, row, attack_script, effect_script):
    lines = ['script = ExtResource("%s")' % attack_script,
             "damage_min = %d" % row["dmin"],
             "damage_max = %d" % row["dmax"],
             "damage_type = %d" % row["dtype"]]
    if row["splash"]:
        lines.append("is_aoe_damage = true")
    lines.append("attacks_per_second = %s" % num(td.aps(row["cooldown"])))
    windup = er.WINDUP.get(row["shape"], 0.0)
    if windup:
        lines.append("windup_seconds = %s" % num(windup))
    lines.append("attack_range = %s" % num(td.cells(row["range"])))
    lines.append("target_types = %d" % row["targets"])
    lines.append('delivery = SubResource("Delivery")')
    if effect_script is not None:
        lines.append('effects = Array[ExtResource("%s")]([SubResource("Splash")])'
                     % effect_script)
    s.sub("Resource", "Attack", lines)


def _card(s, row):
    """This tower's command card, in slot order.

    Its own named ability FIRST, then the upgrades above it, then the standard
    three. That order is the point: a player looking at an elemental tower
    should read what it DOES before what it costs to replace.
    """
    card = []
    if row["key"] in ea.ABILITIES:
        card.append(s.ext("Resource", ea.ability_path(row["key"])))
    if row["key"] == ARMOR_CHOICE_TOWER:
        card.append(s.ext("Resource", A_ARMOR_CHOICE))

    if row["key"] == "elemental_core":
        # Ten elements would want ten squares on a card that holds twelve, so
        # they go behind one. See MorphMenuAbility.
        card.append(s.ext("Resource", A_MORPH_MENU))
    else:
        for source, target in er.upgrade_pairs():
            if source == row["key"]:
                card.append(s.ext("Resource", upgrade_ability_path(source, target)))
        # The way back down, straight after the ways up. See RETURN_MIN_VALUE.
        if row["total"] >= RETURN_MIN_VALUE:
            card.append(s.ext("Resource", A_RETURN_TO_CORE))

    card.append(s.ext("Resource", A_ATTACK))
    if row["targets"] == td.BOTH:
        card.append(s.ext("Resource", A_PRIORITIZE))
    card.append(s.ext("Resource", A_SELL))
    return card


# --- prefabs ----------------------------------------------------------------

def gen_prefab(row, heights):
    key = row["key"]
    height = heights[key]

    s = Scene()
    building = s.ext("Script", S_BUILDING)
    attack = s.ext("Script", S_ATTACK_COMPONENT)
    stats = s.ext("Resource", stats_path(key))
    model = s.ext("PackedScene", model_path(key))
    ring_mat = s.ext("Material", RING_MATERIAL)

    s.sub("TorusMesh", "SelectionRing", [
        "inner_radius = 0.40", "outer_radius = 0.46",
        "rings = 24", "ring_segments = 4",
        'material = ExtResource("%s")' % ring_mat,
    ])

    s.node(pascal(key), "Node3D", ".",
           node_paths=["_visual_root", "_selection_ring"],
           script=building,
           props=['_visual_root = NodePath("Visual")',
                  'stats = ExtResource("%s")' % stats,
                  '_selection_ring = NodePath("SelectionRing")',
                  "health_bar_height = %s" % num(round(height + 0.28, 3)),
                  "select_radius = 0.5",
                  "select_height = %s" % num(round(height * 0.45, 3))])
    s.node("Visual", None, ".", instance=model)
    s.node("SelectionRing", "MeshInstance3D", ".", props=[
        "transform = %s" % t3(y=0.035),
        "visible = false",
        "cast_shadow = 0",
        'mesh = SubResource("SelectionRing")',
    ])
    s.node("Attack", "Node", ".",
           node_paths=["_unit", "_muzzle", "_turret_head"],
           script=attack,
           props=['_unit = NodePath("..")',
                  '_muzzle = NodePath("../Visual/Turret/Muzzle")',
                  '_turret_head = NodePath("../Visual/Turret")'])
    _add_animations(s, row["shape"])
    write(prefab_path(key), s.render("[gd_scene format=3]"))


def _add_animations(s, shape):
    """Attack animations live in the PREFAB rather than in the model, because
    they need the unit and a model does not have one - the same model scene is
    used by the build ghost, which must not recoil at anything."""
    for index, entry in enumerate(er.ANIMATION.get(shape, [])):
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
            s.node("Spin%d" % (index + 1), "Node", ".",
                   node_paths=["_spinner", "_unit"],
                   script=s.ext("Script", S_SPIN),
                   props=["_spinner = %s" % node,
                          '_unit = NodePath("..")',
                          "turns_per_second = %s" % num(entry[2]),
                          "idle_turns_per_second = %s" % num(entry[3]),
                          "spin_change_rate = 2.5"])


# --- upgrade and build abilities --------------------------------------------

def gen_upgrade_abilities():
    for source, target in er.upgrade_pairs():
        row = BY_KEY[target]
        s = Scene()
        script = s.ext("Script", S_UPGRADE_TOWER)
        stats = s.ext("Resource", stats_path(target))
        props = ["ability_id = %d" % _UPGRADE_IDS[(source, target)],
                 'tower_stats = ExtResource("%s")' % stats,
                 "required_tech_id = %d" % row["tech"],
                 'display_name = "%s"' % _upgrade_label(source, row),
                 'description = "%s"' % _path_text(row),
                 # IMMEDIATE: the tower is already standing where the upgrade
                 # will stand, so there is nothing to aim.
                 "targeting = 1",
                 "slot = %d" % _upgrade_slot(source, target)]
        s.node("resource", None, ".", script=script, props=props)
        write(upgrade_ability_path(source, target), as_resource(
            s, '[gd_resource type="Resource" script_class="UpgradeTowerAbility" format=3]'))


def _upgrade_label(source, row):
    """What the button says. "Morph into" rather than "Upgrade to" off the
    Elemental Core, because that step costs nothing - calling it an upgrade
    would have a player looking for a price that is not there."""
    verb = "Morph into" if source == "elemental_core" else "Upgrade to"
    return "%s %s" % (verb, row["display"])


def _upgrade_slot(source, target):
    """Which square this upgrade claims on the tower below it.

    UPGRADES GET THE BEST KEYS, and a BRANCH takes the first two squares of
    the top row, side by side. The 800g tower of every element is where the
    path is chosen and it is the single most consequential press in the game,
    so the two 4,000g paths sit adjacent and in a fixed order: first path
    first, second path second, the same two squares for all ten elements. A
    tower with one upgrade takes the first square on its own, so the key that
    moves a tower up its line is the same key at every tier.

    The Elemental Core is the exception and carries TEN of them, one per
    element, filling its own submenu card from square 0 in the order
    element_roster walks the elements.
    """
    if source == "elemental_core":
        cores = [t for src, t in er.upgrade_pairs() if src == "elemental_core"]
        return cores.index(target)

    used = [t for src, t in er.upgrade_pairs() if src == source]
    return BRANCH_SLOTS[used.index(target)]


def _path_text(row):
    """One line describing what this tower is for, on the button that buys it.

    Comes off the PATH rather than off the tier, so all three tiers of a path
    say the same thing - a player choosing between two 4,000g upgrades is
    choosing between two paths and should read them as such.
    """
    path = row["path"]
    if path is None:
        return PATH_TEXT.get(row["element"], "")
    return PATH_TEXT.get(path["key"], "")


def gen_morph_menu():
    """The Elemental Core's element list, as one submenu."""
    s = Scene()
    script = s.ext("Script", S_MORPH_MENU)
    ability_script = s.ext("Script", S_UNIT_ABILITY)
    entries = [s.ext("Resource", upgrade_ability_path("elemental_core", target))
               for source, target in er.upgrade_pairs()
               if source == "elemental_core"]
    s.node("resource", None, ".", script=script, props=[
        "ability_id = %d" % _MORPH_MENU_ID,
        "morphs = Array[ExtResource(\"%s\")]([%s])" % (
            ability_script, ", ".join('ExtResource("%s")' % e for e in entries)),
        'display_name = "Choose Element"',
        'description = "Morph this Core into an element you have researched. '
        'The morph is free; the technology is not."',
        "targeting = 4",
        "slot = 0",
        'icon = ExtResource("%s")'
        % s.ext("Texture2D", action_icon_path("choose_element")),
    ])
    write(A_MORPH_MENU, as_resource(
        s, '[gd_resource type="Resource" script_class="MorphMenuAbility" format=3]'))


def gen_return_to_core():
    """The way back down out of an element, as ONE shared .tres.

    One resource for the whole roster rather than one per tower, exactly as
    Sell and Attack are: what it does is the same everywhere and nothing about
    it is per tower, so sixty copies would only be sixty files to keep in step.

    It names the Core BY PATH rather than as an ext_resource, and that is the
    whole reason it can exist at all - see ReturnToCoreAbility. The Core's card
    reaches every element and every element's tiers carry this ability, so a
    resource reference here would close a cycle through the entire roster.

    Its icon IS the Core's, on the same optional terms every icon here is: it
    is baked from the finished model, so a run before the bake writes the file
    without one and the next run picks it up.
    """
    core = BY_KEY["elemental_core"]
    s = Scene()
    script = s.ext("Script", S_RETURN_TO_CORE)
    props = ["ability_id = %d" % _RETURN_TO_CORE_ID,
             'core_stats_path = "%s"' % stats_path("elemental_core"),
             'display_name = "Return to Elemental Core"',
             'description = "Take this tower back down to a bare Elemental '
             'Core and choose another element. Everything sunk into it above '
             "the Core is refunded at the usual sell share; the Core's own "
             "gold stays in the cell. The tower keeps blocking until it "
             'finishes, and calling it off costs nothing."',
             # IMMEDIATE: the Core arrives on the cell the tower already
             # stands on, so there is nothing to aim at.
             "targeting = 1",
             "slot = %d" % RETURN_SLOT]
    if has_icon(core["display"]):
        props.append('icon = ExtResource("%s")'
                     % s.ext("Texture2D", icon_path(core["display"])))
    s.node("resource", None, ".", script=script, props=props)
    write(A_RETURN_TO_CORE, as_resource(
        s, '[gd_resource type="Resource" script_class="ReturnToCoreAbility" format=3]'))


def gen_build_ability():
    """The Elemental Core is the ONE elemental tower the builder places. Every
    element is reached by morphing it, which is what keeps the build menu four
    buttons long while the elemental roster is eighty towers deep."""
    s = Scene()
    script = s.ext("Script", S_BUILD_TOWER)
    stats = s.ext("Resource", stats_path("elemental_core"))
    s.node("resource", None, ".", script=script, props=[
        "ability_id = %d" % _BUILD_CORE_ID,
        'tower_stats = ExtResource("%s")' % stats,
        'display_name = "Elemental Core"',
        'description = "%s"' % PATH_TEXT["core"],
        # PLACEMENT: choosing it arms the snapped footprint ghost.
        "targeting = 5",
        # The square is authored HERE and nowhere else. This generator writes
        # the .tres, so a slot changed by hand in the resource is overwritten
        # the next time ModelGen runs - change it in this line instead.
        "slot = 4",
    ])
    write(build_ability_path("elemental_core"), as_resource(
        s, '[gd_resource type="Resource" script_class="BuildTowerAbility" format=3]'))


PATH_TEXT = {
    "core": "The technology base tower. Morphs free into any element you have "
            "researched, and is worth nothing until you have.",
    "fire": "Burns creeps over time. Splits into the meteor caller and the "
            "living flame.",
    "ice": "Chills everything it hits, stacking towards a cap. Splits into the "
           "slowing Lich and the piercing Crystal.",
    "lightning": "Hits harder the healthier the target is. Splits into the "
                 "long ranged Glyph and the short ranged stunner.",
    "holy": "Strikes several creeps with one attack. Splits into the anti-air "
            "shroom and the support vault.",
    "void": "Grows: at full mana it turns one of your other towers into "
            "another of itself, free and once only.",
    "unholy": "Corrupts what it hits, so a corrupted creep explodes when it "
              "dies. Splits into poison and permanent damage.",
    "water": "Throws a wave every fourth attack. Splits into the anti-air "
             "paralyzer and the slowing sludge.",
    "earth": "Permanently eats armor. Splits into heavy siege splash and pure "
             "single target.",
    "arcane": "Fills with mana as it attacks and hits far harder when full. "
              "Splits into the caster and the bouncing orb.",
    "primal": "Stuns on every fourth attack. Splits into the gold making "
              "Primalist and the beast unleashing Beastmaster.",

    "doom_guard": "Calls meteors. Built at full mana and strongest the moment "
                  "it is placed, weakening every second afterwards. Cannot hit air.",
    "firelord": "A living flame. A chance on every attack to burst over "
                "several creeps and permanently eat their armor.",
    "lich": "Chills deeper than anything else, with splash. The Ultimate kills "
            "a fully chilled creep with its own health.",
    "crystal": "Pierces every creep in a line and IGNORES ARMOR ENTIRELY, in "
               "exchange for lower base damage.",
    "annihilation_glyph": "The longest reach in the game. Ramps up on one "
                          "target and loses everything when it switches.",
    "orb_keeper": "Very short reach and a very fast attack. Fills up over four "
                  "attacks and spends the lot on a stun.",
    "divineshroom": "AIR ONLY from this tier up. Heavy splash, deep slow, and "
                    "the only armor reduction that goes below zero.",
    "titan_vault": "Support. Strikes many creeps at once and leaves them "
                   "taking more Spell Damage from everything.",
    "harbinger": "Drags a creep back down the lane it came from and burns a "
                 "share of its maximum health.",
    "leviathan": "Eats armor and turns it into its own attack damage, which it "
                 "loses again if it stops shooting.",
    "gravedigger": "Stacks poison on several creeps at once and detonates it "
                   "once it is deep enough.",
    "alchemist": "Permanently gains damage for every creep it kills, and keeps "
                 "it across upgrades.",
    "hurricane_elemental": "Pulls flyers out of the sky and pins them where "
                           "your ground towers can reach them.",
    "sludge_monstrosity": "An aura that grinds every creep near it slower, "
                          "whether or not it is shooting them.",
    "ancient_warden": "Heavy siege splash that permanently eats armor. What "
                      "you put at the front of a maze.",
    "scorpion": "Pure single target. Worth the most on the first shot after "
                "standing idle, and criticals against a hurt target.",
    "spellslinger": "A caster: it burns and slows on its own clock as well as "
                    "attacking, and spends mana on splashing orbs.",
    "arcane_orb": "Attacks bounce between creeps, feeding the tower and "
                  "draining away again when it stops.",
    "primalist": "GENERATES GOLD on every attack, less for every other "
                 "Primalist standing near it.",
    "beastmaster": "Unleashes a beast down the lane, damaging and stunning "
                   "every ground creep in its path.",
}


def generate(heights):
    gen_passives()
    gen_armor_choice()
    for row in er.tower_rows():
        gen_stats(row, heights)
        gen_prefab(row, heights)
    gen_upgrade_abilities()
    gen_morph_menu()
    gen_return_to_core()
    gen_build_ability()
    print("wrote %d elemental stats, %d prefabs, %d passives, %d upgrades"
          % (len(BY_KEY), len(BY_KEY), len(ea.ABILITIES), len(_UPGRADE_IDS)))
