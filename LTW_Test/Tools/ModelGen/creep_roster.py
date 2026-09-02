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

THE PLAN is this file's own: which body the creep is built on. A new creep is
usually a new row rather than a new builder - the shapes that make one row
differ from another are in creep_models.SHAPES. A new BUILDER is for a creature
the existing plans would have to lie about, which is the bar the brute cleared
and nothing in tier 1 did.
"""

# Body plans. One builder each in creep_models.py.
QUADRUPED = "quadruped"
BIPED = "biped"
ARACHNID = "arachnid"
GOLEM = "golem"
WRAITH = "wraith"
TREANT = "treant"
BRUTE = "brute"
# Tier 2's three. Each is here because the plans above would have had to LIE
# about the creature, which is the bar a new builder has to clear:
WINGED = "winged"    # a solid flyer. WRAITH has no body, only a hood and rags
SHELLED = "shelled"  # wider than it is tall and roofed. QUADRUPED is a barrel
MACHINE = "machine"  # wheels, not legs, and it is the roster's only built thing
# Tier 4's one. Same bar again: every plan above walks on something, and a Naga
# has no legs at all - drawing a pair on one is the kind of lie this table
# exists to refuse. What it swings instead is its own tail, which is the trick
# the WRAITH plan already uses for its tatters.
SERPENT = "serpent"

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
    # Tier 3 starts here. The bracket is a cost bracket and nothing else, so
    # the ladder does not restart - a 225,000g creep simply stands on the top
    # rung of the same ladder the Sheep stands on the bottom of.
    # Tier 2. Above 1,000g up to and including 100,000g, ending on its Boss.
    # The ladder does not restart at a bracket - see the note above.
    ("knight", "Knight", BIPED, 1000, GROUND, False),
    ("vengeful_spirit", "Vengeful Spirit", BIPED, 2250, GROUND, False),
    ("forest_troll", "Forest Troll", BIPED, 4000, GROUND, False),
    ("wyvern", "Wyvern", WINGED, 7500, AIR, False),
    ("voidwalker", "Voidwalker", BIPED, 10000, GROUND, False),
    ("faceless_one", "Faceless One", BRUTE, 12500, GROUND, False),
    ("dragonspawn", "Dragonspawn", BIPED, 15000, GROUND, False),
    ("sea_turtle", "Sea Turtle", SHELLED, 20000, GROUND, False),
    ("banshee", "Banshee", WRAITH, 30000, AIR, False),
    ("kobold_geomancer", "Kobold Geomancer", BIPED, 60000, GROUND, False),
    ("siege_engine", "Siege Engine", MACHINE, 75000, ATTACKER, False),
    ("infernal", "Infernal", GOLEM, 100000, GROUND, True),
    # ------------------------------------------------------------------
    # TIER 3. Above 100,000g. It was one row for a long time - the Ancient
    # Wendigo was built out of order because the prototype had nothing a mid
    # tier tower could be measured against - and the rest of the bracket is
    # authored around it rather than the other way about.
    #
    # NINE of these are bipeds, brutes and golems, which is the plan crowding
    # PLACEHOLDER_ART warns about: one silhouette at nine sizes. Every one of
    # them is pulled apart on what build_biped says changes the OUTLINE -
    # stoop, robe, head and weapon - and no two share a pair of them.
    # ------------------------------------------------------------------
    ("death_revenant", "Death Revenant", BIPED, 100000, GROUND, False),
    ("satyr_shadowdancer", "Satyr Shadowdancer", BIPED, 125000, GROUND, False),
    ("crypt_fiend", "Crypt Fiend", ARACHNID, 150000, GROUND, False),
    ("necromancer", "Necromancer", BIPED, 175000, GROUND, False),
    ("spirit_walker", "Spirit Walker", BIPED, 200000, GROUND, False),
    ("ancient_wendigo", "Ancient Wendigo", BRUTE, 225000, GROUND, False),
    ("shaman", "Shaman", BIPED, 250000, GROUND, False),
    ("abomination", "Abomination", BRUTE, 275000, GROUND, False),
    ("gryphon_rider", "Gryphon Rider", WINGED, 300000, AIR, False),
    ("ogre_magi", "Ogre Magi", BRUTE, 350000, GROUND, False),
    ("chaos_wardens", "Chaos Wardens", BIPED, 400000, GROUND, False),
    ("behemoth", "Behemoth", GOLEM, 500000, GROUND, True),
    # ------------------------------------------------------------------
    # TIER 4 - SUDDEN DEATH. The whole bracket unlocks in one second at 25:00
    # and every tier below it stops being sendable, so unlike every other
    # bracket these are only ever seen NEXT TO EACH OTHER. That is what the
    # loud hides in style.py are for and it is also why the plans are spread
    # as far as they are: four flyers, three heavyweights, a machine, a
    # serpent, a beast and two small ones, and no two neighbours in the send
    # list share a plan.
    # ------------------------------------------------------------------
    ("treasure_goblin", "Treasure Goblin", BIPED, 333333, GROUND, False),
    ("huntress", "Huntress", BIPED, 500000, GROUND, False),
    ("obsidian_statue", "Obsidian Statue", GOLEM, 600000, GROUND, True),
    ("mountain_giant", "Mountain Giant", BRUTE, 600000, ATTACKER, False),
    ("harpy_windwitch", "Harpy Windwitch", WINGED, 700000, AIR, False),
    ("naga_siren", "Naga Siren", SERPENT, 800000, GROUND, False),
    ("kodo_beast", "Kodo Beast", QUADRUPED, 800000, GROUND, False),
    ("goblin_shredder", "Goblin Shredder", MACHINE, 1000000, GROUND, False),
    ("frost_wyrm", "Frost Wyrm", WINGED, 1500000, AIR, False),
    ("phoenix", "Phoenix", WINGED, 3000000, ATTACKER, True),
    ("demon", "Demon", GOLEM, 4200000, GROUND, True),
    # Not sendable on its own: three of these crawl out of a dead Obsidian
    # Statue and nothing else in the game spawns one. It takes the Statue own
    # rung, because it is priced by what bought it - the same reading the
    # Timber Wolf takes from the Sheep pack.
    ("ghoul", "Ghoul", BIPED, 600000, GROUND, False),
]


def by_key():
    return dict((row[0], row) for row in CREEPS)


def is_flying(key):
    return by_key()[key][4] == AIR


def is_attacker(key):
    return by_key()[key][4] == ATTACKER


# The one creep that is drawn as VAPOUR without being on the wraith plan.
#
# The rule has moved once already - being translucent used to belong to the AIR
# family and moved onto WRAITH when the first solid flyer arrived - and this is
# it moving a second time, for the same kind of reason. The Spirit Walker walks
# THROUGH your towers, and a creep the maze does not touch has to look like one
# a maze cannot touch. It is on the biped plan because it is a person, and it
# is vapour because of what it does.
#
# A named set rather than a column on every row, deliberately: adding one is an
# edit HERE, in the file that owns the rule, and reads as a change to the rule
# rather than as a property somebody set on a creep.
VAPOUR_KEYS = {"spirit_walker"}


def is_vapour(key):
    """Whether this creep is drawn translucent rather than opaque.

    THE PLAN's answer, not the family's, and tier 2 is what forced the split.
    Being translucent used to be part of the AIR rule, because the only flyer
    in the game was a ghost. The Wyvern is a solid animal that happens to fly,
    and drawing it as vapour would have said "spirit" about a beast.

    So the AIR family keeps the two tells that really carry it - NO LEGS and a
    shadow disc pinned to the ground - and being made of vapour belongs to the
    WRAITH plan, which is what a Shade and a Banshee are. See style.py.
    """
    return by_key()[key][2] == WRAITH or key in VAPOUR_KEYS


def keys():
    return [row[0] for row in CREEPS]
