# The technology disc roster of Warcraft III Line Tower Wars 12.4a, as
# unit_data.md section 5 records it.
#
# Nothing in this file is invented. The structure is 5.1, the effect numbers
# are 5.2, and the two project decisions applied on top are the same two every
# other roster file makes:
#
#   radii are stated in WC3 map units and divided by UNITS_PER_CELL
#   an effect stated as a percentage is authored as a SHARE, so "+8%" is 0.08
#
# THE SHAPE IS THE SAME FOR ALL TEN ELEMENTS, which is why the table below is
# generated from ELEMENTS rather than written out thirty-one times:
#
#     Technology Disc 2,500g --(free morph, needs the element's Basic tech)-->
#       Element disc
#         -> Advanced disc   250,000g, needs 2 of that element's 3 techs
#           -> Ultimate disc 1,000,000g, needs all 3, and one per player
#
# WHAT A DISC IS is in game_rules.md and it is worth having in mind while
# reading the numbers: a disc is NOT a wall. Creeps walk straight over one. It
# claims its cell against anything else being built there and it changes
# nothing about how a creep moves, so a disc is what fills the holes a maze
# already has rather than another way of making one. That is what the two
# ON-STEP effects here depend on, and it is why they can exist at all.

from roster import cells

# unit_data.md 5.1. The inactive disc is bought; the first morph is free and
# every tier above it is paid for.
#
# `gold` is the price of ONE step and `total` is everything it took to end up
# with one, the same split every other stats file in the game uses - so the
# sell refund and the Value column follow the total, and an element disc costs
# nothing to step into while still being worth the 2,500 that bought the disc
# under it.
DISC_GOLD = [2500, 0, 250000, 1000000]
DISC_TOTAL = [2500, 2500, 252500, 1252500]

# How many of the element's three technologies each tier needs (unit_data.md
# 5.1). 0 on the inactive disc, which is unlocked from the start and is the
# only building in the game that needs nothing at all.
DISC_TECHS = [0, 1, 2, 3]

# The tier a player may own only one of per element (11.0a). The disc half of
# "you cannot fill the whole maze with the best thing".
UNIQUE_TIER = 3

# What each tier is called. The source writes them "Technology Disc: Advanced
# Fire"; these are the same three tiers named the way a command card can print
# them, which is what unit_data.md 8.1 makes the .tres the authority on.
#
# Shorter for a real reason as well as a readable one: a display name is what
# the icon renderer names its PNG after, and a colon is not a legal character
# in a Windows filename.
DISC_NAMES = ["Technology Disc", "%s Disc", "Advanced %s Disc",
              "Ultimate %s Disc"]

# unit_data.md 1.4 and 1.5: a disc cannot be attacked at all, so its armour
# type is Invulnerable and its health is a number nothing will ever read. It is
# authored anyway rather than left at 0, because a unit whose maximum health is
# zero is a unit every ratio in the game divides by nothing.
DISC_HEALTH = 100

# UnitStats.ArmorType.INVULNERABLE. See unit_data.md 1.5 - this is the whole of
# what makes a wall of discs something an attacker creep cannot open, and it is
# enforced by being invulnerable rather than by a list of exceptions anywhere.
INVULNERABLE = 0

# Every element's effect, one entry per tier, exactly as unit_data.md 5.2 gives
# them.
#
# `script` is the DiscPassive subclass, `name` is what the card calls it, and
# `radius` is 0 for the two ON-STEP discs - which is also how DiscPassive tells
# the two shapes apart, so a radius here is never optional decoration.
#
# `tiers` is three dictionaries of that passive's own @exports, in tier order:
# element, advanced, ultimate. The base disc carries no passive at all, which
# is what "a base disc does nothing" means and is why there are three rather
# than four.
DISCS = {
    # On-step. Reworked in 10.0a; the 9.4 sheet's version is gone.
    "arcane": {
        "script": "res://Scripts/Abilities/DiscPassives/ArcaneDiscPassive.gd",
        "name": "Null Field",
        "radius": 0.0,
        "tiers": [
            {"duration_seconds": 12.0, "spell_amp": 0.10, "trigger_seconds": 1.0},
            {"duration_seconds": 20.0, "spell_amp": 0.10, "trigger_seconds": 1.0},
            {"duration_seconds": 25.0, "spell_amp": 0.10, "trigger_seconds": 1.0},
        ],
    },
    "earth": {
        "script": "res://Scripts/Abilities/DiscPassives/EarthDiscPassive.gd",
        "name": "Quickening",
        "radius": cells(300),
        "tiers": [
            {"attack_speed_bonus": 0.08},
            {"attack_speed_bonus": 0.12},
            {"attack_speed_bonus": 0.15},
        ],
    },
    # Reworked in 11.0a. The erosion floor is 0 and lives in the script rather
    # than here, because all three tiers share it - the one thing in the game
    # that goes past zero is the Divineshroom line and it says so itself.
    "unholy": {
        "script": "res://Scripts/Abilities/DiscPassives/UnholyDiscPassive.gd",
        "name": "Corrosion",
        "radius": cells(300),
        "tiers": [
            {"armor_per_hit": 0.05},
            {"armor_per_hit": 0.067},
            {"armor_per_hit": 0.1},
        ],
    },
    # Added in 10.0a. Its stacking rule - a weaker disc must never override a
    # stronger one - was a real bug fixed in 12.3a and is a property of
    # TowerBuffs rather than of these numbers.
    "primal": {
        "script": "res://Scripts/Abilities/DiscPassives/PrimalDiscPassive.gd",
        "name": "Far Sight",
        "radius": cells(300),
        "tiers": [
            {"range_bonus_cells": cells(100)},
            {"range_bonus_cells": cells(200)},
            {"range_bonus_cells": cells(250)},
        ],
    },
    # On-step. The 9.4 sheet gives the first two tiers as approximate; the
    # Ultimate's three figures are exact.
    "fire": {
        "script": "res://Scripts/Abilities/DiscPassives/FireDiscPassive.gd",
        "name": "Detonate",
        "radius": 0.0,
        "tiers": [
            {"max_health_share": 0.20, "cooldown_seconds": 30.0,
             "creep_immunity_seconds": 5.0},
            {"max_health_share": 0.24, "cooldown_seconds": 30.0,
             "creep_immunity_seconds": 5.0},
            {"max_health_share": 0.33, "cooldown_seconds": 15.0,
             "creep_immunity_seconds": 3.6},
        ],
    },
    "ice": {
        "script": "res://Scripts/Abilities/DiscPassives/IceDiscPassive.gd",
        "name": "Frostbind",
        "radius": cells(300),
        "tiers": [
            {"chill_per_hit": 0.01, "chill_cap": 0.20},
            {"chill_per_hit": 0.015, "chill_cap": 0.30},
            {"chill_per_hit": 0.018, "chill_cap": 0.36},
        ],
    },
    # The wide radius, alongside Holy. Two thirds of this effect is worth
    # nothing until an attacker creep arrives, so where it goes is the front of
    # a maze and its reach is shaped for that.
    "lightning": {
        "script": "res://Scripts/Abilities/DiscPassives/LightningDiscPassive.gd",
        "name": "Static Field",
        "radius": cells(500),
        "tiers": [
            {"heal_share": 0.01, "return_share": 5.0, "stun_chance": 0.15},
            {"heal_share": 0.016, "return_share": 7.5, "stun_chance": 0.20},
            {"heal_share": 0.0175, "return_share": 10.0, "stun_chance": 0.25},
        ],
    },
    # The one disc whose two numbers climb differently: only the armour scales
    # past Advanced, and the regeneration deliberately stops. Visible here as
    # the same figure twice rather than hidden in a rule anywhere.
    "holy": {
        "script": "res://Scripts/Abilities/DiscPassives/HolyDiscPassive.gd",
        "name": "Sanctuary",
        "radius": cells(500),
        "tiers": [
            {"armor_bonus": 3.0, "regen_bonus_share": 1.65},
            {"armor_bonus": 6.0, "regen_bonus_share": 2.00},
            {"armor_bonus": 8.0, "regen_bonus_share": 2.00},
        ],
    },
    # The "reward a varied maze" disc. Note the Advanced tier raises only the
    # CAP: the step per tower type is the same 2% the base disc gives, so what
    # the upgrade buys is the room to reach further with it.
    "void": {
        "script": "res://Scripts/Abilities/DiscPassives/VoidDiscPassive.gd",
        "name": "Emptiness",
        "radius": cells(300),
        "tiers": [
            {"damage_per_type": 0.02, "damage_cap": 0.08},
            {"damage_per_type": 0.02, "damage_cap": 0.16},
            {"damage_per_type": 0.03, "damage_cap": 0.24},
        ],
    },
    # Mana regeneration is the WHOLE effect. The whirlpool in the 9.4 sheet was
    # removed from the source game and must not be built.
    "water": {
        "script": "res://Scripts/Abilities/DiscPassives/WaterDiscPassive.gd",
        "name": "Wellspring",
        "radius": cells(300),
        "tiers": [
            {"mana_regen_per_second": 2.0},
            {"mana_regen_per_second": 4.0},
            {"mana_regen_per_second": 5.4},
        ],
    },
}

# The order the roster is WALKED in, which decides nothing a player ever sees.
#
# Its own list rather than DISCS.keys(), for the same reason element_roster has
# one: ids are handed out in this order and are permanent once shipped, so the
# order has to be something that cannot quietly change. Which square each
# element claims on the card is a different question entirely and is answered
# by the elemental roster's own CORE_MORPH_SLOTS - see disc_content.
ELEMENT_ORDER = ["arcane", "earth", "fire", "holy", "ice",
                 "lightning", "primal", "unholy", "void", "water"]

# The first unit_type_id and the first ability_id this roster claims.
#
# LITERALS, scanned once off the folders and never computed. CLAUDE.md: an id
# is authored rather than derived, it is unique within its namespace and
# permanent once it exists, and the registry refuses a duplicate loudly at boot
# - so a collision is a failed boot rather than a bug that ships. Both numbers
# are picked clear of everything the other generators count out and everything
# the hand-authored creep content claims.
FIRST_UNIT_TYPE_ID = 184
FIRST_ABILITY_ID = 383


def element_label(element):
    """The element as a display name writes it: "Fire", "Lightning"."""
    return element.capitalize()


def disc_key(element, tier):
    """The key every file of one disc is named by.

    tier 0 is the inactive disc and has no element at all, which is why it is
    the one key not built from one.
    """
    if tier == 0:
        return "technology_disc"
    if tier == 1:
        return "%s_disc" % element
    if tier == 2:
        return "advanced_%s_disc" % element
    return "ultimate_%s_disc" % element


def disc_display(element, tier):
    if tier == 0:
        return DISC_NAMES[0]
    return DISC_NAMES[tier] % element_label(element)


def disc_rows():
    """Every disc in the game, inactive one first, then each element bottom
    up.

    One dictionary per disc with everything the content stage needs and nothing
    it has to look up again: its key, its display name, its element, its tier,
    its two prices, how many technologies it wants, and the passive it carries.
    """
    rows = [{
        "key": disc_key(None, 0),
        "display": disc_display(None, 0),
        "element": None,
        "tier": 0,
        "gold": DISC_GOLD[0],
        "total": DISC_TOTAL[0],
        "techs": DISC_TECHS[0],
        "unique": False,
        "passive": None,
    }]

    for element in ELEMENT_ORDER:
        entry = DISCS[element]
        for tier in (1, 2, 3):
            rows.append({
                "key": disc_key(element, tier),
                "display": disc_display(element, tier),
                "element": element,
                "tier": tier,
                "gold": DISC_GOLD[tier],
                "total": DISC_TOTAL[tier],
                "techs": DISC_TECHS[tier],
                "unique": tier == UNIQUE_TIER,
                "passive": {
                    "script": entry["script"],
                    "name": entry["name"],
                    "radius": entry["radius"],
                    "fields": entry["tiers"][tier - 1],
                },
            })
    return rows


def upgrade_pairs():
    """Every morph in the roster, as (from_key, to_key).

    The inactive disc morphs into all ten elements, and each element disc
    climbs its own two rungs. Walked in the same fixed order disc_rows uses,
    because upgrade ability ids are handed out along it.
    """
    pairs = []
    for element in ELEMENT_ORDER:
        pairs.append((disc_key(None, 0), disc_key(element, 1)))
    for element in ELEMENT_ORDER:
        pairs.append((disc_key(element, 1), disc_key(element, 2)))
        pairs.append((disc_key(element, 2), disc_key(element, 3)))
    return pairs


def by_key():
    return {row["key"]: row for row in disc_rows()}


def unit_type_ids():
    """key -> unit_type_id, handed out along the walk order above and permanent
    from the moment they ship. See FIRST_UNIT_TYPE_ID."""
    ids = {}
    for index, row in enumerate(disc_rows()):
        ids[row["key"]] = FIRST_UNIT_TYPE_ID + index
    return ids
