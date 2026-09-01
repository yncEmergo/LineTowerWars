class_name StartingTech
extends Node

## How a match HANDS OUT its opening technology, which is the whole of what
## MatchSettings.TechMode decides.
##
## Three answers, and only two of them do anything here:
##
##   PICK    the player spends their free technologies themselves, whenever
##           they like. Nothing happens - it is the game as it was.
##   RANDOM  one Ultimate is rolled for the whole match and handed to
##           everybody, so every player opens on the same tower.
##   DRAFT   three Ultimates are rolled for the whole match, every player is
##           shown the same three, and **the world is held still until they
##           have all chosen**.
##
## A node in the match scene next to TechManager, reached through References,
## and NOT an autoload: it receives no `@rpc` of its own. A draft pick is an
## ordinary player order and travels the road every other one takes - through
## `Commands`, checked for who sent it, applied here - exactly as a Research
## Center press does.
##
## **What it owns is which Ultimates, and who has not chosen yet.** What that
## costs the record is TechManager's, in the same way a research press is: this
## calls grant_ultimate and holds none of the rules about prices or history.
##
## THE ROLL IS THE AUTHORITY'S, and the options ride down to clients in the
## snapshot rather than being rolled again there (3.4). Both machines could
## derive the same three from the seed, and that is exactly the kind of second
## simulation the rules forbid: it would agree until the day it did not, and
## the symptom would be a client drawing three buttons the server refuses two
## of.

## Either half of the draft changed: which Ultimates are offered, or who is
## still to choose. One signal rather than two, because the screen that listens
## redraws whole either way.
signal draft_changed()

## Given back by pick() when it went through. Same convention as TechManager,
## so a caller reads one kind of answer from both.
const ALLOWED: String = ""

var _options: Array[TechDefinition] = []
## Slots that still have to choose. A player is in here exactly while the match
## is waiting on them, so this doubles as "is a draft running".
var _pending: PackedInt32Array = PackedInt32Array()

var _session: MatchSession:
	get:
		return References.match_session


func _ready() -> void:
	# A player who leaves during the draft is not somebody to keep waiting for.
	# Without this, one crashed client holds every other player in a paused
	# world for the rest of the match.
	MatchStart.player_dropped.connect(_on_player_dropped)


## Deals the opening. Called by Main once the world is built and the technology
## registry exists, on every machine - a client reaches the DRAFT branch and
## nothing else, because everything that grants anything is the authority's.
func apply(setup: MatchSetup) -> void:
	if setup == null || setup.settings == null:
		return

	match setup.settings.tech_mode:
		MatchSettings.TechMode.RANDOM:
			_deal_one_ultimate()
		MatchSettings.TechMode.DRAFT:
			_begin_draft(setup)
		_:
			return


## Whether the match is waiting on somebody's choice. What holds the world
## still, and what the draft screen is shown for.
func is_drafting() -> bool:
	return !_pending.is_empty()


## The Ultimates on offer, in the order they are drawn. Empty unless a draft is
## running, and briefly empty on a client that is paused and has not had its
## first snapshot yet.
func options() -> Array[TechDefinition]:
	return _options


## Whether the player at this client is one of the ones still to choose.
func needs_local_pick() -> bool:
	var session: MatchSession = _session
	if session == null:
		return false
	return _pending.has(session.local_slot())


## How many players the match is still waiting on, for the line the draft
## screen shows once you have chosen and somebody else has not.
func pending_count() -> int:
	return _pending.size()


## One player choosing their Ultimate. The far end of the road their button
## press took, called by CommandService once it knows who is asking - never
## called by anything a player touches.
##
## Returns the reason it was refused, or ALLOWED, exactly as TechManager's
## orders do.
func pick(player_id: int, tech_id: int) -> String:
	if !is_drafting():
		return "there is no draft running"
	if !_pending.has(player_id):
		return "you have already chosen"

	var chosen: TechDefinition = _option_for(tech_id)
	if chosen == null:
		return "that Ultimate is not one of the three on offer"

	var manager: TechManager = References.tech_manager
	if manager == null:
		return "this scene has no TechManager"

	var reason: String = manager.grant_ultimate(player_id, chosen)
	if reason != TechManager.ALLOWED:
		return reason

	_pending = _without(player_id)
	Log.info("Draft pick", {
		"player": player_id,
		"ultimate": chosen.ultimate_name,
		"waiting_on": _pending.size(),
	})
	_settle()
	return ALLOWED


## The draft as it goes on the wire: how many Ultimates are on offer, those
## ids, then the slots still to choose. Empty when no draft is running, which
## is every tick of nearly every match.
##
## Self-describing rather than two fields, for the reason the technology block
## already is: both halves are a different length every time and they are read
## back together or not at all.
func draft_record() -> PackedInt32Array:
	if !is_drafting():
		return PackedInt32Array()

	var record: PackedInt32Array = PackedInt32Array([_options.size()])
	for tech in _options:
		record.append(tech.tech_id)
	record.append_array(_pending)
	return record


## The same record, arriving on a client. Set rather than worked out: the roll
## is the server's and so is the count of who is left, and a client that
## derived either would be running a second simulation of the opening.
func set_replicated_draft(record: PackedInt32Array) -> void:
	var options: Array[TechDefinition] = []
	var pending: PackedInt32Array = PackedInt32Array()

	if record.size() >= 1:
		var count: int = clampi(record[0], 0, record.size() - 1)
		var registry: TechRegistry = _registry()
		for index in range(1, count + 1):
			var tech: TechDefinition = null if registry == null \
				else registry.tech_for(record[index])
			if tech != null:
				options.append(tech)
		for index in range(count + 1, record.size()):
			pending.append(record[index])

	if _same_as(options, pending):
		return
	_options = options
	_pending = pending
	_settle()


# --- the two modes --------------------------------------------------------

## RANDOM: one Ultimate for the whole match, handed to every player.
##
## Rolled once and given to everybody rather than rolled per player, which is
## the rule - the point of the mode is that everyone opens on the same tower
## and the match is about playing it rather than about who drew better.
func _deal_one_ultimate() -> void:
	if !MatchSession.is_authority():
		return

	var paths: Array[TechDefinition] = _path_techs()
	if paths.is_empty():
		Log.err("Random technology mode has no Ultimates to roll, nobody is given one")
		return

	var chosen: TechDefinition = paths[_rng().randi_range(0, paths.size() - 1)]
	var manager: TechManager = References.tech_manager
	if manager == null:
		Log.err("Random technology mode found no TechManager, nobody is given one")
		return

	Log.info("Random Ultimate for the whole match", chosen.ultimate_name)
	for slot in _slots():
		var reason: String = manager.grant_ultimate(slot, chosen)
		if reason != TechManager.ALLOWED:
			Log.err("Could not hand a player the match Ultimate", {
				"player": slot, "why": reason,
			})


## DRAFT: three Ultimates for the whole match, and the world held still until
## everybody has taken one.
##
## A CLIENT reaches this too, and does exactly one thing with it: it stops. It
## rolls nothing and knows nothing yet - the three on offer and who is left
## arrive in the next snapshot - but it must not run a single tick ahead of a
## server that is already waiting, or its match clock would be ahead of the
## server's for the rest of the game.
func _begin_draft(setup: MatchSetup) -> void:
	_pending = PackedInt32Array()
	for player in setup.players:
		if player != null:
			_pending.append(player.slot)

	if !MatchSession.is_authority():
		_settle()
		return

	_options = _roll_options()
	if _options.is_empty():
		Log.err("Draft technology mode has no Ultimates to offer, it is skipped")
		_pending = PackedInt32Array()
		return

	var names: Array[String] = []
	for tech in _options:
		names.append(tech.ultimate_name)
	Log.info("Draft opened", {"options": names, "players": _pending.size()})
	_settle()


## The three on offer, drawn without replacement so nobody is shown the same
## Ultimate twice. Fewer than three when the build contains fewer.
func _roll_options() -> Array[TechDefinition]:
	var pool: Array[TechDefinition] = _path_techs()
	var chosen: Array[TechDefinition] = []
	var rng: RandomNumberGenerator = _rng()
	while !pool.is_empty() && chosen.size() < MatchSettings.DRAFT_OPTIONS:
		var index: int = rng.randi_range(0, pool.size() - 1)
		chosen.append(pool[index])
		pool.remove_at(index)
	return chosen


# --- holding the world still ---------------------------------------------

## Puts the pause where the draft is, and tells whatever draws it.
##
## One place both machines end up in, whichever direction they came from - the
## authority from a pick it just applied, a client from the snapshot that told
## it about one - so there is exactly one line that decides whether the world
## is moving.
func _settle() -> void:
	var session: MatchSession = _session
	if session != null:
		session.set_paused(is_drafting())
	draft_changed.emit()


## A player who left is not one to keep waiting for (D13). Their slot simply
## stops being outstanding, and if they were the last one the match starts.
func _on_player_dropped(slot: int) -> void:
	if !_pending.has(slot):
		return
	_pending = _without(slot)
	Log.info("Draft no longer waiting on a player who left", slot)
	_settle()


# --- lookups --------------------------------------------------------------

## The one shared match RNG, so a server rolling the opening rolls from the
## same stream everything else in the match does and the seed in the log is
## the whole story.
func _rng() -> RandomNumberGenerator:
	return MatchSession.match_rng()


func _registry() -> TechRegistry:
	var session: MatchSession = _session
	return null if session == null else session.techs()


## Every technology that leads to an Ultimate, ascending by id - the registry's
## own order, which is stable across machines by construction.
func _path_techs() -> Array[TechDefinition]:
	var registry: TechRegistry = _registry()
	if registry == null:
		return []
	return registry.path_techs()


func _slots() -> Array:
	var session: MatchSession = _session
	if session == null:
		return []
	var slots: Array = []
	for slot in range(1, session.player_count() + 1):
		slots.append(slot)
	return slots


func _option_for(tech_id: int) -> TechDefinition:
	for tech in _options:
		if tech.tech_id == tech_id:
			return tech
	return null


func _without(slot: int) -> PackedInt32Array:
	var left: PackedInt32Array = PackedInt32Array()
	for entry in _pending:
		if entry != slot:
			left.append(entry)
	return left


## Whether an arriving record says anything this one does not already know.
## The snapshot repeats it twenty times a second, and rebuilding the screen off
## every one of them would be the only work this class ever did.
func _same_as(options: Array[TechDefinition], pending: PackedInt32Array) -> bool:
	if options.size() != _options.size() || pending.size() != _pending.size():
		return false
	for index in range(options.size()):
		if options[index] != _options[index]:
			return false
	for index in range(pending.size()):
		if pending[index] != _pending[index]:
			return false
	return true
