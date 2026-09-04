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

## A life changed hands: `thief` took `lives` off `victim`. Raised on whichever
## machine is drawing the world - the authority raises it as it happens and
## every client is told - so the HUD listens here and nowhere else.
##
## The only EVENT on this service, which is otherwise nothing but state. It is
## here because it has the same two ends as everything else does and needs no
## second channel of its own: an @rpc has to live on an autoload (CLAUDE.md),
## and this is the autoload that already carries the server's word about the
## world. What makes it an event rather than a field is that a leak is a THING
## THAT HAPPENED - two snapshots of the lives either side of one say a number
## changed and cannot say who took it.
signal leak_reported(thief: int, victim: int, lives: int)

## Fields per unit in the snapshot: id, type, owner, area, x, y, z, yaw,
## health, flags, mana, maximum mana, job progress, banked damage, ability
## choice, ability cooldown, ability link, shield, maximum shield.
##
## Mana is in there because an elemental tower's whole ability is usually "fill
## up, then spend it", and a client that could not see the bar would be
## watching a tower fire for no reason it could read. The MAXIMUM is sent as
## well rather than looked up, because one tower in the game lowers its own -
## see Building.set_max_mana.
##
## The same two fields carry a CREEP's pool, for the creeps whose trait runs on
## one (CreepMana). They are the same question about a different kind of unit
## and only one of the two kinds ever answers on a given record, so nothing on
## the wire grew when the creeps that need mana arrived.
##
## A flat float array rather than an array of dictionaries, because a dictionary
## per unit would spend more bytes on the KEY NAMES than on the values, twenty
## times a second.
##
## The yaw is in there because a client runs no movement code (3.4) and so has
## nothing to turn a unit with. Without it every creep walks the maze facing
## whichever way it happened to spawn, which is exactly what it looked like.
##
## The job progress is one number for whichever countdown the flags say is
## running - a tower only ever runs one at a time. It is in for the same reason
## the mana is: a client that could not see the bar would be watching a tower
## it had told to sell simply stand there. It also puts the rising model back
## on a client, which had only the two ends of that movement before.
##
## What is NOT sent is what a morph is turning INTO, so a client draws no
## upgrade preview and its panel pictures the tower rather than what it is
## becoming. That is a whole unit type per record for one icon, and the
## countdown, the name and the bar are all right without it.
##
## The banked damage is the attack damage a tower's passives have added to it
## for good - the Alchemist line's whole ability. It is in here for the same
## reason the mana is, and more sharply: it is bought by KILLING, which only
## ever happens on the server, so a client that was not told would draw its own
## tower's damage line and its stack bar at zero for the whole match. One field
## for the tower rather than one per passive; see
## Building.replicated_damage_bonus.
##
## The ability choice is which option a tower's CYCLED ability is set to - the
## Ultimate Alchemist's armour type. It rides along for the reason the
## Prioritize flag does: it is a setting the player changed on their own tower,
## so a card that went on drawing the old answer would read as a dead button.
##
## The last two are the same argument again, for a tower's ACTIVE ability: how
## long it still has to wait, and which unit it has been aimed at. Both are the
## server's to decide and neither is something a client could work out, so
## without them a Beastmaster's card would draw a ready button for an ability
## on cooldown and an unlit square for a tower that is linked. The link is also
## simulation on the way back out - it is where the beast runs - so a client
## that was not told would draw it running the wrong way. One pair per unit
## rather than one per ability, on the same grounds the ability choice is one
## number; see ActiveAbilityState.
##
## The SHIELD is damage standing in front of a unit's health, and the most that
## shield ever held. It gets a pair of its own rather than riding the mana
## fields, even though nothing today carries both: a shield is a second bar
## drawn in a different place for a different reason, and the day something does
## carry both, an alias would have silently drawn one of them as the other.
##
## The maximum is sent because nothing else remembers it. A shield is a pool
## with no clock, so once a hit has eaten into one there is no other record of
## how big it started - and that is exactly what the background behind the bar
## is showing.
##
## Floats hold every one of these exactly: a float32 is exact on integers up to
## 16.7 million, which is far past any id this game will hand out. The shield is
## the first field that is not a whole number and does not need to be - it is
## drawn as a bar and rounded for the line under it.
const UNIT_STRIDE: int = 19
## Fields per player: slot, gold, income, lives, value, placement, and whether
## the creep-unlock cheat has been granted to them.
##
## The cheat is in here because it decides what a client's send card DRAWS - a
## creep whose wait has been waived is neither greyed out nor counting down -
## and a client that had to guess would sit there showing a countdown for a
## delay the server has already dropped. One int in a record that is sent per
## player rather than per unit.
const PLAYER_STRIDE: int = 7
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

## Fields per status effect: the unit it sits on, the kind, the ability that
## applied it, its magnitude, the seconds left, the stacks held and the ceiling
## on those. See StatusEntry, which reads and writes this record itself.
##
## Sent only for the units clients are actually LOOKING at, unlike everything
## else in phase A - see _watched. A creep in a maze carries several of these
## and a maze carries hundreds of creeps, so the complete version of this would
## cost more than the whole rest of the snapshot put together for something at
## most one creep per player can be reading at a time.
const EFFECT_STRIDE: int = StatusEntry.RECORD_SIZE

## The draft block is described by StartingTech.draft_record rather than by a
## stride here, because it is the only part of a snapshot this service neither
## builds nor reads a field of: it asks the object that owns the draft for a
## record and hands the same record back on the other side.
##
## Fields before one unit's queued orders: its id, and how many follow.
## Self-describing rather than a fixed stride, for the reason TECH_HEADER is:
## a chain is a different length for every unit and changes as it is worked
## through.
const ORDER_HEADER: int = 2
## Fields per order that DRAWS something: the ability, and the point it names.
##
## Only the ones a player can SEE are on the wire at all - a walk still to be
## made, a tower ordered and not started. An attack aimed at one creep is a
## task like any other and puts nothing on the ground, so a client is never
## told about it: what it would draw is the ring that already blinks on the
## creep, locally, the moment the order is given.
##
## It is what makes this affordable next to the rest of phase A. A queue only
## exists on a unit somebody has ordered, and only the builder's chain of
## towers is ever more than a couple of entries long.
const ORDER_STRIDE: int = 4

const FLAG_UNDER_CONSTRUCTION: int = 1
const FLAG_SELLING: int = 2
const FLAG_UPGRADING: int = 4
## Whether a tower's Prioritize toggle is set to air. Simulation rather than
## presentation - it changes what the server shoots - so the client is told
## rather than remembering its own click.
const FLAG_PRIORITIZE_AIR: int = 8
## Whether the morph running is a RETURN to an Elemental Core rather than an
## upgrade. Sent because the two are one phase with one clock and the panel
## calls them different things, so without it a client says a tower being
## reverted is being upgraded.
const FLAG_RETURNING: int = 16
## Whether a creep is DOWN waiting on a revive. Presentation on the server -
## hidden, with a shaft of light over the spot - and so invisible to a client
## until it was told, which is exactly what it looked like: a creep standing
## still on an empty health bar and then walking off again. A bit rather than a
## field, on a number the record already carried. See Creep.set_replicated_down.
const FLAG_DOWN: int = 64
## Whether a player has this unit in a FIGHT - whether an attack order is the
## task it is working on. Only the builder acts on it, and it has to be sent:
## an attack ordered onto a unit draws no marker, so it is not in the order
## chain a client is given and the client cannot work this out for itself. See
## AttackComponent.is_fighting_on_command.
const FLAG_FIGHTING_ON_COMMAND: int = 32

## How far a unit may move between two snapshots and still be DRAWN as having
## walked there, in player cells.
##
## A client runs no movement of its own: it writes whatever position the
## snapshot carries and lets the physics interpolator draw the gap. That is
## right for a creep walking a lane and wrong for one that JUMPED - a leak into
## the next maze, a tower built on top of a creep, a Harbinger taking its
## progress - where the same interpolation streaks it across the whole map in
## one tick.
##
## Worked out from the distance rather than sent as a flag, deliberately. The
## snapshot is UNRELIABLE, so a flag set for one tick is lost with the packet
## carrying it and the streak comes back - while a jump is still a jump in the
## next packet that does arrive. Nothing in the game covers this much ground in
## a tick under its own power, so anything that has must have been placed.
const TELEPORT_CELLS: float = 2.0

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

## SERVER: peer id -> the unit whose status effects that peer wants told.
##
## The one thing in phase A that is not "the whole world every tick", and it
## earns the exception: the debuff row draws for the ONE unit a player has
## selected, so this is at most a player's worth of records rather than a
## maze's. Pruned against the live peer list on every broadcast, so a peer that
## dropped stops being asked about.
var _watched: Dictionary = {}
## CLIENT: unit id -> Array[StatusEntry], the newest the server sent. Empty for
## anything but the unit this client asked about.
var _effects: Dictionary = {}
## The answer effects_for() hands back for a unit nothing was sent about, which
## is nearly every unit on nearly every call. Shared rather than built each
## time; see effects_for.
var _no_effects: Array[StatusEntry] = []
## CLIENT: the unit currently asked about, so the request goes out on a change
## of selection rather than every tick.
var _watching: int = MatchSession.NO_UNIT
## CLIENT: the units that had a drawn order chain in the LAST snapshot.
##
## A chain that is finished simply stops being in the block, the same way a
## dead unit stops being in the unit records - so something has to remember
## who was in it to notice who has dropped out and clear their markers.
var _ordered: Dictionary = {}

var _session: MatchSession:
	get:
		return References.match_session


func _ready() -> void:
	# Runs AFTER everything in the match scene, which is the whole point on the
	# server: a snapshot has to describe the tick that just finished, not the
	# one about to start. Autoloads sit above the scene in tree order, so
	# without this it would broadcast the world one tick stale.
	#
	# BOTH properties, and the second is the one that does the work here.
	# Godot 4.3 split the two callbacks apart: process_priority orders the
	# RENDER frame and process_physics_priority orders the TICK. This service
	# broadcasts from _physics_process, so on its own the line above ordered
	# something this class does not even implement, and the snapshot really was
	# a tick stale - exactly what the comment above says it must not be.
	process_priority = 1000
	process_physics_priority = 1000
	# And keeps running while the world is held still (StartingTech's draft):
	# a paused client is still told what the server can see, and the message
	# that ENDS the pause is the snapshot itself.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_physics_process(false)
	Net.status_changed.connect(_on_network_status_changed)


func _on_network_status_changed(_status: NetworkService.Status) -> void:
	# Nothing to send and nothing to receive while offline, which is also every
	# single player run.
	set_physics_process(Net.is_online())
	_applied_tick = -1
	_incoming.clear()
	_watched.clear()
	_effects.clear()
	_ordered.clear()
	_watching = MatchSession.NO_UNIT


func _physics_process(_delta: float) -> void:
	if _session == null:
		return
	# Asked BEFORE multiplayer.is_server(), which reaches get_unique_id() and
	# pushes "No multiplayer peer is assigned" once the peer is gone. That is
	# the window between leaving a match and the match scene being torn down,
	# and it errors every tick inside it. There is nothing to replicate off the
	# network in any case.
	if !Net.is_online():
		return
	if multiplayer.is_server():
		_broadcast()
		return
	_apply_incoming()


# --- leaks ----------------------------------------------------------------

## Says that a creep just took `lives` off `victim` and gave them to `thief`.
##
## Called by the AUTHORITY, once per leak, from where the leak actually happens
## - see Creep._reach_end. Raised locally whatever kind of run this is, so a
## single player game needs no network at all, and forwarded to every client
## when there is one.
##
## Sent to EVERYBODY rather than to the two players involved. Who is allowed to
## read a leak is a question about the HUD - a spectator watching the whole
## match sees every line of it, a player sees the ones they are in - and
## deciding it here would settle it for both.
##
## RELIABLE, unlike the snapshot beside it. A snapshot that goes missing is
## replaced 50 ms later by a complete one; a message that goes missing is
## simply never shown, and a player who was not told a life was taken has no
## other way to find out which of two things happened.
func report_leak(thief: int, victim: int, lives: int) -> void:
	if lives <= 0:
		return
	leak_reported.emit(thief, victim, lives)
	if Net.is_online() && multiplayer.is_server():
		receive_leak.rpc(thief, victim, lives)


@rpc("authority", "reliable")
func receive_leak(thief: int, victim: int, lives: int) -> void:
	if multiplayer.is_server():
		return
	leak_reported.emit(thief, victim, lives)


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
	var orders: PackedFloat32Array = PackedFloat32Array()
	for id in session.unit_ids():
		var unit: Unit = session.unit_for(int(id))
		if unit != null:
			units.append_array(_unit_record(unit))
			_append_orders(orders, unit)

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
					1 if state.creeps_unlocked else 0,
				])
				_append_techs(techs, state, slot)
			_append_stocks(stocks, manager, slot)

	return {
		"t": session.tick(), "u": units, "p": players, "s": stocks,
		"r": techs, "e": _build_effects(), "o": orders,
		"d": _draft_record(),
	}


## One unit's order chain, or nothing at all when it has none - which is every
## unit in a maze bar the handful somebody is steering.
##
## Written in the same pass that writes the unit records rather than in a
## second walk of the registry: the world is already being iterated once a
## tick, and this is one null check per unit on top of it.
func _append_orders(records: PackedFloat32Array, unit: Unit) -> void:
	if unit.order_queue == null:
		return

	var drawn: Array[QueuedOrder] = unit.order_queue.drawn_orders()
	if drawn.is_empty():
		return

	records.append_array([unit.unit_id, drawn.size()])
	for order: QueuedOrder in drawn:
		records.append_array([
			order.ability.ability_id,
			order.target_position.x, order.target_position.y,
			order.target_position.z,
		])


## The status effects on every unit some client is watching, in one flat array
## tagged by unit id.
##
## Distinct units rather than distinct peers: two players looking at the same
## creep are told about it once, and the snapshot is one broadcast rather than
## one packet per peer.
func _build_effects() -> PackedFloat32Array:
	var records: PackedFloat32Array = PackedFloat32Array()
	if _watched.is_empty():
		return records

	_prune_watchers()
	var session: MatchSession = _session
	var done: Dictionary = {}
	for peer in _watched:
		var id: int = int(_watched[peer])
		if done.has(id):
			continue
		done[id] = true
		var unit: Unit = session.unit_for(id)
		if unit == null:
			continue
		# Asked of the UNIT rather than cast to a Creep, which is what this was
		# and what kept two whole systems off the wire: a tower carries what a
		# creep has cursed it with and everything a technology disc lends it,
		# and neither reached a client at all. See Unit.status_entries().
		for entry in unit.status_entries():
			entry.append_to(records, id)
	return records


## Forgets whoever has left. A peer that disconnects never asks to stop
## watching, so the list is checked against the live one rather than being kept
## in step by a signal that a crash would skip.
func _prune_watchers() -> void:
	var live: PackedInt32Array = Net.peer_ids()
	var gone: Array = []
	for peer in _watched:
		if !live.has(int(peer)):
			gone.append(peer)
	for peer in gone:
		_watched.erase(peer)


## A client saying which unit's debuffs it needs. Reliable rather than
## unreliable, because it is sent once per change of selection and a lost one
## would leave that panel permanently empty rather than late by a tick.
@rpc("any_peer", "reliable")
func watch_unit(id: int) -> void:
	if !multiplayer.is_server():
		return
	var peer: int = multiplayer.get_remote_sender_id()
	if id == MatchSession.NO_UNIT:
		_watched.erase(peer)
	else:
		_watched[peer] = id


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
		if building.is_returning():
			flags |= FLAG_RETURNING
	var down_creep: Creep = unit as Creep
	if down_creep != null && down_creep.is_down():
		flags |= FLAG_DOWN
	if unit.attack_component != null:
		if unit.attack_component.prioritizes_air():
			flags |= FLAG_PRIORITIZE_AIR
		if unit.attack_component.is_fighting_on_command():
			flags |= FLAG_FIGHTING_ON_COMMAND

	# The two mana fields carry a CREEP's pool as well as a tower's now. Same
	# two floats either way, so nothing on the wire grew when the creeps that
	# run a trait on mana arrived - see CreepMana.
	var mana: Vector2i = _mana_of(unit, building)
	var shield: Vector2 = _shield_of(unit)

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
		mana.x,
		mana.y,
		0.0 if building == null else building.phase_progress(),
		0 if building == null else building.permanent_damage_bonus(),
		0 if building == null else building.ability_choice(),
		unit.active_ability.cooldown_left,
		unit.active_ability.link_id,
		shield.x,
		shield.y,
	])


## What this unit holds and the most it can hold, as (current, maximum).
##
## One question for both kinds, because the wire has one pair of fields for it.
## A unit with no second pool at all answers (0, 0), which a client reads back
## as "no bar".
func _mana_of(unit: Unit, building: Building) -> Vector2i:
	if building != null:
		return Vector2i(building.current_mana, building.max_mana)

	var creep: Creep = unit as Creep
	if creep == null || creep.mana() == null:
		return Vector2i.ZERO
	return Vector2i(creep.mana().current, creep.mana().maximum)


## The damage standing in front of this unit's health and the most that ever
## stood there, as (current, maximum). (0, 0) for anything unshielded, which a
## client reads back as "no bar".
##
## Asked of the unit rather than of its StatusEffects, so a shield granted some
## other way later is on the wire the moment the unit answers with it.
func _shield_of(unit: Unit) -> Vector2:
	return Vector2(unit.shield_points(), unit.shield_maximum())


## One player's whole technology state. Sent every tick like everything else in
## phase A, whether or not it changed - it is a handful of ints against a world
## of units, and being complete is what lets a client that missed a packet be
## corrected by the next one rather than reconciled.
func _append_techs(into: PackedInt32Array, state: PlayerState, slot: int) -> void:
	var ids: PackedInt32Array = state.tech.owned_ids()
	into.append_array([slot, state.tech.undo_ticks_left(), ids.size()])
	into.append_array(ids)


## The technology DRAFT, if one is running: which Ultimates are on offer and
## who has yet to take one. Empty in every other match, which is nearly all of
## them - the key costs one empty array a tick for the two seconds it is not.
##
## On the wire at all because a client rolls NOTHING (3.4). It could derive the
## same three Ultimates from the seed, and that is exactly the second
## simulation the rules forbid: it would agree until it did not, and the
## symptom would be three buttons the server refuses two of.
func _draft_record() -> PackedInt32Array:
	var draft: StartingTech = References.starting_tech
	if draft == null:
		return PackedInt32Array()
	return draft.draft_record()


func _apply_draft(record: PackedInt32Array) -> void:
	var draft: StartingTech = References.starting_tech
	if draft != null:
		draft.set_replicated_draft(record)


func _append_stocks(into: PackedInt32Array, manager: PlayerManager, slot: int) -> void:
	var area: PlayerArea = manager.area_for(slot)
	if area == null:
		return
	# Every building on the strip, flattened into one run of records. A reserve
	# is named by its CREEP TYPE rather than by which building or which square
	# it sits on, so which of them a creep belongs to never has to cross the
	# wire and re-laying the strip out cannot move somebody's stock.
	for building in area.send_buildings():
		for entry in building.stock_entries():
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

	# Before the units, deliberately: this is the one field that can say the
	# world is being held still, and a client that applied a world first and
	# learned it was paused afterwards would run a tick it should not have.
	_apply_draft(payload.get("d", PackedInt32Array()) as PackedInt32Array)
	_apply_units(payload.get("u", PackedFloat32Array()) as PackedFloat32Array)
	_apply_players(payload.get("p", PackedInt32Array()) as PackedInt32Array)
	_apply_stocks(payload.get("s", PackedInt32Array()) as PackedInt32Array)
	_apply_techs(payload.get("r", PackedInt32Array()) as PackedInt32Array)
	_apply_effects(payload.get("e", PackedFloat32Array()) as PackedFloat32Array)
	# After the units, necessarily: a chain names a unit, and one that arrived
	# in this same snapshot has to exist before anything can be hung off it.
	_apply_orders(payload.get("o", PackedFloat32Array()) as PackedFloat32Array)


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
	var to: Vector3 = Vector3(records[at + 4], records[at + 5], records[at + 6])
	# Placed rather than moved when the server put it somewhere it could not
	# have walked to. See TELEPORT_CELLS.
	if unit.global_position.distance_squared_to(to) > TELEPORT_CELLS * TELEPORT_CELLS:
		unit.teleport_to(to)
	else:
		unit.global_position = to
	unit.rotation.y = records[at + 7]
	unit.set_replicated_health(records[at + 8])

	var flags: int = int(records[at + 9])
	# Every unit carries one, since tier 4 put an aimed ability on a creep.
	unit.active_ability.set_replicated(records[at + 15], int(records[at + 16]))

	var building: Building = unit as Building
	if building != null:
		building.set_replicated_phase(
			(flags & FLAG_UNDER_CONSTRUCTION) != 0,
			(flags & FLAG_SELLING) != 0,
			(flags & FLAG_UPGRADING) != 0,
			(flags & FLAG_RETURNING) != 0,
			records[at + 12]
		)
		building.set_replicated_mana(int(records[at + 10]), int(records[at + 11]))
		building.replicated_damage_bonus = int(records[at + 13])
		building.replicated_ability_choice = int(records[at + 14])

	# The same two fields, read back onto whichever kind of pool this unit has.
	# The ceiling comes down the wire as well as the count, because one tier 4
	# trait raises its own - see CreepMana.raise_ceiling().
	var creep: Creep = unit as Creep
	if creep != null:
		creep.set_replicated_down((flags & FLAG_DOWN) != 0)
		if creep.mana() != null:
			creep.mana().maximum = maxi(0, int(records[at + 11]))
			creep.mana().set_replicated(int(records[at + 10]))

	unit.set_replicated_shield(records[at + 17], records[at + 18])

	if unit.attack_component != null:
		unit.attack_component.set_prioritize_air((flags & FLAG_PRIORITIZE_AIR) != 0)
		unit.attack_component.set_fighting_on_command(
			(flags & FLAG_FIGHTING_ON_COMMAND) != 0)


## A unit the server no longer has. Unregistered immediately rather than left
## to _exit_tree, because queue_free is deferred and the next snapshot would
## otherwise still find it and treat it as alive.
func _remove(id: int) -> void:
	var session: MatchSession = _session
	var unit: Unit = session.unit_for(id)
	session.unregister_unit(id)
	if unit != null:
		# The one thing a client can tell about a death without being sent
		# anything: a creep that was here last tick is gone. That is what a
		# bounty popup needs and it costs no wire field (3.3). It is also all
		# it can tell - a creep despawned for any other reason would pop the
		# same number, which today is only a leak with nowhere left to go.
		if unit is Creep:
			BountyPopup.show_for(unit)
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
				records[index + 4], records[index + 5], records[index + 6] != 0
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
		if area != null && stats != null:
			# Offered to every building; the one that does not hold this creep
			# ignores it. Cheaper than sending which building it was and
			# impossible to get wrong, since a creep is on exactly one card.
			for building in area.send_buildings():
				building.set_replicated_stock(stats, records[index + 2])
		index += STOCK_STRIDE


## Replaces what this client knows about every unit's debuffs.
##
## Rebuilt whole rather than merged, for the reason the unit list is: what
## arrived IS the answer, so a unit that has dropped off it has nothing on it
## any more and no removal message is needed to say so.
## Every unit's order chain, replaced whole; every unit that had one last tick
## and is not in this snapshot has its cleared. Same lifecycle the unit records
## have, and for the same reason - the snapshot is the complete answer, so
## absence IS the message that a chain is finished.
func _apply_orders(records: PackedFloat32Array) -> void:
	var session: MatchSession = _session
	var seen: Dictionary = {}

	var index: int = 0
	while index + ORDER_HEADER <= records.size():
		var id: int = int(records[index])
		var count: int = int(records[index + 1])
		index += ORDER_HEADER

		var chain: Array[QueuedOrder] = []
		for _entry: int in count:
			if index + ORDER_STRIDE > records.size():
				break
			var ability: UnitAbility = session.abilities().ability_for(int(records[index]))
			if ability != null:
				chain.append(QueuedOrder.replicated(ability, Vector3(
					records[index + 1], records[index + 2], records[index + 3]
				)))
			index += ORDER_STRIDE

		var unit: Unit = session.unit_for(id)
		if unit == null:
			continue
		seen[id] = true
		OrderQueue.of(unit).set_replicated(chain)

	var empty: Array[QueuedOrder] = []
	for id in _ordered:
		if seen.has(id):
			continue
		var gone: Unit = session.unit_for(int(id))
		# A unit that has been removed entirely takes its markers with it, so
		# only one that is still standing has anything left to clear.
		if gone != null && gone.order_queue != null:
			gone.order_queue.set_replicated(empty)
	_ordered = seen


func _apply_effects(records: PackedFloat32Array) -> void:
	_effects.clear()
	var index: int = 0
	while index + EFFECT_STRIDE <= records.size():
		var id: int = int(records[index])
		if !_effects.has(id):
			var fresh: Array[StatusEntry] = []
			_effects[id] = fresh
		var list: Array[StatusEntry] = _effects[id]
		list.append(StatusEntry.from_record(records, index))
		index += EFFECT_STRIDE


## Asks the server to keep this client told about one unit's debuffs, or about
## none when given NO_UNIT. Called by the panel as the selection changes.
##
## Does nothing at all on the authority, which reads the effects off the creep
## itself and has no server to ask.
func request_watch(id: int) -> void:
	if MatchSession.is_authority() || !Net.is_online():
		return
	if id == _watching:
		return
	_watching = id
	watch_unit.rpc_id(Net.SERVER_PEER_ID, id)


## The debuffs the server last reported on one unit. Empty on the authority,
## which has the real thing to read - see Unit.status_entries().
##
## The miss returns ONE SHARED EMPTY ARRAY rather than a fresh one. It used to
## be asked once per panel repaint, and is now asked by every tower on a client
## for its own reach, damage and attack speed - which is per tower per tick,
## against a dictionary that holds at most a handful of watched units. Building
## a throwaway array for each of those misses was the whole cost of the call.
##
## Safe to share only because nothing mutates what comes back: every reader
## folds it into a number or draws it. Kept as a constant-in-spirit `var`
## because GDScript cannot make a typed Array a const.
func effects_for(id: int) -> Array[StatusEntry]:
	var list: Array[StatusEntry] = _effects.get(id, _no_effects)
	return list


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
