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
## Floats are quantised to a thousandth of a unit before hashing, because a
## checksum over raw floats compares bit patterns rather than positions - and
## two machines that agree to within a millionth of a unit agree.

## The quantisation step: positions are compared to the nearest millimetre.
const SCALE: float = 1000.0


## The checksum of a freshly built match. Everything it walks was created from
## the setup, in the order the setup gave, which is exactly the claim being
## tested.
static func of(setup: MatchSetup, areas: Array[PlayerArea], session: MatchSession) -> int:
	var parts: PackedStringArray = PackedStringArray()
	_add_setup(parts, setup)
	_add_areas(parts, areas)
	_add_units(parts, session)
	return "|".join(parts).hash()


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
		parts.append("u%d:%d:%s:%s" % [
			id, unit.owner_player_id, stats_name, _point(unit.global_position),
		])


static func _point(position: Vector3) -> String:
	return "%d,%d,%d" % [
		roundi(position.x * SCALE), roundi(position.y * SCALE), roundi(position.z * SCALE),
	]
