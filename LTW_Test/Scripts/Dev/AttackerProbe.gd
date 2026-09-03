class_name AttackerProbe
extends Node

## SCAFFOLDING. Drives a headless match and checks the two things that were
## just changed about ATTACKER creeps: that one already walking can still be
## re-aimed, and that a commanded walk goes ROUND the maze rather than into it.
##
##   godot --path . --headless res://Scenes/Dev/attacker_probe.tscn
##
## Same shape as CreepProbe next to it, and for the same reason: a scene that
## instances a match underneath itself is the only way to get a real PlayerArea,
## a real flow field and real towers without adding an autoload.
##
## DELETE THIS WITH THE REST OF Scripts/Dev WHEN THE WORK IS DONE.

const MATCH_SCENE: String = "res://Scenes/Server/server_match.tscn"
const CREEPS: String = "res://Resources/UnitStats/Creeps"
const TOWERS: String = "res://Resources/UnitStats/Towers"
const ABILITIES: String = "res://Resources/Abilities"
const TAG: String = "ATTACKER"

## Ticks to let the match settle before the first check.
const WARMUP_TICKS: int = 20
## Internal row the pocket is built on. Well inside the buildable zone, which
## runs from row 6 to row 65 on the authored grid.
const POCKET_ROW: int = 30
## The tower the walls are made of. One player cell across, so two internal
## cells, which is why every wall cell below is even aligned.
const WALL_TOWER: String = "archer"
## How long the commanded walk is watched, in ticks. Generous against a detour
## that takes about seven seconds.
##
## Watched a TICK at a time, which matters at the very end: an attacker whose
## order has finished goes back to marching on the nearest tower on the next
## tick, so a slower poll catches it a third of a cell away from the point it
## really did stand on.
const WALK_TICKS: int = 600
## The creep the pocket is walked with: a plain melee attacker, and it has to
## be one.
##
## The Siege Engine cannot do this job. It carries Bombardment, which fires on
## a clock of its own and does not care that the creep is walking - so one
## pressed against a wall it could not get round quietly knocked the tower down
## after about eight seconds and strolled through the hole. Legitimate, and not
## what is being measured: the probe reported the creep arriving whether it had
## read the maze or not. A Mountain Giant has only its own attack, and an
## ordered walk forbids that - move means move.
const POCKET_CREEP: String = "mountain_giant"

var _area: PlayerArea = null
var _passes: int = 0
var _fails: int = 0
var _lines: PackedStringArray = PackedStringArray()


func _ready() -> void:
	# Both, and high: process_physics_priority is the only one that orders the
	# TICK, and a parent runs before its children by default - see CLAUDE.md.
	process_priority = 100000
	process_physics_priority = 100000
	_start_match()
	_run()


func _start_match() -> void:
	var packed: PackedScene = load(MATCH_SCENE) as PackedScene
	var setup: MatchSetup = MatchSetup.new()
	setup.players.append(MatchPlayer.create(1, "Probe"))
	setup.players.append(MatchPlayer.create(2, "Probe Two"))
	setup.local_slot = 0
	setup.rng_seed = 1
	MenuNavigation.pending_match = setup
	add_child(packed.instantiate())


func _run() -> void:
	await _ticks(WARMUP_TICKS)
	_area = _find_area()
	if _area == null:
		_fail("setup", "no PlayerArea, the match did not start")
		_finish()
		return

	_park_builder()
	await _check_retarget_while_walking()
	_reset()
	# A clear two seconds, not two ticks. The check above leaves the Siege
	# Engine's rockets in the air, and one of them landed on a wall the check
	# below had only just built - which read as pathfinding taking a shortcut.
	await _ticks(40)
	await _check_walks_out_of_a_pocket()
	_finish()


# --- 1: an attacker already walking can still be re-aimed ------------------

## The bug: an attack order was refused for a creep that was MOVING, so the
## first click landed and every one after it was thrown away until the creep
## happened to be standing still again.
func _check_retarget_while_walking() -> void:
	var attack: UnitAbility = _ability("attack_ability")
	var move: UnitAbility = _ability("move_ability")
	var first: Building = _place_tower(Vector2i(4, POCKET_ROW))
	var second: Building = _place_tower(Vector2i(12, POCKET_ROW))
	if attack == null || move == null || first == null || second == null:
		_fail("retarget", "could not set the case up")
		return

	var creep: Creep = await _spawn("siege_engine", Vector2i(8, POCKET_ROW - 14))
	if creep == null:
		return

	# Sent walking somewhere with a plain MOVE order first, which is the state
	# the next click used to be thrown away in.
	Commands.submit(move, [creep], AbilityTarget.at_position(
		_at(Vector2i(8, POCKET_ROW - 4))))
	await _ticks(6)

	_check("a commanded attacker is walking", creep.is_moving(), "")
	_check("and may not FIRE while it walks", !creep.can_attack(),
		"move means move")
	_check("but may still be GIVEN an attack order",
		creep.can_take_attack_order() && attack.can_execute(creep), "")

	# The real road, exactly as a left click takes it.
	Commands.submit(attack, [creep], AbilityTarget.at_unit(first))
	await _ticks(4)
	_check("clicking a tower while walking takes",
		creep.attack_component.ordered_target() == first,
		_name_of(creep.attack_component.ordered_target()))

	# And again on a second tower while the creep is chasing the first, which
	# is the half that used to work exactly once per selection.
	await _ticks(10)
	var chasing: bool = creep.is_moving()
	Commands.submit(attack, [creep], AbilityTarget.at_unit(second))
	await _ticks(4)
	_check("and takes again mid-chase",
		creep.attack_component.ordered_target() == second,
		"was chasing" if chasing else "was standing")


# --- 2: a commanded walk reads the maze ------------------------------------

## Puts the creep in a three sided pocket that opens AWAY from where it is
## sent. Walking straight at the point cannot get out of one: the creep presses
## into the far wall and slides along it until a corner stops it. Reading a
## route walks it out of the pocket, around the side and back down.
func _check_walks_out_of_a_pocket() -> void:
	var move: UnitAbility = _ability("move_ability")
	if move == null || !_build_pocket():
		_fail("pocket", "could not build the pocket")
		return

	var creep: Creep = await _spawn(POCKET_CREEP, Vector2i(8, POCKET_ROW - 3))
	if creep == null:
		return

	_check("the pocket is sealed", _pocket_sealed(), "")
	var destination: Vector3 = _at(Vector2i(8, POCKET_ROW + 4))
	var route: Array[Vector2i] = _area.route_between(creep.global_position, destination)
	_check("a route out of the pocket exists", !route.is_empty(),
		"%d cells" % route.size())

	Commands.submit(move, [creep], AbilityTarget.at_position(destination))

	# The NORTHMOST row it reaches is what proves the route was read. The
	# pocket only opens north, so a creep walking straight at its destination
	# presses into the south wall and never goes back the way it came - it can
	# only ever be found at the row it started on or beyond it.
	var closest: float = INF
	var northmost: int = _area.world_to_internal_cell(creep.global_position).y
	var settled: bool = false
	var sealed: bool = true
	for _index in range(WALK_TICKS):
		await _ticks(1)
		closest = minf(closest, _flat_distance(creep.global_position, destination))
		northmost = mini(northmost, _area.world_to_internal_cell(
			creep.global_position).y)
		sealed = sealed && _pocket_sealed()
		if !creep.is_moving():
			settled = true
			break

	var row: int = _area.world_to_internal_cell(creep.global_position).y
	_check("the wall stood for the whole walk", sealed,
		"nothing was knocked through")
	_check("the creep leaves the pocket the only way out of it",
		northmost < POCKET_ROW - 6, "reached row %d, mouth at %d"
		% [northmost, POCKET_ROW - 6])
	_check("and the walk ends", settled,
		"got within %.2f of the point" % closest)
	_check("south of the wall it started north of", row > POCKET_ROW + 1,
		"row %d, wall on %d" % [row, POCKET_ROW])
	_check("standing on the point it was sent to",
		creep.has_arrived_at(destination), "%.2f away" % closest)


## A U of towers open away from the destination, with the creep inside it.
##
## Roomy on purpose. A tighter pocket put the creep within its own attack reach
## of the wall, and the first tick after it spawns is a tick it is standing
## still - so it simply shot the wall down before the move order arrived. A
## 35 health Archer goes in one swing. Everything after that tick is safe,
## because a walking creep may not fire at all.
func _build_pocket() -> bool:
	var built: bool = true
	# The south wall, which is between the creep and where it is sent.
	for x in [2, 4, 6, 8, 10, 12]:
		built = built && _place_tower(Vector2i(x, POCKET_ROW)) != null
	# The two sides, running back north to close the pocket in.
	for row in [POCKET_ROW - 2, POCKET_ROW - 4, POCKET_ROW - 6]:
		built = built && _place_tower(Vector2i(2, row)) != null
		built = built && _place_tower(Vector2i(12, row)) != null
	return built


## Whether every cell of the pocket is really walled, asked rather than assumed.
##
## It is worth a check of its own because the pocket going quietly leaky is
## exactly what a passing test looks like: the creep reaches its destination
## either way and only the ROUTE it took says which. It has already happened
## once, to a rocket left over from the check above landing on a fresh wall.
func _pocket_sealed() -> bool:
	for row in range(POCKET_ROW, POCKET_ROW + 2):
		for x in range(2, 14):
			if _area.is_point_free(_at(Vector2i(x, row))):
				return false
	for row in range(POCKET_ROW - 6, POCKET_ROW):
		for x in [2, 3, 12, 13]:
			if _area.is_point_free(_at(Vector2i(x, row))):
				return false
	return true


# --- helpers ---------------------------------------------------------------

func _find_area() -> PlayerArea:
	var manager: PlayerManager = References.player_manager
	return null if manager == null else manager.area_for(1)


func _ability(stem: String) -> UnitAbility:
	return load("%s/%s.tres" % [ABILITIES, stem]) as UnitAbility


func _at(cell: Vector2i) -> Vector3:
	return _area.internal_cell_center(cell)


func _flat_distance(from: Vector3, to: Vector3) -> float:
	var offset: Vector3 = to - from
	offset.y = 0.0
	return offset.length()


func _spawn(stem: String, cell: Vector2i, owner_slot: int = 1) -> Creep:
	var stats: CreepStats = load("%s/%s_stats.tres" % [CREEPS, stem]) as CreepStats
	if stats == null:
		_fail(stem, "no stats resource")
		return null
	var scene: PackedScene = stats.scene()
	if scene == null:
		_fail(stem, "no prefab")
		return null

	var creep: Creep = scene.instantiate() as Creep
	_area.creeps_root().add_child(creep)
	creep.spawn(owner_slot, _area, _at(cell))
	await _ticks(1)
	return creep


## Stands a wall tower on an internal cell, switched off so it never shoots at
## what is being measured. It still holds its cells on the movement grid, which
## is the only thing these are here for.
func _place_tower(cell: Vector2i) -> Building:
	var stats: BuildingStats = load(
		"%s/%s_stats.tres" % [TOWERS, WALL_TOWER]) as BuildingStats
	if stats == null:
		_fail(WALL_TOWER, "no tower stats")
		return null
	var scene: PackedScene = stats.scene()
	if scene == null:
		_fail(WALL_TOWER, "no tower prefab")
		return null

	var tower: Building = scene.instantiate() as Building
	_area.add_child(tower)
	tower.place(1, _area, cell, 0, true)
	tower.process_mode = Node.PROCESS_MODE_DISABLED
	return tower


func _reset() -> void:
	for creep: Creep in _area.creeps():
		_free(creep)
	for child: Node in _area.get_children():
		if child is Building:
			_free(child)


func _free(unit: Node) -> void:
	if unit == null || !is_instance_valid(unit):
		return
	# Stopped BEFORE it is taken out, because remove_child runs _exit_tree at
	# once and anything still mid-tick then walks a node with no transform. A
	# tower has to go out that way all the same - that is what hands its grid
	# cells back before the next check asks for them.
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	var parent: Node = unit.get_parent()
	if parent != null:
		parent.remove_child(unit)
	unit.queue_free()


## Walks the player's own builder out of the way and switches it off. It starts
## in the middle of the buildable zone, carries an attack, and would otherwise
## chew on whatever is being measured. Same reason CreepProbe parks it.
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
			builder.global_position = _area.clamp_point(_at(Vector2i(1, 8)))


func _ticks(count: int) -> void:
	for _index in range(maxi(1, count)):
		await get_tree().physics_frame


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


func _name_of(unit: Unit) -> String:
	if unit == null || !is_instance_valid(unit):
		return "nothing"
	return unit.name


func _finish() -> void:
	print("\n[%s] ---------------------------------------------" % TAG)
	for line: String in _lines:
		print("[%s] %s" % [TAG, line])
	print("[%s] ---------------------------------------------" % TAG)
	print("[%s] %d passed, %d FAILED" % [TAG, _passes, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
