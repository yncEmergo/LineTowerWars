class_name TutorialDirector
extends Node

## Runs the tutorial: which lesson is open, what it has handed over, and what
## has happened since it opened.
##
## A node in the match scene beside PlayerManager, reached through References.
## It does nothing at all unless the match says it is a TUTORIAL, so it sits in
## the ordinary match scene rather than in one of its own - which is the point:
## **the tutorial is a real match**. The same world, the same economy, the same
## towers and the same opponent machinery, with a script on top telling somebody
## what to press. A separate scene would be a second game to keep working.
##
## **It counts what has happened SINCE the current lesson opened**, and every
## step asks it rather than the world. That is what makes the lessons
## independent of the systems they teach: nothing in the builder, the sender or
## the Research Center knows a tutorial exists, and adding a lesson about
## something new is a step subclass and a counter here rather than a hook in the
## thing being taught.
##
## The counters come off `MatchStats`, which is already counting all of it for
## the end screen - so a lesson that asks "have they built three towers" is
## reading a number that was going to be kept anyway. What this holds is only
## the mark: what those totals were when the lesson opened.

## The lesson changed - opened, finished, or the whole tutorial ended. One
## signal rather than three, because the panel that listens redraws whole.
signal lesson_changed()

## The name this holds the world still by. Its own rather than the draft's, so
## the two can overlap without either releasing the other - see MatchSession.
const HOLD_REASON: StringName = &"tutorial"

@export_group("Settings")
## The lessons, in teaching order.
@export var script_resource: TutorialScript

var _index: int = -1
var _step: TutorialStep = null
## Simulation seconds the current lesson has been open.
var _elapsed: float = 0.0
## Whether the player has pressed Continue on the current lesson.
var _acknowledged: bool = false
## What the running totals were when the lesson opened, so everything a step
## asks is "since this lesson" rather than "ever".
var _mark: MatchStatLine = null
var _running: bool = false

var _session: MatchSession:
	get:
		return References.match_session


func _ready() -> void:
	# Immune to the pause it causes itself, for the reason StartingTech is: the
	# thing that ENDS a held lesson runs here, and would never run if it stopped
	# with the world.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_physics_process(false)


## Starts the tutorial, or does nothing at all. Called by Main once the world
## is built, in every match.
##
## **The mode is the whole gate.** A multiplayer match and a skirmish reach this
## line and leave, which is what lets the director live in the ordinary match
## scene without costing them anything.
func begin(setup: MatchSetup) -> void:
	if setup == null || setup.mode != MatchSetup.Mode.TUTORIAL:
		return
	if script_resource == null:
		Log.err("The tutorial has no script, there are no lessons to teach")
		return
	if !script_resource.validate():
		Log.err("The tutorial script is not usable, see the errors above")
		return

	_running = true
	set_physics_process(true)
	Log.info("Tutorial started", {"lessons": script_resource.count()})
	_open(0)


## Whether a tutorial is being played at all, for the panel that draws it.
func is_running() -> bool:
	return _running && _step != null


## The lesson on screen, or null once the tutorial is over.
func current_step() -> TutorialStep:
	return _step


## Which lesson this is and how many there are, for the "3 of 14" a panel draws.
func lesson_number() -> int:
	return _index + 1


func lesson_count() -> int:
	return 0 if script_resource == null else script_resource.count()


## Whether the player may be offered a way past the current lesson yet.
##
## The anti-softlock rule, and the panel asks it every frame. See
## TutorialStep.skip_after_seconds for why it is not optional.
func may_skip() -> bool:
	if _step == null:
		return false
	return _elapsed >= maxf(0.0, _step.skip_after_seconds)


## Seconds the current lesson has been open.
##
## It runs while the world is HELD, and it has to: a lesson that is only read
## holds the world for the whole time it is up, and the way past it - the skip
## the anti-softlock rule promises - is measured in exactly this number. A clock
## that stopped with the world would make every read lesson unskippable.
func seconds_on_step() -> float:
	return _elapsed


# --- what the lessons ask -------------------------------------------------

## Whether the player has pressed Continue on the lesson that is open.
func was_acknowledged() -> bool:
	return _acknowledged


## Towers this player has put up since the lesson opened.
func towers_built_this_step() -> int:
	return _since(func(line: MatchStatLine) -> int: return line.towers_built)


func upgrades_this_step() -> int:
	return _since(func(line: MatchStatLine) -> int: return line.towers_upgraded)


func sends_this_step() -> int:
	return _since(func(line: MatchStatLine) -> int: return line.sends)


func kills_this_step() -> int:
	return _since(func(line: MatchStatLine) -> int: return line.creeps_killed)


## How many technologies the player owns in total.
##
## In TOTAL rather than since the lesson opened, unlike everything above, and
## the difference is real: research can be UNDONE inside its window, so a count
## of presses would let a player finish a lesson by buying something and giving
## it straight back. What the lesson is about is owning one.
func technologies_owned() -> int:
	var state: PlayerState = _local_state()
	return 0 if state == null else state.tech.owned_count()


## One counter's movement since the lesson opened.
##
## Reads MatchStats, which is already keeping every one of these for the end
## screen - so a lesson costs a subtraction rather than a second set of hooks
## into the systems it is teaching.
func _since(read: Callable) -> int:
	var line: MatchStatLine = _live_line()
	if line == null || _mark == null:
		return 0
	return maxi(0, int(read.call(line)) - int(read.call(_mark)))


# --- running --------------------------------------------------------------

## Simulation, so a lesson's clock runs on the same beat the world does. It
## keeps running while the world is held - see seconds_on_step.
func _physics_process(_engine_delta: float) -> void:
	if !_running || _step == null:
		return
	_elapsed += MatchSession.tick_seconds()
	if _step.is_complete(self):
		advance()


## The player pressed Continue. What finishes a lesson that is only read, and
## what is ignored by every other kind - a step decides for itself whether an
## acknowledgement means anything.
func acknowledge() -> void:
	_acknowledged = true


## Past this lesson whether or not it was finished. The panel's way out, offered
## once skip_after_seconds has passed.
##
## The same call as finishing it, deliberately: a skipped lesson has still
## handed over its gold and switched on whatever it switches on, because the one
## that comes after it was written assuming the one before happened.
func skip() -> void:
	if _step != null:
		Log.info("Tutorial lesson skipped", {"lesson": lesson_number(),
			"title": _step.title})
	advance()


## On to the next lesson, or to the end of the tutorial.
func advance() -> void:
	if !_running:
		return
	_open(_index + 1)


func _open(index: int) -> void:
	_index = index
	_step = null if script_resource == null else script_resource.step_at(index)
	_elapsed = 0.0
	_acknowledged = false

	if _step == null:
		_finish()
		return

	_mark = _snapshot_line()
	_apply_grants(_step)
	_step.on_enter(self)
	# After the grants, so a lesson that hands over gold does it before the
	# world stops rather than on the frame it starts again.
	_hold(_step.pauses_world)
	Log.info("Tutorial lesson", {
		"lesson": lesson_number(), "of": lesson_count(), "title": _step.title,
	})
	lesson_changed.emit()


func _finish() -> void:
	_running = false
	set_physics_process(false)
	_hold(false)
	Log.info("Tutorial finished")
	lesson_changed.emit()


## What a lesson hands over the moment it opens.
##
## Applied through the ordinary calls rather than through the command road, and
## the reason is worth stating: this is not a player ORDER, it is the tutorial
## being the rules. A lesson handing out gold is closer to a match's starting
## gold than to a cheat somebody pressed, and routing it as an order would mean
## inventing a command nothing else would ever use.
##
## The tutorial is offline by construction - it is a game mode with one player
## in it - so there is no authority to ask and nobody to disagree with.
func _apply_grants(step: TutorialStep) -> void:
	var state: PlayerState = _local_state()
	if state != null:
		if step.grant_gold > 0:
			state.gain(step.grant_gold)
		if step.grant_income > 0:
			state.add_income(step.grant_income)
		if step.unlocks_creeps:
			_unlock_creeps(state)

	_draw_blueprint(step.blueprint())


## Opens the whole send card for the player: every creep's start delay counts as
## served, and every reserve is filled to go with it.
##
## The same two halves the developer cheat throws, for the same reason it throws
## both: a card that is open and empty is not an open card. See
## CommandService._apply_cheat_unlock_creeps, which this deliberately mirrors
## rather than calls - that one is an order with an authority behind it, and
## this is the tutorial setting the board up.
func _unlock_creeps(state: PlayerState) -> void:
	state.creeps_unlocked = true
	var manager: PlayerManager = References.player_manager
	if manager == null:
		return
	var area: PlayerArea = manager.area_for(state.player_id)
	if area == null:
		return
	for building in area.send_buildings():
		building.fill_all_stocks()


## Puts a saved plan on the ground, or takes one off.
##
## The overlay is PRESENTATION and local from end to end, which is exactly what
## the tutorial wants from it: a blue square on every cell still to build on,
## disappearing as each is filled. It says where without ordering anything and
## without taking the mouse off the player.
##
## It is the SAME overlay the builder's own Show Blueprint command drives, so a
## player who puts one up themselves and a lesson that puts one up for them are
## using one thing. A lesson that names no slot takes whatever is up down, which
## is what stops the last lesson's plan hanging around over the next one.
func _draw_blueprint(plan: TowerLayout) -> void:
	var overlay: BlueprintOverlay = References.blueprint_overlay
	if overlay == null:
		return
	if plan == null:
		overlay.hide_blueprint()
		return
	overlay.show_layout(plan)


# --- lookups --------------------------------------------------------------

## Holds the world still for a lesson, or lets it go.
##
## Its own holder name, so a lesson and a technology draft can overlap without
## either releasing the other - which is the whole reason MatchSession.hold
## takes a name rather than a bool.
func _hold(held: bool) -> void:
	var session: MatchSession = _session
	if session != null:
		session.hold(HOLD_REASON, held)


func _local_state() -> PlayerState:
	var manager: PlayerManager = References.player_manager
	return null if manager == null else manager.local_state()


## The player's live totals, still moving.
func _live_line() -> MatchStatLine:
	var stats: MatchStats = References.match_stats
	var manager: PlayerManager = References.player_manager
	if stats == null || manager == null:
		return null
	return stats.line_for(manager.local_player_id())


## A COPY of those totals, taken when a lesson opens so everything asked
## afterwards is "since then".
##
## A copy and not a reference, obviously - but worth the line, because the thing
## being copied is the very object that goes on being written to.
func _snapshot_line() -> MatchStatLine:
	var line: MatchStatLine = _live_line()
	if line == null:
		return MatchStatLine.new()
	return line.duplicate() as MatchStatLine
