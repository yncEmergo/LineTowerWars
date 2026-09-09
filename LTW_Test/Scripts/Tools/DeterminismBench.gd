class_name DeterminismBench
extends Node

## Proves - or disproves - that the simulation is deterministic, by running the
## same match twice and comparing what the world looked like along the way.
##
## **Why this has to exist before lockstep.** Under lockstep every peer runs the
## whole simulation and the only thing crossing the wire is player input, so a
## single divergence anywhere compounds forever and the match is dead. A desync
## reported from a real game is close to undebuggable: nobody can say which tick
## it started on, and nothing reproduces it. This turns that into a number.
##
## **What it actually tests, stated plainly.** Two runs of the SAME BINARY on
## the SAME MACHINE from the same seed. That catches the whole family of
## iteration-order and unseeded-randomness bugs, which is what the determinism
## inventory taken before the cutover went looking for. It does NOT catch
## cross-machine float divergence, because there is only one machine here - that
## needs two boxes running `replay=` against the same trace, which this supports
## and which is the next step up.
##
## Three modes, one scene:
##
##     out=user://a.json seed=1 ticks=400  ->  run and write a trace
##     replay=<trace>                      ->  run again, feeding the RECORDED
##                                             commands rather than generating
##                                             them, and write a second trace
##     compare=<a>,<b>                     ->  report the first differing tick
##
## `perturb=<tick>` deliberately corrupts the world on that tick, which is how
## the harness is shown to FAIL when it should. A harness nobody has watched
## fail is not evidence.
##
## KEPT, not scaffolding - which is why it sits in `Scripts/Tools` beside
## `PerfBench` rather than in `Scripts/Dev`, the folder that gets deleted. It is
## run again every time the simulation grows something new, on the same footing
## as the performance bench: a determinism claim goes stale the moment somebody
## adds a feature, so the tool that checks it has to outlive the migration.

const MATCH_SCENE: String = "res://Scenes/Server/server_match.tscn"

## How the world is sampled: cheap enough to take often, since the whole value
## of the trace is LOCATING a divergence rather than merely noticing one.
const DEFAULT_EVERY: int = 10

var _seed: int = 1
var _players: int = 2
var _ticks: int = 400
var _every: int = DEFAULT_EVERY
var _out: String = "user://determinism_a.json"
var _replay_path: String = ""
var _compare: String = ""
var _perturb: int = -1

var _tick: int = 0
var _started: bool = false
var _setup: MatchSetup = null
var _areas: Array[PlayerArea] = []
var _samples: Array = []
var _recorded: Array = []
var _replay_by_tick: Dictionary = {}
var _sent_this_run: int = 0
var _rejected: int = 0

## Class names whose every instance has its physics processing switched off, from
## `skip=Creep,Projectile`. **This is the falsifier's own falsifier.**
##
## A trace is only evidence about a refactor if it would MOVE when a gameplay
## loop stops running. At one fixed tick rate a loop left on `_physics_process`
## and a loop moved onto an explicit stepper both run once per tick, so a
## byte-identical trace is equally consistent with a correct refactor, a refactor
## that missed ten loops, and no refactor at all. The only way to know which is
## to break each loop on purpose and watch the trace go red.
##
## Any loop whose omission leaves the trace unchanged is a HOLE IN THE HASH, not
## a loop that does not matter. See `netcode-rework.md` 13.2.
var _skip: Dictionary = {}
var _skipped_nodes: int = 0

## Every private field `_deep_hash` reaches through `get()`, and whether it has
## ever resolved on a real instance.
##
## **Reading a private field by name is how this hash covers accumulators that no
## public accessor exposes, and it fails SILENTLY if one is ever renamed** - a
## missing property answers `null`, hashes identically on every run, and the
## trace stays green while covering nothing. That is precisely the failure this
## whole section exists to remove, so the coverage is asserted rather than
## assumed: anything still false at the end is reported as UNCOVERED.
##
## Accessors were the alternative and were rejected: `Building`, `Creep` and
## `StatusEffects` are all already over gdlint's public-method ceiling, and a
## harness should not push shipping classes further over it to see itself work.
var _probed: Dictionary = {}
var _declared: Dictionary = {}
var _seen_class: Dictionary = {}

## Seeded from the match seed so the driver is reproducible, but kept SEPARATE
## from the simulation's own stream - see _send_from.
var _driver_rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_read_arguments()

	if !_compare.is_empty():
		_run_compare()
		return

	if !_replay_path.is_empty():
		_load_replay(_replay_path)

	_start_match()


# --- arguments ------------------------------------------------------------

func _read_arguments() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = argument.split("=", true, 1)
		if pair.size() == 2:
			_apply_argument(pair[0].strip_edges(), pair[1].strip_edges())


func _apply_argument(key: String, value: String) -> void:
	match key:
		"seed":
			_seed = int(value)
		"players":
			_players = maxi(1, int(value))
		"ticks":
			_ticks = maxi(1, int(value))
		"every":
			_every = maxi(1, int(value))
		"out":
			_out = value
		"replay":
			_replay_path = value
		"compare":
			_compare = value
		"perturb":
			_perturb = int(value)
		"rate":
			# **The two-rate falsifier, and the only test that can see the delta
			# refactor at all.** At one fixed rate a loop reading the engine
			# delta and a loop reading the simulation step get the same number,
			# so no trace can tell them apart. Run the same match at 20 Hz and at
			# 30 Hz: after the refactor the traces must be IDENTICAL, because a
			# simulation second stopped depending on how fast the machine runs.
			# Before it they differ on the first moving creep.
			Engine.physics_ticks_per_second = maxi(1, int(value))
		"skip":
			# **The sabotage matrix.** See _apply_skips.
			for name: String in value.split(",", false):
				_skip[name.strip_edges()] = true
		_:
			push_warning("DeterminismBench ignored an argument: " + key)


# --- running a match ------------------------------------------------------

func _start_match() -> void:
	var packed: PackedScene = load(MATCH_SCENE) as PackedScene
	if packed == null:
		push_error("DeterminismBench could not load " + MATCH_SCENE)
		_quit()
		return

	_setup = MatchSetup.new()
	for slot: int in range(1, _players + 1):
		_setup.players.append(MatchPlayer.create(slot, "Det %d" % slot))
	_setup.local_slot = 1
	_setup.rng_seed = _seed
	_driver_rng.seed = _seed
	MenuNavigation.pending_match = _setup

	add_child(packed.instantiate())

	# Every command the authority accepts, which IS the input stream a replay
	# has to reproduce. Connected rather than hooked into CommandService, so
	# nothing in the shipping path knows this file exists.
	if Commands != null:
		Commands.command_applied.connect(_on_command_applied)
		Commands.command_rejected.connect(_on_command_rejected)

	_started = true


func _collect_areas() -> void:
	var manager: PlayerManager = References.player_manager
	if manager == null:
		return
	_areas.clear()
	for slot: int in range(1, _players + 1):
		var area: PlayerArea = manager.area_for(slot)
		if area != null:
			_areas.append(area)


func _physics_process(_delta: float) -> void:
	if !_started:
		return

	if _areas.is_empty():
		_collect_areas()
		if _areas.is_empty():
			return

	_drive_tick()

	if _tick == _perturb:
		_apply_perturbation()

	if _tick % _every == 0:
		_sample()

	_tick += 1
	if _tick > _ticks:
		_finish()


## What makes the two runs worth comparing: a world that just sits there proves
## nothing, so the match is driven hard enough to exercise spawning, pathing,
## targeting and damage.
##
## The stream is derived from the SEED rather than from the wall clock, so a
## second run generates the identical stream without needing the trace - which
## is what lets `record` twice be a valid test on its own.
func _drive_tick() -> void:
	_apply_skips()
	if !_replay_by_tick.is_empty():
		_replay_tick()
		return

	# Two cheats first, and they are not a shortcut past the thing being tested:
	# they travel the same Commands road every other order does, and without
	# them a fresh match has 40 gold and every creep still behind its unlock
	# delay, so nothing sends and the world barely moves. Re-issued on a slow
	# beat so the driver never stalls on an empty purse.
	if _tick % 40 == 2:
		for area: PlayerArea in _areas:
			_cheat(Command.PlayerAction.CHEAT_GOLD, area.player_id)
			_cheat(Command.PlayerAction.CHEAT_UNLOCK_CREEPS, area.player_id)
		return

	# **One tower each, because without it half the simulation never exists.**
	# The driver used to send creeps and nothing else, so no `Building` was ever
	# constructed, nothing ever fired, and no projectile was ever spawned - and a
	# sabotage run naming either of those disabled zero nodes and came back
	# green, which reads exactly like a hash that covers them. See 13.2.
	# **Early, because a tower takes about thirteen seconds to finish building**
	# and only shoots after that. Ordered late in a short run it is still
	# scaffolding when the trace ends, and the projectile road is never
	# exercised - which is exactly how `skip=Projectile` came back NOT TESTED.
	# **Two DIFFERENT towers, because one is not enough to cover both loops.**
	# The status-preferring sort picks a tower whose attack applies a chill, and
	# that tower turned out not to fire a projectile - so `skip=Projectile`
	# disabled zero nodes and came back NOT TESTED the moment the sort changed.
	# The second build takes the next choice down, so a projectile tower exists
	# whatever the first one is.
	if _tick == 8:
		for area: PlayerArea in _areas:
			_build_from(area, 0)
		return
	if _tick == 20:
		# **The SAME tower again, not the next one down.** Building a second,
		# different tower was tried and the second placement does not take -
		# so the area ends up with one tower rather than two, its rate of fire
		# halves, and no projectile exists at a tick boundary for the sabotage
		# walk to find. Two of the same is what actually keeps the projectile
		# road busy.
		for area: PlayerArea in _areas:
			_build_from(area, 0)
		return

	# **Then upgrade it, which is the only road to an ELEMENT.** A basic tower
	# carries no element and therefore no status-applying passive, so a driver
	# that only builds leaves `Creep._status` null for the whole run and the
	# `StatusEffects` timers hashed but never proven. It also exercises the
	# upgrade clock, which 13.2 wants and nothing else reaches.
	if _tick == 300 || _tick == 420:
		for area: PlayerArea in _areas:
			_upgrade_in(area)
		return

	# Every player holds the send key, which is the heaviest ordinary load the
	# game produces and the one the stutter was reported in.
	if _tick < 6 || _tick % 4 != 0:
		return
	for area: PlayerArea in _areas:
		_send_from(area)


## Orders one finished tower upgraded, preferring an upgrade that leads to a
## tower which applies a status.
func _upgrade_in(area: PlayerArea) -> void:
	var session: MatchSession = References.match_session
	if session == null:
		return
	for id: Variant in session.unit_ids():
		var unit: Unit = session.unit_for(int(id))
		if !(unit is Building) || unit.owner_player_id != area.player_id:
			continue
		if unit.stats == null:
			continue
		# **`upgrading_abilities` is the CANCEL button shown while an upgrade
		# runs, not the list of upgrades.** The upgrade itself sits in
		# `abilities` beside the attack and the sell, which is why reading the
		# obvious field found nothing and reported it as nothing to upgrade.
		var choices: Array = []
		for entry: Variant in unit.stats.abilities:
			var ability: UnitAbility = entry as UnitAbility
			if ability == null:
				continue
			if _tower_of(ability) != null:
				choices.append(ability)
			else:
				choices.append_array(ability.submenu_abilities())
		choices.sort_custom(func(a: Variant, b: Variant) -> bool:
			return _applies_status(a) && !_applies_status(b))
		for entry: Variant in choices:
			var ability: UnitAbility = entry as UnitAbility
			if ability == null || _tower_of(ability) == null:
				continue
			var command: Command = Command.create(
				ability.ability_id, [unit], AbilityTarget.none(), false
			)
			command.tick = _tick
			command.player_slot = area.player_id
			Commands.call("_queue", command)
			_sent_this_run += 1
			return


## The tower an ability would produce, whether it BUILDS one or UPGRADES into
## one. Asked by property rather than by class, because the two are different
## subclasses that both carry `tower_stats`.
static func _tower_of(ability: UnitAbility) -> Resource:
	if ability == null:
		return null
	return ability.get("tower_stats") as Resource


## Whether this tower carries a passive that puts a status on what it hits.
##
## Asked by PROPERTY rather than by class name: a passive exposing `slow_per_hit`
## or `stun_seconds` is one that reaches `StatusEffects`, and that stays true for
## a passive nobody has written yet.
func _applies_status(ability: Variant) -> bool:
	var stats: Resource = _tower_of(ability as UnitAbility)
	if stats == null:
		return false
	for entry: Variant in stats.get("abilities"):
		var passive: TowerPassive = entry as TowerPassive
		if passive == null:
			continue
		for property: Dictionary in passive.get_property_list():
			var name: String = String(property.get("name", ""))
			if name == "slow_per_hit" || name == "stun_seconds":
				return true
	return false


## Orders one tower built, from whichever unit in this area owns a
## `BuildTowerAbility`.
##
## Found by ABILITY rather than by class, so it does not care whether the
## builder is a `Builder`, and it travels the same `Commands` road every other
## order does - the ability's own rules refuse an illegal cell, which is the
## point: a driver that bypassed them would be testing a world the game cannot
## reach.
func _build_from(area: PlayerArea, choice: int) -> void:
	var session: MatchSession = References.match_session
	if session == null:
		return
	for id: Variant in session.unit_ids():
		var unit: Unit = session.unit_for(int(id))
		if unit == null || unit.owner_player_id != area.player_id || unit.stats == null:
			continue
		# **One level down, because a builder's card carries the build MENU and
		# the towers hang off it.** Looking only at the top level found nothing
		# and reported it as nothing to build, which is the same shape as the
		# send driver refusing submenus - see `_send_from`.
		var offered: Array = []
		for entry: Variant in unit.stats.abilities:
			var ability: UnitAbility = entry as UnitAbility
			if ability == null:
				continue
			if _tower_of(ability) != null:
				offered.append(ability)
			else:
				offered.append_array(ability.submenu_abilities())

		# **A tower that applies a STATUS if one is offered.** `StatusEffects` is
		# ticked by `Creep`, so its loop is already covered by `skip=Creep` - but
		# `_status` is built lazily and stays null until something chills or
		# stuns, so a driver that only ever fires plain damage leaves those
		# timers hashed and unproven. Preferring a frost or stunning tower is
		# what turns that from coverage into evidence.
		# **No status-preferring sort here, and that is a decision rather than an
		# omission.** Ordering the buildable list to favour a chilling tower was
		# tried, to make `Creep._status` resolve; the upgrades it needed were
		# never applied, so it did not, and the tower it did pick fires no
		# projectile - which silently cost `skip=Projectile` its red row. A
		# driver tuned toward one uncovered loop must not uncover another.

		var picked: int = 0
		for entry: Variant in offered:
			var build: UnitAbility = entry as UnitAbility
			if build == null || _tower_of(build) == null:
				continue
			if picked < choice:
				picked += 1
				continue
			var row: int = area.build_zone_first_row()
			var column: int = _driver_rng.randi_range(2, 8)
			var where: Vector3 = area.internal_cell_center(Vector2i(column, row))
			var command: Command = Command.create(
				build.ability_id, [unit], AbilityTarget.at_position(where), false
			)
			command.tick = _tick
			command.player_slot = area.player_id
			Commands.call("_queue", command)
			_sent_this_run += 1
			return


func _cheat(action: Command.PlayerAction, slot: int) -> void:
	var command: Command = Command.create_player_action(action)
	command.tick = _tick
	command.player_slot = slot
	Commands.call("_queue", command)
	_sent_this_run += 1


func _send_from(area: PlayerArea) -> void:
	var buildings: Array = area.send_buildings()
	if buildings.is_empty():
		return
	var building: SendBuilding = buildings[0] as SendBuilding
	if building == null || building.stats == null:
		return

	# The SEND abilities only. The card also carries submenus and settings, and
	# ordering one of those is a no-op that would quietly make the driver do
	# nothing while still looking busy.
	var abilities: Array = []
	for entry: Variant in building.stats.abilities:
		if entry is SendCreepAbility:
			abilities.append(entry)
	if abilities.is_empty():
		return

	# The DRIVER's own generator, never MatchSession.match_rng().
	#
	# This is not a style preference, it is the difference between the harness
	# working and lying. A real player's choice of creep is not drawn from the
	# match RNG, and if the driver draws from it then RECORD and REPLAY consume
	# different numbers of rolls - replay does not generate, so it does not draw
	# - and every gameplay roll afterwards is handed a different number. The
	# replay would then diverge from the recording for a reason that is entirely
	# the test's own fault, which is the worst possible failure for a tool whose
	# only job is to say whether a divergence is real.
	var index: int = _driver_rng.randi_range(0, abilities.size() - 1)
	var ability: UnitAbility = abilities[index] as UnitAbility
	if ability == null:
		return

	var command: Command = Command.create(
		ability.ability_id, [building], null, false
	)
	command.tick = _tick
	command.player_slot = area.player_id

	Commands.call("_queue", command)
	_sent_this_run += 1


func _replay_tick() -> void:
	var entries: Variant = _replay_by_tick.get(_tick)
	if entries == null:
		return
	for entry: Variant in entries as Array:
		var command: Command = Command.from_dict(_from_json_safe(entry as Dictionary))
		if command == null:
			push_error("DeterminismBench could not rebuild a command from the trace")
			continue
		Commands.call("_queue", command)
		_sent_this_run += 1


## Rejections are counted rather than printed one by one: a driver holding the
## send key produces the same refusal hundreds of times, and the first few say
## everything the rest would.
func _on_command_rejected(command: Command, reason: String) -> void:
	_rejected += 1
	if _rejected <= 3:
		print("DET rejected (ability=%d slot=%d units=%d): %s" % [
			command.ability_id, command.player_slot, command.unit_ids.size(), reason,
		])


func _on_command_applied(command: Command) -> void:
	if command == null:
		return
	var data: Dictionary = command.to_dict()
	data["tick"] = command.tick
	_recorded.append(_to_json_safe(data))


## `Command.to_dict()` is the WIRE format, and it is right for the wire: Godot
## encodes a Vector3 as twelve bytes and a PackedInt32Array as itself. JSON can
## do neither - it turns the vector into the STRING "(0, 0, 0)" and the packed
## array into floats - and `from_dict` then reads a String where it wants a
## Vector3 and hands back something unusable.
##
## Cost an hour: the replay ran, reported no error, injected nothing, and looked
## exactly like a determinism failure at the first sampled tick. The trace is a
## FILE format and needs its own encoding; it is not the wire and should not
## pretend to be.
static func _to_json_safe(data: Dictionary) -> Dictionary:
	var out: Dictionary = data.duplicate()
	var at: Variant = data.get("at", Vector3.ZERO)
	if at is Vector3:
		out["at"] = [(at as Vector3).x, (at as Vector3).y, (at as Vector3).z]
	var units: Array = []
	for id: int in PackedInt32Array(data.get("units", PackedInt32Array())):
		units.append(id)
	out["units"] = units
	return out


static func _from_json_safe(data: Dictionary) -> Dictionary:
	var out: Dictionary = data.duplicate()
	var at: Variant = data.get("at", null)
	if at is Array && (at as Array).size() == 3:
		var parts: Array = at as Array
		out["at"] = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	else:
		out["at"] = Vector3.ZERO
	var units: PackedInt32Array = PackedInt32Array()
	for id: Variant in data.get("units", []) as Array:
		units.append(int(id))
	out["units"] = units
	return out


# --- sampling -------------------------------------------------------------

## Two numbers per sample, on purpose.
##
## `world` is `WorldChecksum.of(...)`, which is what the game ALREADY computes
## and compares at match start - so a divergence it sees is a divergence the
## shipping code would also see.
##
## `deep` is this harness's own, and it exists because `WorldChecksum` covers
## identity and POSITION but not health, gold, lives or mana. A desync that
## moved only a creep's health would be invisible to the first number and is
## caught by the second. **`WorldChecksum` was deliberately not widened**: it is
## shipping code with a shipping cost, and whether it should carry more is a
## design question rather than something a test harness gets to decide.
## Switches off the physics processing of every node of a named class, every
## tick, so that a class spawned later is caught too.
##
## `set_physics_process(false)` rather than freeing anything: the world keeps its
## shape, the unit registry keeps its entries, and the only thing that changes is
## that one loop stops advancing. That is exactly the mistake a refactor makes.
func _apply_skips() -> void:
	if _skip.is_empty():
		return
	var session: MatchSession = References.match_session
	if session != null:
		for id: Variant in session.unit_ids():
			var unit: Unit = session.unit_for(int(id))
			if unit != null:
				_skip_node(unit)
				if unit.attack_component != null:
					_skip_node(unit.attack_component)
	for root: Node3D in [References.projectiles_root, References.effects_root]:
		if root != null:
			for child: Node in root.get_children():
				_skip_node(child)


func _skip_node(node: Node) -> void:
	if node == null || !_matches_skip(node):
		return
	if node.is_physics_processing():
		node.set_physics_process(false)
		_skipped_nodes += 1


## **The whole inheritance chain, not just the leaf class.** `Building` declares
## the loop and `SendBuilding` inherits it, so a matrix entry naming the class
## that OWNS the loop has to reach the subclasses that run it - otherwise
## `skip=Building` leaves every send building ticking and the entry reads green
## for a reason that has nothing to do with the hash.
func _matches_skip(node: Node) -> bool:
	if _skip.has(node.get_class()):
		return true
	var script: Script = node.get_script() as Script
	while script != null:
		if _skip.has(script.get_global_name()):
			return true
		script = script.get_base_script()
	return false


static func _script_name(node: Node) -> String:
	var script: Script = node.get_script() as Script
	return "" if script == null else String(script.get_global_name())


## Reads a private field by name and records that it resolved.
## **Three outcomes, not two, and conflating the last two cries wolf.** A property
## that does not exist and a property that is legitimately null both answer
## `null` to `get()`, so the property list is asked once per class to tell them
## apart:
##
##   MISSING  - renamed or deleted. The hash covers nothing and looks green.
##              This is the failure the whole probe exists to catch.
##   NEVER SET - the field exists and was null on every instance the run saw.
##              A gap in the DRIVER, not in the hash: something was never made to
##              happen. `Creep._status` is lazily built and stays null until a
##              creep is actually chilled or stunned.
##   resolved - covered.
func _probe(node: Object, owner_name: String, field: String) -> Variant:
	var key: String = "%s.%s" % [owner_name, field]
	_seen_class[owner_name] = int(_seen_class.get(owner_name, 0)) + 1
	if !_declared.has(key):
		var found: bool = false
		for entry: Dictionary in node.get_property_list():
			if String(entry.get("name", "")) == field:
				found = true
				break
		_declared[key] = found
	var value: Variant = node.get(field)
	if value != null:
		_probed[key] = true
	elif !_probed.has(key):
		_probed[key] = false
	return value


## Records whether each named field exists on a class, without needing the run to
## have produced an instance of it.
func _verify_class(sample: Object, owner_name: String, fields: PackedStringArray) -> void:
	if sample == null:
		return
	var present: Dictionary = {}
	for entry: Dictionary in sample.get_property_list():
		present[String(entry.get("name", ""))] = true
	for field: String in fields:
		var key: String = "%s.%s" % [owner_name, field]
		_declared[key] = present.has(field)
		if !_probed.has(key):
			_probed[key] = false


func _sample() -> void:
	var session: MatchSession = References.match_session
	_samples.append({
		"tick": _tick,
		"world": WorldChecksum.of(_setup, _areas, session),
		"deep": _deep_hash(session),
	})


func _deep_hash(session: MatchSession) -> int:
	var parts: PackedStringArray = PackedStringArray()

	if session != null:
		for id: Variant in session.unit_ids():
			var unit: Unit = session.unit_for(int(id))
			if unit == null:
				parts.append("u%d:gone" % id)
				continue
			# Health is a float and is quantised for the same reason a position
			# is: two machines that agree to a thousandth agree, and hashing
			# raw bit patterns would call that a desync.
			parts.append("u%d:%d/%d:%s" % [
				id,
				roundi(unit.current_health * WorldChecksum.SCALE),
				unit.max_health(),
				_point(unit.global_position),
			])
			parts.append(_unit_extras(unit))

	var manager: PlayerManager = References.player_manager
	if manager != null:
		for slot: int in range(1, _players + 1):
			var state: PlayerState = manager.state_for(slot)
			if state == null:
				parts.append("s%d:none" % slot)
				continue
			parts.append("s%d:%d/%d/%d" % [slot, state.gold, state.income, state.lives])

	parts.append(_effects_hash())
	parts.append(_area_extras())
	return "|".join(parts).hash()


## The per-unit accumulators nothing else hashes.
##
## `WorldChecksum` was deliberately NOT widened for these - its docstring says
## why: it is shipping code with a shipping cost, and what it covers is a design
## question rather than something a harness decides. This is the harness, so it
## pays what it likes.
func _unit_extras(unit: Unit) -> String:
	var bits: PackedStringArray = PackedStringArray()

	var attack: AttackComponent = unit.attack_component
	if attack != null:
		# **Building.checksum_state records only the active ability's cooldown**,
		# so a missed attack step shows up later and indirectly, as creep health
		# drifting - which names the wrong tick and the wrong system.
		bits.append("atk:%d/%d/%d" % [
			_q(_probe(attack, "AttackComponent", "_cooldown")),
			_q(_probe(attack, "AttackComponent", "_windup_left")),
			int(_probe(attack, "AttackComponent", "_scan_wait")),
		])

	if unit is Creep:
		# `_stall_elapsed` crossing its threshold RE-PLANS A PATH, which makes it
		# the highest-consequence unhashed float in the file.
		bits.append("crp:%d/%d" % [
			_q(_probe(unit, "Creep", "_stall_elapsed")),
			_q(_probe(unit, "Creep", "_march_elapsed")),
		])
		var status: Object = _probe(unit, "Creep", "_status")
		if status != null:
			bits.append("st:%d/%d/%d/%d" % [
				_q(_probe(status, "StatusEffects", "_stun_left")),
				_q(_probe(status, "StatusEffects", "_paralyze_left")),
				_q(_probe(status, "StatusEffects", "_armor_eroded")),
				_q(_probe(status, "StatusEffects", "_armor_delta")),
			])

	if unit is Building:
		bits.append("bld:%d/%d" % [
			_q(_probe(unit, "Building", "_upgrade_elapsed")),
			_q(_probe(unit, "Building", "_sell_elapsed")),
		])

	if unit is SendBuilding:
		# **SendBuilding overrides checksum_state at all**, so every CreepStock
		# reserve timer is unhashed today. A missed send step stops sends
		# mid-match and no trace says so.
		# `stock_entries()` answers [unit_type_id, count] pairs for the snapshot -
		# the COUNT, which is already hashed, and not the regeneration clock that
		# moves it. The clocks are the CreepStock objects themselves.
		#
		# **Walked in unit_type_id order rather than Dictionary order**, which is
		# not something two machines may be trusted to agree on - the same rule
		# `commands_for` sorts by peer for.
		var stocks: Variant = _probe(unit, "SendBuilding", "_stocks")
		if stocks != null:
			var by_id: Array = []
			for key: Variant in (stocks as Dictionary):
				var stats: CreepStats = key as CreepStats
				if stats != null:
					by_id.append([stats.unit_type_id, (stocks as Dictionary)[key]])
			by_id.sort_custom(func(a: Array, b: Array) -> bool:
				return int(a[0]) < int(b[0]))
			for pair: Array in by_id:
				var stock: Object = pair[1] as Object
				if stock == null:
					continue
				bits.append("stk%d:%d/%s" % [
					int(pair[0]),
					_q(_probe(stock, "CreepStock", "_elapsed")),
					str(_probe(stock, "CreepStock", "_unlocked")),
				])

	return ",".join(bits)


## Projectiles, piercing projectiles, beast charges and ground hazards.
##
## **Four damage-dealing loops that sit outside the falsifier entirely.** All
## four extend `VisualEffect3D`, none is a registered `Unit`, so
## `session.unit_ids()` has never seen one - and all four deal damage on a
## delta-driven schedule.
func _effects_hash() -> String:
	# BOTH roots: projectiles, pierces and burning ground go to
	# `projectiles_root`, while `AttackDelivery` puts its own effects on
	# `effects_root`. Hashing one of the two would leave the other invisible.
	var bits: PackedStringArray = PackedStringArray()
	for root: Node3D in [References.projectiles_root, References.effects_root]:
		if root == null:
			continue
		for child: Node in root.get_children():
			var node: Node3D = child as Node3D
			if node == null:
				continue
			bits.append("%s@%s" % [_script_name(node), _point(node.global_position)])
	return "fx:%d:%s" % [bits.size(), ",".join(bits)]


## Rubble, which decides whether a rebuild is legal, is not replicated by design,
## and is in no checksum anywhere.
func _area_extras() -> String:
	var bits: PackedStringArray = PackedStringArray()
	for area: PlayerArea in _areas:
		var rubble: Variant = _probe(area, "PlayerArea", "_rubble")
		if rubble == null:
			continue
		var cells: Array = (rubble as Dictionary).keys()
		cells.sort()
		var each: PackedStringArray = PackedStringArray()
		for cell: Variant in cells:
			each.append("%s:%d" % [cell, _q((rubble as Dictionary)[cell])])
		bits.append("rb%d:%s" % [area.player_id, ",".join(each)])
	return "|".join(bits)


## A float, quantised the way every other float in this file is: two machines
## that agree to a thousandth agree, and hashing raw bit patterns would call
## that a desync.
static func _q(value: Variant) -> int:
	return 0 if value == null else roundi(float(value) * WorldChecksum.SCALE)


static func _point(position: Vector3) -> String:
	return "%d,%d,%d" % [
		roundi(position.x * WorldChecksum.SCALE),
		roundi(position.y * WorldChecksum.SCALE),
		roundi(position.z * WorldChecksum.SCALE),
	]


## Moves one creep by a millimetre. The point is to prove the harness REPORTS a
## divergence at the right tick - a checker that has only ever been seen to pass
## is not evidence that it can fail.
func _apply_perturbation() -> void:
	for area: PlayerArea in _areas:
		var creeps: Array = area.creeps()
		if creeps.is_empty():
			continue
		var creep: Creep = creeps[0] as Creep
		if creep == null:
			continue
		creep.global_position += Vector3(0.001, 0.0, 0.0)
		print("DET perturbed a creep at tick %d" % _tick)
		return
	print("DET perturb at tick %d found no creep to move" % _tick)


# --- output ---------------------------------------------------------------

func _finish() -> void:
	var trace: Dictionary = {
		"seed": _seed,
		"players": _players,
		"ticks": _ticks,
		"every": _every,
		"mode": "replay" if !_replay_path.is_empty() else "record",
		"commands_sent": _sent_this_run,
		"commands_applied": _recorded.size(),
		"samples": _samples,
		"commands": _recorded,
	}

	var file: FileAccess = FileAccess.open(_out, FileAccess.WRITE)
	if file == null:
		push_error("DeterminismBench could not write " + _out)
	else:
		file.store_string(JSON.stringify(trace, "  "))
		file.close()

	print("DET wrote %s" % _out)
	print("DET seed=%d players=%d ticks=%d every=%d" % [
		_seed, _players, _ticks, _every,
	])
	print("DET commands sent=%d applied=%d rejected=%d samples=%d" % [
		_sent_this_run, _recorded.size(), _rejected, _samples.size(),
	])

	# **The positive control for the hash itself.** A field that never resolved
	# hashed as zero on every sample and covered nothing, which looks exactly
	# like a field that was simply always zero.
	# **A field on an object that is never built is never probed at all**, so it
	# would not even be reported as MISSING - the probe only sees what the run
	# happens to construct. `StatusEffects` is built lazily on the first creep to
	# be chilled or stunned, so a run where nothing lands a slow leaves its
	# timers both unexercised AND unverified, which is the worse half.
	#
	# Checked against a fresh instance instead, which needs no creep. This closes
	# the rename risk; the "never exercised" half is reported separately and
	# honestly.
	_verify_class(StatusEffects.new(null), "StatusEffects",
		["_stun_left", "_paralyze_left", "_armor_eroded", "_armor_delta"])

	var missing: PackedStringArray = PackedStringArray()
	var never_set: PackedStringArray = PackedStringArray()
	for key: Variant in _probed:
		if bool(_probed[key]):
			continue
		if bool(_declared.get(key, false)):
			never_set.append(str(key))
		else:
			missing.append(str(key))
	missing.sort()
	never_set.sort()
	var seen: PackedStringArray = PackedStringArray()
	var names: Array = _seen_class.keys()
	names.sort()
	for name: Variant in names:
		seen.append("%s=%d" % [name, int(_seen_class[name])])
	print("DET probed %s" % " ".join(seen))
	if missing.is_empty() && never_set.is_empty():
		print("DET coverage OK, every probed field resolved")
	if !missing.is_empty():
		print("DET MISSING FIELDS (renamed? the hash covers nothing here) %s"
			% " ".join(missing))
	if !never_set.is_empty():
		print("DET never set (the driver never made it happen) %s"
			% " ".join(never_set))
	if !_skip.is_empty():
		print("DET skipped=%s nodes_disabled=%d" % [
			" ".join(PackedStringArray(_skip.keys())), _skipped_nodes,
		])
	_quit()


func _load_replay(path: String) -> void:
	var trace: Dictionary = _read_trace(path)
	if trace.is_empty():
		return
	_seed = int(trace.get("seed", _seed))
	_players = int(trace.get("players", _players))
	for entry: Variant in trace.get("commands", []) as Array:
		var data: Dictionary = entry as Dictionary
		var tick: int = int(data.get("tick", 0))
		if !_replay_by_tick.has(tick):
			_replay_by_tick[tick] = []
		(_replay_by_tick[tick] as Array).append(data)
	print("DET replaying %d commands over %d ticks from %s" % [
		(trace.get("commands", []) as Array).size(), _replay_by_tick.size(), path,
	])


static func _read_trace(path: String) -> Dictionary:
	if !FileAccess.file_exists(path):
		push_error("DeterminismBench found no trace at " + path)
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if !(parsed is Dictionary):
		push_error("DeterminismBench could not parse " + path)
		return {}
	return parsed as Dictionary


# --- comparing ------------------------------------------------------------

## The whole point of the tool: not "do these differ" but "WHERE". A divergence
## located to a tick is something a probe can be pointed at; one that is merely
## detected is a bug report nobody can act on.
func _run_compare() -> void:
	var paths: PackedStringArray = _compare.split(",")
	if paths.size() != 2:
		push_error("DeterminismBench wants compare=<a.json>,<b.json>")
		_quit()
		return

	var a: Dictionary = _read_trace(paths[0].strip_edges())
	var b: Dictionary = _read_trace(paths[1].strip_edges())
	if a.is_empty() || b.is_empty():
		_quit()
		return

	var left: Array = a.get("samples", []) as Array
	var right: Array = b.get("samples", []) as Array

	print("DET compare %s (%d samples) vs %s (%d samples)" % [
		paths[0], left.size(), paths[1], right.size(),
	])
	if int(a.get("seed", 0)) != int(b.get("seed", 1)):
		print("DET WARNING seeds differ: %d vs %d - of course they diverge" % [
			int(a.get("seed", 0)), int(b.get("seed", 1)),
		])

	var count: int = mini(left.size(), right.size())
	for index: int in range(count):
		var one: Dictionary = left[index] as Dictionary
		var two: Dictionary = right[index] as Dictionary
		var world_same: bool = int(one.get("world", 0)) == int(two.get("world", 1))
		var deep_same: bool = int(one.get("deep", 0)) == int(two.get("deep", 1))
		if world_same && deep_same:
			continue

		var which: String = "world+deep"
		if world_same:
			which = "deep only - health, gold or lives moved but positions did not"
		elif deep_same:
			which = "world only"
		print("DET DIVERGED first at tick %d (%s)" % [int(one.get("tick", -1)), which])
		print("DET   a world=%d deep=%d" % [
			int(one.get("world", 0)), int(one.get("deep", 0)),
		])
		print("DET   b world=%d deep=%d" % [
			int(two.get("world", 0)), int(two.get("deep", 0)),
		])
		_quit()
		return

	if left.size() != right.size():
		print("DET DIVERGED in LENGTH: %d samples vs %d, identical up to tick %d" % [
			left.size(), right.size(), count * int(a.get("every", 1)),
		])
		_quit()
		return

	print("DET IDENTICAL across %d samples, %d ticks" % [
		count, count * int(a.get("every", 1)),
	])
	_quit()


func _quit() -> void:
	get_tree().quit()
