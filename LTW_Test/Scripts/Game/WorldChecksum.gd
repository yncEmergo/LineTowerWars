class_name WorldChecksum

## One number describing the world a machine has just built, so two machines
## can find out in one message whether they built the same one (2.5).
##
## Cheap insurance against a whole class of bug that is otherwise found by a
## player: two clients that start from the same `MatchSetup` and quietly place
## a building one cell apart, or hand out unit ids in a different order, will
## diverge from their very first tick and look fine doing it.
##
## **local_slot is deliberately not in it.** It is the one field of a setup that
## is SUPPOSED to differ per machine, and a server plays no slot at all. What is
## checksummed is only what every machine must agree on.
##
## **Positions are compared EXACTLY, bit for bit.** They used to be rounded to
## the nearest millimetre, on the reasoning that two machines agreeing to within
## a millionth of a unit agree. That reasoning belongs to a replicated world,
## where a client's copy is an approximation of the server's and a tolerance is
## the only sane way to compare them.
##
## Under lockstep it is exactly backwards. Two peers run the same arithmetic on
## the same inputs, so they agree to the last bit or they have ALREADY diverged
## and are going to keep diverging. A millimetre of slack does not absorb that,
## it only delays the report until the drift is big enough to cross the rounding
## - by which time the tick that caused it is thousands of ticks back and the
## trail is cold. The tolerance was buying nothing and costing the early warning.
##
## `SCALE` survives for the values that are still quantised: health, cooldowns,
## construction progress and the aura fields, all of them reached through the
## `checksum_state()` virtual on the units themselves. Those want the same
## treatment and it is a wider change - three classes override that method - so
## it is deliberately left for the checksum rewrite rather than done halfway
## here.

## The quantisation step for the values that are still rounded. See above.
const SCALE: float = 1000.0


## The checksum of a freshly built match. Everything it walks was created from
## the setup, in the order the setup gave, which is exactly the claim being
## tested.
static func of(setup: MatchSetup, areas: Array[PlayerArea], session: MatchSession) -> int:
	var parts: PackedStringArray = PackedStringArray()
	_add_setup(parts, setup)
	_add_rng(parts, session)
	_add_areas(parts, areas)
	_add_units(parts, session)
	_add_players(parts)
	return "|".join(parts).hash()


## The match generator's own position in its stream.
##
## **The single most valuable thing in this file, and it was missing.** Every
## other entry here is an EFFECT - a position, a health, a gold total - so a
## divergence only shows up once it has moved something a player could see, and
## by then the tick it started on is long gone. The generator's state is the
## CAUSE: two peers that have drawn a different NUMBER of times disagree here on
## the very turn it happened, whether or not the draw has changed anything yet.
##
## It is also the check that finds the likeliest desync there is. Every roll in
## the simulation goes through `MatchSession.match_rng()` and every presentation
## path is supposed to use the global `randf()` instead; the instant one of them
## gets that backwards, one machine draws and the others do not, and this says so
## immediately instead of surfacing as half a millimetre of position a minute
## later.
static func _add_rng(parts: PackedStringArray, session: MatchSession) -> void:
	if session == null:
		parts.append("rng:none")
		return
	parts.append("rng:%d" % session.rng().state)


static func _add_setup(parts: PackedStringArray, setup: MatchSetup) -> void:
	if setup == null:
		parts.append("setup:none")
		return

	parts.append("match:%s" % setup.match_id)
	parts.append("seed:%d" % setup.rng_seed)
	parts.append("players:%d" % setup.player_count())
	# In slot order rather than list order: the list is built from a roster and
	# two machines have no reason to agree on how it was sorted.
	for slot in range(1, setup.player_count() + 1):
		var player: MatchPlayer = setup.player_for(slot)
		if player == null:
			parts.append("p%d:missing" % slot)
			continue
		parts.append("p%d:%s:%d" % [slot, player.display_name, player.network_id])

	var config: GameConfig = References.game_config
	if config != null:
		parts.append("gold:%d" % config.starting_gold)
		parts.append("income:%d" % config.starting_income)
		parts.append("lives:%d" % config.starting_lives(setup.player_count()))


## An area is a whole prefab, so its position and the shape of its grid are the
## two things a mismatch would show up in.
static func _add_areas(parts: PackedStringArray, areas: Array[PlayerArea]) -> void:
	var by_slot: Dictionary = {}
	for area in areas:
		if area != null:
			by_slot[area.player_id] = area

	var slots: Array = by_slot.keys()
	slots.sort()
	for slot in slots:
		var area: PlayerArea = by_slot[slot] as PlayerArea
		parts.append("area%d:%s:%dx%d:%d-%d" % [
			slot,
			_point(area.global_position),
			area.internal_width(),
			area.internal_depth(),
			area.build_zone_first_row(),
			area.build_zone_row_end(),
		])


## By unit id, which is the name both machines call a unit by (0.4). Walking
## the registry rather than the scene tree is the point: if the ids were handed
## out in a different order, the same units land under different keys and the
## checksum says so.
static func _add_units(parts: PackedStringArray, session: MatchSession) -> void:
	if session == null:
		parts.append("units:none")
		return

	var ids: Array = session.unit_ids()
	parts.append("units:%d" % ids.size())
	for id in ids:
		var unit: Unit = session.unit_for(int(id))
		if unit == null:
			parts.append("u%d:missing" % id)
			continue
		var stats_name: String = "-" if unit.stats == null else unit.stats.resource_path
		# Identity, place, and then whatever the UNIT says about itself. That
		# last part is virtual on purpose: a checksum that reached in here for
		# each field would go blind the day somebody adds a resource and does
		# not think of this file. See Unit.checksum_state.
		parts.append("u%d:%d:%s:%s:%s" % [
			id,
			unit.owner_player_id,
			stats_name,
			_point(unit.global_position),
			unit.checksum_state(),
		])


## What each player OWNS, which is half of what a match is and none of which is
## visible in the units above.
##
## In slot order, for the same reason the setup is: a slot is the lane, every
## machine numbers them identically, and a Dictionary's own order is not
## something two machines are entitled to agree on.
##
## MANA is deliberately absent. It lives on `Building` and `Creep` rather than
## on `Unit`, so reaching it needs a cast - and a cast on exactly this kind of
## walk is what silently kept three whole systems off the wire once already
## (`CLAUDE.md`, known weaknesses). If mana is wanted here, it wants a virtual
## on `Unit` first, the way `status_entries()` had to become one.
static func _add_players(parts: PackedStringArray) -> void:
	var manager: PlayerManager = References.player_manager
	if manager == null:
		parts.append("players:none")
		return

	for state: PlayerState in manager.states_in_slot_order():
		parts.append("s%d:%d:%d:%d" % [
			state.player_id, state.gold, state.income, state.lives,
		])


## One position, as the exact bits of its three components.
##
## `PackedFloat64Array` rather than 32 so this is right under a double-precision
## build as well: a component that is really a float32 widens to a double without
## losing anything, and one that is really a double keeps every bit. Either way
## both peers run the same build, so both take the same branch.
static func _point(position: Vector3) -> String:
	var bytes: PackedByteArray = PackedFloat64Array([
		position.x, position.y, position.z,
	]).to_byte_array()
	return "%d,%d,%d" % [
		bytes.decode_u64(0), bytes.decode_u64(8), bytes.decode_u64(16),
	]
