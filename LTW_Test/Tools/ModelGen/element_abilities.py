# The named ability of every elemental tower, as data.
#
# unit_data.md section 4 states one ability per tower and eighty of them in
# total. This file is those eighty rows: which TowerPassive script runs it, what
# it is called, and the numbers its .tres is authored with. Every number here is
# copied straight out of unit_data.md 4.1 to 4.10.
#
# ONE ROW PER TOWER, keyed by the tower's own key, so a tower cannot end up with
# somebody else's ability and an ability cannot end up on no tower at all -
# element_content.py walks the roster and looks each row up.
#
# THE UNITS ARE THE GAME'S, NOT THE SOURCE'S. unit_data.md states distances in
# Warcraft III map units and percentages as whole numbers; the passives take
# player cells and shares of one, exactly as every other resource in the project
# does. So 400 AoE is written cells(400) and "-3.75% per hit" is written 0.0375.
# Doing that conversion HERE rather than in the passive is what lets a .tres be
# read against a script's @export without a divisor in the way.
#
# Where the source records a rule this project has no machinery for, the row
# still carries the number and the passive is written to describe it and do
# nothing. Those are listed in game_rules.md rather than being silently dropped.

from roster import cells

# The script each ability family runs. One per element and path, thirty in all -
# a family shares a script and its tiers differ only in the numbers below.
S = "res://Scripts/Abilities/TowerPassives/%s.gd"

ARCANIZE = S % "ArcanizePassive"
SPELLCASTER = S % "SpellcasterPassive"
SHIFTING_POWER = S % "ShiftingPowerPassive"
SHATTER_ARMOR = S % "ShatterArmorPassive"
GERMINATE = S % "GerminatePassive"
IGNITE = S % "IgnitePassive"
BLAZING_INFERNO = S % "BlazingInfernoPassive"
FRENZIED_FLAMES = S % "FrenziedFlamesPassive"
VOLCANIC_ERUPTION = S % "VolcanicEruptionPassive"
BURSTING_LIGHT = S % "BurstingLightPassive"
LIGHT_BURST = S % "LightBurstPassive"
LUMINOUS_GRASP = S % "LuminousGraspPassive"
FROST_ATTACK = S % "FrostAttackPassive"
CHILLING_DEATH = S % "ChillingDeathPassive"
ICE_LANCE = S % "IceLancePassive"
OVERCHARGE = S % "OverchargePassive"
FOCUSED_LIGHTNING = S % "FocusedLightningPassive"
CRASH_LIGHTNING = S % "CrashLightningPassive"
BREAK = S % "BreakPassive"
ANCIENT_BLOOM = S % "AncientBloomPassive"
BLOODTHIRST = S % "BloodthirstPassive"
CORRUPTION = S % "CorruptionPassive"
POISON = S % "PoisonPassive"
DEVOUR_ESSENCE = S % "DevourEssencePassive"
VOID_GROWTH = S % "VoidGrowthPassive"
VOID_CONVERSION = S % "VoidConversionPassive"
TEMPORAL_RIFT = S % "TemporalRiftPassive"
FEASTING_VOID = S % "FeastingVoidPassive"
CRUSHING_WAVE = S % "CrushingWavePassive"
PRESSURING_WATER = S % "PressuringWaterPassive"
TORRENT = S % "TorrentPassive"

# unit_data.md 1.3: the base slow duration. Every chill that does not state its
# own takes it, which is nearly all of them.
SLOW_SECONDS = 4.0

# Towers the VOID line can eat, by unit_type_id.
#
# By ID rather than by a stats reference on purpose - see VoidSpreadPassive: an
# ability holding its own tower's stats would be a reference cycle, and holding
# the ones it converts would drag every one of them into memory with the card.
#
# Written out rather than looked up from the roster tables, because these are
# AUTHORED CHOICES about which towers the Void may take and not a query. The
# ids are permanent by design, so a literal here cannot go stale; what it does
# do is put the whole rule on one screen next to the ability that runs it.
#
# The 10g stubs and their 30g upgrades are the only Basic towers on the list,
# and no elemental tower is on it at all. Which of the six a Voidling actually
# takes is decided at runtime by price and then by distance, so a 10g tower is
# always eaten before a 30g one standing the same distance away.
BASIC_10G = (26, 36, 46)
BASIC_30G = (27, 37, 47)
VOIDLING = 97
VOIDALISK = 98
GREATER_HARBINGER = 100
ULTIMATE_HARBINGER = 101

# Where the Harbinger's rift draws itself: an X on the ground at the spot the
# creep is going back to, standing for as long as the delay lasts.
#
# The passive also takes a mark for the creep to CARRY, and nothing authors one.
# It was tried and dropped on review - a badge riding a walking creep read as
# noise rather than as a warning - and the hook is left because carrying
# something is the right shape for the idea, not because this needs one.
RIFT_MARKER = "res://Scenes/Effects/rift_marker.tscn"

# What Primal 2 actually sends down the lane. A creature rather than a shot, so
# it is not in the projectile table with the sixteen elemental bolts - see
# effects.beast_charge.
BEAST = "res://Scenes/Effects/beast_charge.tscn"

# How fast the beast runs, in cells per second, and how wide a band it
# flattens as a half-width in cells.
#
# ONE PAIR FOR THE WHOLE LINE, unlike every other number in this file: the same
# animal is sent at every tier and the Ultimate's is not a faster one, it is one
# that runs further and hits harder. So the flight time is NOT constant across
# the three - the Ultimate's beast is on the field for a little over two seconds
# and the other two for about half of that, because unit_data.md gives them half
# the distance.
#
# The band is two cells across, which is wider than the model. That is
# deliberate and the model is the half that gives: see effects.beast_charge.
BEAST_SPEED = 4.7
BEAST_RADIUS = 1.0


def _p(script, name, **fields):
    """One ability row: which script, what it is called, and its numbers."""
    return {"script": script, "name": name, "fields": fields}


# --- the eighty ------------------------------------------------------------
#
# Keyed by tower key. Read element by element, in the order unit_data.md
# writes them, so a row can be checked against its paragraph without hunting.
ABILITIES = {
    # --- 4.3 Fire ---------------------------------------------------------
    "fire_fire_pit": _p(IGNITE, "Ignite", interval_seconds=2.1,
                        radius_cells=cells(400), damage_per_second=5.0,
                        duration_seconds=8.0),
    "fire_magma_well": _p(IGNITE, "Ignite", interval_seconds=2.1,
                          radius_cells=cells(400), damage_per_second=13.0,
                          duration_seconds=8.0),
    "fire_lesser_moonbeam": _p(
        BLAZING_INFERNO, "Blazing Inferno", decay_per_second=0.0083,
        max_bonus_share=3.0, explosion_share=0.66, explosion_cells=cells(200)),
    "fire_greater_moonbeam": _p(
        BLAZING_INFERNO, "Blazing Inferno", decay_per_second=0.0083,
        max_bonus_share=3.0, explosion_share=0.80, explosion_cells=cells(250)),
    "fire_ultimate_moonbeam": _p(
        FRENZIED_FLAMES, "Frenzied Flames", regen_per_second=10.0,
        max_damage_per_second=1575.0, duration_seconds=3.0,
        radius_cells=cells(300)),
    # No radius: the eruption reaches whatever the tower's own splash already
    # covers, so the tier's Splash column is the one number that says how far.
    "fire_lesser_firelord": _p(
        VOLCANIC_ERUPTION, "Volcanic Eruption", chance=0.4, targets=3,
        bonus_share=1.0, armor_share=0.07),
    "fire_greater_firelord": _p(
        VOLCANIC_ERUPTION, "Volcanic Eruption", chance=0.4, targets=5,
        bonus_share=1.0, armor_share=0.12),
    "fire_ultimate_firelord": _p(
        VOLCANIC_ERUPTION, "Magma Blast", chance=0.4, targets=8,
        bonus_share=1.0, armor_share=0.12,
        guaranteed_every=5, missing_armor_bonus=0.06),

    # --- 4.5 Ice ----------------------------------------------------------
    "ice_obelisk": _p(FROST_ATTACK, "Frost Attack", slow_per_hit=0.0375,
                      slow_cap=0.20, slow_seconds=SLOW_SECONDS,
                      chill_source="obelisk"),
    "ice_runic_monolith": _p(FROST_ATTACK, "Frost Attack", slow_per_hit=0.045,
                             slow_cap=0.25, slow_seconds=SLOW_SECONDS,
                             chill_source="runic_monolith"),
    "ice_lesser_lich": _p(FROST_ATTACK, "Frost Blast", slow_per_hit=0.055,
                          slow_cap=0.30, slow_seconds=SLOW_SECONDS + 1.0,
                          chill_source="lesser_lich"),
    "ice_greater_lich": _p(FROST_ATTACK, "Frost Blast", slow_per_hit=0.0635,
                           slow_cap=0.36, slow_seconds=SLOW_SECONDS + 1.5,
                           chill_source="greater_lich"),
    "ice_ultimate_lich": _p(
        CHILLING_DEATH, "Chilling Death", slow_per_hit=0.075, slow_cap=0.45,
        slow_seconds=SLOW_SECONDS + 3.0, chill_source="ultimate_lich",
        frostbite_share=0.02, frostbite_cooldown=15.0,
        aura_cells=cells(700), attack_slow=0.15),
    "ice_lesser_crystal": _p(ICE_LANCE, "Ice Lance", max_targets=15,
                             damage_per_target=0.05),
    "ice_greater_crystal": _p(ICE_LANCE, "Ice Lance", max_targets=15,
                              damage_per_target=0.075),
    "ice_ultimate_crystal": _p(ICE_LANCE, "Crystalized Light", max_targets=20,
                               damage_per_target=0.10,
                               mana_drain_per_second=0.35,
                               mana_drain_seconds=12.0),

    # --- 4.6 Lightning ----------------------------------------------------
    "lightning_shock_particle": _p(OVERCHARGE, "Overcharge",
                                   damage_per_tenth=2.0),
    "lightning_power_generator": _p(OVERCHARGE, "Overcharge",
                                    damage_per_tenth=7.0),
    "lightning_lesser_annihilation_glyph": _p(
        FOCUSED_LIGHTNING, "Focused Lightning", bonus_per_attack=0.5,
        max_stacks=5),
    "lightning_greater_annihilation_glyph": _p(
        FOCUSED_LIGHTNING, "Focused Lightning", bonus_per_attack=0.75,
        max_stacks=5),
    "lightning_ultimate_annihilation_glyph": _p(
        FOCUSED_LIGHTNING, "Annihilation", bonus_per_attack=1.0, max_stacks=5,
        chain_targets=2, chain_cells=cells(500)),
    "lightning_lesser_orb_keeper": _p(
        CRASH_LIGHTNING, "Crash Lightning", mana_per_attack=10.0,
        current_health_share=0.012, stun_seconds=0.67, burst_damage=300),
    "lightning_greater_orb_keeper": _p(
        CRASH_LIGHTNING, "Crash Lightning", mana_per_attack=15.0,
        current_health_share=0.018, stun_seconds=0.67, burst_damage=800),
    "lightning_ultimate_orb_keeper": _p(
        CRASH_LIGHTNING, "Arc Lightning", mana_per_attack=20.0,
        current_health_share=0.025, stun_seconds=0.67, burst_damage=2500,
        max_mana_cost=5, max_mana_floor=20, neighbour_penalty=20,
        neighbour_cells=cells(150)),

    # --- 4.4 Holy ---------------------------------------------------------
    "holy_light_flies": _p(BURSTING_LIGHT, "Bursting Light",
                           additional_targets=4),
    "holy_holy_lantern": _p(BURSTING_LIGHT, "Bursting Light",
                            additional_targets=5),
    "holy_lesser_divineshroom": _p(
        LIGHT_BURST, "Light Burst", slow_per_hit=0.0333, slow_cap=0.40,
        slow_seconds=SLOW_SECONDS, chill_source="lesser_divineshroom",
        armor_per_hit=0.12, armor_floor=-3.0),
    "holy_greater_divineshroom": _p(
        LIGHT_BURST, "Light Burst", slow_per_hit=0.0416, slow_cap=0.50,
        slow_seconds=SLOW_SECONDS, chill_source="greater_divineshroom",
        armor_per_hit=0.15, armor_floor=-3.0),
    "holy_ultimate_divineshroom": _p(
        LIGHT_BURST, "Divine Spores", slow_per_hit=0.06, slow_cap=0.66,
        slow_seconds=SLOW_SECONDS, chill_source="ultimate_divineshroom",
        armor_per_hit=0.25, armor_floor=-3.0, tower_heal_share=0.10,
        heal_cells=cells(300)),
    "holy_lesser_titan_vault": _p(
        LUMINOUS_GRASP, "Luminous Grasp", additional_targets=6,
        spell_amplification=0.12, amplification_seconds=5.0, slow_amount=0.14),
    "holy_greater_titan_vault": _p(
        LUMINOUS_GRASP, "Luminous Grasp", additional_targets=7,
        spell_amplification=0.12, amplification_seconds=7.0, slow_amount=0.18),
    "holy_ultimate_titan_vault": _p(
        LUMINOUS_GRASP, "Titan Defense Mechanism", additional_targets=10,
        spell_amplification=0.15, amplification_seconds=7.0, slow_amount=0.24,
        aura_cells=cells(700), slow_extension=2.0, damage_reduction=0.20),

    # --- 4.9 Void ---------------------------------------------------------
    "void_voidling": _p(VOID_GROWTH, "Void Growth", regen_per_second=1.0,
                        mana_per_attack=1.0, reach_cells=cells(400),
                        becomes_type_id=VOIDLING,
                        converts_type_ids=BASIC_10G + BASIC_30G),
    "void_voidalisk": _p(VOID_GROWTH, "Void Growth", regen_per_second=1.0,
                         mana_per_attack=1.0, reach_cells=cells(400),
                         becomes_type_id=VOIDALISK,
                         converts_type_ids=(VOIDLING,)),
    "void_lesser_harbinger": _p(
        TEMPORAL_RIFT, "Temporal Rift", regen_per_second=10.0,
        radius_cells=cells(300), delay_seconds=3.0, health_share=0.02,
        flat_damage=300, creep_cooldown=9.0, refund_share=0.5,
        marker_scene_path=RIFT_MARKER),
    "void_greater_harbinger": _p(
        TEMPORAL_RIFT, "Temporal Rift", regen_per_second=10.0,
        radius_cells=cells(300), delay_seconds=3.2, health_share=0.03,
        flat_damage=800, creep_cooldown=9.0, refund_share=0.5,
        marker_scene_path=RIFT_MARKER),
    "void_ultimate_harbinger": _p(
        TEMPORAL_RIFT, "Whispers of the Void", regen_per_second=10.0,
        radius_cells=cells(300), delay_seconds=3.6, health_share=0.05,
        flat_damage=4250, creep_cooldown=9.0, refund_share=0.5,
        slow_amount=0.45,
        marker_scene_path=RIFT_MARKER),
    "void_lesser_leviathan": _p(
        FEASTING_VOID, "Feasting Void", armor_per_hit=0.17,
        damage_per_hit=1.5, damage_cap=90.0, idle_reset=3.0),
    "void_greater_leviathan": _p(
        FEASTING_VOID, "Feasting Void", armor_per_hit=0.20,
        damage_per_hit=3.0, damage_cap=200.0, idle_reset=3.0),
    "void_ultimate_leviathan": _p(
        FEASTING_VOID, "Hungering Void", armor_per_hit=0.27,
        damage_per_hit=8.0, damage_cap=600.0, idle_reset=3.0, life_steal=0.10),

    # --- 4.8 Unholy -------------------------------------------------------
    "unholy_plague_well": _p(CORRUPTION, "Corruption", duration_seconds=4.0,
                             explosion_damage=28, explosion_cells=cells(160)),
    "unholy_defiled_fountain": _p(CORRUPTION, "Corruption",
                                  duration_seconds=4.0, explosion_damage=76,
                                  explosion_cells=cells(160)),
    "unholy_lesser_gravedigger": _p(
        POISON, "Poison", additional_targets=1, stack_share=0.20,
        stacks_to_explode=10, explosion_cooldown=3.0),
    "unholy_greater_gravedigger": _p(
        POISON, "Poison", additional_targets=2, stack_share=0.25,
        stacks_to_explode=10, explosion_cooldown=3.0),
    "unholy_ultimate_gravedigger": _p(
        POISON, "Pestilence", additional_targets=2, stack_share=0.35,
        stacks_to_explode=10, explosion_cooldown=3.0,
        explosion_cells=cells(200), explodes_on_death=True),
    "unholy_lesser_alchemist": _p(
        DEVOUR_ESSENCE, "Devour Essence", damage_per_kill=2, damage_cap=100,
        overflow_cells=cells(300)),
    "unholy_greater_alchemist": _p(
        DEVOUR_ESSENCE, "Devour Essence", damage_per_kill=3, damage_cap=200,
        overflow_cells=cells(300)),
    "unholy_ultimate_alchemist": _p(
        DEVOUR_ESSENCE, "Unholy Concoction", damage_per_kill=5, damage_cap=500,
        overflow_cells=cells(300), armor_type_seconds=8.0),

    # --- 4.10 Water -------------------------------------------------------
    "water_splasher": _p(CRUSHING_WAVE, "Crushing Wave", every=4, damage=12,
                         radius_cells=cells(150)),
    "water_tidecaller": _p(CRUSHING_WAVE, "Crushing Wave", every=4, damage=44,
                           radius_cells=cells(150)),
    "water_lesser_hurricane_elemental": _p(
        PRESSURING_WATER, "Pressuring Water", paralyze_chance=0.5,
        paralyze_seconds=1.5, paralyze_cells=cells(400),
        paralyze_cooldown=9.0, every=3, charged_bonus=0.25),
    "water_greater_hurricane_elemental": _p(
        PRESSURING_WATER, "Pressuring Water", paralyze_chance=0.5,
        paralyze_seconds=1.8, paralyze_cells=cells(400),
        paralyze_cooldown=9.0, every=3, charged_bonus=0.33),
    "water_ultimate_hurricane_elemental": _p(
        PRESSURING_WATER, "Raging Tempest", paralyze_chance=0.75,
        paralyze_seconds=2.5, paralyze_cells=cells(400),
        paralyze_cooldown=9.0, every=3, charged_bonus=0.0,
        mana_per_target=3.0, fork_damage=2000, mana_per_fork=10,
        fork_cells=cells(400)),
    "water_lesser_sludge_monstrosity": _p(
        TORRENT, "Torrent", aura_cells=cells(400),
        slow_per_stack=0.048, slow_cap=0.24, stun_every=3, stun_seconds=1.0),
    "water_greater_sludge_monstrosity": _p(
        TORRENT, "Torrent", aura_cells=cells(400),
        slow_per_stack=0.07, slow_cap=0.28, stun_every=3, stun_seconds=1.2),
    "water_ultimate_sludge_monstrosity": _p(
        TORRENT, "Crippling Decay", aura_cells=cells(400),
        slow_per_stack=0.09, slow_cap=0.36, stun_every=3, stun_seconds=1.8,
        stun_needs_same_target=True, physical_amplification=0.10),

    # --- 4.2 Earth --------------------------------------------------------
    "earth_rockfall": _p(SHATTER_ARMOR, "Shatter Armor", armor_per_hit=0.1,
                         armor_floor=1.0),
    "earth_avalanche": _p(SHATTER_ARMOR, "Shatter Armor", armor_per_hit=0.1,
                          armor_floor=0.0),
    "earth_lesser_ancient_warden": _p(
        SHATTER_ARMOR, "Devastating Attack", armor_per_hit=0.12,
        armor_floor=0.0),
    "earth_greater_ancient_warden": _p(
        SHATTER_ARMOR, "Devastating Attack", armor_per_hit=0.2,
        armor_floor=0.0),
    "earth_ultimate_ancient_warden": _p(
        SHATTER_ARMOR, "Nature's Guidance", armor_per_hit=0.5, armor_floor=0.0,
        self_heal_share=0.0235),
    "earth_lesser_scorpion": _p(
        GERMINATE, "Germinate", idle_threshold=1.0,
        bonus_per_half_second=0.1, max_idle_bonus=0.5, idle_charges=5,
        crit_bonus=0.5, max_crit_chance=0.5),
    "earth_greater_scorpion": _p(
        GERMINATE, "Germinate", idle_threshold=1.0,
        bonus_per_half_second=0.15, max_idle_bonus=0.75, idle_charges=5,
        crit_bonus=0.5, max_crit_chance=0.6),
    "earth_ultimate_scorpion": _p(
        GERMINATE, "Lethal Strike", idle_threshold=1.0,
        bonus_per_half_second=0.2, max_idle_bonus=1.0, idle_charges=5,
        crit_bonus=0.5, max_crit_chance=0.75, mana_per_attack=5.0,
        kill_mana=100, idle_guarantees_crit=True),

    # --- 4.1 Arcane -------------------------------------------------------
    "arcane_apprentice": _p(ARCANIZE, "Arcanize", mana_per_attack=1.0,
                            full_mana_bonus=1.0),
    "arcane_sorcerer": _p(ARCANIZE, "Arcanize", mana_per_attack=1.0,
                          full_mana_bonus=1.5),
    "arcane_lesser_spellslinger": _p(
        SPELLCASTER, "Spellcaster", regen_per_second=10.0, cast_seconds=3.34,
        cast_cells=cells(600), damage_per_second=90.0, duration_seconds=15.0,
        slow_per_tick=0.08, slow_cap=0.40, growth_per_target=0.10,
        orb_mana_cost=50, orb_bonus_damage=110, orb_splash_cells=cells(180)),
    "arcane_greater_spellslinger": _p(
        SPELLCASTER, "Spellcaster", regen_per_second=10.0, cast_seconds=3.34,
        cast_cells=cells(600), damage_per_second=250.0, duration_seconds=15.0,
        slow_per_tick=0.10, slow_cap=0.40, growth_per_target=0.10,
        orb_mana_cost=50, orb_bonus_damage=315, orb_splash_cells=cells(240)),
    "arcane_ultimate_spellslinger": _p(
        SPELLCASTER, "Spell Mastery", regen_per_second=10.0, cast_seconds=3.34,
        cast_cells=cells(800), damage_per_second=600.0, duration_seconds=15.0,
        slow_per_tick=0.125, slow_cap=0.50, growth_per_target=0.15,
        orb_mana_cost=30, orb_bonus_damage=750, orb_splash_cells=cells(240),
        attune_share=1.0, attune_interval=0.5),
    "arcane_lesser_arcane_orb": _p(
        SHIFTING_POWER, "Shifting Power", bounces=3, bounce_cells=cells(200),
        mana_per_target=2.0, drain_per_second=2.0, max_mana_bonus=0.5,
        flying_bonus=0.15),
    "arcane_greater_arcane_orb": _p(
        SHIFTING_POWER, "Shifting Power", bounces=4, bounce_cells=cells(220),
        mana_per_target=2.25, drain_per_second=2.0, max_mana_bonus=0.5,
        flying_bonus=0.20),
    "arcane_ultimate_arcane_orb": _p(
        SHIFTING_POWER, "Arcane Surge", bounces=4, bounce_cells=cells(240),
        mana_per_target=4.0, drain_per_second=8.0, max_mana_bonus=0.5,
        flying_bonus=0.33, surge_threshold=0.8, surge_bounces=2,
        surge_drain_per_second=15.0),

    # --- 4.7 Primal -------------------------------------------------------
    "primal_quarry": _p(BREAK, "Break", mana_per_attack=1.0, stun_seconds=0.8),
    "primal_coreway": _p(BREAK, "Break", mana_per_attack=1.0,
                         stun_seconds=1.0),
    "primal_lesser_primalist": _p(
        ANCIENT_BLOOM, "Ancient Bloom", gold_per_attack=120,
        gold_per_neighbour=48, minimum_gold=12, crowding_cells=cells(250),
        regen_per_second=13.0, blast_damage=350, blast_cells=cells(200),
        armor_reduction=1.0, armor_seconds=7.0, refund_below=3,
        refund_share=0.5),
    "primal_greater_primalist": _p(
        ANCIENT_BLOOM, "Ancient Bloom", gold_per_attack=300,
        gold_per_neighbour=120, minimum_gold=30, crowding_cells=cells(250),
        regen_per_second=13.0, blast_damage=775, blast_cells=cells(200),
        armor_reduction=2.0, armor_seconds=7.0, refund_below=3,
        refund_share=0.5),
    "primal_ultimate_primalist": _p(
        ANCIENT_BLOOM, "Primordial Bond", gold_per_attack=750,
        gold_per_neighbour=0, minimum_gold=750, crowding_cells=0.0,
        regen_per_second=13.0, blast_damage=1800, blast_cells=cells(200),
        armor_reduction=3.0, armor_seconds=7.0, refund_below=3,
        refund_share=0.5),
    "primal_lesser_beastmaster": _p(
        BLOODTHIRST, "Bloodthirst", additional_targets=1,
        multishot_cells=cells(400), mana_per_target=5.0,
        beast_scene_path=BEAST, beast_cells=cells(700), beast_speed=BEAST_SPEED,
        beast_radius=BEAST_RADIUS, beast_damage=240, stun_seconds=0.5,
        stun_cooldown=8.0),
    "primal_greater_beastmaster": _p(
        BLOODTHIRST, "Bloodthirst", additional_targets=1,
        multishot_cells=cells(400), mana_per_target=5.0,
        beast_scene_path=BEAST, beast_cells=cells(700), beast_speed=BEAST_SPEED,
        beast_radius=BEAST_RADIUS, beast_damage=570, stun_seconds=0.7,
        stun_cooldown=8.0),
    "primal_ultimate_beastmaster": _p(
        BLOODTHIRST, "Stampede", additional_targets=1,
        multishot_cells=cells(500), mana_per_target=5.0,
        beast_scene_path=BEAST, beast_cells=cells(1200), beast_speed=BEAST_SPEED,
        beast_radius=BEAST_RADIUS, beast_damage=1865, stun_seconds=1.2,
        stun_cooldown=8.0, range_bonus_per_cell=0.128, max_range_bonus=1.0),
}

# What each tower's ability .tres is called on disk.
def ability_path(key):
    return "res://Resources/Abilities/Towers/%s_ability.tres" % key


# And its SECOND one, where it has one. A different stem rather than a suffix
# on the same name, so the two never sort next to each other and get mistaken
# for one file and its backup.
def extra_ability_path(key):
    return "res://Resources/Abilities/Towers/%s_second_ability.tres" % key


# --- the second ability ------------------------------------------------------
#
# ONE tower in the roster carries two named abilities, and it is the Ultimate
# Harbinger. Its rift is paid for with mana and its spread runs on a clock, so
# they cannot share a square: a repeating wait is something a player plans
# around, and the only place the game can show a wait is a slot of its own.
#
# A separate table rather than a second entry in ABILITIES, because that one is
# keyed by tower and being one-row-per-tower is what makes it checkable against
# unit_data.md paragraph by paragraph. This is the exception, written where it
# can be seen to be one.
EXTRA_ABILITIES = {
    "void_ultimate_harbinger": _p(
        VOID_CONVERSION, "Void Conversion", period_seconds=60.0,
        reach_cells=cells(500), becomes_type_id=ULTIMATE_HARBINGER,
        converts_type_ids=(GREATER_HARBINGER,)),
}
