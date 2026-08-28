"""The creep table, straight from unit_data.md 6.2 and the creep `.tres` files.

The same job roster.py does for the Basic towers: one row per creep, holding
only what the GENERATOR needs and nothing it does not.

WHAT IS NOT HERE, on purpose. A creep's health, armour, speed, bounty, income,
stock and pack size all live in `Resources/UnitStats/Creeps/<key>_stats.tres`,
which unit_data.md 8.1 makes the authority once a creep exists. This tool does
not write those files and must never be able to disagree with them, so it does
not restate them - it reads the three things a MODEL is decided by:

    gold      which rung of the ladder the creep stands on. style.creep_rung
    family    ground / air / attacker, the loudest thing a model has to say
    boss      forces the top of the ladder whatever the price

`gold` and the family flags DO duplicate the `.tres`, and there is no way
around that short of parsing Godot resources here. They are the values least
likely to move - a creep's price is its identity in the send list - and a drift
is visible immediately, because the wrong creep would be wearing the wrong
armour plates. Change the `.tres` and this row in the same commit, exactly as
unit_data.md asks.

THE PLAN is this file's own: which body the creep is built on. Six of them
cover the whole of tier 1, and a new creep is usually a new row rather than a
new builder - the shapes that make one row differ from another are in
creep_models.SHAPES.
"""

# Body plans. One builder each in creep_models.py.
QUADRUPED = "quadruped"
BIPED = "biped"
ARACHNID = "arachnid"
GOLEM = "golem"
WRAITH = "wraith"
TREANT = "treant"

# Families, and the whole of what a family is for: what the creep does to the
# maze. See style.py under CREEPS for the visual rule each one carries.
GROUND = "ground"
AIR = "air"
ATTACKER = "attacker"

# How high a flyer is drawn, in world units. Mirrors CreepStats.fly_height,
# which the Shade's `.tres` leaves at its default - the ONE number in this file
# that is a default rather than an authored value, and the shadow disc under a
# flyer is drawn at minus this.
FLY_HEIGHT = 1.2

# key, display, plan, gold, family, boss
#
# In unlock order, which is ascending cost, which is also the order the ladder
# climbs - so reading this table top to bottom is reading the ladder.
CREEPS = [
    ("sheep", "Sheep", QUADRUPED, 10, GROUND, False),
    # Not sendable on its own: it only ever arrives inside a Sheep pack. It
    # takes the Sheep's rung because it is priced with it.
    ("timber_wolf", "Timber Wolf", QUADRUPED, 10, GROUND, False),
    ("skeleton_warrior", "Skeleton Warrior", BIPED, 25, GROUND, False),
    ("acolyte", "Acolyte", BIPED, 40, GROUND, False),
    ("forest_spider", "Forest Spider", ARACHNID, 50, GROUND, False),
    ("swordsman", "Swordsman", BIPED, 70, GROUND, False),
    ("fel_orc_grunt", "Fel Orc Grunt", BIPED, 100, GROUND, False),
    ("vile_temptress", "Vile Temptress", BIPED, 150, GROUND, False),
    ("shade", "Shade", WRAITH, 225, AIR, False),
    ("mud_golem", "Mud Golem", GOLEM, 400, GROUND, False),
    ("priest", "Priest", BIPED, 600, GROUND, False),
    ("corrupted_treant", "Corrupted Treant", TREANT, 750, ATTACKER, False),
    ("rot_golem", "Rot Golem", GOLEM, 1000, GROUND, True),
]


def by_key():
    return dict((row[0], row) for row in CREEPS)


def is_flying(key):
    return by_key()[key][4] == AIR


def is_attacker(key):
    return by_key()[key][4] == ATTACKER


def keys():
    return [row[0] for row in CREEPS]
