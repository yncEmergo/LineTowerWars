class_name CreepProbe
extends Node

## SCAFFOLDING. Drives a headless match and checks every creep trait against
## what its description promises.
##
##   godot --path . --headless res://Scenes/Dev/creep_probe.tscn
##   godot --path . --headless res://Scenes/Dev/creep_probe.tscn -- only=wendigo
##
## Built the same way PerfBench is - a scene of its own that instances a match
## underneath itself and works through the game's own calls - because that is
## the only shape that gets a real PlayerArea, a real flow field and real
## towers without an autoload, and an autoload cannot be added while the editor
## is open (CLAUDE.md).
##
## DELETE THIS WITH THE REST OF Scripts/Dev WHEN THE REVIEW IS DONE.

const MATCH_SCENE: String = "res://Scenes/Server/server_match.tscn"
const CREEPS: String = "res://Resources/UnitStats/Creeps"
const TOWERS: String = "res://Resources/UnitStats/Towers"
const ABILITIES: String = "res://Resources/Abilities"
const TAG: String = "PROBE"

## Ticks to let the match settle before the first check.
const WARMUP_TICKS: int = 20

var _area: PlayerArea = null
var _passes: int = 0
var _fails: int = 0
var _lines: PackedStringArray = PackedStringArray()
## Creeps pinned where they were put, so a check that needs ten seconds is not
## racing the creep to the end of the lane. Applied after the match scene has
## moved them, which is what the priority below is for.
var _held: Dictionary = {}
var _only: String = ""
var _next_cell: int = 0


func _ready() -> void:
	# Both, and high: process_physics_priority is the only one that orders the
	# TICK, and a parent runs before its children by default - see CLAUDE.md.
	process_priority = 100000
	process_physics_priority = 100000
	_read_arguments()
	_start_match()
	_run()


func _read_arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = argument.split("=", true, 1)
		if parts.size() == 2 && parts[0].strip_edges() == "only":
			_only = parts[1].strip_edges()


func _start_match() -> void:
	var packed: PackedScene = load(MATCH_SCENE) as PackedScene
	var setup: MatchSetup = MatchSetup.new()
	# TWO of them, because one rule cannot be checked with one: a leak is a
	# TRANSFER, and PlayerState.steal_life_from refuses a thief who is also the
	# victim. Everything else is done in player 1's area whoever owns it.
	setup.players.append(MatchPlayer.create(1, "Probe"))
	setup.players.append(MatchPlayer.create(2, "Probe Two"))
	setup.local_slot = 0
	setup.rng_seed = 1
	MenuNavigation.pending_match = setup
	add_child(packed.instantiate())


## Keeps a pinned creep where it was put. After the match scene's own tick,
## because of the priority set in _ready.
func _physics_process(_delta: float) -> void:
	var gone: Array = []
	for key in _held:
		if !is_instance_valid(key):
			gone.append(key)
			continue
		(key as Creep).global_position = _held[key]
	for key in gone:
		_held.erase(key)


# --- The run ------------------------------------------------------------

func _run() -> void:
	await _ticks(WARMUP_TICKS)
	_area = _find_area()
	if _area == null:
		_fail("setup", "no PlayerArea, the match did not start")
		_finish()
		return

	for check: Array in _checks():
		if !_only.is_empty() && !String(check[0]).contains(_only):
			continue
		_reset()
		await _ticks(2)
		await call(String(check[1]))
	_finish()


## Every check, as [name, method]. Grouped by tier and in roster order, so a
## reader can follow it against unit_data.md 6.2 to 6.5.
func _checks() -> Array:
	return [
		["diag clock", "_check_clock"],
		["t1 sheep / fast producing", "_check_fast_producing"],
		["t1 skeleton / death pact 1", "_check_death_pact"],
		["t1 acolyte / unholy sacrifice 1", "_check_unholy_sacrifice"],
		["t1 spider / skittering", "_check_skittering"],
		["t1 swordsman / devotion aura 1", "_check_devotion_aura"],
		["t1 grunt / fel blood", "_check_fel_blood"],
		["t1 temptress / endurance aura 1", "_check_endurance_aura"],
		["t1 shade / flying", "_check_flying"],
		["t1 mud golem / lesser spell resistance", "_check_lesser_spell_resistance"],
		["t1 priest / regen aura 1", "_check_regen_aura"],
		["t1 treant / attacker", "_check_attacker"],
		["t1 rot golem / boss 1", "_check_boss"],

		["t2 knight / armored 1", "_check_armored"],
		["t2 voidwalker / chaotic void", "_check_chaotic_void"],
		["t2 dragonspawn / spell resistance", "_check_spell_resistance"],
		["t2 siege engine / bombardment", "_check_bombardment"],

		["t3 crypt fiend / ethereal aura", "_check_ethereal_aura"],
		["t3 necromancer / bone shield", "_check_bone_shield"],
		["t3 spirit walker / ethereal", "_check_ethereal"],
		["t3 spirit walker / spiritual aid", "_check_spiritual_aid"],
		["t3 wendigo / hardened skin", "_check_hardened_skin"],
		["t3 shaman / elemental warding", "_check_elemental_warding"],
		["t3 shaman / wind rush", "_check_wind_rush"],
		["t3 abomination / regenerative flesh", "_check_regenerative_flesh"],
		["t3 ogre magi / earth shield", "_check_earth_shield"],
		["t3 chaos wardens / chaos barrier", "_check_chaos_barrier"],
		["t3 chaos wardens / mana drain", "_check_mana_drain"],
		["t3 behemoth / abyssal carapace", "_check_abyssal_carapace"],

		["t4 huntress / elunes grace", "_check_elunes_grace"],
		["t4 huntress / quickness", "_check_quickness"],
		["t4 statue / annihilation aura", "_check_annihilation_aura"],
		["t4 statue / exhume ghouls", "_check_exhume_ghouls"],
		["t4 mountain giant / blocked", "_check_blocked"],
		["t4 mountain giant / stoneskin", "_check_stoneskin"],
		["t4 harpy / wicked curse", "_check_wicked_curse"],
		["t4 naga siren / sirens song", "_check_sirens_song"],
		["t4 kodo / war stance", "_check_war_stance"],
		["t4 shredder / goblin engineering", "_check_goblin_engineering"],
		["t4 shredder / reactive armor", "_check_reactive_armor"],
		["t4 phoenix / volatile death", "_check_volatile_death"],
		["t4 phoenix / legendary spell resistance", "_check_legendary_resistance"],
		["t4 phoenix / dive", "_check_dive"],
		["t4 demon / unfathomable power", "_check_unfathomable_power"],
		["t4 goblin / escape portal", "_check_escape_portal"],

		["x quickness vs a long ranged tower", "_check_dodge_against_towers"],
		["x armor eaten by a tower vs hardened skin", "_check_eaten_armor"],
		["x sirens song gives back what a tower ate", "_check_armor_restored"],
		["x earth shield strips a tower chill", "_check_shield_vs_chill"],
		["x goblin engineering vs two chill towers", "_check_cap_vs_towers"],
		["x annihilation aura vs a tower shooting", "_check_aura_vs_damage"],
		["x spell resistance vs a tower burn", "_check_resistance_vs_burn"],
		["x an attacker takes a tower down", "_check_tower_destroyed"],
		["x a paralyzed flyer is a ground target", "_check_paralyzed_flyer"],
		["x an altered armor type beats war stance", "_check_altered_type"],
		["x an ethereal creep walks through a wall", "_check_walks_through"],
		["x a boss steals two lives on a leak", "_check_leak"],
		["x population is charged per creep", "_check_population"],
		["x sudden death opens tier 4 and shuts the rest", "_check_sudden_death"],
		["x a goblin is refused above the income cap", "_check_income_cap"],

		["y every reach is a round quarter", "_check_quarter_reaches"],
		["y no line a player reads says the word cell", "_check_no_cell_word"],
		["y a trait quotes its creep rather than copying it", "_check_placeholders"],
		["y tier 4 reserves are under their ceiling", "_check_tier4_stock"],
		["y the tier 4 card reads from Q with the goblin on V", "_check_tier4_card"],
		["y a 900 range tower is one a huntress dodges", "_check_dodge_threshold"],
	]


# --- Tier 1 -------------------------------------------------------------

func _check_clock() -> void:
	var started: float = float(Time.get_ticks_msec())
	var deltas: float = 0.0
	for index in range(40):
		await get_tree().physics_frame
		deltas += get_physics_process_delta_time()
	_check("forty ticks is two seconds of simulation",
		absf(deltas - 2.0) < 0.05,
		"rate %d, deltas %.3f, wall %.2fs" % [
			Engine.physics_ticks_per_second, deltas,
			(float(Time.get_ticks_msec()) - started) * 0.001])

	# Nothing else may be touching a creep parked in the middle of the zone.
	# The builder starts there and attacks, which is what this catches.
	var creep: Creep = await _spawn("fel_orc_grunt")
	creep.take_damage(60, DamageTable.DamageType.SPELL)
	var samples: PackedStringArray = PackedStringArray()
	var last: float = creep.current_health
	var dipped: bool = false
	for index in range(6):
		await _ticks(10)
		dipped = dipped || creep.current_health < last
		last = creep.current_health
		samples.append("%.1f" % creep.current_health)
	_check("nothing but the creep itself touches a parked creep", !dipped,
		", ".join(samples))


func _check_fast_producing() -> void:
	var sheep: CreepStats = _creep_stats("sheep")
	var plain: CreepStats = _creep_stats("skeleton_warrior")
	var boosted: float = _stock_seconds(sheep)
	var normal: float = _stock_seconds(plain)
	_check("fast producing refills faster than the plain rate",
		boosted < normal, "sheep %.2fs vs skeleton %.2fs" % [boosted, normal])
	_check("by exactly the share the card quotes",
		absf(normal / boosted - 1.25) < 0.01, "%.3f" % (normal / boosted))
	_check("sheep sends 2 sheep and 1 wolf", sheep.pack_creep_count() == 3
		&& sheep.pack_contents().size() == 2, str(sheep.pack_creep_count()))


func _check_death_pact() -> void:
	var creep: Creep = await _spawn("skeleton_warrior")
	var before: int = _gold()
	creep.take_damage(9999, DamageTable.DamageType.NORMAL)
	_check("a revive is not a death", creep.is_down() && !creep.is_alive(), "")
	_check("a revive pays no bounty", _gold() == before, str(_gold() - before))

	await _seconds(2.0)
	var share: float = creep.current_health / float(creep.max_health())
	_check("gets back up at the authored share", creep.is_alive()
		&& absf(share - 0.33) < 0.06, "%.2f" % share)

	creep.take_damage(9999, DamageTable.DamageType.NORMAL)
	await _ticks(2)
	_check("the second death is real", !is_instance_valid(creep)
		|| !creep.is_alive(), "")
	_check("and pays the bounty", _gold() > before, str(_gold() - before))


func _check_unholy_sacrifice() -> void:
	var dying: Creep = await _spawn("acolyte")
	var friend: Creep = await _spawn("acolyte", Vector3(0.6, 0.0, 0.0))
	friend.take_damage(10, DamageTable.DamageType.NORMAL)
	var hurt: float = friend.current_health
	dying.take_damage(9999, DamageTable.DamageType.NORMAL)
	await _ticks(2)
	_check("heals a packmate as it dies", friend.current_health > hurt,
		"%.0f -> %.0f" % [hurt, friend.current_health])


func _check_skittering() -> void:
	var tower: Building = _place_tower("watch_tower")
	var skitterer: Creep = await _spawn("forest_spider", _toward(tower, 0.2))
	var ordinary: Creep = await _spawn("swordsman", _toward(tower, 0.35))
	var picked: Creep = TargetFinder.best_target(_area, tower.global_position,
		tower.stats.attack)
	_check("a skittering creep is not picked while anything else is in range",
		picked == ordinary, "picked %s" % _name_of(picked))

	_free(ordinary)
	await _ticks(2)
	picked = TargetFinder.best_target(_area, tower.global_position,
		tower.stats.attack)
	_check("but is picked when it is all there is", picked == skitterer,
		"picked %s" % _name_of(picked))
	_free(skitterer)


func _check_devotion_aura() -> void:
	var plain: Creep = await _spawn("skeleton_warrior")
	var alone: int = plain.armor_value()
	var giver: Creep = await _spawn("swordsman", Vector3(0.5, 0.0, 0.0))
	await _seconds(0.5)
	_check("devotion aura 1 grants +1 armor", plain.armor_value() == alone + 1,
		"%d -> %d" % [alone, plain.armor_value()])

	_free(giver)
	await _seconds(0.5)
	_check("and is lost when the giver goes", plain.armor_value() == alone,
		str(plain.armor_value()))


func _check_fel_blood() -> void:
	var creep: Creep = await _spawn("fel_orc_grunt")
	creep.take_damage(60, DamageTable.DamageType.SPELL)
	var hurt: float = creep.current_health
	await _seconds(2.0)
	var gained: float = creep.current_health - hurt
	_check("fel blood regenerates about 3 a second", absf(gained - 6.0) < 0.6,
		"%.1f in 2s, from %.0f of %d" % [gained, hurt, creep.max_health()])


func _check_endurance_aura() -> void:
	var plain: Creep = await _spawn("skeleton_warrior")
	var alone: float = plain.current_move_speed()
	var giver: Creep = await _spawn("vile_temptress", Vector3(0.5, 0.0, 0.0))
	await _seconds(0.5)
	var hasted: float = plain.current_move_speed()
	_check("endurance aura 1 is +10% movement",
		absf(hasted / alone - 1.1) < 0.01, "%.3f -> %.3f" % [alone, hasted])
	_free(giver)


func _check_flying() -> void:
	var flyer: Creep = await _spawn("shade")
	var cannon: Building = _place_tower("cannon")
	var watch: Building = _place_tower("watch_tower")
	_check("a ground-only attack cannot hit a flyer",
		!TargetFinder.can_be_hit_by(flyer, cannon.stats.attack), "")
	_check("an air-capable attack can",
		TargetFinder.can_be_hit_by(flyer, watch.stats.attack), "")
	_check("and the flyer reads none of the maze", flyer.ignores_maze(), "")


func _check_lesser_spell_resistance() -> void:
	var creep: Creep = await _spawn("mud_golem")
	var plain: Creep = await _spawn("swordsman", Vector3(0.6, 0.0, 0.0))
	var resisted: int = creep.resolve_damage(100, DamageTable.DamageType.SPELL)
	var normal: int = plain.resolve_damage(100, DamageTable.DamageType.SPELL)
	_check("takes a third less spell damage",
		absf(float(resisted) / float(normal) - 0.67) < 0.02,
		"%d vs %d" % [resisted, normal])

	creep.status().chill(_ability("Passives/lesser_spell_resistance"),
		"probe", 0.4, 0.4, 4.0, true)
	await _ticks(2)
	var slow: float = 1.0 - creep.status().move_ratio()
	_check("takes half of a movement chill", absf(slow - 0.2) < 0.01,
		"%.2f" % slow)


func _check_regen_aura() -> void:
	# A creep with no regeneration and no revive of its own, so what is
	# measured is the aura and nothing else.
	var plain: Creep = await _spawn("knight")
	plain.take_damage(200, DamageTable.DamageType.SPELL)
	var hurt: float = plain.current_health
	await _seconds(1.0)
	var alone: float = plain.current_health - hurt
	_check("a creep with no regeneration of its own mends at nothing",
		is_zero_approx(alone), "%.1f in 1s" % alone)

	hurt = plain.current_health
	var priest: Creep = await _spawn("priest", Vector3(0.5, 0.0, 0.0))
	await _seconds(2.0)
	var gained: float = plain.current_health - hurt
	_check("regen aura 1 restores about 2 a second", absf(gained - 4.0) < 0.6,
		"%.1f in 2s" % gained)
	_free(priest)


func _check_attacker() -> void:
	var tower: Building = _place_tower("watch_tower")
	var creep: Creep = await _spawn("corrupted_treant", _toward(tower, 0.4), false)
	var health: float = tower.current_health
	await _seconds(3.0)
	_check("an attacker creep damages a tower it is standing on",
		tower.current_health < health,
		"%.0f -> %.0f" % [health, tower.current_health])
	_check("and is commandable", creep.is_controllable(), "")


func _check_boss() -> void:
	var stats: CreepStats = _creep_stats("rot_golem")
	_check("a boss is sent one at a time", stats.pack_size == 1,
		str(stats.pack_size))
	_check("and steals two lives", stats.lives_stolen == 2,
		str(stats.lives_stolen))


# --- Tier 2 -------------------------------------------------------------

func _check_armored() -> void:
	var creep: Creep = await _spawn("knight")
	var single: int = creep.resolve_damage(1000, DamageTable.DamageType.NORMAL, false)
	var area_hit: int = creep.resolve_damage(1000, DamageTable.DamageType.NORMAL, true)
	_check("armored 1 takes 10% less from area damage",
		absf(float(area_hit) / float(single) - 0.9) < 0.02,
		"%d vs %d" % [area_hit, single])
	var spell_single: int = creep.resolve_damage(1000, DamageTable.DamageType.SPELL, false)
	var spell_area: int = creep.resolve_damage(1000, DamageTable.DamageType.SPELL, true)
	_check("and nothing off an area SPELL", spell_area == spell_single,
		"%d vs %d" % [spell_area, spell_single])


func _check_chaotic_void() -> void:
	var creep: Creep = await _spawn("voidwalker")
	var pool: CreepMana = creep.mana()
	_check("the voidwalker carries a pool", pool != null && pool.maximum == 26,
		"" if pool == null else str(pool.maximum))
	if pool == null:
		return

	creep.take_damage(200, DamageTable.DamageType.SPELL)
	await _ticks(1)
	_check("one hit is one mana, whatever it cost", pool.current == 1,
		str(pool.current))

	# One short of the top, so the next hit is the one that spends it.
	for index in range(pool.maximum - 2):
		creep.take_damage(1, DamageTable.DamageType.SPELL)
	await _ticks(1)
	_check("and stops one short of the top", pool.current == pool.maximum - 1,
		str(pool.current))

	var before: float = creep.current_health
	creep.take_damage(1, DamageTable.DamageType.SPELL)
	await _ticks(1)
	var healed: float = creep.current_health - before + 1.0
	_check("a full pool heals a twentieth of the creep and empties",
		pool.current == 0
		&& absf(healed - float(creep.max_health()) * 0.05) < 3.0,
		"mana %d, healed %.0f" % [pool.current, healed])


func _check_spell_resistance() -> void:
	var creep: Creep = await _spawn("dragonspawn")
	var plain: Creep = await _spawn("knight", Vector3(0.7, 0.0, 0.0))
	var resisted: int = creep.resolve_damage(1000, DamageTable.DamageType.SPELL)
	var normal: int = plain.resolve_damage(1000, DamageTable.DamageType.SPELL)
	_check("takes half the spell damage",
		absf(float(resisted) / float(normal) - 0.5) < 0.02,
		"%d vs %d" % [resisted, normal])

	creep.status().stun(_ability("Passives/spell_resistance"), 10.0)
	await _ticks(1)
	_check("and serves a tenth of a harmful clock", creep.status().is_stunned(), "")
	await _seconds(1.2)
	_check("so a ten second stun is over in one",
		!creep.status_or_null() || !creep.status().is_stunned(), "")


func _check_bombardment() -> void:
	var tower: Building = _place_tower("watch_tower")
	var creep: Creep = await _spawn("siege_engine", _toward(tower, 1.2))
	var health: float = tower.current_health
	await _seconds(5.0)
	_check("bombardment reaches a tower it never walked to",
		tower.current_health < health,
		"%.0f -> %.0f" % [health, tower.current_health])


# --- Tier 3 -------------------------------------------------------------

func _check_ethereal_aura() -> void:
	var fiend: Creep = await _spawn("crypt_fiend")
	var friend: Creep = await _spawn("knight", Vector3(0.6, 0.0, 0.0))
	var before: int = friend.armor_value() + fiend.armor_value()
	await _seconds(7.0)
	var after: int = friend.armor_value() + fiend.armor_value()
	_check("ethereal aura hands out armor on its clock", after >= before + 2,
		"%d -> %d" % [before, after])

	# A GIFT rather than an aura: what it handed over survives the giver.
	var kept: float = friend.status().granted_armor() + fiend.status().granted_armor()
	_free(fiend)
	await _seconds(0.6)
	_check("and what it handed over is kept, not lent",
		friend.status().granted_armor() + kept > 0.0, "%.0f" % kept)


func _check_bone_shield() -> void:
	var creep: Creep = await _spawn("necromancer")
	var stats: CreepStats = _creep_stats("necromancer")
	_check("bone shield spends the armor", creep.armor_value() == 0,
		str(creep.armor_value()))
	var expected: int = int(round(float(stats.max_health) * 1.2))
	_check("and buys 4% health a point", absi(creep.max_health() - expected) <= 1,
		"%d vs %d" % [creep.max_health(), expected])

	creep.status().chill(_ability("Passives/bone_shield"), "probe", 0.5, 0.5, 4.0, false)
	await _ticks(2)
	_check("and cannot be slowed", is_equal_approx(creep.status().move_ratio(), 1.0),
		"%.2f" % creep.status().move_ratio())


func _check_ethereal() -> void:
	var creep: Creep = await _spawn("spirit_walker")
	_check("an ethereal creep reads none of the maze", creep.ignores_maze(), "")
	_check("but is not flying", !creep.is_flying(), "")
	var cannon: Building = _place_tower("cannon")
	_check("so a ground-only tower may still shoot it",
		TargetFinder.can_be_hit_by(creep, cannon.stats.attack), "")

	creep.take_damage(20000, DamageTable.DamageType.NORMAL)
	var hurt: float = creep.current_health
	await _seconds(1.0)
	_check("and it mends fast", creep.current_health - hurt > 400.0,
		"%.0f in 1s" % (creep.current_health - hurt))


func _check_spiritual_aid() -> void:
	var walker: Creep = await _spawn("spirit_walker")
	var friend: Creep = await _spawn("knight", Vector3(0.6, 0.0, 0.0))
	var before: int = friend.armor_value() + walker.armor_value()
	await _seconds(14.0)
	var after: int = friend.armor_value() + walker.armor_value()
	_check("spiritual aid thickens the pack on its clock", after >= before + 2,
		"%d -> %d" % [before, after])
	_check("and spreads rather than topping one creep up",
		friend.armor_value() > 0 && walker.status().granted_armor() > 0.0,
		"walker %.0f, knight %.0f" % [walker.status().granted_armor(),
			friend.status().granted_armor()])

	# The Crypt Fiend's gift must not spend the Spirit Walker's own allowance.
	friend.status().bless_armor(_ability("Passives/ethereal_aura"), 20.0)
	var lent: float = friend.status().granted_armor(
		_ability("Passives/spiritual_aid"))
	_check("and its allowance is its own, not the pack's total",
		lent < 20.0, "%.1f of its own" % lent)


func _check_hardened_skin() -> void:
	var creep: Creep = await _spawn("ancient_wendigo")
	var start: int = creep.armor_value()
	for index in range(40):
		creep.take_damage(20, DamageTable.DamageType.NORMAL)
	await _ticks(1)
	_check("small hits never add up", creep.armor_value() == start,
		"%d -> %d" % [start, creep.armor_value()])

	creep.take_damage(4000, DamageTable.DamageType.NORMAL)
	await _ticks(1)
	_check("one heavy hit strips a point", creep.armor_value() == start - 1,
		"%d -> %d" % [start, creep.armor_value()])

	creep.take_damage(4000, DamageTable.DamageType.SPELL)
	await _ticks(1)
	_check("spell damage strips nothing", creep.armor_value() == start - 1,
		str(creep.armor_value()))


func _check_elemental_warding() -> void:
	var creep: Creep = await _spawn("shaman")
	var plain: int = creep.resolve_damage(10000, DamageTable.DamageType.PIERCING)
	creep.take_damage(10000, DamageTable.DamageType.PIERCING)
	await _seconds(0.4)
	var warded: int = creep.resolve_damage(10000, DamageTable.DamageType.PIERCING)
	_check("braces against what has hurt it most",
		absf(float(warded) / float(plain) - 0.3) < 0.03,
		"%d vs %d" % [warded, plain])

	creep.take_damage(60000, DamageTable.DamageType.SIEGE)
	await _seconds(0.4)
	_check("and holds the brace for the swap gate",
		creep.warding().warded_type() == int(DamageTable.DamageType.PIERCING),
		str(creep.warding().warded_type()))
	await _seconds(3.2)
	_check("then moves it to the new worst type",
		creep.warding().warded_type() == int(DamageTable.DamageType.SIEGE),
		str(creep.warding().warded_type()))


func _check_wind_rush() -> void:
	var shaman: Creep = await _spawn("shaman")
	var friend: Creep = await _spawn("knight", Vector3(0.6, 0.0, 0.0))
	var pool: CreepMana = shaman.mana()
	_check("the shaman starts part full", pool != null && pool.current == 10
		&& pool.maximum == 14, "" if pool == null else "%d/%d" % [pool.current, pool.maximum])

	friend.status().chill(_ability("Passives/wind_rush"), "probe", 0.5, 0.5, 20.0, false)
	var slowed: float = friend.current_move_speed()
	await _seconds(5.0)
	_check("and hurries the slowest creep near it",
		friend.current_move_speed() > slowed,
		"%.2f -> %.2f" % [slowed, friend.current_move_speed()])


func _check_regenerative_flesh() -> void:
	var creep: Creep = await _spawn("abomination")
	creep.status().chill(_ability("Passives/regenerative_flesh"),
		"probe", 0.4, 0.4, 10.0, false)
	await _ticks(1)
	_check("a ten second slow is capped to 1.4",
		creep.status().move_ratio() < 1.0, "%.2f" % creep.status().move_ratio())
	await _seconds(2.0)
	_check("and is gone well inside the window",
		creep.status_or_null() == null
		|| is_equal_approx(creep.status().move_ratio(), 1.0),
		"still %.2f" % (1.0 if creep.status_or_null() == null
			else creep.status().move_ratio()))

	# An aura's slow is a HOLD it re-states, so the 1.4 second ceiling has no
	# claim on it - a Sludge Monstrosity and a Titan Vault grind an Abomination
	# down exactly as they do anything else. See StatusEffects._slow_seconds.
	creep.status().slow(_ability("Passives/regenerative_flesh"),
		"probe_aura", 0.4, 10.0, false, true)
	await _seconds(2.0)
	_check("but an aura's slow it serves in full",
		creep.status().move_ratio() < 1.0, "%.2f" % creep.status().move_ratio())

	creep.take_damage(int(float(creep.max_health()) * 0.9),
		DamageTable.DamageType.SPELL)
	var hurt: float = creep.current_health
	await _seconds(1.0)
	var gained: float = creep.current_health - hurt
	_check("a hurt abomination mends near the cap", gained > 150.0,
		"%.0f in 1s" % gained)


func _check_earth_shield() -> void:
	var magi: Creep = await _spawn("ogre_magi")
	var friend: Creep = await _spawn("knight", Vector3(0.6, 0.0, 0.0))
	friend.status().chill(_ability("Passives/earth_shield"), "probe", 0.5, 0.5, 60.0, false)
	await _ticks(2)
	_check("the packmate starts slowed", friend.status().move_ratio() < 1.0,
		"%.2f" % friend.status().move_ratio())

	await _seconds(15.0)
	_check("earth shield strips it inside its interval",
		is_equal_approx(friend.status().move_ratio(), 1.0),
		"%.2f" % friend.status().move_ratio())
	_check("and mends it", friend.status().mend_per_second() > 0.0,
		"%.1f/s" % friend.status().mend_per_second())


func _check_chaos_barrier() -> void:
	var creep: Creep = await _spawn("chaos_wardens")
	var pool: CreepMana = creep.mana()
	_check("the warden starts full", pool != null && pool.current == 100,
		"" if pool == null else str(pool.current))
	var full: int = creep.resolve_damage(10000, DamageTable.DamageType.NORMAL)
	await _seconds(6.0)
	var drained: int = creep.resolve_damage(10000, DamageTable.DamageType.NORMAL)
	_check("and takes more as the pool drains", drained > full,
		"%d -> %d at %d mana" % [full, drained, pool.current])
	_check("draining 5% of the ceiling a second", pool.current <= 75
		&& pool.current >= 65, str(pool.current))


func _check_mana_drain() -> void:
	var tower: Building = _place_tower("arcane_sorcerer")
	tower.gain_mana(10000.0)
	var before: int = tower.current_mana
	_check("the test tower has mana to take", before > 0, str(before))
	var creep: Creep = await _spawn("chaos_wardens", _toward(tower, 0.3))
	creep.mana().drain()
	await _seconds(1.0)
	_check("an empty warden drains a tower it stands beside",
		tower.current_mana < before,
		"%d -> %d" % [before, tower.current_mana])
	_check("and keeps far more than it took", creep.mana().current > 0,
		str(creep.mana().current))


func _check_abyssal_carapace() -> void:
	var creep: Creep = await _spawn("behemoth")
	var stats: CreepStats = _creep_stats("behemoth")
	var tenth: int = int(round(float(stats.max_health) * 0.1))
	_check("the bar is a tenth of the creep",
		absi(creep.max_health() - tenth) <= 2,
		"%d of %d" % [creep.max_health(), stats.max_health])
	var shield: float = creep.status().shield_points()
	_check("and the rest stands in front of it",
		absf(shield - float(stats.max_health) * 0.9) < 100.0, "%.0f" % shield)

	creep.take_damage(1000, DamageTable.DamageType.SPELL)
	await _ticks(1)
	_check("the shield is spent before the health",
		is_equal_approx(creep.current_health, float(creep.max_health()))
		&& creep.status().shield_points() < shield,
		"health %.0f, shield %.0f" % [creep.current_health,
			creep.status().shield_points()])


# --- Tier 4 -------------------------------------------------------------

func _check_elunes_grace() -> void:
	var creep: Creep = await _spawn("huntress")
	creep.take_damage(1000, DamageTable.DamageType.NORMAL)
	await _ticks(1)
	_check("the first hit lands", creep.current_health < float(creep.max_health()),
		"%.0f" % creep.current_health)
	_check("and the ward goes up behind it", creep.status().is_warded(), "")

	var held: float = creep.current_health
	creep.take_damage(100000, DamageTable.DamageType.NORMAL)
	await _ticks(1)
	_check("nothing lands while it is warded",
		is_equal_approx(creep.current_health, held), "%.0f" % creep.current_health)


func _check_quickness() -> void:
	var creep: Creep = await _spawn("huntress")
	var short_reach: float = 3.0
	var long_reach: float = 8.0
	_check("nothing is dodged from close in",
		is_zero_approx(creep.dodge_chance_against(short_reach)),
		"%.2f" % creep.dodge_chance_against(short_reach))
	_check("half is dodged from far off",
		absf(creep.dodge_chance_against(long_reach) - 0.5) < 0.01,
		"%.2f" % creep.dodge_chance_against(long_reach))


func _check_annihilation_aura() -> void:
	var tower: Building = _place_tower("watch_tower")
	var full: float = tower.attack_damage_ratio()
	var statue: Creep = await _spawn("obsidian_statue", _toward(tower, 0.3))
	await _seconds(0.5)
	var weakened: float = tower.attack_damage_ratio()
	_check("a statue weakens a tower it walks past",
		absf(weakened / full - 0.85) < 0.02, "%.2f -> %.2f" % [full, weakened])

	_free(statue)
	await _seconds(1.5)
	_check("and the tower recovers once it is gone",
		is_equal_approx(tower.attack_damage_ratio(), full),
		"%.2f" % tower.attack_damage_ratio())


func _check_exhume_ghouls() -> void:
	var statue: Creep = await _spawn("obsidian_statue")
	var before: int = _area.creeps().size()
	statue.take_damage(99999999, DamageTable.DamageType.SPELL)
	await _ticks(3)
	var after: int = _area.creeps().size()
	_check("a dead statue leaves three ghouls", after == before + 2,
		"%d -> %d" % [before, after])


func _check_blocked() -> void:
	var giants: Array[Creep] = []
	for index in range(3):
		giants.append(await _spawn("mountain_giant",
			Vector3(float(index) * 0.3, 0.0, 0.0)))
	await _ticks(2)
	_check("three of a kind is no penalty at all",
		is_equal_approx(giants[0].attack_damage_ratio(), 1.0),
		"%.2f" % giants[0].attack_damage_ratio())

	giants.append(await _spawn("mountain_giant", Vector3(0.9, 0.0, 0.0)))
	giants.append(await _spawn("mountain_giant", Vector3(1.2, 0.0, 0.0)))
	await _ticks(2)
	_check("the fourth and fifth cost 8% each",
		absf(giants[0].attack_damage_ratio() - 0.84) < 0.02,
		"%.2f" % giants[0].attack_damage_ratio())


func _check_stoneskin() -> void:
	var creep: Creep = await _spawn("mountain_giant")
	creep.status().chill(_ability("Passives/stoneskin_fortitude"),
		"probe", 0.5, 0.5, 10.0, false)
	await _ticks(2)
	_check("stoneskin refuses a chill outright",
		is_equal_approx(creep.status().move_ratio(), 1.0),
		"%.2f" % creep.status().move_ratio())


func _check_wicked_curse() -> void:
	var tower: Building = _place_tower("watch_tower")
	var harpy: Creep = await _spawn("harpy_windwitch", _toward(tower, 0.3))
	var full: float = tower.attack_speed_ratio()
	harpy.take_damage(99999999, DamageTable.DamageType.SPELL)
	await _ticks(3)
	var cursed: float = tower.attack_speed_ratio()
	_check("a dying harpy curses the tower over it",
		absf(cursed / full - 0.7) < 0.02, "%.2f -> %.2f" % [full, cursed])


func _check_sirens_song() -> void:
	var siren: Creep = await _spawn("naga_siren")
	var pool: CreepMana = siren.mana()
	_check("the siren carries a fifty point pool",
		pool != null && pool.maximum == 50,
		"" if pool == null else str(pool.maximum))
	if pool == null:
		return

	siren.take_damage(int(float(siren.max_health()) * 0.5),
		DamageTable.DamageType.SPELL)
	for index in range(pool.maximum - 1):
		siren.take_damage(1, DamageTable.DamageType.SPELL)
	await _ticks(2)
	_check("a full pool raises its own ceiling", pool.maximum == 100,
		str(pool.maximum))
	_check("and empties", pool.current == 0, str(pool.current))


func _check_war_stance() -> void:
	var kodo: Creep = await _spawn("kodo_beast")
	var calm_armor: int = kodo.armor_value()
	var calm_type: int = int(kodo.armor_type_value())
	kodo.take_damage(int(float(kodo.max_health()) * 0.8),
		DamageTable.DamageType.SPELL)
	await _ticks(2)
	_check("below the line it counts as hero armor",
		int(kodo.armor_type_value()) == int(UnitStats.ArmorType.HERO)
		&& calm_type != int(UnitStats.ArmorType.HERO),
		"%d -> %d" % [calm_type, int(kodo.armor_type_value())])
	_check("and gains seven points", kodo.armor_value() == calm_armor + 7,
		"%d -> %d" % [calm_armor, kodo.armor_value()])

	kodo.heal(float(kodo.max_health()))
	await _ticks(2)
	_check("healing it back over the line turns all of it off",
		int(kodo.armor_type_value()) == calm_type
		&& kodo.armor_value() == calm_armor, str(kodo.armor_value()))


func _check_goblin_engineering() -> void:
	var creep: Creep = await _spawn("goblin_shredder")
	var source: UnitAbility = _ability("Passives/goblin_engineering")
	creep.status().chill(source, "one", 0.6, 0.6, 20.0, false)
	creep.status().chill(source, "two", 0.6, 0.6, 20.0, false)
	await _ticks(2)
	var slow: float = 1.0 - creep.status().move_ratio()
	_check("however many chill it, it is never past a quarter",
		absf(slow - 0.25) < 0.01, "%.2f" % slow)


func _check_reactive_armor() -> void:
	var creep: Creep = await _spawn("goblin_shredder")
	var small: int = _landed(creep, 200)
	var middle: int = _landed(creep, 800)
	var large: int = _landed(creep, 5000)
	_check("a small hit lands whole", small == 200, str(small))
	_check("the middle band is cut by 95%",
		absi(middle - (300 + 25)) <= 2, str(middle))
	_check("and the top band by 75%",
		absi(large - (300 + 35 + 1000)) <= 3, str(large))


func _check_volatile_death() -> void:
	var tower: Building = _place_tower("watch_tower")
	var phoenix: Creep = await _spawn("phoenix", _toward(tower, 0.3), false)
	var health: float = tower.current_health
	phoenix.take_damage(99999999, DamageTable.DamageType.SPELL)
	await _ticks(3)
	_check("a dying phoenix damages the towers around it",
		tower.current_health < health,
		"%.0f -> %.0f" % [health, tower.current_health])


func _check_legendary_resistance() -> void:
	var creep: Creep = await _spawn("phoenix", Vector3.ZERO, false)
	var plain: Creep = await _spawn("kodo_beast", Vector3(0.8, 0.0, 0.0))
	var resisted: int = creep.resolve_damage(10000, DamageTable.DamageType.SPELL)
	var normal: int = plain.resolve_damage(10000, DamageTable.DamageType.SPELL)
	_check("takes three quarters less spell damage",
		absf(float(resisted) / float(normal) - 0.25) < 0.02,
		"%d vs %d" % [resisted, normal])

	creep.status().stun(_ability("Passives/legendary_spell_resistance"), 10.0)
	creep.status().chill(_ability("Passives/legendary_spell_resistance"),
		"probe", 0.5, 0.5, 10.0, true)
	await _ticks(2)
	_check("and no timed harmful effect applies at all",
		!creep.status().is_stunned()
		&& is_equal_approx(creep.status().move_ratio(), 1.0),
		"stunned %s, move %.2f" % [creep.status().is_stunned(),
			creep.status().move_ratio()])


func _check_dive() -> void:
	var tower: Building = _place_tower("watch_tower")
	var phoenix: Creep = await _spawn("phoenix", _toward(tower, -1.2), false)
	phoenix.status().erode_armor(_ability("Passives/volatile_death"), 8.0, 0.0)
	await _ticks(1)
	var eaten: int = phoenix.armor_value()

	var dive: DiveAbility = _ability("Creeps/dive_ability") as DiveAbility
	var target: AbilityTarget = AbilityTarget.at_position(
		tower.global_position + Vector3(3.0, 0.0, 0.0))
	var health: float = tower.current_health
	dive.execute(phoenix, target)
	_check("the dive starts", phoenix.is_diving(), "")
	await _seconds(1.5)
	_check("and burns the towers it passes over", tower.current_health < health,
		"%.0f -> %.0f" % [health, tower.current_health])

	phoenix.stop()
	await _ticks(1)
	_check("stopping it ends the dive", !phoenix.is_diving(), "")
	_check("and hands the armor back", phoenix.armor_value() > eaten,
		"%d -> %d" % [eaten, phoenix.armor_value()])


func _check_unfathomable_power() -> void:
	var demon: Creep = await _spawn("demon")
	var before: float = demon.current_health
	demon.take_damage(99999999, DamageTable.DamageType.SPELL)
	await _ticks(2)
	_check("nothing touches a demon",
		is_instance_valid(demon) && is_equal_approx(demon.current_health, before),
		"%.0f" % demon.current_health)

	var giver: Creep = await _spawn("swordsman", Vector3(0.5, 0.0, 0.0))
	var alone: int = demon.armor_value()
	await _seconds(0.5)
	_check("and no aura reaches it", demon.armor_value() == alone,
		"%d -> %d" % [alone, demon.armor_value()])
	_free(giver)


func _check_escape_portal() -> void:
	var goblin: Creep = await _spawn("treasure_goblin")
	var before: int = _gold()
	goblin.take_damage(1, DamageTable.DamageType.NORMAL)
	await _ticks(3)
	_check("one point of damage removes a goblin",
		!is_instance_valid(goblin) || !goblin.is_alive(), "")
	_check("and pays its whole bounty", _gold() - before >= 30000,
		str(_gold() - before))
	_check("it can never steal a life",
		_creep_stats("treasure_goblin").lives_stolen == 0, "")


# --- Helpers ------------------------------------------------------------

## What actually reaches a creep's health out of one hit, measured rather than
## computed: the bands one creep in the roster carries are applied after
## resolve_damage and are not part of what it answers.
func _landed(creep: Creep, amount: int) -> int:
	var before: float = creep.current_health
	creep.take_damage(amount, DamageTable.DamageType.SPELL)
	var lost: int = int(round(before - creep.current_health))
	creep.heal(float(lost))
	return lost


func _find_area() -> PlayerArea:
	var manager: PlayerManager = References.player_manager
	return null if manager == null else manager.area_for(1)


func _creep_stats(stem: String) -> CreepStats:
	return load("%s/%s_stats.tres" % [CREEPS, stem]) as CreepStats


func _ability(path: String) -> UnitAbility:
	return load("%s/%s.tres" % [ABILITIES, path]) as UnitAbility


func _gold() -> int:
	var manager: PlayerManager = References.player_manager
	if manager == null:
		return 0
	var state: PlayerState = manager.state_for(1)
	return 0 if state == null else state.gold


## Spawns one creep at an offset from the probe's anchor and, unless told
## otherwise, pins it there for the rest of the check.
func _spawn(stem: String, offset: Vector3 = Vector3.ZERO,
		hold: bool = true, owner_slot: int = 1) -> Creep:
	var stats: CreepStats = _creep_stats(stem)
	if stats == null:
		_fail(stem, "no stats resource")
		return null
	var scene: PackedScene = stats.scene()
	if scene == null:
		_fail(stem, "no prefab")
		return null

	var creep: Creep = scene.instantiate() as Creep
	_area.creeps_root().add_child(creep)
	var at: Vector3 = _anchor() + offset
	creep.spawn(owner_slot, _area, at)
	if hold:
		_held[creep] = creep.global_position
	await _ticks(1)
	return creep


## Where creeps are put: the middle of the build zone, well clear of the exit.
func _anchor() -> Vector3:
	var center: Vector3 = _area.build_zone_center()
	return Vector3(center.x, 0.0, center.z)


func _place_tower(stem: String) -> Building:
	var stats: BuildingStats = load("%s/%s_stats.tres" % [TOWERS, stem]) as BuildingStats
	if stats == null:
		_fail(stem, "no tower stats")
		return null
	var scene: PackedScene = stats.scene()
	if scene == null:
		_fail(stem, "no tower prefab")
		return null

	var footprint: Vector2i = _area.cells_to_internal(stats.footprint_cells)
	var cell: Vector2i = _tower_cell(footprint)
	if cell.x < 0:
		_fail(stem, "nowhere to stand it")
		return null
	var tower: Building = scene.instantiate() as Building
	_area.add_child(tower)
	tower.place(1, _area, cell, 0, true)
	return tower


## A free cell as near the anchor as one can be found, so a creep spawned at
## the anchor is standing on the tower rather than a lane away from it. Every
## check that pairs the two needs that: an aura, a curse and a blast are all
## measured in a cell or two.
##
## Searched outwards in rings rather than along a row, and it steps AROUND the
## anchor cell itself so the spot the creeps are put in stays walkable.
func _tower_cell(footprint: Vector2i) -> Vector2i:
	var home: Vector2i = _area.world_to_internal_cell(_anchor())
	for ring in range(1, 12):
		for dx in range(-ring, ring + 1):
			for dz in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var cell: Vector2i = home + Vector2i(dx * footprint.x, dz * footprint.y)
				if cell.x >= 0 && cell.y >= 0 && _area.can_place(cell, footprint):
					return cell
	return Vector2i(-1, -1)


func _free(unit: Node) -> void:
	if unit == null || !is_instance_valid(unit):
		return
	_held.erase(unit)
	# Stopped BEFORE it is taken out, because remove_child runs _exit_tree at
	# once and anything still mid-tick then walks a node with no transform. A
	# tower has to go out that way all the same - that is what hands its grid
	# cells back before the next check asks for them.
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	var parent: Node = unit.get_parent()
	if parent != null:
		parent.remove_child(unit)
	unit.queue_free()


## Empties the area between checks, so nothing one check left behind can be
## picked up by the aura scan of the next.
func _reset() -> void:
	_held.clear()
	for creep: Creep in _area.creeps():
		_free(creep)
	for child: Node in _area.get_children():
		if child is Building:
			_free(child)
	_park_builder()


## Walks the player's own builder into a corner and switches it off.
##
## It starts in the MIDDLE of the buildable zone, which is exactly where this
## probe puts its creeps - and it carries a 4-5 damage attack on a three second
## clock. Left where it stands it quietly chews on whatever is being measured,
## which read as a regeneration trait paying about a third of what its card
## promises. It is not a bug in anything: it is the builder doing its job in
## the one spot a test rig wanted empty.
func _park_builder() -> void:
	var root: Node3D = References.units_root
	if root == null:
		return
	for child: Node in root.get_children():
		var builder: Builder = child as Builder
		if builder == null:
			continue
		builder.process_mode = Node.PROCESS_MODE_DISABLED
		if builder.area == _area:
			builder.global_position = _area.clamp_point(
				_anchor() + Vector3(20.0, 0.0, 20.0))


func _ticks(count: int) -> void:
	for index in range(maxi(1, count)):
		await get_tree().physics_frame


func _seconds(amount: float) -> void:
	await _ticks(maxi(1, int(round(amount * 20.0))))


func _check(what: String, passed: bool, detail: String) -> void:
	if passed:
		_passes += 1
		_lines.append("  ok   %s%s" % [what, "" if detail.is_empty()
			else "  (%s)" % detail])
		return
	_fails += 1
	_lines.append("  FAIL %s%s" % [what, "" if detail.is_empty()
		else "  (%s)" % detail])


func _fail(what: String, detail: String) -> void:
	_check(what, false, detail)


func _name_of(creep: Creep) -> String:
	if creep == null || !is_instance_valid(creep):
		return "nothing"
	return creep.stats.display_name


func _finish() -> void:
	print("\n[%s] ---------------------------------------------" % TAG)
	for line: String in _lines:
		print("[%s] %s" % [TAG, line])
	print("[%s] ---------------------------------------------" % TAG)
	print("[%s] %d passed, %d FAILED" % [TAG, _passes, _fails])
	get_tree().quit(0 if _fails == 0 else 1)


## Seconds one send of this creep takes to come back, with its passives folded
## in. Measured through the real CreepStock rather than by reading the passive,
## so what is checked is the number a player waits out.
func _stock_seconds(stats: CreepStats) -> float:
	var stock: CreepStock = CreepStock.new()
	stock.setup(stats)
	stock.unlock()
	var seconds: float = 0.0
	while !stock.is_full() && seconds < 1000.0:
		var before: int = stock.count
		stock.advance(0.05)
		seconds += 0.05
		if stock.count > before:
			return seconds
	return seconds


## An offset from the anchor that lands `share` of the way towards a tower, so
## a check can put a creep on top of one without knowing where either is.
##
## An OFFSET rather than a world point, because _spawn takes offsets - handing
## it a world position was the harness bug that put the first run's creeps in
## another lane entirely.
func _toward(tower: Building, share: float) -> Vector3:
	if tower == null || !is_instance_valid(tower):
		return Vector3.ZERO
	var offset: Vector3 = tower.global_position - _anchor()
	offset.y = 0.0
	var length: float = offset.length()
	if length < 0.001:
		return Vector3.ZERO
	return offset.normalized() * maxf(0.0, length - share) if share >= 0.0 \
		else offset.normalized() * (length - share)


# --- Creeps against real towers -----------------------------------------

func _check_dodge_against_towers() -> void:
	var huntress: Creep = await _spawn("huntress")
	# ELUNE'S GRACE FIRST. The first hit of any kind wards it for fifteen
	# seconds, so a dodge measured before that window is over reads as a
	# hundred percent dodge - which is what the first run of this check
	# reported and is the trait next door rather than this one. The second
	# ward only lands below half health, and this keeps it topped up.
	_strike(huntress, 1, 1.0)
	await _seconds(15.5)
	huntress.heal(float(huntress.max_health()))
	_check("the ward is over before anything is counted",
		!huntress.status().is_warded(), "")

	var far_landed: int = _count_landed(huntress, 9.0, 200)
	var share: float = float(far_landed) / 200.0
	_check("about half of a long shot misses", absf(share - 0.5) < 0.12,
		"%d of 200 landed" % far_landed)
	_check("and nothing at all misses from close in",
		_count_landed(huntress, 3.0, 200) == 200, "")


## How many of `tried` shots from this reach actually took health off, with the
## creep healed back between each so nothing else can end the run.
func _count_landed(creep: Creep, reach: float, tried: int) -> int:
	var landed: int = 0
	for index in range(tried):
		var before: float = creep.current_health
		_strike(creep, 100, reach)
		if creep.current_health < before:
			landed += 1
		creep.heal(float(creep.max_health()))
	return landed


func _check_eaten_armor() -> void:
	var wendigo: Creep = await _spawn("ancient_wendigo")
	var start: int = wendigo.armor_value()
	var warden: Building = _place_tower("earth_lesser_ancient_warden")
	_check("the armor eater is in reach", warden != null
		&& TargetFinder.is_in_range(warden.global_position, wendigo,
			warden.stats.attack.attack_range), "")

	await _seconds(8.0)
	_check("a tower eating armor gets under the hardened skin",
		wendigo.armor_value() < start,
		"%d -> %d" % [start, wendigo.armor_value()])
	_check("and the two erosions compose rather than clamping each other",
		wendigo.status().armor_delta() < 0
		|| wendigo.heavy_hits_taken() > 0,
		"eaten %d, heavy hits %d" % [wendigo.status().armor_delta(),
			wendigo.heavy_hits_taken()])


func _check_armor_restored() -> void:
	var siren: Creep = await _spawn("naga_siren")
	var base: int = siren.armor_value()
	siren.status().erode_armor(_ability("Passives/sirens_song"), 5.0, 0.0)
	await _ticks(1)
	var eaten: int = siren.armor_value()
	_check("a tower can eat a siren's armor", eaten < base,
		"%d -> %d" % [base, eaten])

	var pool: CreepMana = siren.mana()
	for index in range(pool.maximum):
		siren.take_damage(1, DamageTable.DamageType.SPELL)
	await _ticks(2)
	_check("and the song gives some of it back", siren.armor_value() > eaten,
		"%d -> %d" % [eaten, siren.armor_value()])
	_check("but never past what it started with", siren.armor_value() <= base,
		"%d of %d" % [siren.armor_value(), base])


func _check_shield_vs_chill() -> void:
	var magi: Creep = await _spawn("ogre_magi")
	var friend: Creep = await _spawn("knight", Vector3(0.5, 0.0, 0.0))
	var lich: Building = _place_tower("ice_lesser_lich")
	# A tower shoots ONE creep at a time, and which of the pair it settles on
	# is its own business - so what is read is the pair rather than the one
	# this check happened to name.
	await _seconds(6.0)
	var chilled: float = minf(friend.status().move_ratio(),
		magi.status().move_ratio())
	_check("a lich chills one of the pair", chilled < 1.0, "%.2f" % chilled)

	# Taken away, so nothing is re-applying while the shield works: what is
	# checked is that the shield really strips what is already there.
	_free(lich)
	await _seconds(15.0)
	var left: float = minf(friend.status().move_ratio(),
		magi.status().move_ratio())
	_check("and earth shield takes it off inside its interval",
		is_equal_approx(left, 1.0), "%.2f" % left)


func _check_cap_vs_towers() -> void:
	# ONE CREEP AT A TIME. A tower shoots one target, so a shredder standing
	# beside anything else is simply not the creep being chilled - the pair
	# version of this check read a cap that nothing had ever tested.
	_place_tower("ice_lesser_lich")
	_place_tower("ice_lesser_crystal")
	_place_tower("water_lesser_sludge_monstrosity")

	var plain: Creep = await _spawn("kodo_beast")
	await _seconds(8.0)
	var loose: float = 1.0 - plain.status().move_ratio()
	_check("a lane of chill towers really slows an ordinary creep",
		loose > 0.25, "%.2f" % loose)
	_free(plain)

	var shredder: Creep = await _spawn("goblin_shredder")
	await _seconds(8.0)
	var capped: float = 1.0 - shredder.status().move_ratio()
	_check("the same lane does reach the shredder", capped > 0.0,
		"%.2f" % capped)
	_check("and never takes it past its quarter", capped <= 0.2501,
		"%.2f" % capped)


func _check_aura_vs_damage() -> void:
	# NOT a creep with a shield in front of its health: what is measured is
	# health, and a Behemoth spends nine tenths of every hit on its carapace
	# without the bar moving at all.
	var target: Creep = await _spawn("kodo_beast")
	var tower: Building = _place_tower("greater_watch_tower")
	var full: int = await _damage_over(target, 8.0)
	_check("the tower is shooting at all", full > 0, str(full))

	var statue: Creep = await _spawn("obsidian_statue", _toward(tower, 0.3))
	await _seconds(1.0)
	var weakened: int = await _damage_over(target, 8.0)
	_check("a statue in the maze makes every shot land softer",
		full > 0 && weakened < full,
		"%d -> %d over eight seconds" % [full, weakened])


func _check_resistance_vs_burn() -> void:
	var resistant: Creep = await _spawn("phoenix", Vector3.ZERO, true)
	var plain: Creep = await _spawn("kodo_beast", Vector3(0.5, 0.0, 0.0))
	var source: UnitAbility = _ability("TowerPassives/ignite") if false else \
		_ability("Passives/legendary_spell_resistance")
	plain.status().burn(source, 1000.0, 4.0)
	resistant.status().burn(source, 1000.0, 4.0)
	await _ticks(2)
	_check("an ordinary creep starts burning",
		plain.current_health < float(plain.max_health()), "")
	_check("and one immune to timed effects never does",
		is_equal_approx(resistant.current_health, float(resistant.max_health())),
		"%.0f of %d" % [resistant.current_health, resistant.max_health()])


func _check_tower_destroyed() -> void:
	var tower: Building = _place_tower("lesser_archer")
	var cell: Vector2i = tower.cell
	var footprint: Vector2i = tower.footprint()
	var giant: Creep = await _spawn("mountain_giant", _toward(tower, 0.3), false)
	# Watched rather than waited out. Rubble lasts seven seconds, so a check
	# that simply slept for twelve read a square that had already cleared.
	var down: bool = false
	for index in range(30):
		await _seconds(0.5)
		if !is_instance_valid(tower) || !tower.is_alive():
			down = true
			break
	_check("an attacker creep takes a cheap tower down", down, "")
	_check("and the square is refused while the rubble is there",
		down && !_area.can_place(cell, footprint), "")
	await _seconds(7.5)
	_check("and is free again once the rubble is gone",
		_area.can_place(cell, footprint), "")


func _check_paralyzed_flyer() -> void:
	var flyer: Creep = await _spawn("wyvern")
	var cannon: Building = _place_tower("cannon")
	_check("a ground-only tower cannot reach a flyer",
		!TargetFinder.can_be_hit_by(flyer, cannon.stats.attack), "")

	flyer.status().paralyze(_ability("Passives/flying"), 5.0)
	await _ticks(1)
	_check("a paralyzed one is pinned where it can",
		TargetFinder.can_be_hit_by(flyer, cannon.stats.attack), "")
	_check("and is held still while it lasts", flyer.status().is_held(), "")


func _check_altered_type() -> void:
	var kodo: Creep = await _spawn("kodo_beast")
	kodo.take_damage(int(float(kodo.max_health()) * 0.8),
		DamageTable.DamageType.SPELL)
	await _ticks(2)
	_check("war stance has made it hero armor",
		int(kodo.armor_type_value()) == int(UnitStats.ArmorType.HERO), "")

	var altered: bool = kodo.status().alter_armor_type(
		_ability("Passives/war_stance"), int(UnitStats.ArmorType.LIGHT), 5.0)
	await _ticks(1)
	_check("a tower altering the type wins over the creep's own trait",
		altered && int(kodo.armor_type_value()) == int(UnitStats.ArmorType.LIGHT),
		str(int(kodo.armor_type_value())))


func _check_walks_through() -> void:
	var row: Array[Building] = []
	for index in range(4):
		var tower: Building = _place_tower("lesser_archer")
		if tower != null:
			row.append(tower)
	_check("a wall of towers went up", row.size() >= 3, str(row.size()))

	var walker: Creep = await _spawn("spirit_walker", Vector3.ZERO, false)
	var started: float = walker.global_position.z
	await _seconds(4.0)
	_check("an ethereal creep goes straight down the lane",
		absf(walker.global_position.z - started) > 1.0,
		"moved %.2f" % absf(walker.global_position.z - started))
	_check("and never took a route to do it", walker.ignores_maze(), "")


func _check_leak() -> void:
	var manager: PlayerManager = References.player_manager
	var victim: PlayerState = manager.state_for(1)
	var before: int = victim.lives
	# Owned by the OTHER player, walking this maze: a leak is a transfer and
	# a thief who is also the victim steals nothing.
	var boss: Creep = await _spawn("rot_golem", Vector3.ZERO, false, 2)
	boss.global_position = _exit_point()
	await _seconds(1.0)
	_check("a boss takes two lives when it leaks", victim.lives == before - 2,
		"%d -> %d" % [before, victim.lives])


func _check_population() -> void:
	var manager: PlayerManager = References.player_manager
	_check("nothing is standing yet", manager.population_for(1) == 0,
		str(manager.population_for(1)))
	await _spawn("skeleton_warrior")
	await _spawn("obsidian_statue", Vector3(0.4, 0.0, 0.0))
	await _spawn("demon", Vector3(0.8, 0.0, 0.0))
	await _ticks(1)
	_check("population is charged per creep, at each creep's own rate",
		manager.population_for(1) == 9, str(manager.population_for(1)))


func _check_sudden_death() -> void:
	var config: GameConfig = References.game_config
	var was: float = config.sudden_death_seconds
	var senders: Array[SendBuilding] = _area.send_buildings()
	_check("the area carries a sender per tier", senders.size() == 4,
		str(senders.size()))

	config.sudden_death_seconds = 1500.0
	_check("before it, tiers 1 to 3 are open and tier 4 is shut",
		senders[0].is_open() && senders[2].is_open() && !senders[3].is_open(), "")
	_check("and a tier 4 creep quotes the sudden death clock, not its own 0:00",
		senders[3].unlock_text(_creep_stats("huntress")) == "25:00",
		senders[3].unlock_text(_creep_stats("huntress")))
	_check("while a tier 3 creep still quotes its own start delay",
		senders[2].unlock_text(_creep_stats("behemoth")) == "19:30",
		senders[2].unlock_text(_creep_stats("behemoth")))

	config.sudden_death_seconds = 0.5
	await _seconds(1.0)
	_check("after it, tier 4 is the only one open",
		!senders[0].is_open() && !senders[2].is_open() && senders[3].is_open(), "")
	config.sudden_death_seconds = was


func _check_income_cap() -> void:
	var config: GameConfig = References.game_config
	var manager: PlayerManager = References.player_manager
	var state: PlayerState = manager.state_for(1)
	var sender: SendBuilding = _sender_for("treasure_goblin")
	if sender == null:
		_fail("income cap", "no sender carries the treasure goblin")
		return

	state.creeps_unlocked = true
	state.gain(10000000)
	state.add_income(-state.income)
	await _ticks(1)
	_check("a goblin can be sent under the cap",
		sender.can_send(_creep_stats("treasure_goblin")), "")

	state.add_income(config.income_cap)
	await _ticks(1)
	_check("and is refused outright above it",
		!sender.can_send(_creep_stats("treasure_goblin")),
		"income %d of %d" % [state.income, config.income_cap])
	_check("while an ordinary tier 4 creep still goes",
		sender.can_send(_creep_stats("huntress")), "")


# --- Helpers the second batch needs -------------------------------------

## One attack landing on a creep, from a tower reaching this far, through the
## real hit path - so what is exercised is AttackHit's own dodge roll.
func _strike(creep: Creep, damage: int, reach: float) -> void:
	var hit: AttackHit = AttackHit.new()
	hit.damage = damage
	hit.damage_type = DamageTable.DamageType.SPELL
	hit.area = _area
	hit.attack_range = reach
	hit.attacker_position = creep.global_position
	hit.resolve(creep, creep.global_position)


## Health a creep loses over a window, with it healed back afterwards so the
## reading can be taken twice on the same creep.
func _damage_over(creep: Creep, seconds: float) -> int:
	creep.heal(float(creep.max_health()))
	var before: float = creep.current_health
	await _seconds(seconds)
	var lost: int = int(round(before - creep.current_health))
	creep.heal(float(creep.max_health()))
	return lost


## A point on the end zone, for the one check that has to make a creep leak.
func _exit_point() -> Vector3:
	var bounds: Rect2 = _area.local_bounds()
	return _area.to_global(Vector3(bounds.size.x * 0.5, 0.0, bounds.size.y - 0.1))


## The sender whose card carries this creep.
func _sender_for(stem: String) -> SendBuilding:
	var wanted: CreepStats = _creep_stats(stem)
	for sender: SendBuilding in _area.send_buildings():
		if sender.stock_for(wanted) != null:
			return sender
	return null


# --- The displayed-values rework ----------------------------------------

## Every reach the game states, gathered off the resources themselves.
##
## A walk of the CONTENT rather than a list, so a reach authored tomorrow is
## checked without anybody adding it here. The names are the ones
## Tools round_cells knows; anything else on these resources is not a distance.
const REACH_FIELDS: Array[String] = [
	"attack_range", "radius", "radius_cells", "aura_cells", "reach_cells",
	"blast_cells", "bounce_cells", "cast_cells", "chain_cells", "beast_cells",
	"crowding_cells", "explosion_cells", "fork_cells", "from_range_cells",
	"heal_cells", "multishot_cells", "neighbour_cells", "orb_splash_cells",
	"overflow_cells", "paralyze_cells", "range_bonus_cells", "damage_radius_cells",
	"multishot_range_cells", "creep_aura_radius_cells",
]


func _check_quarter_reaches() -> void:
	var odd: PackedStringArray = PackedStringArray()
	var counted: int = 0
	for path in _content_paths():
		var res: Resource = load(path)
		if res == null:
			continue
		for field: String in REACH_FIELDS:
			if !(field in res):
				continue
			var value: float = float(res.get(field))
			counted += 1
			if !_is_quarter(value):
				odd.append("%s.%s=%s" % [path.get_file(), field, value])
		counted += _check_attack_reaches(res, odd)

	_check("every authored reach is a multiple of 0.25",
		odd.is_empty(), "%d checked, %s" % [counted,
			"all round" if odd.is_empty() else ", ".join(odd)])

	var speeds: PackedStringArray = PackedStringArray()
	for path in _files_under(CREEPS):
		var stats: CreepStats = load(path) as CreepStats
		if stats != null && !_is_quarter(stats.move_speed):
			speeds.append("%s=%s" % [stats.display_name, stats.move_speed])
	_check("and so is every creep's speed", speeds.is_empty(),
		"all round" if speeds.is_empty() else ", ".join(speeds))


## An attack hangs off a unit rather than being a resource of its own, so its
## range and its splash are reached through it.
func _check_attack_reaches(res: Resource, odd: PackedStringArray) -> int:
	if !("attack" in res):
		return 0
	var attack: AttackStats = res.get("attack") as AttackStats
	if attack == null:
		return 0

	var counted: int = 1
	if !_is_quarter(attack.attack_range):
		odd.append("%s attack_range=%s" % [res.get("display_name"), attack.attack_range])
	for effect: AttackEffect in attack.effects:
		if effect == null || !("radius" in effect):
			continue
		counted += 1
		if !_is_quarter(float(effect.get("radius"))):
			odd.append("%s splash=%s" % [res.get("display_name"), effect.get("radius")])
	return counted


func _check_no_cell_word() -> void:
	var offenders: PackedStringArray = PackedStringArray()
	var counted: int = 0
	for path in _content_paths():
		var res: Resource = load(path)
		if res == null || !res.has_method("tooltip_data"):
			continue
		var data: AbilityTooltipData = res.call("tooltip_data", "", null)
		if data == null:
			continue
		counted += 1
		var text: String = data.description
		for row: PackedStringArray in data.specials:
			text += " " + row[1]
		# "per cell" is the one place the word is a UNIT rather than a noun
		# beside a number, and taking it out leaves the sentence with none.
		text = text.replace("per cell of range", "")
		if text.to_lower().contains("cell"):
			offenders.append(str(res.get("display_name")))

	_check("no tooltip writes the word cell", offenders.is_empty(),
		"%d checked, %s" % [counted, "clean" if offenders.is_empty()
			else ", ".join(offenders)])


func _check_placeholders() -> void:
	var boss: Creep = await _spawn("rot_golem")
	var statue: Creep = await _spawn("obsidian_statue", Vector3(0.5, 0.0, 0.0))
	var boss_text: String = _card_text(boss, "Boss")
	var statue_text: String = _card_text(statue, "Power of the Destroyer")

	_check("a boss card names the lives its stats really steal",
		boss_text.contains("steals 2 lives") && !boss_text.contains("{"),
		boss_text)
	_check("and the statue names the population it really costs",
		statue_text.contains("takes up 3 of") && !statue_text.contains("{"),
		statue_text)

	# Nothing anywhere may still be carrying a raw placeholder into a tooltip.
	var raw: PackedStringArray = PackedStringArray()
	for path in _content_paths():
		var res: Resource = load(path)
		if res == null || !("description" in res):
			continue
		var text: String = str(res.get("description"))
		if text.contains("{") && !res.has_method("description_values"):
			raw.append(path.get_file())
	_check("and no ability writes a placeholder it cannot fill",
		raw.is_empty(), "clean" if raw.is_empty() else ", ".join(raw))


## What one entry on a live unit's own card actually reads.
func _card_text(unit: Unit, ability_name: String) -> String:
	for entry in unit.stats.abilities:
		var ability: UnitAbility = entry as UnitAbility
		if ability != null && ability.display_name == ability_name:
			return ability.tooltip_data("", unit).description
	return "<no %s on the card>" % ability_name


func _check_tier4_stock() -> void:
	var sender: SendBuilding = _area.send_buildings()[3]
	var over: PackedStringArray = PackedStringArray()
	for entry in sender.current_abilities():
		var send: SendCreepAbility = entry as SendCreepAbility
		if send == null || send.creep_stats == null:
			continue
		var stats: CreepStats = send.creep_stats
		var ceiling: int = 32
		if stats.lives_stolen > 1:
			ceiling = 8
		elif stats.is_flying || stats.refused_above_income_cap:
			ceiling = 16
		if stats.max_stock > ceiling:
			over.append("%s %d>%d" % [stats.display_name, stats.max_stock, ceiling])
	_check("no tier 4 reserve is over its ceiling", over.is_empty(),
		"clean" if over.is_empty() else ", ".join(over))


func _check_tier4_card() -> void:
	var wanted: Dictionary = {
		"Huntress": 0, "Obsidian Statue": 1, "Mountain Giant": 2,
		"Harpy Windwitch": 3, "Naga Siren": 4, "Kodo Beast": 5,
		"Goblin Shredder": 6, "Frost Wyrm": 7, "Phoenix": 8, "Demon": 9,
		"Treasure Goblin": 11,
	}
	var wrong: PackedStringArray = PackedStringArray()
	for entry in _area.send_buildings()[3].current_abilities():
		var send: SendCreepAbility = entry as SendCreepAbility
		if send == null:
			continue
		var expected: int = int(wanted.get(send.display_name, -1))
		if send.card_slot() != expected:
			wrong.append("%s at %d" % [send.display_name, send.card_slot()])
	_check("every tier 4 creep sits on the square it should",
		wrong.is_empty(), "clean" if wrong.is_empty() else ", ".join(wrong))

	# The bottom right square is the one the letter rows spell V, and it is
	# where the Treasure Goblin was asked to live.
	# Loaded rather than taken off References: a SERVER match wires no input
	# config at all, and the card letters are a rule of the game rather than
	# something that match happens to be holding.
	var config: ControlsConfig = load(
		"res://Resources/Config/controls_config.tres") as ControlsConfig
	var rows: PackedStringArray = PackedStringArray() if config == null \
		else config.command_hotkey_rows
	var last: String = "" if rows.is_empty() else rows[rows.size() - 1]
	_check("and that square is the one spelled V",
		last.length() >= 4 && last[3].to_upper() == "V", last)


func _is_quarter(value: float) -> bool:
	return absf(value / 0.25 - round(value / 0.25)) < 0.001


## Every ability and unit resource in the build, which is what both sweeps walk.
func _content_paths() -> Array[String]:
	var paths: Array[String] = _files_under(ABILITIES)
	paths.append_array(_files_under("res://Resources/UnitStats"))
	return paths


## Every .tres under a folder, recursively. The content sweeps above walk the
## FOLDERS rather than a list, so a reach or a description authored tomorrow is
## checked without anybody adding it here.
func _files_under(folder: String) -> Array[String]:
	var found: Array[String] = []
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var full: String = folder.path_join(entry)
		if dir.current_is_dir():
			found.append_array(_files_under(full))
		elif entry.ends_with(".tres"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	found.sort()
	return found


## The source rule is "900 or more attack range", and the towers it means are
## the ones at exactly 900. Before every reach was snapped to a quarter those
## sat at 7.03 against a 7.031 threshold and were never dodged at all - the
## rule was real and fired on nothing. This is that pinned down.
func _check_dodge_threshold() -> void:
	var huntress: Creep = await _spawn("huntress")
	var tower: Building = _place_tower("arcane_sorcerer")
	var reach: float = tower.stats.attack.attack_range
	_check("the 900 range towers are stated as 7", is_equal_approx(reach, 7.0),
		"%s" % reach)
	_check("and a huntress dodges them",
		huntress.dodge_chance_against(reach) > 0.0,
		"%.2f at %s" % [huntress.dodge_chance_against(reach), reach])
	_check("while anything shorter still lands every shot",
		is_zero_approx(huntress.dodge_chance_against(reach - 0.25)),
		"%.2f at %s" % [huntress.dodge_chance_against(reach - 0.25), reach - 0.25])
