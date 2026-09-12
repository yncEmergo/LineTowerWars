class_name MatchStats
extends Node

## Counts what happened in a match, so the end screen has something to show.
##
## A node in the match scene beside PlayerManager, reached through References.
## Not an autoload: it lives and dies with one match, exactly as the session and
## the economy do, and it receives no `@rpc` of its own.
##
## **It is not simulation and it is not replicated.** Nothing here is in the
## world checksum, nothing here refuses anything, and a machine that recorded
## none of it plays the identical match. That is deliberate, and it is what
## makes the counting safe to do wherever the event is raised rather than having
## to be threaded onto the wire.
##
## **Which machines count is decided by the model underneath.** Under LOCKSTEP -
## the shipped one - every peer is an authority and runs the same simulation, so
## every peer arrives at the same numbers without a byte being sent. Under the
## replication path the server is the only authority, so a client's own totals
## stay at zero; the end screen still draws the STANDINGS, which are replicated,
## and the per-player detail is blank. That is a known limit of a path kept only
## for load comparisons, and it is cheaper to write down than to replicate.
##
## The call sites are one line each and they live where the thing happens: a
## send in SendBuilding, a bounty in Creep, a build in Builder. Routing them
## through signals instead would mean a signal per counter on classes that have
## no other reason to carry one.

## How often the sampled figures - peak income, peak value - are re-read, in
## simulation ticks. A peak is not an event, so it has to be looked at rather
## than reported; half a second is far finer than any peak actually moves.
const SAMPLE_TICKS: int = 10

var _lines: Dictionary = {}
var _ticks: int = 0
## The summary, taken once when the match is decided and handed out unchanged
## afterwards. Null until then.
var _final: MatchSummary = null

var _players: PlayerManager:
	get:
		return References.player_manager

var _session: MatchSession:
	get:
		return References.match_session


func _ready() -> void:
	# Deferred for the reason PlayerStatsPanel's wiring is: the player states are
	# created in Main._ready, which runs after every child's _ready.
	_begin.call_deferred()


func _begin() -> void:
	var manager: PlayerManager = _players
	var session: MatchSession = _session
	if manager == null || session == null:
		Log.warn("MatchStats found no PlayerManager or MatchSession, nothing is recorded")
		return

	_lines.clear()
	for slot in range(1, session.player_count() + 1):
		var line: MatchStatLine = MatchStatLine.new()
		line.slot = slot
		line.display_name = session.display_name_for(slot)
		line.color_index = session.color_index_for(slot)
		line.is_local = session.is_local_player(slot)
		_lines[slot] = line

	manager.income_paid.connect(_on_income_paid)
	manager.match_ended.connect(_on_match_ended)


# --- what the match reports -----------------------------------------------

## One press of a send button that went through, with the pack it put out.
func record_send(player_id: int, creep_stats: CreepStats) -> void:
	var line: MatchStatLine = _line(player_id)
	if line == null || creep_stats == null:
		return
	line.sends += 1
	line.creeps_sent += creep_stats.pack_creep_count()
	line.gold_on_sends += creep_stats.gold_cost


## A creep that died in this defender's maze, and the bounty it paid them.
##
## The DEFENDER rather than whoever fired, which is the same rule the bounty
## itself follows: the area already knows who owns it, so no damage source has
## to be tracked for either.
func record_kill(defender_id: int, bounty: int) -> void:
	var line: MatchStatLine = _line(defender_id)
	if line == null:
		return
	line.creeps_killed += 1
	line.gold_from_bounty += maxi(0, bounty)


## A leak: `count` lives moved from the defender to the sender. Both ends are
## recorded, because a life is stolen rather than lost and the two players read
## the same event as two different numbers.
func record_leak(sender_id: int, defender_id: int, count: int) -> void:
	if count <= 0:
		return
	var thief: MatchStatLine = _line(sender_id)
	if thief != null:
		thief.lives_stolen += count
	var victim: MatchStatLine = _line(defender_id)
	if victim != null:
		victim.lives_lost += count


func record_tower_built(player_id: int, cost: int) -> void:
	var line: MatchStatLine = _line(player_id)
	if line == null:
		return
	line.towers_built += 1
	line.gold_on_towers += maxi(0, cost)


## A tower the player sold. The refund is deliberately NOT taken back off
## gold_on_towers: what that number answers is how much was committed to the
## field over the match, and a tower that stood for twenty minutes was bought
## whether or not it was eventually sold.
func record_tower_sold(player_id: int) -> void:
	var line: MatchStatLine = _line(player_id)
	if line != null:
		line.towers_sold += 1


## One rung of an upgrade that finished. Rungs rather than towers, because that
## is the number that says how far a maze has actually climbed - a player who
## took one tower to the top has spent as much as one who raised three a tier.
func record_tower_upgraded(player_id: int) -> void:
	var line: MatchStatLine = _line(player_id)
	if line != null:
		line.towers_upgraded += 1


## A tower an attacker creep brought down.
func record_tower_lost(player_id: int) -> void:
	var line: MatchStatLine = _line(player_id)
	if line != null:
		line.towers_lost += 1


## One research press, whatever it bought. `count` is how many technologies the
## press handed over - four for an Ultimate taken whole, one for a square.
func record_research(player_id: int, count: int, gold: int) -> void:
	var line: MatchStatLine = _line(player_id)
	if line == null:
		return
	line.technologies += maxi(0, count)
	line.gold_on_tech += maxi(0, gold)


## A press taken back inside its undo window. Removed rather than left standing,
## because an undone purchase never happened - which is the whole of what the
## window means.
func record_research_undone(player_id: int, count: int, gold: int) -> void:
	var line: MatchStatLine = _line(player_id)
	if line == null:
		return
	line.technologies = maxi(0, line.technologies - maxi(0, count))
	line.gold_on_tech = maxi(0, line.gold_on_tech - maxi(0, gold))


# --- the sampled figures --------------------------------------------------

## Income is paid to everybody on one beat, so it is counted from the beat
## rather than from each payment.
func _on_income_paid() -> void:
	var manager: PlayerManager = _players
	if manager == null:
		return
	for slot: int in _lines:
		var state: PlayerState = manager.state_for(slot)
		if state != null:
			(_lines[slot] as MatchStatLine).gold_from_income += state.income


func _physics_process(_delta: float) -> void:
	# Only a machine that runs the world has anything to sample. See the note at
	# the top about what that means under each model.
	if !MatchSession.is_authority() || _lines.is_empty():
		return

	_ticks += 1
	if _ticks < SAMPLE_TICKS:
		return
	_ticks = 0

	var manager: PlayerManager = _players
	if manager == null:
		return
	for slot: int in _lines:
		var state: PlayerState = manager.state_for(slot)
		if state == null:
			continue
		var line: MatchStatLine = _lines[slot]
		line.peak_income = maxi(line.peak_income, state.income)
		line.peak_value = maxi(line.peak_value, manager.value_for(slot))


# --- the summary ----------------------------------------------------------

## One player's totals AS THEY STAND, still moving.
##
## The tutorial reads this to answer "how many towers since this lesson opened",
## which is a subtraction against a mark it took itself. Nothing else should:
## what the end screen wants is the settled record, and that is summary().
func line_for(player_id: int) -> MatchStatLine:
	return _line(player_id)


## The finished record, taken the moment the match was decided. Null until it
## has been.
func summary() -> MatchSummary:
	return _final


## The finished record, settling one now if the match never reached an end -
## which is what a player leaving early gets.
##
## Emptied as it is handed over, so a second match in the same process cannot
## inherit the last one's numbers.
func take_summary() -> MatchSummary:
	if _final == null:
		_settle(0)
	var taken: MatchSummary = _final
	_final = null
	return taken


func _on_match_ended(winner_slot: int) -> void:
	_settle(winner_slot)


## Freezes everything and reads the standings off the player states, which are
## the authority on all of them - and which a client has correctly through
## replication even when it has counted nothing else.
func _settle(winner_slot: int) -> void:
	if _final != null:
		return

	var record: MatchSummary = MatchSummary.new()
	record.winner_slot = winner_slot

	var session: MatchSession = _session
	if session != null:
		record.duration_seconds = session.elapsed_seconds()
		record.reached_sudden_death = session.is_sudden_death()
		record.settings_text = session.settings().describe()
		if session.setup() != null:
			record.match_id = session.setup().match_id

	var manager: PlayerManager = _players
	var slots: Array = _lines.keys()
	slots.sort()
	for slot: Variant in slots:
		var line: MatchStatLine = _lines[slot]
		_read_standing(line, manager)
		_read_ultimates(line)
		record.lines.append(line)

	record.sort_by_placement()
	_final = record
	Log.info("Match summary taken", {
		"winner": winner_slot,
		"players": record.lines.size(),
		"length": record.duration_text(),
	})


func _read_standing(line: MatchStatLine, manager: PlayerManager) -> void:
	if manager == null:
		return
	var state: PlayerState = manager.state_for(line.slot)
	if state == null:
		return
	line.lives_left = maxi(0, state.lives)
	line.income = state.income
	line.peak_income = maxi(line.peak_income, state.income)
	line.value = state.value
	line.peak_value = maxi(line.peak_value, state.value)
	line.placement = state.placement


## Which Ultimate towers this player actually completed, worked out from what
## they own rather than recorded as it happened.
##
## Derived on purpose: an Ultimate is four technologies and there is no single
## press that means "I have finished one" - a draft pick, a random deal, a roll
## and four separate squares all arrive at the same place. Asking TechManager at
## the end is the one reading that cannot disagree with what a player has.
func _read_ultimates(line: MatchStatLine) -> void:
	var manager: TechManager = References.tech_manager
	var session: MatchSession = _session
	if manager == null || session == null:
		return

	for path: TechDefinition in session.techs().path_techs():
		if _owns_whole(manager, line.slot, path):
			line.ultimates.append(path.ultimate_name)


func _owns_whole(manager: TechManager, slot: int, path: TechDefinition) -> bool:
	var needed: Array[TechDefinition] = manager.ultimate_requirement(path)
	if needed.is_empty():
		return false
	for entry in needed:
		if !manager.owns(slot, entry.tech_id):
			return false
	return true


func _line(player_id: int) -> MatchStatLine:
	if !_lines.has(player_id):
		return null
	return _lines[player_id] as MatchStatLine
