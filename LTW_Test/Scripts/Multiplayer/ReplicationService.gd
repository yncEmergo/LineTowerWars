class_name ReplicationService
extends Node

## The server's answer to "what does the world look like now", sent every tick.
## **Registered as the autoload `Replication`**, an autoload for the same forced
## reason `Commands` is: an `@rpc` routes by node path, and the two match scenes
## do not share one.
##
## **Phase A: the whole world, every tick** (3.2). Every unit and every player,
## whether or not anything changed. That is bandwidth-ugly on purpose and will
## not scale to fifteen players - it is the shortest path to two people actually
## playing, and it makes every later optimisation something to be MEASURED
## against rather than guessed at. Phase B (3.3) replaces most of it with spawn
## events plus local extrapolation.
##
## Being complete is also what makes it simple. A snapshot that carries
## everything needs no spawn message, no despawn message and no reconciliation:
## a unit that is in it exists, a unit that is not is gone, and a client that
## missed a packet is corrected 50 ms later by the next one. That is why it is
## sent UNRELIABLE - re-sending a stale world would be worse than skipping it.
##
## The client half is deliberately dumb. It runs no simulation (3.4, and D17 -
## no prediction in the first version), so there is nothing to reconcile and
## nothing that can drift. What it draws is what arrived.

## Fields per unit in the snapshot: id, type, owner, area, x, y, z, yaw,
## health, flags, mana, maximum mana.
##
## Mana is in there because an elemental tower's whole ability is usually "fill
## up, then spend it", and a client that could not see the bar would be
## watching a tower fire for no reason it could read. The MAXIMUM is sent as
## well rather than looked up, because one tower in the game lowers its own -
## see Building.set_max_mana.
##
## A flat float array rather than an array of dictionaries, because a dictionary
## per unit would spend more bytes on the KEY NAMES than on the values, twenty
## times a second.
##
## The yaw is in there because a client runs no movement code (3.4) and so has
## nothing to turn a unit with. Without it every creep walks the maze facing
## whichever way it happened to spawn, which is exactly what it looked like.
##
## Floats hold every one of these exactly: a float32 is exact on integers up to
## 16.7 million, which is far past any id this game will hand out.
const UNIT_STRIDE: int = 12
## Fields per player: slot, gold, income, lives, value, placement.
const PLAYER_STRIDE: int = 6
## Fields per reserve: slot, creep type, count.
const STOCK_STRIDE: int = 3
## Fields before one player's researched technology ids: their slot, the ticks
## left on their undo window, and how many ids follow.
##
## Self-describing rather than a fixed stride, because the list is a different
## length for every player and grows all match. Grouped with the ids rather
## than folded into the player record, so everything about technology arrives
## and is applied in one piece - a set of ids and the window over it are read
## back together or not at all.
const TECH_HEADER: int = 3

const FLAG_UNDER_CONSTRUCTION: int = 1
const FLAG_SELLING: int = 2
const FLAG_UPGRADING: int = 4
## Whether a tower's Prioritize toggle is set to air. Simulation rather than
## presentation - it changes what the server shoots - so the client is told
## rather than remembering its own click.
const FLAG_PRIORITIZE_AIR: int = 8

## Newest snapshot received and not yet applied, or empty.
##
## Buffered rather than applied on arrival, for the same reason commands are
## queued: a packet lands in the middle of a frame, and moving every unit there
## would fight the physics interpolation that makes 20 Hz look smooth. Applied
## on the tick instead, which is where the interpolator expects movement.
var _incoming: Dictionary = {}
## Tick of the last snapshot applied, so an out-of-order packet is dropped
## rather than dragging the world backwards.
var _applied_tick: int = -1

var _session: MatchSession:
	get:
		return References.match_session


func _ready() -> void:
	# Runs AFTER everything in the match scene, which is the whole point on the
	# server: a snapshot has to describe the tick that just finished, not the
	# one about to start. Autoloads sit above the scene in tree order, so
	# without this it would broadcast the world one tick stale.
	process_priority = 1000
	set_physics_process(false)
	Net.status_changed.connect(_on_network_status_changed)


func _on_network_status_changed(_status: NetworkService.Status) -> void:
	# Nothing to send and nothing to receive while offline, which is also every
	# single player run.
	set_physics_process(Net.is_online())
	_applied_tick = -1
	_incoming.clear()


func _physics_process(_delta: float) -> void:
	if _session == null:
		return
	if multiplayer.is_server():
		_broadcast()
		return
	_apply_incoming()


# --- server ---------------------------------------------------------------

func _broadcast() -> void:
	var peers: PackedInt32Array = Net.peer_ids()
	if peers.is_empty():
		return
	receive_snapshot.rpc(_build_snapshot())


## Everything a client needs to draw the world, read straight off it.
func _build_snapshot() -> Dictionary:
	var session: MatchSession = _session
	var units: PackedFloat32Array = PackedFloat32Array()
	for id in session.unit_ids():
		var unit: Unit = session.unit_for(int(id))
		if unit != null:
			units.append_array(_unit_record(unit))

	var players: PackedInt32Array = PackedInt32Array()
	var stocks: PackedInt32Array = PackedInt32Array()
	var techs: PackedInt32Array = PackedInt32Array()
	var manager: PlayerManager = References.player_manager
	if manager != null:
		for slot in range(1, session.player_count() + 1):
			var state: PlayerState = manager.state_for(slot)
			if state != null:
				players.append_array([
					slot, state.gold, state.income, state.lives,
					state.value, state.placement,
				])
				_append_techs(techs, state, slot)
			_append_stocks(stocks, manager, slot)

	return {"t": session.tick(), "u": units, "p": players, "s": stocks, "r": techs}


func _unit_record(unit: Unit) -> PackedFloat32Array:
	var type_id: int = UnitTypeRegistry.NO_TYPE
	if unit.stats != null:
		type_id = unit.stats.unit_type_id

	var flags: int = 0
	var building: Building = unit as Building
	if building != null:
		if building.is_under_construction():
			flags |= FLAG_UNDER_CONSTRUCTION
		if building.is_selling():
			flags |= FLAG_SELLING
		if building.is_upgrading():
			flags |= FLAG_UPGRADING
	if unit.attack_component != null && unit.attack_component.prioritizes_air():
		flags |= FLAG_PRIORITIZE_AIR

	var position: Vector3 = unit.global_position
	return PackedFloat32Array([
		unit.unit_id,
		type_id,
		unit.owner_player_id,
		0 if unit.area == null else unit.area.player_id,
		position.x, position.y, position.z,
		unit.rotation.y,
		unit.current_health,
		flags,
		0 if building == null else building.current_mana,
		0 if building == null else building.max_mana,
	])


## One player's whole technology state. Sent every tick like everything else in
## phase A, whether or not it changed - it is a handful of ints against a world
## of units, and being complete is what lets a client that missed a packet be
## corrected by the next one rather than reconciled.
func _append_techs(into: PackedInt32Array, state: PlayerState, slot: int) -> void:
	var ids: PackedInt32Array = state.tech.owned_ids()
	into.append_array([slot, state.tech.undo_ticks_left(), ids.size()])
	into.append_array(ids)


func _append_stocks(into: PackedInt32Array, manager: PlayerManager, slot: int) -> void:
	var area: PlayerArea = manager.area_for(slot)
	if area == null || area.send_building() == null:
		return
	for entry in area.send_building().stock_entries():
		into.append_array([slot, int(entry[0]), int(entry[1])])


# --- client ---------------------------------------------------------------

## Unreliable and unordered on purpose. A snapshot is only ever the CURRENT
## world, so a lost one costs 50 ms and a late one is worth less than the newer
## one already applied - re-sending either would spend bandwidth making the
## client's world older.
@rpc("authority", "unreliable")
func receive_snapshot(payload: Dictionary) -> void:
	if multiplayer.is_server():
		return
	_incoming = payload


func _apply_incoming() -> void:
	if _incoming.is_empty():
		return

	var payload: Dictionary = _incoming
	_incoming = {}

	var tick: int = int(payload.get("t", 0))
	if tick <= _applied_tick:
		# Arrived out of order. The world it describes is older than the one
		# already on screen.
		return
	_applied_tick = tick

	_apply_units(payload.get("u", PackedFloat32Array()) as PackedFloat32Array)
	_apply_players(payload.get("p", PackedInt32Array()) as PackedInt32Array)
	_apply_stocks(payload.get("s", PackedInt32Array()) as PackedInt32Array)
	_apply_techs(payload.get("r", PackedInt32Array()) as PackedInt32Array)


## Every unit in the snapshot is created or updated; every unit not in it is
## removed. That is the whole lifecycle, and it needs no spawn or death message
## of its own.
func _apply_units(records: PackedFloat32Array) -> void:
	var session: MatchSession = _session
	var seen: Dictionary = {}

	var index: int = 0
	while index + UNIT_STRIDE <= records.size():
		var id: int = int(records[index])
		seen[id] = true
		var unit: Unit = session.unit_for(id)
		if unit == null:
			unit = _spawn(id, records, index)
		elif _changed_type(unit, records, index):
			unit = _replace(unit, id, records, index)
		if unit != null:
			_update(unit, records, index)
		index += UNIT_STRIDE

	for id in session.unit_ids():
		if !seen.has(int(id)):
			_remove(int(id))


## A unit this client has never heard of: a creep that was just sent, or a
## tower somebody just placed. Built from the same prefab the server used,
## found through the type id (D12's argument, applied to units).
func _spawn(id: int, records: PackedFloat32Array, at: int) -> Unit:
	var unit: Unit = _instantiate(records, at)
	if unit != null:
		_adopt(unit, id, records, at)
	return unit


## The node, parented and nothing else. Split from adopting it because an
## upgrade needs the replacement to EXIST before the tower it replaces leaves,
## and to take that tower's id and grid cells only afterwards. See _replace().
func _instantiate(records: PackedFloat32Array, at: int) -> Unit:
	var session: MatchSession = _session
	var stats: UnitStats = session.unit_types().stats_for(int(records[at + 1]))
	if stats == null:
		Log.err("Snapshot names a unit type this build does not contain", {
			"type": int(records[at + 1]),
			"unit": int(records[at]),
		})
		return null

	var scene: PackedScene = stats.scene()
	if scene == null:
		Log.err("Replicated unit type names no loadable prefab", stats.display_name)
		return null

	var unit: Unit = scene.instantiate() as Unit
	if unit == null:
		Log.err("Replicated unit prefab root is not a Unit", stats.display_name)
		return null

	var parent: Node = _parent_for(unit, _area_of(records, at))
	if parent == null:
		Log.err("Nowhere to put a replicated unit", stats.display_name)
		unit.queue_free()
		return null

	# Set before the node enters the tree, so nothing ever sees it owned by the
	# default player - which would read as an enemy unit for one call.
	unit.owner_player_id = int(records[at + 2])
	parent.add_child(unit)
	return unit


## Gives a parented unit the id, the owner and the place the server says it
## has. This is where a building claims its grid cells, which is why it must
## not run while the unit it is replacing still holds them.
func _adopt(unit: Unit, id: int, records: PackedFloat32Array, at: int) -> void:
	unit.adopt(
		id,
		int(records[at + 2]),
		_area_of(records, at),
		Vector3(records[at + 4], records[at + 5], records[at + 6])
	)


func _area_of(records: PackedFloat32Array, at: int) -> PlayerArea:
	var manager: PlayerManager = References.player_manager
	if manager == null:
		return null
	return manager.area_for(int(records[at + 3]))


## Whether the id this snapshot is describing has become a DIFFERENT unit type
## since the last one. Only an upgrade does that: a tower keeps its id across
## the swap on purpose, so that to every other machine and to the player's own
## selection it stays the same tower. See Building._complete_upgrade().
##
## Comparing the type is what lets the whole feature cost no wire format at
## all - the type id is already in every record, for the spawn path.
func _changed_type(unit: Unit, records: PackedFloat32Array, at: int) -> bool:
	if unit.stats == null:
		return false
	return unit.stats.unit_type_id != int(records[at + 1])


## Rebuilds a unit that changed type, under the id it already had.
##
## The order is the authority's own, step for step, and every step of it is
## load bearing:
##   1. the replacement enters the tree, so anything told about it finds a unit
##      that has run its _ready
##   2. the swap is ANNOUNCED while the old unit is still standing, so the
##      selection and the control groups move across rather than emptying
##   3. only then does the old unit go, which is what hands back its id and
##      releases the grid cells it was holding
##   4. the replacement adopts that id and takes those cells
## Doing 4 before 3 leaves the cell marked free with a tower standing on it,
## which this client would then draw a green build ghost over.
func _replace(old_unit: Unit, id: int, records: PackedFloat32Array, at: int) -> Unit:
	var replacement: Unit = _instantiate(records, at)
	if replacement == null:
		# The build does not contain the type the server upgraded into, which
		# _instantiate has already reported. Keeping the old node on screen
		# beats leaving a hole, so nothing else changes.
		return old_unit

	var session: MatchSession = _session
	session.replace_unit(old_unit, replacement)

	# remove_child runs _exit_tree straight away - queue_free would not - which
	# is what gives the id and the cells back before the replacement asks.
	var parent: Node = old_unit.get_parent()
	if parent != null:
		parent.remove_child(old_unit)
	old_unit.queue_free()

	_adopt(replacement, id, records, at)
	return replacement


## Where a replicated unit belongs, which is wherever the same unit is parented
## when this machine spawns one itself: creeps under their area's creep root,
## towers under the area, everything else under the shared units root.
func _parent_for(unit: Unit, area: PlayerArea) -> Node:
	if unit is Creep:
		return null if area == null else area.creeps_root()
	if unit is Building:
		return area
	return References.units_root


func _update(unit: Unit, records: PackedFloat32Array, at: int) -> void:
	unit.global_position = Vector3(records[at + 4], records[at + 5], records[at + 6])
	unit.rotation.y = records[at + 7]
	unit.set_replicated_health(int(records[at + 8]))

	var flags: int = int(records[at + 9])
	var building: Building = unit as Building
	if building != null:
		building.set_replicated_phase(
			(flags & FLAG_UNDER_CONSTRUCTION) != 0,
			(flags & FLAG_SELLING) != 0,
			(flags & FLAG_UPGRADING) != 0
		)
		building.set_replicated_mana(int(records[at + 10]), int(records[at + 11]))
	if unit.attack_component != null:
		unit.attack_component.set_prioritize_air((flags & FLAG_PRIORITIZE_AIR) != 0)


## A unit the server no longer has. Unregistered immediately rather than left
## to _exit_tree, because queue_free is deferred and the next snapshot would
## otherwise still find it and treat it as alive.
func _remove(id: int) -> void:
	var session: MatchSession = _session
	var unit: Unit = session.unit_for(id)
	session.unregister_unit(id)
	if unit != null:
		unit.queue_free()


func _apply_players(records: PackedInt32Array) -> void:
	var manager: PlayerManager = References.player_manager
	if manager == null:
		return

	var index: int = 0
	while index + PLAYER_STRIDE <= records.size():
		var state: PlayerState = manager.state_for(records[index])
		if state != null:
			state.set_replicated(
				records[index + 1], records[index + 2], records[index + 3],
				records[index + 4], records[index + 5]
			)
		index += PLAYER_STRIDE


func _apply_stocks(records: PackedInt32Array) -> void:
	var manager: PlayerManager = References.player_manager
	var session: MatchSession = _session
	if manager == null || session == null:
		return

	var index: int = 0
	while index + STOCK_STRIDE <= records.size():
		var area: PlayerArea = manager.area_for(records[index])
		var stats: CreepStats = session.unit_types().stats_for(records[index + 1]) as CreepStats
		if area != null && area.send_building() != null && stats != null:
			area.send_building().set_replicated_stock(stats, records[index + 2])
		index += STOCK_STRIDE


## What every player has researched, and how long their Undo button has left.
##
## Walked by the count each record carries rather than by a stride, and a short
## record is dropped whole: applying half of one would leave a player quietly
## missing a technology, which is exactly the kind of difference that only
## shows up as a tower that refuses to be built.
func _apply_techs(records: PackedInt32Array) -> void:
	var manager: PlayerManager = References.player_manager
	if manager == null:
		return

	var index: int = 0
	while index + TECH_HEADER <= records.size():
		var last: int = index + TECH_HEADER + records[index + 2]
		if last > records.size():
			Log.warn("Technology snapshot record is short, the rest of it was dropped")
			return
		var state: PlayerState = manager.state_for(records[index])
		if state != null:
			state.tech.set_replicated(
				records.slice(index + TECH_HEADER, last), records[index + 1]
			)
		index = last
