class_name FormationProbe
extends Node

## SCAFFOLDING. Delete with the rest of Scripts/Dev when the movement work lands.
##
## **The positive control that was skipped last time.** The formation that
## shipped was proven as arithmetic, headless, twice - and never once proven to
## FIRE in a real match. "Barely improved" and "never ran" look identical from
## the outside, so this boots a real match, spawns real attacker creeps, sends a
## real order down the real Commands road, and reports what each creep was
## actually told to do and where it actually ended up.
##
## Modelled on DeterminismBench: park a MatchSetup in MenuNavigation.pending_match
## and add the server match scene as a child.

const MATCH_SCENE: String = "res://Scenes/Server/server_match.tscn"
const CREEP_FOLDER: String = "res://Resources/UnitStats/Creeps"
const TOWER_STATS: String = "res://Resources/UnitStats/Towers/watch_tower_stats.tres"
const MOVE_ABILITY: String = "res://Resources/Abilities/move_ability.tres"
const ATTACK_ABILITY: String = "res://Resources/Abilities/attack_ability.tres"

## Ticks to wait after boot before spawning, after spawning before ordering, and
## after ordering before reporting. The last is the one that matters: long
## enough that a group which is going to settle has settled.
const BOOT_TICKS: int = 30
const SETTLE_TICKS: int = 20
const WALK_TICKS: int = 240

var _tick: int = 0
var _area: PlayerArea = null
var _creeps: Array[Creep] = []
var _ordered_at: Array[Vector3] = []
var _count: int = 8
var _creep_key: String = "corrupted_treant"
## "ground" orders a move onto open ground; "tower" builds one and attacks it.
var _mode: String = "ground"
var _tower: Building = null
## Positive control for the hold: a run where nobody ever entered the hold
var _ever_held: int = 0
var _required_pitch: float = 0.0


func _ready() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var pair: PackedStringArray = argument.split("=", true, 1)
		if pair.size() != 2:
			continue
		match pair[0].strip_edges():
			"creeps":
				_count = maxi(2, int(pair[1]))
			"creep":
				_creep_key = pair[1].strip_edges()
			"mode":
				_mode = pair[1].strip_edges()

	var packed: PackedScene = load(MATCH_SCENE) as PackedScene
	if packed == null:
		print("PROBE FATAL no match scene")
		get_tree().quit()
		return

	var setup: MatchSetup = MatchSetup.new()
	setup.players.append(MatchPlayer.create(1, "Probe"))
	setup.local_slot = 1
	setup.rng_seed = 12345
	MenuNavigation.pending_match = setup
	add_child(packed.instantiate())


func _physics_process(_delta: float) -> void:
	_tick += 1

	if _tick == BOOT_TICKS:
		_spawn()
	elif _tick == BOOT_TICKS + SETTLE_TICKS:
		_order()
	elif _tick == BOOT_TICKS + SETTLE_TICKS + WALK_TICKS:
		_report()
		get_tree().quit()
	else:
		var since: int = _tick - BOOT_TICKS - SETTLE_TICKS
		if since > 0 && since % 10 == 0:
			_sample()


func _spawn() -> void:
	var manager: PlayerManager = References.player_manager
	if manager == null:
		print("PROBE FATAL no player manager")
		get_tree().quit()
		return
	_area = manager.area_for(1)
	if _area == null:
		print("PROBE FATAL no area")
		get_tree().quit()
		return

	var stats: CreepStats = ResourceLoader.load(
		"%s/%s_stats.tres" % [CREEP_FOLDER, _creep_key], "") as CreepStats
	var scene: PackedScene = null
	if stats != null:
		scene = ResourceLoader.load(stats.scene_path, "PackedScene") as PackedScene
	if scene == null:
		print("PROBE FATAL no creep scene")
		get_tree().quit()
		return

	if _mode == "tower":
		_build_tower()

	# Clustered deliberately, because a pack that starts spread out would hide
	# the very thing being measured.
	var origin: Vector3 = _area.internal_cell_center(Vector2i(
		_area.internal_width() / 2, _area.internal_depth() / 4))
	for index in range(_count):
		var creep: Creep = scene.instantiate() as Creep
		if creep == null:
			continue
		_area.creeps_root().add_child(creep)
		var offset: Vector3 = Vector3(
			float(index % 3) * 0.3, 0.0, float(index / 3) * 0.3)
		creep.spawn(1, _area, _area.nearest_free_point(origin + offset))
		_creeps.append(creep)

	# The pitch the layout HAS to deliver, so a delivered pitch below it is a
	# defect rather than a preference. Printed from the creep's own radius, so
	# a run against the wrong creep cannot look like a pass.
	var required: float = 0.0
	for creep: Creep in _creeps:
		required = maxf(required, 2.0 * creep.crowd_radius())
	print("PROBE creep=%s spawned=%d attackers=%d required_pitch=%.3f cell=%.3f" % [
		_creep_key, _creeps.size(), _attacker_count(), required,
		_area.internal_cell_size()])
	_required_pitch = required


## One finished tower in the middle of the lane, placed the way PerfBench does
## rather than bought, because what is under test is the ring around it.
func _build_tower() -> void:
	var stats: BuildingStats = ResourceLoader.load(TOWER_STATS, "") as BuildingStats
	if stats == null:
		print("PROBE FATAL no tower stats")
		return
	var scene: PackedScene = stats.scene()
	if scene == null:
		print("PROBE FATAL no tower scene")
		return
	var footprint: Vector2i = _area.cells_to_internal(stats.footprint_cells)
	var cell: Vector2i = Vector2i(
		_area.internal_width() / 2, int(float(_area.internal_depth()) * 0.55))
	if !_area.can_place(cell, footprint):
		print("PROBE FATAL cannot place tower at %s" % str(cell))
		return
	var building: Building = scene.instantiate() as Building
	if building == null:
		return
	_area.add_child(building)
	building.place(_area.player_id, _area, cell, stats.gold_cost, true)
	_tower = building


func _attacker_count() -> int:
	var total: int = 0
	for creep: Creep in _creeps:
		if creep.is_attacker():
			total += 1
	return total


func _order() -> void:
	var ability: UnitAbility = ResourceLoader.load(MOVE_ABILITY, "") as UnitAbility
	if ability == null:
		print("PROBE FATAL no move ability")
		get_tree().quit()
		return

	var units: Array = []
	for creep: Creep in _creeps:
		units.append(creep)

	if _mode == "tower":
		if _tower == null || !is_instance_valid(_tower):
			print("PROBE FATAL no tower to attack")
			get_tree().quit()
			return
		var attack: UnitAbility = ResourceLoader.load(ATTACK_ABILITY, "") as UnitAbility
		if attack == null:
			print("PROBE FATAL no attack ability")
			get_tree().quit()
			return
		var reach: float = _creeps[0].attack_component.order_reach()
		var ring: int = _area.reach_cells(_tower.global_position, reach * 0.8).size()
		# POSITIVE CONTROL for the whole ring design: zero free cells within
		# reach means the run never reached the code under test.
		print("PROBE mode=tower ability=%s spreads_group=%s reach=%.3f ring_cells_free=%d" % [
			attack.display_name, str(attack.spreads_group), reach, ring])
		Commands.submit_for(1, attack, units, AbilityTarget.at_unit(_tower), false)
		call_deferred("_capture_targets")
		return

	var destination: Vector3 = _area.internal_cell_center(Vector2i(
		_area.internal_width() / 2, int(float(_area.internal_depth()) * 0.55)))
	print("PROBE mode=ground ability=%s spreads_group=%s destination=%s" % [
		ability.display_name, str(ability.spreads_group), _flat(destination)])
	Commands.submit_for(1, ability, units, AbilityTarget.at_position(destination), false)

	# Read back what each creep was ACTUALLY told, one tick later than the
	# submit so the command has been applied. Done here rather than in _report
	# because a walk overwrites the target as it goes.
	call_deferred("_capture_targets")


func _capture_targets() -> void:
	_ordered_at.clear()
	for creep: Creep in _creeps:
		_ordered_at.append(creep._target_position)

	var distinct: Dictionary = {}
	for point: Vector3 in _ordered_at:
		distinct[_key(point)] = true

	# THE POSITIVE CONTROL. One distinct target means the formation did not
	# fire at all, whatever else the run says.
	print("PROBE targets_distinct=%d of %d" % [distinct.size(), _ordered_at.size()])
	var delivered: float = _min_gap(_ordered_at)
	print("PROBE target_spread=%.3f delivered_pitch=%.3f required=%.3f ok=%s" % [
		_spread(_ordered_at), delivered, _required_pitch,
		str(delivered >= _required_pitch - 0.001)])


## Mid-walk, because the end state alone cannot say WHERE it went wrong.
func _sample() -> void:
	var moving: int = 0
	var alive: int = 0
	var miss: float = 0.0
	for index in range(_creeps.size()):
		var creep: Creep = _creeps[index]
		if creep == null || !is_instance_valid(creep):
			continue
		alive += 1
		if creep.is_moving():
			moving += 1
		if index < _ordered_at.size():
			var offset: Vector3 = creep.global_position - _ordered_at[index]
			offset.y = 0.0
			miss += offset.length()
	var mean: float = 0.0 if alive == 0 else miss / float(alive)
	var idle: int = 0
	var holding: int = 0
	for creep: Creep in _creeps:
		if creep == null || !is_instance_valid(creep):
			continue
		if creep.order_queue == null || creep.order_queue.is_empty():
			idle += 1
		if creep._holding_position:
			holding += 1
	_ever_held = maxi(_ever_held, holding)
	# While the tower still stands, the ring is what is under test - so the
	# geometry is reported HERE and not in the summary, which is measured long
	# after the pack has killed it and moved on.
	var live: Array[Vector3] = []
	for creep: Creep in _creeps:
		if creep != null && is_instance_valid(creep) && !creep.is_moving():
			live.append(creep.global_position)
	var tower_up: bool = _tower != null && is_instance_valid(_tower) && _tower.is_alive()
	var in_reach: int = 0
	if tower_up:
		for creep: Creep in _creeps:
			if creep == null || !is_instance_valid(creep) || creep.attack_component == null:
				continue
			if creep.attack_component.is_in_reach(_tower):
				in_reach += 1
	print("PROBE t=%d alive=%d moving=%d no_order=%d holding=%d miss=%.3f tower=%s parked_gap=%.3f in_reach=%d" % [
		_tick, alive, moving, idle, holding, mean, str(tower_up),
		_min_gap(live), in_reach])


func _report() -> void:
	var final: Array[Vector3] = []
	var moving: int = 0
	var reached: int = 0
	for index in range(_creeps.size()):
		var creep: Creep = _creeps[index]
		if creep == null || !is_instance_valid(creep):
			continue
		final.append(creep.global_position)
		if creep.is_moving():
			moving += 1
		if index < _ordered_at.size():
			var offset: Vector3 = creep.global_position - _ordered_at[index]
			offset.y = 0.0
			if offset.length() <= 0.25:
				reached += 1

	var contact: float = 0.0
	for creep: Creep in _creeps:
		if creep != null && is_instance_valid(creep):
			contact = 2.0 * creep.crowd_radius()
			break
	print("PROBE alive=%d internal_cell=%.3f contact_distance=%.3f" % [
		final.size(), _area.internal_cell_size(), contact])
	print("PROBE final_spread=%.3f min_final_gap=%.3f" % [
		_spread(final), _min_gap(final)])
	print("PROBE still_moving=%d reached_own_slot=%d of %d ever_held=%d" % [
		moving, reached, _creeps.size(), _ever_held])

	# How far each creep ended from where it was sent. A large mean with nobody
	# still moving is the "stopped in the wrong place" failure.
	var total: float = 0.0
	var worst: float = 0.0
	var counted: int = 0
	for index in range(mini(_creeps.size(), _ordered_at.size())):
		var creep: Creep = _creeps[index]
		if creep == null || !is_instance_valid(creep):
			continue
		var offset: Vector3 = creep.global_position - _ordered_at[index]
		offset.y = 0.0
		total += offset.length()
		worst = maxf(worst, offset.length())
		counted += 1
	var mean: float = 0.0 if counted == 0 else total / float(counted)
	print("PROBE miss_mean=%.3f miss_worst=%.3f" % [mean, worst])


func _key(point: Vector3) -> String:
	return "%.2f|%.2f" % [point.x, point.z]


func _flat(point: Vector3) -> String:
	return "(%.2f, %.2f)" % [point.x, point.z]


## Largest distance between any two of them, which says whether the group is a
## blob or a block.
func _spread(points: Array) -> float:
	var widest: float = 0.0
	for a in range(points.size()):
		for b in range(a + 1, points.size()):
			var offset: Vector3 = points[a] - points[b]
			offset.y = 0.0
			widest = maxf(widest, offset.length())
	return widest


func _min_gap(points: Array) -> float:
	var closest: float = INF
	for a in range(points.size()):
		for b in range(a + 1, points.size()):
			var offset: Vector3 = points[a] - points[b]
			offset.y = 0.0
			closest = minf(closest, offset.length())
	return 0.0 if closest == INF else closest
