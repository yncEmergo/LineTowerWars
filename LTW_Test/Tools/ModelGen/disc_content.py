"""Stats, prefabs, passives and morph abilities for the technology discs.

The mirror of element_content.py and structurally the same file: a
BuildingStats per disc naming its own prefab and model by path, a prefab per
disc, one DiscPassive .tres per disc that has an element, and one upgrade
ability per rung naming only the disc ABOVE it.

What is different about a disc, and all of it is in this file:

  IT IS NOT A WALL. `blocks_movement = false` on every one of the thirty-one,
  which is the whole design of the thing - creeps walk straight over a disc, so
  it fills the holes a maze already has rather than making new ones. See
  game_rules.md and PlayerArea.CELL_WALKABLE

  IT CANNOT BE ATTACKED OR ATTACK. Armour type Invulnerable and no AttackStats
  at all, so its prefab carries no AttackComponent and its card carries neither
  Attack nor Prioritize. unit_data.md 1.5

  ITS GATE IS AN ELEMENT COUNT, not a technology id. An Advanced disc needs two
  of an element's three technologies and an Ultimate needs all three, and there
  is no single id that means either - so every disc morph is a
  DiscUpgradeAbility rather than a plain UpgradeTowerAbility

  ONE ULTIMATE PER PLAYER PER ELEMENT (11.0a), authored as a flag on the ten
  Ultimate morphs and enforced by the ability

THE CARD IS THE ELEMENTAL CORE'S, deliberately and by reusing its own table.
The inactive disc carries all ten morphs on the same ten squares the Core
carries its own, so the key that turns a Core into Fire is the key that turns a
disc into Fire. A player learns ten letters once.

THE ICON IS OPTIONAL here on exactly the terms it is optional in
element_content: an ext_resource that does not resolve takes the WHOLE .tres
down with it, and icons are baked FROM the finished art by a renderer that has
to run in the editor. A disc whose PNG is not there yet is written without one
and picks it up on the next run. Bake, then run again.
"""

import io
import os

import disc_models as dm
import disc_roster as dr
import element_content as ec
from tscn import Scene, num, t3

STATS_DIR = "Resources/UnitStats/Discs"
ABILITY_DIR = "Resources/Abilities/Discs"
PREFAB_DIR = "Scenes/Units/Discs"

S_BUILDING_STATS = "res://Scripts/Config/BuildingStats.gd"
S_UNIT_ABILITY = "res://Scripts/Abilities/UnitAbility.gd"
S_BUILD_TOWER = "res://Scripts/Abilities/BuildTowerAbility.gd"
S_DISC_UPGRADE = "res://Scripts/Abilities/DiscUpgradeAbility.gd"
S_DISC_REVERT = "res://Scripts/Abilities/DiscRevertAbility.gd"
S_DISC = "res://Scripts/Units/Disc.gd"

A_SELL = "res://Resources/Abilities/sell_ability.tres"
A_SHOW_RANGES = "res://Resources/Abilities/show_ranges_ability.tres"
A_CANCEL_BUILD = "res://Resources/Abilities/cancel_build_ability.tres"
A_CANCEL_SELL = "res://Resources/Abilities/cancel_sell_ability.tres"
A_CANCEL_UPGRADE = "res://Resources/Abilities/cancel_upgrade_ability.tres"
A_REVERT = "res://Resources/Abilities/Discs/revert_disc_ability.tres"

RING_MATERIAL = "res://Resources/Materials/Towers/selection_ring.tres"

# TechDefinition.Element, which is alphabetical and is the enum a
# DiscUpgradeAbility authors. Written out rather than derived from the roster's
# own walk order, because the two are different questions and neither should be
# able to move the other - see disc_roster.ELEMENT_ORDER.
ELEMENT_ENUM = {
    "arcane": 0, "earth": 1, "fire": 2, "holy": 3, "ice": 4,
    "lightning": 5, "primal": 6, "unholy": 7, "void": 8, "water": 9,
}

# The square the BUILD button takes on the builder's build menu.
#
# 5 is the middle of the second row, which is the S key on the authored grid -
# and S is what a player asked for. The square is authored HERE and nowhere
# else: this generator writes the .tres, so a slot changed by hand in the
# resource is overwritten on the next run.
BUILD_SLOT = 5

# Where a disc's own effect sits, and it is the SAME square an elemental
# tower's named ability takes. A player who has learned where to read what a
# tower does reads what a disc does in the same place, which is worth more than
# the square being chosen freshly for a card that has room to spare.
PASSIVE_SLOT = ec.PASSIVE_SLOT

# The square a disc's upgrade takes. The first of the branch squares an
# elemental tower uses, on the same grounds: an upgrade gets the best key, and a
# disc never has two, so it is that square at every tier.
UPGRADE_SLOT = ec.BRANCH_SLOTS[0]

# The square the way back down asks for, shared with Return to Core so that the
# key which undoes a choice is one key across the whole game. It does not
# usually GET this one - Sell claims it first, off the grid, and pushes this
# along to the next free square - and it is authored as the square it wants
# rather than the one it lands on for the reason element_content gives.
REVERT_SLOT = ec.RETURN_SLOT

BY_KEY = dr.by_key()
TYPE_IDS = dr.unit_type_ids()

# Ability ids, handed out in one fixed pass so nothing can collide: the disc
# passives first, then the morphs, then the two loose ones.
_PASSIVE_IDS = {}
_UPGRADE_IDS = {}
_BUILD_ID = 0
_REVERT_ID = 0


def _assign_ids():
    """Hands out every ability id this roster claims, in one fixed order.

    PERMANENT once run and never re-sorted. CLAUDE.md: an id is authored rather
    than derived, the number carries no meaning, and re-ordering anything here
    would renumber the rest of the roster. The registry refuses a duplicate
    loudly at boot, so a collision is a failed boot rather than a bug that
    ships.
    """
    global _BUILD_ID, _REVERT_ID
    next_id = dr.FIRST_ABILITY_ID

    for row in dr.disc_rows():
        if row["passive"] is not None:
            _PASSIVE_IDS[row["key"]] = next_id
            next_id += 1

    for source, target in dr.upgrade_pairs():
        _UPGRADE_IDS[(source, target)] = next_id
        next_id += 1

    _BUILD_ID = next_id
    _REVERT_ID = next_id + 1
    return next_id + 2


LAST_ABILITY_ID = _assign_ids()


def stats_path(key):
    return "res://%s/%s_stats.tres" % (STATS_DIR, key)


def prefab_path(key):
    return "res://%s/%s.tscn" % (PREFAB_DIR, key)


def passive_path(key):
    return "res://%s/%s_effect.tres" % (ABILITY_DIR, key)


def upgrade_ability_path(source, target):
    return "res://%s/morph_%s_to_%s_ability.tres" % (ABILITY_DIR, source, target)


def build_ability_path():
    return "res://%s/build_technology_disc_ability.tres" % ABILITY_DIR


def write(res_path, text):
    path = res_path.replace("res://", "")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    io.open(path, "w", encoding="utf-8", newline="\n").write(text)


def as_resource(scene, header):
    return scene.render(header).replace('[node name="resource"]', "[resource]")


def _value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return '"%s"' % value
    return num(value)


# --- the effects ------------------------------------------------------------

def gen_passives():
    """One DiscPassive .tres per disc that has an element.

    The DESCRIPTION is left empty on purpose, exactly as it is for a tower
    passive: every one of these builds its own line out of its own @exports
    through effect_text(), and an authored description would be a second copy
    of numbers that are already in the file.
    """
    written = 0
    for row in dr.disc_rows():
        entry = row["passive"]
        if entry is None:
            continue

        s = Scene()
        script = s.ext("Script", entry["script"])
        props = [
            "ability_id = %d" % _PASSIVE_IDS[row["key"]],
            'display_name = "%s"' % entry["name"],
            # PASSIVE: it is read, never pressed, and its square carries no
            # hotkey letter.
            "targeting = 0",
            "slot = %d" % PASSIVE_SLOT,
        ]
        if ec.has_icon(row["display"]):
            props.append('icon = ExtResource("%s")'
                         % s.ext("Texture2D", ec.icon_path(row["display"])))
        props.append("radius_cells = %s" % num(entry["radius"]))
        for field, value in entry["fields"].items():
            props.append("%s = %s" % (field, _value(value)))

        s.node("resource", None, ".", script=script, props=props)
        write(passive_path(row["key"]),
              as_resource(s, '[gd_resource type="Resource" format=3]'))
        written += 1
    return written


# --- stats ------------------------------------------------------------------

def gen_stats(row):
    key = row["key"]
    s = Scene()
    stats_script = s.ext("Script", S_BUILDING_STATS)
    ability_script = s.ext("Script", S_UNIT_ABILITY)

    card = _card(s, row)
    cancel_build = s.ext("Resource", A_CANCEL_BUILD)
    cancel_sell = s.ext("Resource", A_CANCEL_SELL)
    cancel_upgrade = s.ext("Resource", A_CANCEL_UPGRADE)

    props = ["unit_type_id = %d" % TYPE_IDS[key],
             'display_name = "%s"' % row["display"]]
    if ec.has_icon(row["display"]):
        props.append('icon = ExtResource("%s")'
                     % s.ext("Texture2D", ec.icon_path(row["display"])))
    props.extend([
        "max_health = %d" % dr.DISC_HEALTH,
        # unit_data.md 1.5. This one line is the whole of what makes a wall of
        # discs something an attacker creep cannot open: TargetFinder finds
        # only attackable buildings, so nothing has to list an exception.
        "armor_type = %d" % dr.INVULNERABLE,
        # No `attack` at all. A disc cannot attack, and the absence is the
        # statement - a zero-damage AttackStats would be a tower that misses.
        "abilities = Array[ExtResource(\"%s\")]([%s])" % (
            ability_script, ", ".join('ExtResource("%s")' % r for r in card)),
        'scene_path = "%s"' % prefab_path(key),
        'model_scene_path = "%s"' % dm.model_path(key),
        # THE LINE THAT MAKES A DISC A DISC. See BuildingStats.blocks_movement.
        "blocks_movement = false",
        'construction_abilities = Array[ExtResource("%s")]([ExtResource("%s")])'
        % (ability_script, cancel_build),
        'selling_abilities = Array[ExtResource("%s")]([ExtResource("%s")])'
        % (ability_script, cancel_sell),
        'upgrading_abilities = Array[ExtResource("%s")]([ExtResource("%s")])'
        % (ability_script, cancel_upgrade),
        "gold_cost = %d" % row["gold"],
        "total_gold_cost = %d" % row["total"],
    ])

    s.node("resource", None, ".", script=stats_script, props=props)
    write(stats_path(key), as_resource(
        s, '[gd_resource type="Resource" script_class="BuildingStats" format=3]'))


def _card(s, row):
    """This disc's command card, in slot order.

    Its own effect FIRST, then the way up, then the way back down, then the
    standard two. The same order an elemental tower's card is built in, and for
    the same reason: what a thing DOES should be read before what it costs to
    replace.

    THE INACTIVE DISC IS THE EXCEPTION and is the reason this is a branch. It
    carries all ten morphs directly, which with Sell and Show Ranges fills the
    card exactly - so it has no room for anything else and needs none: it does
    nothing, so it has no effect to show and nothing to go back to.
    """
    card = []
    if row["passive"] is not None:
        card.append(s.ext("Resource", passive_path(row["key"])))

    for source, target in dr.upgrade_pairs():
        if source == row["key"]:
            card.append(s.ext("Resource", upgrade_ability_path(source, target)))

    # The way back down, straight after the ways up. Never on the inactive
    # disc, which is already at the bottom.
    if row["tier"] > 0:
        card.append(s.ext("Resource", A_REVERT))

    card.append(s.ext("Resource", A_SELL))
    card.append(s.ext("Resource", A_SHOW_RANGES))
    return card


# --- prefabs ----------------------------------------------------------------

def gen_prefab(row, heights):
    """One disc prefab: the Disc node, its model, and a selection ring.

    Shorter than a tower's by exactly the two things a disc has not got - an
    AttackComponent and any attack animation - and that absence is not a gap to
    be filled later. A disc cannot attack.
    """
    key = row["key"]
    height = heights[key]

    s = Scene()
    disc_script = s.ext("Script", S_DISC)
    stats = s.ext("Resource", stats_path(key))
    model = s.ext("PackedScene", dm.model_path(key))
    ring_mat = s.ext("Material", RING_MATERIAL)

    s.sub("TorusMesh", "SelectionRing", [
        "inner_radius = 0.40", "outer_radius = 0.46",
        "rings = 24", "ring_segments = 4",
        'material = ExtResource("%s")' % ring_mat,
    ])

    s.node(dm.pascal(key), "Node3D", ".",
           node_paths=["_visual_root", "_selection_ring"],
           script=disc_script,
           props=['_visual_root = NodePath("Visual")',
                  'stats = ExtResource("%s")' % stats,
                  '_selection_ring = NodePath("SelectionRing")',
                  # Authored anyway, and never drawn: a disc is invulnerable,
                  # so Unit._ready never builds it a bar at all.
                  "health_bar_height = %s" % num(0.4),
                  "select_radius = 0.5",
                  # A CLICK BOX ON THE FLOOR. The anchor a click projects to is
                  # the quad itself rather than something above it, which is
                  # the honest answer for a unit with no height - and is what
                  # makes clicking a disc feel like clicking the ground it is.
                  "select_height = %s" % num(round(height, 3))])
    s.node("Visual", None, ".", instance=model)
    s.node("SelectionRing", "MeshInstance3D", ".", props=[
        "transform = %s" % t3(y=0.035),
        "visible = false",
        "cast_shadow = 0",
        'mesh = SubResource("SelectionRing")',
    ])
    write(prefab_path(key), s.render("[gd_scene format=3]"))


# --- morphs -----------------------------------------------------------------

def gen_upgrade_abilities():
    for source, target in dr.upgrade_pairs():
        row = BY_KEY[target]
        s = Scene()
        script = s.ext("Script", S_DISC_UPGRADE)
        stats = s.ext("Resource", stats_path(target))
        props = ["ability_id = %d" % _UPGRADE_IDS[(source, target)],
                 'tower_stats = ExtResource("%s")' % stats,
                 # required_tech_id stays 0 on every disc morph. The gate is
                 # the element COUNT below, which no single id can express.
                 'display_name = "%s"' % _morph_label(source, row),
                 'description = "%s"' % _effect_text(row),
                 # IMMEDIATE: the disc is already standing on the cell the
                 # morph will occupy, so there is nothing to aim.
                 "targeting = 1",
                 "slot = %d" % _morph_slot(source, row),
                 "required_element = %d" % ELEMENT_ENUM[row["element"]],
                 "required_element_techs = %d" % row["techs"]]
        if row["unique"]:
            props.append("unique_per_player = true")
        s.node("resource", None, ".", script=script, props=props)
        write(upgrade_ability_path(source, target), as_resource(
            s,
            '[gd_resource type="Resource" script_class="DiscUpgradeAbility" format=3]'))


def _morph_label(source, row):
    """What the button says. "Morph into" off the inactive disc, because that
    step costs nothing and calling it an upgrade would have a player looking
    for a price that is not there - the same wording the Elemental Core uses
    for the same reason."""
    verb = "Morph into" if row["tier"] == 1 else "Upgrade to"
    return "%s %s" % (verb, row["display"])


def _morph_slot(source, row):
    """Which square this morph claims on the disc below it.

    Off the INACTIVE disc, the element's own square on the Elemental Core's
    card, read straight out of that table rather than copied: the ten letters
    that choose an element are one set of ten letters in the whole game, and
    two copies of them would drift the first time either card was relaid out.

    Everywhere else, the single upgrade square. A disc never has two.
    """
    if row["tier"] == 1:
        return ec.CORE_MORPH_SLOTS[row["element"]]
    return UPGRADE_SLOT


def _effect_text(row):
    """One line on the button describing what the disc being bought does.

    Deliberately NOT the effect's own numbers. Those are on the passive, which
    writes them itself through effect_text(), and the card already lists that
    passive underneath - see TowerOrderAbility._add_passives. This is the line
    that says what KIND of thing the player is buying.
    """
    return EFFECT_TEXT[row["element"]]


def gen_revert():
    """The way back down out of an element, as ONE shared .tres.

    One resource for all thirty of them rather than one per disc, exactly as
    Sell and Return to Core are: what it does is the same everywhere and
    nothing about it is per disc.

    It names the inactive disc BY PATH rather than as an ext_resource, and that
    is what lets it exist at all - the inactive disc's card reaches all ten
    elements and every one of their tiers carries this ability, so a resource
    reference here would close a cycle through the entire roster. See
    ReturnToCoreAbility, which sidesteps the same cycle the same way.
    """
    base = BY_KEY[dr.disc_key(None, 0)]
    s = Scene()
    script = s.ext("Script", S_DISC_REVERT)
    props = ["ability_id = %d" % _REVERT_ID,
             'core_stats_path = "%s"' % stats_path(base["key"]),
             'display_name = "Deactivate Disc"',
             'description = "Take this disc back down to an inactive '
             'Technology Disc and choose another element. Everything spent on '
             'it above the disc itself is refunded at the usual sell share; '
             "the disc's own gold stays in the square. It keeps its square for "
             'the whole countdown, and calling it off costs nothing."',
             # IMMEDIATE: the inactive disc arrives on the cell this one is
             # already standing on, so there is nothing to aim at.
             "targeting = 1",
             "slot = %d" % REVERT_SLOT]
    if ec.has_icon(base["display"]):
        props.append('icon = ExtResource("%s")'
                     % s.ext("Texture2D", ec.icon_path(base["display"])))
    s.node("resource", None, ".", script=script, props=props)
    write(A_REVERT, as_resource(
        s, '[gd_resource type="Resource" script_class="DiscRevertAbility" format=3]'))


def gen_build_ability():
    """The inactive disc is the ONE disc the builder places. Every element is
    reached by morphing it, which is what keeps the build menu five buttons
    long while the disc roster is thirty-one deep."""
    s = Scene()
    script = s.ext("Script", S_BUILD_TOWER)
    stats = s.ext("Resource", stats_path(dr.disc_key(None, 0)))
    s.node("resource", None, ".", script=script, props=[
        "ability_id = %d" % _BUILD_ID,
        'tower_stats = ExtResource("%s")' % stats,
        'display_name = "Technology Disc"',
        'description = "%s"' % BASE_TEXT,
        # PLACEMENT: choosing it arms the snapped footprint ghost.
        "targeting = 5",
        "slot = %d" % BUILD_SLOT,
    ])
    write(build_ability_path(), as_resource(
        s, '[gd_resource type="Resource" script_class="BuildTowerAbility" format=3]'))


BASE_TEXT = ("Creeps WALK OVER a disc rather than around it, so it fills the "
             "empty squares of a maze instead of making new ones. Worth "
             "nothing until you morph it into an element you have researched.")

EFFECT_TEXT = {
    "arcane": "Creeps that walk over it take more spell damage and stop "
              "hearing their own auras.",
    "earth": "Friendly towers around it attack faster.",
    "fire": "Explodes under a creep that walks over it, for a share of that "
            "creep's maximum health.",
    "holy": "Friendly towers around it gain armor and repair themselves "
            "faster.",
    "ice": "Attacks by friendly towers around it chill what they hit.",
    "lightning": "Friendly towers around it heal off their own damage, throw "
                 "an attacker's damage back at it, and can stun it.",
    "primal": "Friendly towers around it reach further.",
    "unholy": "Attacks by friendly towers around it permanently eat armor.",
    "void": "Friendly towers around it hit harder, the more DIFFERENT kinds "
            "of tower stand in the radius.",
    "water": "Friendly towers around it regenerate mana.",
}


def generate(heights):
    passives = gen_passives()
    for row in dr.disc_rows():
        gen_stats(row)
        gen_prefab(row, heights)
    gen_upgrade_abilities()
    gen_revert()
    gen_build_ability()
    print("wrote %d disc stats, %d prefabs, %d effects, %d morphs"
          % (len(BY_KEY), len(BY_KEY), passives, len(_UPGRADE_IDS)))
