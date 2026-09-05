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
	var digest: WorldDigest = WorldDigest.new()
	_add_setup(digest, setup)
	_add_rng(digest, session)
	_add_areas(digest, areas)
	_add_units(digest, session)
	_add_players(digest)
	return digest.result()


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
static func _add_rng(digest: WorldDigest, session: MatchSession) -> void:
	digest.key(&"rng")
	if session == null:
		digest.i(-1)
		return
	digest.i(int(session.rng().state))
	# **The match CLOCK, which nothing was comparing.** `tick()` is derived from
	# the engine's physics frame with the time spent held subtracted, not from the
	# turn number - so "the tick equals the turn minus whatever this peer paused
	# for" is an invariant that holds by construction and was never checked. It
	# drives creep unlocks and Sudden Death, so a peer whose clock slipped would
	# unlock a creep early and only report it later and indirectly, as position
	# drift with no obvious cause.
	digest.key(&"tick").i(session.tick())


static func _add_setup(digest: WorldDigest, setup: MatchSetup) -> void:
	digest.key(&"setup")
	if setup == null:
		digest.i(-1)
		return

	digest.text(setup.match_id).i(setup.rng_seed).i(setup.player_count())
	# In slot order rather than list order: the list is built from a roster and
	# two machines have no reason to agree on how it was sorted.
	for slot in range(1, setup.player_count() + 1):
		var player: MatchPlayer = setup.player_for(slot)
		digest.i(slot)
		if player == null:
			digest.i(-1)
			continue
		digest.text(player.display_name).i(player.network_id)

	var config: GameConfig = References.game_config
	if config != null:
		digest.key(&"start")
		digest.i(config.starting_gold).i(config.starting_income)
		digest.i(config.starting_lives(setup.player_count()))


## An area is a whole prefab, so its position and the shape of its grid are the
## two things a mismatch would show up in.
static func _add_areas(digest: WorldDigest, areas: Array[PlayerArea]) -> void:
	var by_slot: Dictionary = {}
	for area in areas:
		if area != null:
			by_slot[area.player_id] = area

	var slots: Array = by_slot.keys()
	slots.sort()
	for slot in slots:
		var area: PlayerArea = by_slot[slot] as PlayerArea
		digest.key(&"area").i(slot).vec(area.global_position)
		digest.i(area.internal_width()).i(area.internal_depth())
		digest.i(area.build_zone_first_row()).i(area.build_zone_row_end())


## By unit id, which is the name both machines call a unit by (0.4). Walking
## the registry rather than the scene tree is the point: if the ids were handed
## out in a different order, the same units land under different keys and the
## checksum says so.
static func _add_units(digest: WorldDigest, session: MatchSession) -> void:
	digest.key(&"units")
	if session == null:
		digest.i(-1)
		return

	var ids: Array = session.unit_ids()
	digest.i(ids.size())
	for id in ids:
		var unit: Unit = session.unit_for(int(id))
		digest.i(int(id))
		if unit == null:
			digest.i(-1)
			continue
		var stats_name: String = "-" if unit.stats == null else unit.stats.resource_path
		# Identity, place, and then whatever the UNIT says about itself. That
		# last part is virtual on purpose: a checksum that reached in here for
		# each field would go blind the day somebody adds a resource and does
		# not think of this file. See Unit.checksum_state.
		digest.i(unit.owner_player_id).text(stats_name)
		digest.vec(unit.global_position)
		unit.checksum_state(digest)


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
static func _add_players(digest: WorldDigest) -> void:
	digest.key(&"players")
	var manager: PlayerManager = References.player_manager
	if manager == null:
		digest.i(-1)
		return

	for state: PlayerState in manager.states_in_slot_order():
		digest.i(state.player_id).i(state.gold).i(state.income).i(state.lives)



