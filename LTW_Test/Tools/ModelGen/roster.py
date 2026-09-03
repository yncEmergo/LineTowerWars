# The Basic tower roster of Warcraft III Line Tower Wars 12.4a, as unit_data.md
# section 3 records it, plus the three project decisions that turn those rows
# into resources:
#
#   range and splash are stated in WC3 map units and divided by UNITS_PER_CELL
#   attack speed is stated as a COOLDOWN and is inverted into attacks per second
#   health and armour come from the price tier alone (unit_data.md 1.4)
#
# Nothing here is invented. The one thing this file decides that the source
# does not record is DELIVERY - the source has no projectile data at all
# (unit_data.md 7.2) - and that is one choice per branch, not per tower.

UNITS_PER_CELL = 128.0
# Every reach the game states is a multiple of this. See cells().
QUARTER = 0.25

# DamageTable.DamageType
MAGIC, CHAOS, NORMAL, PIERCING, SIEGE = 0, 1, 2, 3, 4
# The one type that is not physical: it ignores the armour matrix and a creep's
# armour points entirely. No tower's BASIC attack deals it - it is what an
# ability deals, and what an attack that pierces armour deals down its line.
SPELL = 5
# UnitStats.ArmorType
FORTIFIED = 5
# AttackStats target flags
GROUND, AIR = 1, 2
BOTH = GROUND | AIR

# unit_data.md 1.4: health and armour depend only on the price tier.
TIER_BODY = {
    10: (25, 0),
    30: (35, 1),
    150: (75, 3),
    1000: (175, 5),
    5000: (575, 5),
    25000: (2275, 5),
}

# Build, upgrade and sell times are NOT here and are not per tower: every
# tower shares one of each (unit_data.md 1.4 and 1.8), so they live on
# GameConfig as build_seconds and sell_seconds.

# --- delivery, one choice per branch ---------------------------------------
# (kind, projectile path, speed, arc). Instant carries no projectile at all.
# Speeds are HALF what they started at: the first pass read as hitscan, and a
# projectile whose travel time cannot be seen may as well be an instant attack.
# A tuning value, not a copied one - the source records no projectile data.
DELIVERY = {
    "archer":   ("projectile", "res://Scenes/Effects/arrow.tscn", 16.0, 0.0),
    "watch":    ("projectile", "res://Scenes/Effects/arrow.tscn", 16.0, 0.0),
    "cannon":   ("projectile", "res://Scenes/Effects/mortar_shell.tscn", 6.0, 2.4),
    "cutter":   ("instant", "", 0.0, 0.0),
    "carver":   ("instant", "", 0.0, 0.0),
    "crusher":  ("instant", "", 0.0, 0.0),
    "sentry":   ("projectile", "res://Scenes/Effects/magic_bolt.tscn", 10.0, 0.0),
    "defender": ("projectile", "res://Scenes/Effects/magic_bolt.tscn", 10.0, 0.0),
    "turret":   ("projectile", "res://Scenes/Effects/missile.tscn", 13.0, 0.35),
}

# Seconds between an attack committing and its damage landing, per branch.
#
# Authored ONLY where there is an animation to fill it. A windup with nothing
# playing in it is a delay a player cannot see the reason for, so the default
# is 0 and a branch opts in when it gains a swing. It comes out of the attack
# period rather than adding to it - see AttackStats.windup_seconds.
WINDUP = {
    "crusher": 0.55,
}

# Branches whose splash radiates from the TOWER rather than from the creep it
# hit. See Scripts/Combat/SelfSplashEffect.gd; it is a deliberate exception to
# the splash rule in game_rules.md and the Crusher is the reason it exists.
SELF_SPLASH_BRANCHES = ("crusher",)

# What each branch does when it attacks, wired into the PREFAB rather than into
# the model: these components need the unit, and the prefab is where the rest
# of the unit wiring already lives. Decoration that needs no unit - a halo, an
# orbit, a floating core - stays in the model.
#
#   recoil  (node, distance)          kicks back when the shot leaves
#   slam    (node, shockwave)         rises and falls across the windup
#   spin    (node, running, idle)     turns only while there is something to
#                                     kill, and coasts down when there is not
ANIMATION = {
    "archer":   [("recoil", "Turret/Stock", 0.045)],
    "watch":    [("recoil", "Turret/Barrel", 0.075)],
    "cannon":   [("recoil", "Turret/Barrel", 0.06)],
    "cutter":   [("spin", "Turret/Spinner", 1.1, 0.0)],
    "carver":   [("spin", "Turret/Spinner", 2.4, 0.0)],
    "crusher":  [("slam", "Turret/Swing", "res://Scenes/Effects/shockwave.tscn")],
    "sentry":   [],
    "defender": [],
    "turret":   [("recoil", "Turret/Rack", 0.05)],
}

IMPACT = {
    "cannon":   "res://Scenes/Effects/blast_impact.tscn",
    "carver":   "res://Scenes/Effects/blood_spray.tscn",
    "cutter":   "res://Scenes/Effects/blood_spray.tscn",
    "defender": "res://Scenes/Effects/arcane_impact.tscn",
    "turret":   "res://Scenes/Effects/blast_impact.tscn",
    # The Crusher has none on purpose: its blast is centred on itself, so its
    # slam animation draws the ring and an impact visual on the creep it swung
    # at would put a second one in the wrong place.
}

BRANCH_TEXT = {
    "archer": "Cheap ranged opener. Piercing shots that reach a long way for the price, "
              "at ground and air alike.",
    "watch": "Pure single target reach. The longest range in the game, and no "
             "splash at all.",
    "cannon": "Siege mortar. Slow, and the shell damages everything around where it "
              "lands. Cannot hit air at any tier.",
    "cutter": "Cheap grinder. Almost no reach, and the fastest attack in the game.",
    "carver": "Single target grinder. Keeps the line's speed and its very short reach, "
              "and gains air targets from the second tier up.",
    "crusher": "Overhead slam. The slowest attack in the game, over the widest area, "
               "and it reaches air.",
    "sentry": "Cheap magic tower. Long ranged from the very first tier, at ground and "
              "air alike.",
    "defender": "Long ranged magic splash. Damages everything around the target "
                "wherever it stands, ground or air.",
    "turret": "Dedicated anti-air. Cannot hit ground at any tier.",
}

# key, display, line, branch, tier, gold, total, dtype, dmin, dmax,
# cooldown seconds, range units, splash units, targets
TOWERS = [
    # --- Archer line -------------------------------------------------------
    ("lesser_archer",         "Lesser Archer",         "archer", "archer",  0,    10,    10, PIERCING,    1,    1, 0.667,  400,   0, BOTH),
    ("archer",                "Archer",                "archer", "archer",  1,    30,    40, PIERCING,    3,    3, 0.638,  500,   0, BOTH),

    ("lesser_watch_tower",    "Lesser Watch Tower",    "archer", "watch",   0,   150,   190, PIERCING,    8,   10, 0.5,    700,   0, BOTH),
    ("watch_tower",           "Watch Tower",           "archer", "watch",   1,  1000,  1190, PIERCING,   38,   40, 0.5,    700,   0, BOTH),
    ("greater_watch_tower",   "Greater Watch Tower",   "archer", "watch",   2,  5000,  6190, PIERCING,  157,  158, 0.5,    800,   0, BOTH),
    ("ultimate_watch_tower",  "Ultimate Watch Tower",  "archer", "watch",   3, 25000, 31190, PIERCING,  609,  610, 0.5,    800,   0, BOTH),

    ("lesser_cannon",         "Lesser Cannon",         "archer", "cannon",  0,   150,   190, SIEGE,      16,   19, 2.0,    500, 150, GROUND),
    ("cannon",                "Cannon",                "archer", "cannon",  1,  1000,  1190, SIEGE,      77,   81, 2.0,    500, 200, GROUND),
    ("greater_cannon",        "Greater Cannon",        "archer", "cannon",  2,  5000,  6190, SIEGE,     294,  298, 2.0,    600, 250, GROUND),
    ("ultimate_cannon",       "Ultimate Cannon",       "archer", "cannon",  3, 25000, 31190, SIEGE,    1147, 1153, 2.0,    600, 300, GROUND),

    # --- Cutter line -------------------------------------------------------
    ("lesser_cutter",         "Lesser Cutter",         "cutter", "cutter",  0,    10,    10, NORMAL,      1,    1, 0.333,  150,   0, GROUND),
    ("cutter",                "Cutter",                "cutter", "cutter",  1,    30,    40, NORMAL,      3,    3, 0.333,  150,   0, GROUND),

    # unit_data.md 7.1.6: the 9.4 sheet has the first tier Ground only and every
    # tier above it Ground and Air. Copied as the sheet states it.
    ("lesser_carver",         "Lesser Carver",         "cutter", "carver",  0,   150,   190, NORMAL,     14,   16, 0.333,  150,   0, GROUND),
    ("carver",                "Carver",                "cutter", "carver",  1,  1000,  1190, NORMAL,     69,   75, 0.333,  150,   0, BOTH),
    ("greater_carver",        "Greater Carver",        "cutter", "carver",  2,  5000,  6190, NORMAL,    291,  299, 0.333,  200,   0, BOTH),
    ("ultimate_carver",       "Ultimate Carver",       "cutter", "carver",  3, 25000, 31190, NORMAL,   1180, 1191, 0.333,  200,   0, BOTH),

    ("lesser_crusher",        "Lesser Crusher",        "cutter", "crusher", 0,   150,   190, NORMAL,     24,   26, 5.0,    150, 300, BOTH),
    ("crusher",               "Crusher",               "cutter", "crusher", 1,  1000,  1190, NORMAL,    136,  141, 5.0,    150, 300, BOTH),
    ("greater_crusher",       "Greater Crusher",       "cutter", "crusher", 2,  5000,  6190, NORMAL,    601,  608, 5.0,    150, 350, BOTH),
    ("ultimate_crusher",      "Ultimate Crusher",      "cutter", "crusher", 3, 25000, 31190, NORMAL,   2395, 2403, 5.0,    150, 400, BOTH),

    # --- Sentry line -------------------------------------------------------
    ("lesser_sentry",         "Lesser Sentry",         "sentry", "sentry",  0,    10,    10, MAGIC,       2,    2, 1.5,    800,   0, BOTH),
    ("sentry",                "Sentry",                "sentry", "sentry",  1,    30,    40, MAGIC,       6,    6, 1.5,    800,   0, BOTH),

    ("lesser_defender",       "Lesser Defender",       "sentry", "defender",0,   150,   190, MAGIC,       8,   11, 1.2,    800, 100, BOTH),
    ("defender",              "Defender",              "sentry", "defender",1,  1000,  1190, MAGIC,      41,   44, 1.2,    800, 125, BOTH),
    ("greater_defender",      "Greater Defender",      "sentry", "defender",2,  5000,  6190, MAGIC,     160,  163, 1.2,    900, 175, BOTH),
    ("ultimate_defender",     "Ultimate Defender",     "sentry", "defender",3, 25000, 31190, MAGIC,     585,  588, 1.2,    900, 225, BOTH),

    ("lesser_turret",         "Lesser Turret",         "sentry", "turret",  0,   150,   190, SIEGE,      19,   27, 0.8,    900,   0, AIR),
    ("turret",                "Turret",                "sentry", "turret",  1,  1000,  1190, SIEGE,     162,  170, 0.8,    900,   0, AIR),
    ("greater_turret",        "Greater Turret",        "sentry", "turret",  2,  5000,  6190, SIEGE,     553,  561, 0.8,   1000,   0, AIR),
    ("ultimate_turret",       "Ultimate Turret",       "sentry", "turret",  3, 25000, 31190, SIEGE,    2022, 2030, 0.8,   1000,   0, AIR),
]

# Which tower each one can become. A branch point carries two.
UPGRADES = {
    "lesser_archer":       ["archer"],
    "archer":              ["lesser_watch_tower", "lesser_cannon"],
    "lesser_watch_tower":  ["watch_tower"],
    "watch_tower":         ["greater_watch_tower"],
    "greater_watch_tower": ["ultimate_watch_tower"],
    "lesser_cannon":       ["cannon"],
    "cannon":              ["greater_cannon"],
    "greater_cannon":      ["ultimate_cannon"],

    "lesser_cutter":       ["cutter"],
    "cutter":              ["lesser_carver", "lesser_crusher"],
    "lesser_carver":       ["carver"],
    "carver":              ["greater_carver"],
    "greater_carver":      ["ultimate_carver"],
    "lesser_crusher":      ["crusher"],
    "crusher":             ["greater_crusher"],
    "greater_crusher":     ["ultimate_crusher"],

    "lesser_sentry":       ["sentry"],
    "sentry":              ["lesser_defender", "lesser_turret"],
    "lesser_defender":     ["defender"],
    "defender":            ["greater_defender"],
    "greater_defender":    ["ultimate_defender"],
    "lesser_turret":       ["turret"],
    "turret":              ["greater_turret"],
    "greater_turret":      ["ultimate_turret"],
}

# The three towers the builder can place. Everything else is reached by
# upgrading one of them.
BUILDABLE = ["lesser_archer", "lesser_cutter", "lesser_sentry"]

# --- authored ids ----------------------------------------------------------
# Handed out in creation order and permanent once authored. 10-13 and 21-24 are
# BURNED: they belonged to the four test towers this roster replaces, and an id
# is never reused. See CLAUDE.md.
FIRST_UNIT_TYPE_ID = 26
ABILITY_ID_BUILD = 67          # 67, 68, 69 - one per line
ABILITY_ID_CANCEL_UPGRADE = 70
ABILITY_ID_PRIORITIZE = 71
FIRST_UPGRADE_ABILITY_ID = 72  # 72 .. 98, in the order UPGRADES is written


def by_key():
    return {t[0]: t for t in TOWERS}


def unit_type_ids():
    return {t[0]: FIRST_UNIT_TYPE_ID + i for i, t in enumerate(TOWERS)}


def upgrade_ability_ids():
    ids = {}
    n = FIRST_UPGRADE_ABILITY_ID
    for src, targets in UPGRADES.items():
        for target in targets:
            ids[(src, target)] = n
            n += 1
    return ids


def cells(units):
    """A Warcraft III map distance as a REACH the game states, in cells.

    Snapped to the nearest QUARTER CELL rather than handed over as the raw
    division. Dividing 400 by 128 gives 3.125, and a roster written that way
    reads as a wall of numbers nobody can hold - 2.34, 4.69, 7.03, 9.77. The
    quarter is the grain the whole game is now stated in, so a player reading
    "4.75" can picture it and two towers a quarter apart really are different.

    It costs up to an eighth of a cell against the source figure, which is
    below the width of a creep and far below anything a maze is built to.

    The tables above keep the SOURCE number, so unit_data.md still mirrors
    them and a patch note can still be replayed onto them; this is the one
    place the conversion happens and so the one place to change it.
    """
    return round(units / UNITS_PER_CELL / QUARTER) * QUARTER


def aps(cooldown):
    return round(1.0 / cooldown, 3)
