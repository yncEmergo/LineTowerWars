class_name TutorialDirector
extends Node

## Runs the tutorial: which lesson is open, what it has handed over, what the
## player may do while it is up, and what has happened since it opened.
##
## A node in the match scene beside PlayerManager, reached through References.
## It does nothing at all unless the match says it is a TUTORIAL, so it sits in
## the ordinary match scene rather than in one of its own - which is the point:
## **the tutorial is a real match**. The same world, the same economy, the same
## towers and the same opponent machinery, with a script on top telling somebody
## what to press. A separate scene would be a second game to keep working.
##
## **The shape of the match it runs, which the lessons are written against:**
##
##   THE OPENING IS HELD. The first lessons hold the match clock, hand over
##   exactly the gold their task costs, and allow only the one thing they ask
##   for - build these towers on these cells, send these four creeps. No
##   income, no creep unlocking, nothing refilling, and all the time in the
##   world. See TutorialStep, "What it allows".
##
##   THEN IT IS A MATCH. Once the basics are done the clock runs, the limits
##   come off, and the first opponent is WOKEN: it stops sparring and plays its
##   real profile. The lesson ends when it is beaten.
##
##   THEN A SECOND ONE. It has been in the match since the start, building a
##   maze on STANDBY outside the send ring, so the first half was a plain duel.
##   Beating the first brings it in, and its half is where technology is taught.
##
## **It counts what has happened SINCE the current lesson opened**, and every
## step asks it rather than the world. That is what makes the lessons
## independent of the systems they teach: nothing in the builder, the sender or
## the Research Center knows a tutorial exists, and adding a lesson about
## something new is a step subclass and a counter here rather than a hook in the
## thing being taught. The one thing the systems DO answer to is ActionLimits,
## which is a general "this player may only do this much" rather than anything
## that names a tutorial.

## The lesson changed - opened, finished, or the whole tutorial ended. One
## signal rather than three, because the panel that listens redraws whole.
signal lesson_changed()

## The name this holds the world still by, and the clock. Its own rather than
## the draft's, so the two can overlap without either releasing the other -
## see MatchSession.
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
## Income payouts since the tutorial began, and the count when the lesson
## opened. Counted off PlayerManager.income_paid, since nothing else keeps it.
var _payouts: int = 0
var _payouts_mark: int = 0
## The current lesson's waves: which have gone out and which are killed.
var _waves: TutorialWaves = TutorialWaves.new()
## How many of the current lesson's blueprint cells were already built when it
## opened, so a lesson finishing a plan counts only what it asked for.
var _blueprint_mark: int = 0
## Where the builder stood when the current lesson opened, so a lesson about
## moving it can tell that it moved.
var _builder_mark: Vector3 = Vector3.ZERO
## Seconds left before the next lesson opens, while the last one is DONE and
## the player is given a beat to see it land. Below zero when nothing waits.
var _gap_left: float = -1.0
## The world arrows over the builder and the blueprint. Built on begin.
var _arrows: TutorialWorldArrows = null
## Whether a lesson has opened the Research Center. Latched: it stays open.
var _research_open: bool = false
## [from type id, type id] -> whether that tower is somewhere up that one's
## upgrade chain. The walk is the same answer every time it is asked.
var _reach_cache: Dictionary = {}

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
	_set_the_board(setup)
	# A child of this node, and built here rather than in _ready, so nothing is
	# built for a match that is not a tutorial.
	_arrows = TutorialWorldArrows.new()
	_arrows.name = "WorldArrows"
	add_child(_arrows)
	var manager: PlayerManager = References.player_manager
	if manager != null:
		manager.income_paid.connect(_on_income_paid)
		manager.match_ended.connect(_on_match_ended)
	Log.info("Tutorial started", {"lessons": script_resource.count()})
	_open(0)


## Everything that differs from an ordinary match at its first tick: who has
## how many lives, who waits on standby, what the opponents build with, and
## where the clock starts.
func _set_the_board(setup: MatchSetup) -> void:
	var manager: PlayerManager = References.player_manager
	if manager == null:
		return

	var player: PlayerState = manager.local_state()
	if player != null:
		player.set_lives(script_resource.player_lives)

	for rival: TutorialStep.Rival in [TutorialStep.Rival.FIRST, TutorialStep.Rival.SECOND]:
		var state: PlayerState = manager.state_for(TutorialSetup.slot_for(rival))
		if state == null:
			continue
		state.set_lives(script_resource.rival_lives)
		# A lump rather than income, because until it is woken an opponent is a
		# demonstration rather than a player: enough for the short maze its
		# sparring profile plans and no more.
		state.gain(script_resource.opponent_gold)
		# The second waits outside the ring, so the first half is a plain duel.
		state.standby = rival == TutorialStep.Rival.SECOND

	_skip_the_opening(manager.area_for(setup.local_slot))


## Starts the clock at the moment the first creep can be sent, rather than at
## the start of an opening phase.
##
## **The opening is time spent waiting in a real match, and the lessons hold
## the clock anyway** - so the first time it would be read is the sending
## lesson, which must find its creep already open. Moving the clock on, rather
## than waiving the creep's delay, keeps everything after it an ordinary match:
## the next creep unlocks exactly when it would, counted from here.
func _skip_the_opening(area: PlayerArea) -> void:
	var session: MatchSession = _session
	var config: GameConfig = References.game_config
	if session == null || config == null || area == null:
		return

	var earliest: float = INF
	for sender in area.send_buildings():
		if sender.is_sudden_death_tier:
			continue
		for entry: Variant in sender.current_abilities():
			var send: SendCreepAbility = entry as SendCreepAbility
			if send != null && send.creep_stats != null:
				earliest = minf(earliest, send.creep_stats.unlock_seconds)
	if is_inf(earliest):
		return
	session.fast_forward(config.unlock_clock(earliest))


## Whether a tutorial is being played at all, for the panel that draws it.
func is_running() -> bool:
	return _running && _step != null


## Whether the lesson on screen is already DONE and the next one is waiting out
## its delay. The panel says so; the pointers point at nothing.
func is_between_lessons() -> bool:
	return _gap_left >= 0.0


## The lesson on screen, or null once the tutorial is over.
func current_step() -> TutorialStep:
	return _step


## Which STEP is open, as an index into the script. A lesson can be several
## steps - see TutorialScript.lesson_range - so the panel asks the script which
## lesson this is.
func step_index() -> int:
	return _index


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


## Income payouts since the lesson opened.
func payouts_this_step() -> int:
	return _payouts - _payouts_mark


## The current lesson's waves, for a step asking whether they are over and how
## many are killed.
func waves() -> TutorialWaves:
	return _waves


## How many cells of the current lesson's blueprint were already built when it
## opened.
func blueprint_built_at_open() -> int:
	return _blueprint_mark


## Where the builder stood when the current lesson opened.
func builder_at_open() -> Vector3:
	return _builder_mark


## How many technologies the player owns in total.
##
## In TOTAL rather than since the lesson opened, unlike everything above, and
## the difference is real: research can be UNDONE inside its window, so a count
## of presses would let a player finish a lesson by buying something and giving
## it straight back. What the lesson is about is owning one.
func technologies_owned() -> int:
	var state: PlayerState = _local_state()
	return 0 if state == null else state.tech.owned_count()


## Whether an opponent is out of the match.
func is_rival_beaten(rival: TutorialStep.Rival) -> bool:
	var state: PlayerState = _rival_state(rival)
	return state != null && state.is_eliminated()


## An opponent's lives, or -1 for one that does not exist.
func rival_lives(rival: TutorialStep.Rival) -> int:
	var state: PlayerState = _rival_state(rival)
	return -1 if state == null else state.lives


## Whether the player has a tower standing that `from` upgrades into - the Core
## becoming an elemental tower. The tower itself does not count.
func owns_tower_reached_from(from: BuildingStats) -> bool:
	var area: PlayerArea = _local_area()
	if area == null || from == null:
		return false
	for child in area.get_children():
		var building: Building = child as Building
		if building == null:
			continue
		var stats: BuildingStats = building.stats as BuildingStats
		if stats == null || stats == from:
			continue
		var key: Array = [from.unit_type_id, stats.unit_type_id]
		if !_reach_cache.has(key):
			_reach_cache[key] = AiHand.branch_reaches(from, stats.unit_type_id, {})
		if _reach_cache[key]:
			return true
	return false


## The player's own lane.
func _local_area() -> PlayerArea:
	var manager: PlayerManager = References.player_manager
	return null if manager == null else manager.area_for(manager.local_player_id())


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
## keeps running while the world is held.
func _physics_process(_engine_delta: float) -> void:
	if !_running || _step == null:
		return
	var delta: float = MatchSession.tick_seconds()
	if is_between_lessons():
		_gap_left -= delta
		if _gap_left < 0.0:
			_open(_index + 1)
		return
	_elapsed += delta
	_waves.send_due(_elapsed, _send_wave)
	if _step.is_complete(self):
		_finish_lesson()


## The current lesson is done: wait out the next one's delay, then open it.
## Everything this one held stays held through the gap, so nothing starts moving
## in the beat between two lessons that both hold the clock.
func _finish_lesson() -> void:
	var next: TutorialStep = script_resource.step_at(_index + 1)
	var gap: float = 0.0 if next == null else maxf(0.0, next.delay_seconds)
	if gap <= 0.0:
		_open(_index + 1)
		return
	_gap_left = gap
	lesson_changed.emit()


## The player pressed Continue. What finishes a lesson that is only read, and
## what is ignored by every other kind - a step decides for itself whether an
## acknowledgement means anything.
func acknowledge() -> void:
	_acknowledged = true


## On to the next lesson now, or to the end of the tutorial, without waiting out
## a delay.
##
## **There is no skip.** A lesson cannot be passed without doing it: the early
## ones are built so they cannot be got stuck in - exact gold, exact cells,
## nothing else allowed - and a lesson whose end is an opponent beaten is ended
## by the match either way. A tutorial that offers a way out invites taking it.
func advance() -> void:
	if !_running:
		return
	_open(_index + 1)


func _open(index: int) -> void:
	_index = index
	_step = null if script_resource == null else script_resource.step_at(index)
	_elapsed = 0.0
	_acknowledged = false
	_gap_left = -1.0

	if _step == null:
		_finish()
		return

	_mark = _snapshot_line()
	_payouts_mark = _payouts
	_waves.reset(_step.waves)
	_blueprint_mark = _step.blueprint_built()
	var builder: Unit = TutorialGuide.unit_for(TutorialStep.Select.BUILDER)
	_builder_mark = Vector3.ZERO if builder == null else builder.global_position
	_apply_grants(_step)
	_apply_limits(_step)
	_step.on_enter(self)
	# After the grants, so a lesson that hands over gold does it before the
	# world stops rather than on the frame it starts again.
	_hold(_step.pauses_world)
	var session: MatchSession = _session
	if session != null:
		session.hold_clock(HOLD_REASON, _step.holds_clock)
	Log.info("Tutorial lesson", {
		"lesson": _index + 1, "of": script_resource.count(), "title": _step.title,
	})
	lesson_changed.emit()


## The end of the tutorial, whether the last lesson finished or the match did.
## Everything the lessons held is let go: the world, the clock, the limits.
func _finish() -> void:
	if !_running:
		return
	_running = false
	_step = null
	set_physics_process(false)
	_hold(false)
	var session: MatchSession = _session
	if session != null:
		session.hold_clock(HOLD_REASON, false)
	var state: PlayerState = _local_state()
	if state != null:
		state.limits = null
	_draw_blueprint(null)
	Log.info("Tutorial finished")
	lesson_changed.emit()


func _on_income_paid() -> void:
	_payouts += 1


## The match is decided - the last opponent beaten, or the player out of lives.
## Either way there is nothing left to teach, and the result board takes over.
func _on_match_ended(_winner_slot: int) -> void:
	_finish()


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
	if step.unlocks_research:
		_research_open = true

	_draw_blueprint(step.blueprint())
	_set_stock(step)
	if step.wakes_rival != TutorialStep.Rival.NONE:
		_wake(step.wakes_rival)


## Holds the player to what this lesson allows, or to nothing but the Research
## Center lock once the lessons stop restricting. See ActionLimits.
##
## A fresh object every lesson rather than one edited in place, so nothing a
## lesson allowed can outlive it by accident.
func _apply_limits(step: TutorialStep) -> void:
	var state: PlayerState = _local_state()
	if state == null:
		return

	var limits: ActionLimits = ActionLimits.new()
	limits.research = _research_open
	limits.forbidden.append_array(script_resource.forbidden_abilities)
	if step.restricts_actions:
		limits.restricts_abilities = true
		limits.abilities.append_array(script_resource.always_allowed)
		limits.abilities.append_array(step.allowed_abilities)
		var plan: TowerLayout = step.blueprint()
		if step.build_on_blueprint_only && plan != null:
			for cell: Vector2i in plan.cells:
				limits.build_cells[cell] = true
	state.limits = limits


## Sets one reserve on the player's senders to exactly what the lesson asks.
## Every sender whose card carries that creep, though in practice it is one.
func _set_stock(step: TutorialStep) -> void:
	var creep: CreepStats = step.stock_creep()
	var area: PlayerArea = _local_area()
	if creep == null || area == null:
		return
	for sender in area.send_buildings():
		if sender.stock_for(creep) != null:
			sender.set_stock(creep, step.stock_count)


## Brings an opponent into the match properly: into the ring, onto an income
## that matches the player's, and playing its real profile from here on.
func _wake(rival: TutorialStep.Rival) -> void:
	var slot: int = TutorialSetup.slot_for(rival)
	var state: PlayerState = _rival_state(rival)
	var player: PlayerState = _local_state()
	if state == null:
		Log.err("A lesson wakes an opponent the tutorial does not have", slot)
		return

	state.standby = false
	if player != null:
		var matched: int = int(round(float(player.income) * script_resource.rival_income_share))
		if matched > state.income:
			state.add_income(matched - state.income)

	var profile: AiProfile = script_resource.rival_profile(rival)
	var ai: AiDirector = References.ai_director
	var brain: AiPlayer = null if ai == null else ai.brain_for(slot)
	if brain == null || profile == null:
		Log.err("A lesson wakes an opponent that has no brain or no profile", slot)
		return
	brain.change_profile(profile)
	Log.info("Tutorial opponent woken", {
		"slot": slot, "profile": profile.display_name, "income": state.income,
	})


## Puts a saved plan on the ground, or takes one off.
##
## The overlay is PRESENTATION and local from end to end, which is exactly what
## the tutorial wants from it: a blue square on every cell still to build on,
## disappearing as each is filled. It says where without ordering anything and
## without taking the mouse off the player.
##
## It is the SAME overlay the builder's own Show Blueprint command drives, so a
## player who puts one up themselves and a lesson that puts one up for them are
## using one thing. A lesson that names no plan takes whatever is up down, which
## is what stops the last lesson's plan hanging around over the next one.
func _draw_blueprint(plan: TowerLayout) -> void:
	var overlay: BlueprintOverlay = References.blueprint_overlay
	if overlay == null:
		return
	if plan == null:
		overlay.hide_blueprint()
		return
	overlay.show_layout(plan)
	_look_at_plan(plan)


## Puts the camera on the part of the plan still to build.
##
## **A lesson that says "build on the blue squares" is useless if the camera is
## looking somewhere else**, which is where the builder starts and therefore
## where every tutorial opens. The first version drew the squares perfectly and
## off the top of the screen.
##
## The cells still EMPTY rather than the whole plan, because a lesson that adds
## a second row to the first means the second row - and a plan that is the
## whole lane would otherwise centre on the middle of it.
##
## PRESENTATION, and local from end to end: the camera is this machine's view of
## the world and moving it changes nothing in it.
func _look_at_plan(plan: TowerLayout) -> void:
	var camera: RTSCamera = References.rts_camera
	var area: PlayerArea = _local_area()
	if camera == null || area == null || plan.entry_count() <= 0:
		return

	var taken: Dictionary = {}
	for child in area.get_children():
		var building: Building = child as Building
		if building != null:
			taken[building.cell] = true

	# The first row still to build: its middle, so the camera frames the part of
	# the plan the lesson is about rather than the top left corner of it.
	var first_row: int = -1
	var middle: Vector3 = Vector3.ZERO
	var count: int = 0
	for cell: Vector2i in plan.cells:
		if taken.has(cell):
			continue
		if first_row < 0 || cell.y < first_row:
			first_row = cell.y
	for cell: Vector2i in plan.cells:
		if cell.y == first_row && !taken.has(cell):
			middle += area.internal_cell_center(cell)
			count += 1
	if count > 0:
		camera.center_on(middle / float(count))


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


func _rival_state(rival: TutorialStep.Rival) -> PlayerState:
	var manager: PlayerManager = References.player_manager
	var slot: int = TutorialSetup.slot_for(rival)
	return null if manager == null || slot <= 0 else manager.state_for(slot)


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


## Puts one wave into the player's own lane.
##
## **The one thing the tutorial does TO the player**, and it exists because
## nothing else will before the basics are taught: the first opponent spars
## until then and sends nothing.
##
## Spawned as the OPPONENT's creeps and as whole PACKS, so a Sheep send is two
## Sheep and a Timber Wolf exactly as a real one is, and the leak, the bounty
## and the life steal resolve as in a real match.
##
## The same calls SendBuilding makes, and deliberately not a SEND: a send is a
## player order with a price, a reserve and a start delay, and none of those is
## a thing the tutorial is asking for. This is the board being set up.
##
## Answers the creeps it spawned, so TutorialWaves can tell when this wave is
## over.
func _send_wave(wave: TutorialWave) -> Array:
	var spawned: Array = []
	var stats: CreepStats = wave.creep()
	var manager: PlayerManager = References.player_manager
	if stats == null || manager == null:
		return spawned

	var into: PlayerArea = manager.area_for(manager.local_player_id())
	var sender: int = manager.attacker_of(manager.local_player_id())
	if into == null:
		return spawned

	for send in range(wave.sends):
		for entry: Array in stats.pack_contents():
			_spawn_creeps(entry[0] as CreepStats, int(entry[1]), into, sender, spawned)

	Log.info("Tutorial wave", {
		"creep": stats.display_name,
		"sends": wave.sends,
		"creeps": spawned.size(),
		"into": into.player_id,
		"from": sender,
	})
	return spawned


## Spawns `count` of one creep into a lane as `sender`'s, adding each to `into_list`.
func _spawn_creeps(stats: CreepStats, count: int, into: PlayerArea, sender: int,
		into_list: Array) -> void:
	if stats == null:
		return
	var scene: PackedScene = stats.scene()
	if scene == null:
		Log.err("A tutorial wave names a creep with no loadable prefab", stats.display_name)
		return

	for index in range(count):
		var creep: Creep = scene.instantiate() as Creep
		if creep == null:
			Log.err("Tutorial creep prefab root is not a Creep", stats.display_name)
			return
		into.creeps_root().add_child(creep)
		creep.spawn(sender, into, into.random_spawn_point(
			stats.body_radius, MatchSession.match_rng()
		))
		into_list.append(creep)
