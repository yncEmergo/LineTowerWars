# The elemental tower roster of Warcraft III Line Tower Wars 12.4a, as
# unit_data.md section 4 records it, plus the same three project decisions
# roster.py applies to the Basic towers:
#
#   range and splash are stated in WC3 map units and divided by UNITS_PER_CELL
#   attack speed is stated as a COOLDOWN and is inverted into attacks per second
#   health and armour come from the price tier alone (unit_data.md 1.4)
#
# Nothing in the TOWERS table is invented. What this file decides that the
# source does not record is the same two things roster.py decides - DELIVERY
# and the attack ANIMATION - plus one more that only elemental towers have: the
# numbers each tower's named ABILITY is authored with, which are copied out of
# unit_data.md 4.1 to 4.10 into the ABILITIES table at the bottom.
#
# Every element has the same shape (unit_data.md 4):
#
#     Elemental Core 200g --(free, needs the element's Basic tech)--> base 200g
#       -> the 800g upgrade
#         -> Lesser (1) 4,000g -> Greater (1) 10,000g -> Ultimate (1) 30,000g
#         -> Lesser (2) 4,000g -> Greater (2) 10,000g -> Ultimate (2) 30,000g
#
# so the table below is generated from ELEMENTS rather than written out
# eighty-one times: every element names its two base towers and its two paths,
# and the tier structure is the same for all ten.

from roster import (UNITS_PER_CELL, MAGIC, CHAOS, NORMAL, PIERCING, SIEGE,
                    SPELL, GROUND, AIR, BOTH, cells, aps)

# unit_data.md 1.4: an elemental tower's health depends only on its price tier,
# and its armour is 5 at every one of them.
TIER_BODY = {
    200: (100, 5),
    800: (150, 5),
    4000: (750, 5),
    10000: (1500, 5),
    30000: (3000, 5),
}

# The price of the ELEMENTAL CORE itself, and the fact that morphing it into an
# element's base tower is FREE.
#
# That falls straight out of the existing model rather than needing a special
# case: `gold_cost` is the price of ONE step, so an element's 200g base tower
# authors 0 there and 200 in `total_gold_cost`. The Core is what charged the
# 200, and the sell refund still reads the total.
CORE_GOLD = 200

# unit_data.md 1.8: a technology tower refunds half rather than the 60% a Basic
# one does. NOT APPLIED YET - the refund share is one GameConfig value shared
# by every building, and splitting it is a rules change rather than content.
# Written down here so the number is not lost. See game_rules.md.
TECHNOLOGY_SELL_REFUND = 0.5

# --- delivery, one choice per path ------------------------------------------
#
# (kind, projectile path, speed, arc). The source records no projectile data at
# all (unit_data.md 7.2), so this is chosen per path the way roster.DELIVERY is
# chosen per branch - and on the same principle: what the tower's ability
# DESCRIBES is what should be seen leaving it.
DELIVERY = {
    # base towers
    "core": ("instant", "", 0.0, 0.0),
    # Almost flat, on review: a Fire Pit lobbing its bolt read as a mortar,
    # and the crater it fires out of is at eye height already.
    "fire_base": ("projectile", "res://Scenes/Effects/fire_bolt.tscn", 9.0, 0.12),
    "ice_base": ("projectile", "res://Scenes/Effects/frost_bolt.tscn", 11.0, 0.0),
    "lightning_base": ("instant", "", 0.0, 0.0),
    "holy_base": ("projectile", "res://Scenes/Effects/holy_mote.tscn", 14.0, 0.0),
    "void_base": ("projectile", "res://Scenes/Effects/void_bolt.tscn", 10.0, 0.0),
    "unholy_base": ("projectile", "res://Scenes/Effects/poison_glob.tscn", 8.0, 0.7),
    "water_base": ("projectile", "res://Scenes/Effects/water_jet.tscn", 12.0, 0.0),
    "earth_base": ("projectile", "res://Scenes/Effects/boulder.tscn", 6.0, 2.2),
    "arcane_base": ("projectile", "res://Scenes/Effects/arcane_shard.tscn", 12.0, 0.0),
    "primal_base": ("projectile", "res://Scenes/Effects/boulder.tscn", 7.0, 1.6),

    # paths
    # Arc 0 and fast, because the Moonbeam's shot does not travel to its
    # target at all - it is CALLED DOWN on it, see SKY_LAUNCH below. An arc on
    # top of that dive would bow a falling rock upwards.
    "moonbeam": ("projectile", "res://Scenes/Effects/meteor.tscn", 12.8, 0.0),
    "firelord": ("projectile", "res://Scenes/Effects/fire_bolt.tscn", 11.0, 0.4),
    # A plate rather than a bolt, on review, thrown nearly flat and slower than
    # the base pair's shot: what a Lich does is heavy and cold, not fast.
    "lich": ("projectile", "res://Scenes/Effects/frost_disc.tscn", 8.5, 0.12),
    # The one PIERCE in the game. It does not home, it flies through everything
    # in its path, and it stops when it has run out of distance rather than when
    # it has arrived. See PIERCE below and Scripts/Combat/PierceDelivery.gd.
    "crystal": ("pierce", "res://Scenes/Effects/ice_spike.tscn", 26.0, 0.0),
    "annihilation_glyph": ("instant", "", 0.0, 0.0),
    "orb_keeper": ("instant", "", 0.0, 0.0),
    "divineshroom": ("projectile", "res://Scenes/Effects/spore_burst.tscn", 9.0, 0.8),
    "titan_vault": ("projectile", "res://Scenes/Effects/holy_bolt.tscn", 16.0, 0.0),
    "spellslinger": ("projectile", "res://Scenes/Effects/arcane_shard.tscn", 13.0, 0.0),
    # Three times what the rest of the element flies at, and deliberately: an
    # Arcane Orb is a slow single shot carrying most of the tower's damage, and
    # at an ordinary speed a creep it was aimed at had usually walked out of the
    # blast before it landed.
    "arcane_orb": ("projectile", "res://Scenes/Effects/arcane_orb.tscn", 27.0, 0.0),
    "ancient_warden": ("projectile", "res://Scenes/Effects/boulder.tscn", 6.0, 2.4),
    "scorpion": ("projectile", "res://Scenes/Effects/thorn.tscn", 20.0, 0.0),
    "gravedigger": ("projectile", "res://Scenes/Effects/poison_glob.tscn", 9.0, 0.5),
    "alchemist": ("projectile", "res://Scenes/Effects/acid_flask.tscn", 7.0, 2.0),
    "harbinger": ("projectile", "res://Scenes/Effects/void_bolt.tscn", 11.0, 0.0),
    "leviathan": ("instant", "", 0.0, 0.0),
    "hurricane_elemental": ("projectile", "res://Scenes/Effects/water_jet.tscn", 13.0, 0.0),
    "sludge_monstrosity": ("projectile", "res://Scenes/Effects/sludge_glob.tscn", 8.0, 0.9),
    "primalist": ("projectile", "res://Scenes/Effects/nature_bolt.tscn", 11.0, 0.3),
    "beastmaster": ("instant", "", 0.0, 0.0),
}

# Paths whose shot is CALLED DOWN rather than fired, as an offset in world
# units from the point it will land.
#
# The projectile is spawned there instead of at the muzzle, so its whole flight
# is the dive onto the target and the tower it came from is not on the line at
# all. Everything else about it is an ordinary projectile: it homes, it takes
# real time, and the damage lands when it arrives.
#
# The numbers are read against the camera, which looks down the -Z axis pitched
# 70 degrees over from a distance of 15 - see Resources/Config/camera_config.tres.
# Y clears the top of the frame from anywhere in it, so the meteor is never seen
# appearing; -X puts its origin off to the LEFT, which is what makes the fall
# read as diagonal rather than as something dropped straight down.
SKY_LAUNCH = {
    "moonbeam": (-9.0, 16.0, 0.0),
}

# Ground a path's attack sets ALIGHT where it lands, as
# (seconds, tick seconds, damage share per second, share of the splash radius).
#
# The damage is a SHARE of the attack's own rather than a number, so one row
# covers all three tiers of a path and the patch can never drift out of step
# with the attack that lit it.
#
# The RADIUS is a share of the attack's splash for the same reason, and it is
# deliberately not 1. Drawn at the full splash the patch was the loudest thing
# on the field and read as the tower's whole area of effect, which it is not -
# the splash is instant and invisible, and only the fire left behind is drawn.
# Half of it is a fire inside the blast rather than a fire the size of it.
BURNING_GROUND = {
    "moonbeam": (3.0, 0.4, 0.12, 0.5),
}

# Paths whose shot PIERCES: how far it flies before giving up, and what the
# creeps behind the first one take.
#
# The distance is stated against the width of a TOWER rather than against the
# tower's own attack range, and that is the point of it being here at all: what
# a player reads off a piercing shot is how far down the lane it reaches, and
# tying that to a targeting range would move it every time the range is retuned.
# Eight tower widths is far enough to leave the tower's own reach and carry on.
#
# Spell Damage down the line is what makes Ice 2 "ignore armour entirely" -
# unit_data.md 4.5 - since Spell is the one type that skips both the matrix and
# the armour points. The FIRST creep struck is still an ordinary hit of the
# tower's own type.
PIERCE = {
    "crystal": (8.0, SPELL),
}

IMPACT = {
    "fire_base": "res://Scenes/Effects/flame_impact.tscn",
    "moonbeam": "res://Scenes/Effects/flame_impact.tscn",
    "firelord": "res://Scenes/Effects/flame_impact.tscn",
    "ice_base": "res://Scenes/Effects/frost_impact.tscn",
    "lich": "res://Scenes/Effects/frost_impact.tscn",
    "crystal": "res://Scenes/Effects/frost_impact.tscn",
    # Particles rather than a ring on the floor. An electrical hit should
    # throw something off the creep it earths itself in, the way a blade
    # throws blood - a flat disc says "area" and this attack has none.
    "lightning_base": "res://Scenes/Effects/spark_burst.tscn",
    # An ARC, drawn back to the muzzle, so every creep the Glyph strikes has
    # a line of lightning to the tower that struck it - the aimed one and
    # every creep its chain reached. See LightningBolt3D.
    "annihilation_glyph": "res://Scenes/Effects/annihilation_bolt.tscn",
    "orb_keeper": "res://Scenes/Effects/spark_impact.tscn",
    "holy_base": "res://Scenes/Effects/holy_impact.tscn",
    "divineshroom": "res://Scenes/Effects/holy_impact.tscn",
    "titan_vault": "res://Scenes/Effects/holy_impact.tscn",
    "void_base": "res://Scenes/Effects/void_impact.tscn",
    "harbinger": "res://Scenes/Effects/void_impact.tscn",
    "leviathan": "res://Scenes/Effects/void_impact.tscn",
    "unholy_base": "res://Scenes/Effects/toxic_impact.tscn",
    "gravedigger": "res://Scenes/Effects/toxic_impact.tscn",
    "alchemist": "res://Scenes/Effects/toxic_impact.tscn",
    "water_base": "res://Scenes/Effects/water_impact.tscn",
    "hurricane_elemental": "res://Scenes/Effects/water_impact.tscn",
    "sludge_monstrosity": "res://Scenes/Effects/toxic_impact.tscn",
    "earth_base": "res://Scenes/Effects/blast_impact.tscn",
    "ancient_warden": "res://Scenes/Effects/blast_impact.tscn",
    "scorpion": "res://Scenes/Effects/blood_spray.tscn",
    "arcane_base": "res://Scenes/Effects/arcane_impact.tscn",
    "spellslinger": "res://Scenes/Effects/arcane_impact.tscn",
    "arcane_orb": "res://Scenes/Effects/arcane_impact.tscn",
    "primal_base": "res://Scenes/Effects/blast_impact.tscn",
    "primalist": "res://Scenes/Effects/nature_impact.tscn",
    "beastmaster": "res://Scenes/Effects/blood_spray.tscn",
}

# Seconds between an attack committing and its damage landing, per path.
# Authored only where there is an animation to fill it, exactly as roster.WINDUP
# is: a windup with nothing playing in it is a delay a player cannot see the
# reason for.
WINDUP = {
    "moonbeam": 0.5,
    "ancient_warden": 0.45,
    "beastmaster": 0.35,
    "alchemist": 0.3,
}

# What each path does when it attacks, wired into the PREFAB. Same three kinds
# roster.ANIMATION offers, and the same reason they live in the prefab: they
# need the unit, and the build ghost must not recoil at anything.
ANIMATION = {
    "fire_base": [],
    "ice_base": [],
    "lightning_base": [("sparks", "Turret/Sparks")],
    "holy_base": [],
    "void_base": [],
    "unholy_base": [],
    "water_base": [],
    "earth_base": [("recoil", "Turret/Arm", 0.06)],
    "arcane_base": [],
    "primal_base": [("recoil", "Turret/Arm", 0.05)],

    "moonbeam": [("recoil", "Turret/Orb", 0.05)],
    "firelord": [("recoil", "Turret/Core", 0.04)],
    "lich": [("recoil", "Turret/Core", 0.04)],
    "crystal": [("recoil", "Turret/Spike", 0.08)],
    "annihilation_glyph": [("sparks", "Turret/Sparks")],
    "orb_keeper": [("sparks", "Turret/Sparks")],
    "divineshroom": [("recoil", "Turret/Cap", 0.05)],
    "titan_vault": [("recoil", "Turret/Lens", 0.05)],
    "spellslinger": [("spin", "Turret/Sigils", 1.1, 0.25)],
    "arcane_orb": [("spin", "Turret/Shards", 1.4, 0.3)],
    "ancient_warden": [("slam", "Turret/Arm", "res://Scenes/Effects/dust_ring.tscn")],
    "scorpion": [("recoil", "Turret/Bulb", 0.09)],
    "gravedigger": [],
    "alchemist": [("slam", "Turret/Arm", "res://Scenes/Effects/toxic_ring.tscn")],
    "harbinger": [("recoil", "Turret/Eye", 0.05)],
    "leviathan": [("spin", "Turret/Lashes", 2.2, 0.0)],
    "hurricane_elemental": [("spin", "Turret/Vortex", 2.0, 0.6)],
    "sludge_monstrosity": [],
    "primalist": [("recoil", "Turret/Geode", 0.04)],
    "beastmaster": [("slam", "Turret/Horns", "res://Scenes/Effects/dust_ring.tscn")],
}

# --- the elements -----------------------------------------------------------
#
# One entry per element. Each names its two base towers and its two paths, and
# every row is (display name, gold, damage type, dmin, dmax, cooldown seconds,
# range units, splash units, targets, max mana, starting mana share).
#
# The three tiers of a path are written out rather than interpolated, because
# nothing in the source is regular enough to interpolate: the Ultimate Scorpion
# attacks faster than its Greater, the Moonbeam's mana FALLS at its top tier,
# and half the paths change targeting or splash at one tier and not another.
#
# `tech` is which technology gates the tower, by the tech_id authored in
# Resources/Tech. 0 on nothing here - every elemental tower needs one.
ELEMENTS = {
    "fire": {
        "tech": 1,
        "base_key": "fire_base",
        "base": [
            # name, gold, type, dmin, dmax, cooldown, range, splash, targets, mana, start
            ("Fire Pit", 200, NORMAL, 17, 20, 2.0, 400, 150, BOTH, 0, 0.0),
            ("Magma Well", 800, NORMAL, 58, 60, 2.0, 400, 200, BOTH, 0, 0.0),
        ],
        "paths": [
            {
                "key": "moonbeam", "tech": 2, "name": "Moonbeam",
                "tiers": [
                    (4000, SIEGE, 131, 134, 3.0, 800, 275, GROUND, 100, 1.0),
                    (10000, SIEGE, 268, 271, 3.0, 975, 325, GROUND, 100, 1.0),
                    (30000, SIEGE, 871, 874, 3.0, 1200, 400, GROUND, 45, 0.0),
                ],
            },
            {
                "key": "firelord", "tech": 3, "name": "Firelord",
                "tiers": [
                    (4000, NORMAL, 325, 333, 1.0, 400, 75, BOTH, 0, 0.0),
                    (10000, NORMAL, 549, 557, 1.0, 400, 100, BOTH, 0, 0.0),
                    (30000, NORMAL, 980, 988, 1.0, 500, 200, BOTH, 0, 0.0),
                ],
            },
        ],
    },
    "ice": {
        "tech": 7,
        "base_key": "ice_base",
        "base": [
            ("Obelisk", 200, MAGIC, 14, 17, 1.5, 500, 100, BOTH, 0, 0.0),
            ("Runic Monolith", 800, MAGIC, 45, 48, 1.5, 600, 100, BOTH, 0, 0.0),
        ],
        "paths": [
            {
                "key": "lich", "tech": 8, "name": "Lich",
                "tiers": [
                    (4000, MAGIC, 162, 166, 1.5, 600, 150, BOTH, 0, 0.0),
                    (10000, MAGIC, 494, 498, 1.5, 600, 150, BOTH, 0, 0.0),
                    (30000, MAGIC, 946, 950, 1.5, 600, 225, BOTH, 0, 0.0),
                ],
            },
            {
                "key": "crystal", "tech": 9, "name": "Crystal",
                "tiers": [
                    (4000, PIERCING, 205, 207, 1.4, 700, 0, BOTH, 0, 0.0),
                    (10000, PIERCING, 489, 491, 1.4, 700, 0, BOTH, 0, 0.0),
                    (30000, PIERCING, 1333, 1335, 1.4, 800, 0, BOTH, 0, 0.0),
                ],
            },
        ],
    },
    "lightning": {
        "tech": 13,
        "base_key": "lightning_base",
        "base": [
            ("Shock Particle", 200, CHAOS, 20, 20, 0.5, 200, 0, BOTH, 0, 0.0),
            ("Power Generator", 800, CHAOS, 80, 80, 0.5, 200, 0, BOTH, 0, 0.0),
        ],
        "paths": [
            {
                "key": "annihilation_glyph", "tech": 14, "name": "Annihilation Glyph",
                "tiers": [
                    (4000, CHAOS, 499, 511, 2.0, 1000, 0, BOTH, 0, 0.0),
                    (10000, CHAOS, 1122, 1134, 2.0, 1250, 0, BOTH, 0, 0.0),
                    (30000, CHAOS, 2416, 2428, 2.0, 1500, 0, BOTH, 0, 0.0),
                ],
            },
            {
                "key": "orb_keeper", "tech": 15, "name": "Orb Keeper",
                "tiers": [
                    (4000, CHAOS, 240, 240, 0.5, 200, 0, BOTH, 100, 0.0),
                    (10000, CHAOS, 590, 590, 0.5, 200, 0, BOTH, 100, 0.0),
                    (30000, CHAOS, 850, 850, 0.5, 200, 0, BOTH, 100, 0.0),
                ],
            },
        ],
    },
    "holy": {
        "tech": 19,
        "base_key": "holy_base",
        "base": [
            ("Light Flies", 200, PIERCING, 11, 12, 1.8, 800, 0, BOTH, 0, 0.0),
            ("Holy Lantern", 800, PIERCING, 35, 36, 1.8, 850, 0, BOTH, 0, 0.0),
        ],
        "paths": [
            {
                "key": "divineshroom", "tech": 20, "name": "Divineshroom",
                "tiers": [
                    (4000, NORMAL, 232, 233, 1.0, 400, 200, AIR, 0, 0.0),
                    (10000, NORMAL, 443, 444, 1.0, 450, 250, AIR, 0, 0.0),
                    (30000, NORMAL, 1124, 1126, 1.0, 500, 300, AIR, 0, 0.0),
                ],
            },
            {
                "key": "titan_vault", "tech": 21, "name": "Titan Vault",
                "tiers": [
                    (4000, PIERCING, 114, 115, 1.8, 900, 0, BOTH, 0, 0.0),
                    (10000, PIERCING, 315, 316, 1.8, 1000, 0, BOTH, 0, 0.0),
                    (30000, PIERCING, 900, 901, 1.8, 1000, 0, BOTH, 0, 0.0),
                ],
            },
        ],
    },
    "void": {
        "tech": 25,
        "base_key": "void_base",
        "base": [
            ("Voidling", 200, CHAOS, 40, 44, 3.0, 400, 0, BOTH, 45, 0.0),
            ("Voidalisk", 800, CHAOS, 148, 152, 3.0, 400, 0, BOTH, 45, 0.0),
        ],
        "paths": [
            {
                "key": "harbinger", "tech": 26, "name": "Harbinger",
                "tiers": [
                    (4000, MAGIC, 353, 355, 1.8, 600, 0, BOTH, 60, 0.0),
                    (10000, MAGIC, 933, 935, 1.8, 700, 0, BOTH, 60, 0.0),
                    (30000, MAGIC, 2670, 2672, 1.8, 800, 0, BOTH, 60, 0.0),
                ],
            },
            {
                "key": "leviathan", "tech": 27, "name": "Leviathan",
                "tiers": [
                    (4000, CHAOS, 242, 244, 1.6, 400, 150, BOTH, 0, 0.0),
                    (10000, CHAOS, 561, 563, 1.6, 400, 200, BOTH, 0, 0.0),
                    (30000, CHAOS, 1637, 1639, 1.6, 400, 250, BOTH, 0, 0.0),
                ],
            },
        ],
    },
    "unholy": {
        "tech": 4,
        "base_key": "unholy_base",
        "base": [
            ("Plague Well", 200, NORMAL, 16, 17, 1.0, 500, 0, BOTH, 0, 0.0),
            ("Defiled Fountain", 800, NORMAL, 58, 59, 1.0, 600, 0, BOTH, 0, 0.0),
        ],
        "paths": [
            {
                "key": "gravedigger", "tech": 5, "name": "Gravedigger",
                "tiers": [
                    (4000, NORMAL, 148, 152, 0.7, 700, 0, BOTH, 0, 0.0),
                    (10000, NORMAL, 246, 250, 0.7, 700, 0, BOTH, 0, 0.0),
                    (30000, NORMAL, 1089, 1093, 0.7, 700, 0, BOTH, 0, 0.0),
                ],
            },
            {
                "key": "alchemist", "tech": 6, "name": "Alchemist",
                "tiers": [
                    (4000, SIEGE, 254, 260, 2.0, 500, 250, BOTH, 0, 0.0),
                    (10000, SIEGE, 649, 655, 2.0, 500, 250, BOTH, 0, 0.0),
                    (30000, SIEGE, 1678, 1686, 2.0, 600, 300, BOTH, 125, 0.0),
                ],
            },
        ],
    },
    "water": {
        "tech": 10,
        "base_key": "water_base",
        "base": [
            ("Splasher", 200, PIERCING, 12, 13, 1.0, 500, 75, BOTH, 0, 0.0),
            ("Tidecaller", 800, PIERCING, 44, 45, 1.0, 500, 75, BOTH, 0, 0.0),
        ],
        "paths": [
            {
                "key": "hurricane_elemental", "tech": 11, "name": "Hurricane Elemental",
                "tiers": [
                    (4000, PIERCING, 286, 288, 1.2, 500, 100, BOTH, 0, 0.0),
                    (10000, PIERCING, 753, 755, 1.2, 500, 100, BOTH, 0, 0.0),
                    (30000, PIERCING, 2322, 2324, 1.2, 500, 125, BOTH, 100, 0.0),
                ],
            },
            {
                "key": "sludge_monstrosity", "tech": 12, "name": "Sludge Monstrosity",
                "tiers": [
                    (4000, NORMAL, 209, 212, 1.5, 600, 75, BOTH, 0, 0.0),
                    (10000, NORMAL, 561, 564, 1.5, 600, 75, BOTH, 0, 0.0),
                    (30000, NORMAL, 1622, 1625, 1.5, 600, 100, BOTH, 0, 0.0),
                ],
            },
        ],
    },
    "earth": {
        "tech": 16,
        "base_key": "earth_base",
        "base": [
            ("Rockfall", 200, SIEGE, 18, 22, 2.5, 300, 250, GROUND, 0, 0.0),
            ("Avalanche", 800, SIEGE, 75, 87, 2.5, 300, 250, GROUND, 0, 0.0),
        ],
        "paths": [
            {
                "key": "ancient_warden", "tech": 17, "name": "Ancient Warden",
                "tiers": [
                    (4000, SIEGE, 230, 248, 2.5, 400, 300, GROUND, 0, 0.0),
                    (10000, SIEGE, 518, 536, 2.5, 450, 350, GROUND, 0, 0.0),
                    (30000, SIEGE, 1492, 1510, 2.5, 500, 400, GROUND, 0, 0.0),
                ],
            },
            {
                "key": "scorpion", "tech": 18, "name": "Scorpion",
                "tiers": [
                    (4000, PIERCING, 196, 206, 0.7, 700, 0, BOTH, 0, 0.0),
                    (10000, PIERCING, 498, 508, 0.7, 700, 0, BOTH, 0, 0.0),
                    (30000, PIERCING, 1246, 1273, 0.5, 700, 0, BOTH, 999, 1.0),
                ],
            },
        ],
    },
    "arcane": {
        "tech": 22,
        "base_key": "arcane_base",
        "base": [
            ("Apprentice", 200, MAGIC, 11, 13, 0.8, 900, 0, BOTH, 32, 0.0),
            ("Sorcerer", 800, MAGIC, 29, 31, 0.8, 900, 0, BOTH, 64, 0.0),
        ],
        "paths": [
            {
                "key": "spellslinger", "tech": 23, "name": "Spellslinger",
                "tiers": [
                    (4000, MAGIC, 51, 54, 1.0, 800, 0, BOTH, 50, 0.0),
                    (10000, MAGIC, 225, 228, 1.0, 800, 0, BOTH, 50, 0.0),
                    (30000, MAGIC, 852, 855, 1.0, 800, 0, BOTH, 90, 0.0),
                ],
            },
            {
                "key": "arcane_orb", "tech": 24, "name": "Arcane Orb",
                "tiers": [
                    (4000, CHAOS, 71, 73, 0.8, 900, 0, BOTH, 100, 0.0),
                    (10000, CHAOS, 216, 218, 0.8, 900, 0, BOTH, 100, 0.0),
                    (30000, CHAOS, 602, 604, 0.8, 900, 0, BOTH, 100, 0.0),
                ],
            },
        ],
    },
    "primal": {
        "tech": 28,
        "base_key": "primal_base",
        "base": [
            ("Quarry", 200, SIEGE, 23, 29, 2.0, 700, 0, BOTH, 4, 0.0),
            ("Coreway", 800, SIEGE, 92, 98, 2.0, 700, 0, BOTH, 4, 0.0),
        ],
        "paths": [
            {
                "key": "primalist", "tech": 29, "name": "Primalist",
                "tiers": [
                    (4000, MAGIC, 255, 269, 3.0, 900, 0, BOTH, 90, 0.0),
                    (10000, MAGIC, 637, 651, 3.0, 900, 0, BOTH, 90, 0.0),
                    (30000, MAGIC, 1674, 1688, 3.0, 900, 0, BOTH, 90, 0.0),
                ],
            },
            {
                "key": "beastmaster", "tech": 30, "name": "Beastmaster",
                "tiers": [
                    (4000, SIEGE, 130, 136, 0.7, 700, 0, BOTH, 100, 0.0),
                    (10000, SIEGE, 348, 354, 0.7, 700, 0, BOTH, 100, 0.0),
                    (30000, SIEGE, 974, 980, 0.7, 700, 0, BOTH, 100, 0.0),
                ],
            },
        ],
    },
}

# The order elements are walked in, and so the order every id below is handed
# out in. Fixed and never re-sorted, because a unit_type_id is permanent once
# authored and re-ordering this list would renumber the whole roster.
ELEMENT_ORDER = ["fire", "ice", "lightning", "holy", "void",
                 "unholy", "water", "earth", "arcane", "primal"]

# What the ELEMENTAL CORE itself is, as one row in the same shape.
CORE = ("Elemental Core", CORE_GOLD, CHAOS, 6, 7, 1.0, 600, 0, BOTH, 0, 0.0)

# The prefix a tier takes, by its index within a path. unit_data.md 2.4: a
# three-tier elemental path uses Lesser / Greater / Ultimate and has no
# unprefixed rung.
TIER_PREFIX = ["Lesser", "Greater", "Ultimate"]

# --- authored ids -----------------------------------------------------------
#
# Handed out in the order the tables above are walked, and PERMANENT once
# authored. See CLAUDE.md: the number itself carries no meaning, it only has to
# be unique within its namespace and never move.
#
# The Basic roster stops at unit_type_id 63 and ability_id 127.
FIRST_UNIT_TYPE_ID = 64
FIRST_ABILITY_ID = 128


def key_of(element, name):
    """The snake_case key a tower's files are named by."""
    return "%s_%s" % (element, name.lower().replace(" ", "_").replace("'", ""))


def tower_rows():
    """Every elemental tower, in id order, as a flat list of dictionaries.

    ONE walk, used by every stage: the models, the stats, the prefabs and the
    abilities all iterate this, so a tower cannot exist in one of them and not
    in another.

    Each row carries what makes it what it is:
        key       the file name stem, unique across the whole game
        display   what the player reads
        element   which of the ten
        shape     which model builder draws it - the element's base shape for
                  the 200g and 800g towers, and the path's own above that
        ti        index into ELEMENT_PRICE_TIERS
        path      the path dictionary this belongs to, or None for a base tower
        tech      the technology that gates it
    """
    rows = [_core_row()]
    for element in ELEMENT_ORDER:
        entry = ELEMENTS[element]
        rows.extend(_base_rows(element, entry))
        for path in entry["paths"]:
            rows.extend(_path_rows(element, entry, path))
    return rows


def _core_row():
    name, gold, dtype, dmin, dmax, cooldown, rng, splash, targets, mana, start = CORE
    return {
        "key": "elemental_core", "display": name, "element": "core",
        "shape": "core", "ti": 0, "path": None, "tech": 0,
        "gold": gold, "total": gold, "dtype": dtype, "dmin": dmin, "dmax": dmax,
        "cooldown": cooldown, "range": rng, "splash": splash,
        "targets": targets, "mana": mana, "start_mana": start,
    }


def _base_rows(element, entry):
    rows = []
    total = CORE_GOLD
    for index, row in enumerate(entry["base"]):
        name, gold, dtype, dmin, dmax, cooldown, rng, splash, targets, mana, start = row
        # The 200g base tower is reached by a FREE morph from the Core, so the
        # step it charges is 0 while the total sunk into it is the Core's 200.
        step = 0 if index == 0 else gold
        total += step
        rows.append({
            "key": key_of(element, name), "display": name, "element": element,
            "shape": entry["base_key"], "ti": index, "path": None,
            "tech": entry["tech"], "gold": step, "total": total,
            "dtype": dtype, "dmin": dmin, "dmax": dmax, "cooldown": cooldown,
            "range": rng, "splash": splash, "targets": targets,
            "mana": mana, "start_mana": start,
        })
    return rows


def _path_rows(element, entry, path):
    rows = []
    # Everything sunk into the shared base pair, which both paths inherit.
    total = CORE_GOLD + entry["base"][1][1]
    for index, tier in enumerate(path["tiers"]):
        gold, dtype, dmin, dmax, cooldown, rng, splash, targets, mana, start = tier
        total += gold
        display = "%s %s" % (TIER_PREFIX[index], path["name"])
        rows.append({
            "key": key_of(element, display), "display": display,
            "element": element, "shape": path["key"], "ti": index + 2,
            "path": path, "tech": path["tech"], "gold": gold, "total": total,
            "dtype": dtype, "dmin": dmin, "dmax": dmax, "cooldown": cooldown,
            "range": rng, "splash": splash, "targets": targets,
            "mana": mana, "start_mana": start,
        })
    return rows


def upgrade_pairs():
    """Every (source key, target key) an upgrade ability exists for, in order.

    The Core is the branch point of the whole system: it offers TEN upgrades,
    one per element, and each of them is free and gated on that element's Basic
    technology. Everything above is the ordinary two-then-one shape.
    """
    pairs = []
    for element in ELEMENT_ORDER:
        entry = ELEMENTS[element]
        base_keys = [key_of(element, row[0]) for row in entry["base"]]
        pairs.append(("elemental_core", base_keys[0]))
        pairs.append((base_keys[0], base_keys[1]))
        for path in entry["paths"]:
            keys = [key_of(element, "%s %s" % (TIER_PREFIX[i], path["name"]))
                    for i in range(len(path["tiers"]))]
            pairs.append((base_keys[1], keys[0]))
            for index in range(len(keys) - 1):
                pairs.append((keys[index], keys[index + 1]))
    return pairs


def by_key():
    return {row["key"]: row for row in tower_rows()}


def unit_type_ids():
    return {row["key"]: FIRST_UNIT_TYPE_ID + i
            for i, row in enumerate(tower_rows())}
