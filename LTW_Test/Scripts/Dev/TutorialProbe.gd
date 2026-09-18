class_name TutorialProbe
extends Node

## SCAFFOLDING, kept while the tutorial is iterated - see tutorial.md section 11.
## Plays the whole tutorial headless through the real order road and prints what
## each lesson ACTUALLY did, including the orders the restricted lessons must
## refuse and what the arrows resolved to.
##
##   godot --path . --headless res://Scenes/Dev/tutorial_probe.tscn
##
## Written against the current lesson ORDER: the numbers in _play() are lesson
## numbers, so re-ordering the lessons means updating it.

const MATCH_SCENE: String = "res://Scenes/Main.tscn"
const ARCHER: String = "res://Resources/UnitStats/Towers/lesser_archer_stats.tres"
const CORE: String = "res://Resources/UnitStats/Towers/elemental_core_stats.tres"
const SHEEP: String = "res://Resources/UnitStats/Creeps/sheep_stats.tres"
const KNIGHT: String = "res://Resources/UnitStats/Creeps/knight_stats.tres"
const BUILD_MENU: String = "res://Resources/Abilities/build_menu_ability.tres"
const SHOW_BLUEPRINTS: String = "res://Resources/Abilities/Blueprints/show_blueprints_ability.tres"
const SPEED: int = 200
const GIVE_UP_TICKS: int = 20 * 60 * 20

@export var _ai_config: AiConfig
@export var _game_config: GameConfig

var _ticks: int = 0
var _lesson_ticks: int = 0
var _lesson: int = 0
var _acted: Dictionary = {}
var _failures: Array[String] = []
var _passes: Array[String] = []
var _done: bool = false
var _gaps_seen: int = 0
var _was_between: bool = false
## `-- shots` on the command line: run WINDOWED and save a screenshot at the
## moments an arrow is up, so where it DRAWS can be looked at. Headless cannot
## draw, so this is the only way to see it.
var _shots: bool = false
## `-- lose`: run out of lives in the Rookie lesson and check the defeat screen
## instead of playing to the end.
var _lose: bool = false
var _shot_name: String = ""
var _shot_frames: int = 0
var _shots_taken: Dictionary = {}
## Moment title -> the tick it fired on, and ticks spent on the one up now.
var _moments_seen: Dictionary = {}
var _moment_ticks: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_shots = "shots" in OS.get_cmdline_user_args()
	_lose = "lose" in OS.get_cmdline_user_args()
	var setup: MatchSetup = TutorialSetup.create(_game_config, _ai_config)
	MenuNavigation.pending_match = setup
	# Real time when shooting, so a shot lands inside a moment as short as the
	# beat between two lessons.
	Engine.physics_ticks_per_second = 20 if _shots else SPEED
	Engine.max_physics_steps_per_frame = 64
	add_child((load(MATCH_SCENE) as PackedScene).instantiate())
	print("PROBE started")


func _physics_process(_delta: float) -> void:
	if _done:
		return
	if !_shot_name.is_empty():
		return
	# Windowed, the match opens behind the shader warm-up screen.
	if _shots && !ShaderWarmup.is_done():
		return
	_ticks += 1
	var director: TutorialDirector = References.tutorial_director
	if director == null:
		return
	if _ticks > GIVE_UP_TICKS:
		_fail("gave up at lesson %d" % _lesson)
		_finish()
		return
	if !director.is_running():
		if _lesson > 0:
			if !_acted.has("ended"):
				_acted["ended"] = true
				_acted["end_ticks"] = 0
				return
			# A few ticks for the end screen to arrive.
			_acted["end_ticks"] = int(_acted["end_ticks"]) + 1
			if int(_acted["end_ticks"]) < 10:
				return
			if _shoot("the_end_%s" % ("defeat" if _lose else "victory")):
				return
			_note("tutorial finished after lesson %d, %d gaps between lessons seen" % [
				_lesson, _gaps_seen])
			_check(_gaps_seen > 0, "lessons waited out their delay")
			_check_the_end(director)
			_finish()
		return

	if director.current_moment() != null:
		_read_moment(director)
		return
	if director.is_between_lessons() != _was_between:
		_was_between = director.is_between_lessons()
		if _was_between:
			_gaps_seen += 1
			var tasks: Array[TutorialStep.Task] = director.current_step().tasks(director)
			_check(tasks.is_empty() || tasks[0].done,
				"lesson %d: its task is ticked in the gap" % _lesson)
			if _lesson == 2:
				_shoot("l2_done")
			if true:
				_note("lesson %d finished reading '%s'" % [
					_lesson, director.current_step().progress_text(director)])
	if director.is_between_lessons():
		return

	if director.step_index() + 1 != _lesson:
		_lesson = director.step_index() + 1
		_lesson_ticks = 0
		_acted.clear()
		print("LESSON %d  %s  clock=%.1f held=%s gold=%d income=%d" % [
			_lesson, director.current_step().title, _session().elapsed_seconds(),
			_session().is_clock_held(), _me().gold, _me().income,
		])
	_lesson_ticks += 1
	# Let the world settle a beat after every lesson opens.
	if _lesson_ticks < 10:
		return
	if !_acted.has("opened"):
		_acted["opened"] = true
		_on_lesson_opened()
	_play(director)


## Asks for a screenshot, once per name. Answers whether the probe should wait
## for it this tick.
func _shoot(shot: String) -> bool:
	if !_shots || _shots_taken.has(shot):
		return false
	_shots_taken[shot] = true
	_shot_name = shot
	_shot_frames = 30
	return true


func _process(_delta: float) -> void:
	if _shot_name.is_empty():
		return
	_shot_frames -= 1
	if _shot_frames > 0:
		return
	var path: String = "user://tutorial_shots/%s.png" % _shot_name
	DirAccess.make_dir_recursive_absolute("user://tutorial_shots")
	get_viewport().get_texture().get_image().save_png(path)
	print("  SHOT  " + ProjectSettings.globalize_path(path))
	_shot_name = ""


## Keyed by the lesson FILE rather than by its number, so steps can be added or
## taken out of the script without renumbering this.
func _play(director: TutorialDirector) -> void:
	match director.current_step().resource_path.get_file().get_basename():
		"01_builder":
			_play_select_builder()
		"02_move":
			_play_move()
		"03_first_towers", "05_row_cutters", "06_row_archers":
			_play_build(director)
		"04_first_waves", "09_skeleton_wave":
			_play_wave()
		"07_upgrade_archers", "08_cannons":
			_play_upgrade_task(director)
		"10_send_sheep":
			_play_send()
		"11_income_explained":
			_play_explain()
		"12_payout":
			_play_payout()
		"13_beat_rookie":
			_play_rookie()
		"later_technology":
			_play_research()
		"later_elemental":
			_play_core()
		"later_beat_veteran":
			_play_beat(TutorialStep.Rival.SECOND, 1200)


## The move lesson: check where the highlight is, then walk the builder a few
## cells down the lane.
func _play_move() -> void:
	if _acted.has("moved"):
		return
	if _shoot("l1_move"):
		return
	_acted["moved"] = true
	_check(_pointer_target_name().begins_with("CommandSlot"),
		"move lesson: highlight on the Move square (%s)" % _pointer_target_name())
	var builder: Builder = _builder()
	var move: UnitAbility = load("res://Resources/Abilities/move_ability.tres") as UnitAbility
	Commands.submit_for(1, move, [builder],
		AbilityTarget.at_position(builder.global_position + Vector3(0.0, 0.0, 4.0)))


## An upgrade task: first try what it must refuse, then press the one allowed
## upgrade on whichever tower offers it, one at a time.
func _play_upgrade_task(director: TutorialDirector) -> void:
	var step: TutorialStep = director.current_step()
	var allowed: UnitAbility = step.allowed_abilities[0]
	var area: PlayerArea = References.player_manager.area_for(1)
	if !_acted.has("forbidden"):
		_acted["forbidden"] = true
		_acted["gold_before"] = _me().gold
		for child in area.get_children():
			var tower: Building = child as Building
			if tower == null:
				continue
			for entry in tower.current_abilities():
				var other: UpgradeTowerAbility = entry as UpgradeTowerAbility
				if other != null && other != allowed:
					_check(!ActionLimits.permits(other, tower), "%s: %s not permitted" % [
						step.resource_path.get_file(), other.display_name])
					AiHand.order_upgrade(1, tower, other)
					return
		return
	if !_acted.has("checked_gold"):
		_acted["checked_gold"] = true
		_check(_me().gold == int(_acted["gold_before"]), "%s: refused upgrades cost nothing (%d -> %d)" % [
			step.resource_path.get_file(), int(_acted["gold_before"]), _me().gold])
		_note("%s: %d gold for it" % [step.resource_path.get_file(), _me().gold])
	if _shoot("l%d_upgrade_world" % _lesson):
		return
	if !_acted.has("selected_one"):
		# Select a tower that offers the upgrade, so its highlighted square can be
		# looked at.
		for child in area.get_children():
			var candidate: Building = child as Building
			if candidate != null && allowed in candidate.current_abilities():
				References.selection_controller.select_single(candidate)
				_acted["selected_one"] = true
				break
		return
	if _shoot("l%d_upgrade_card" % _lesson):
		return
	if _lesson_ticks % 40 != 0:
		return
	for child in area.get_children():
		var tower: Building = child as Building
		if tower == null:
			continue
		if allowed in tower.current_abilities() && allowed.can_execute(tower):
			AiHand.order_upgrade(1, tower, allowed as UpgradeTowerAbility)
			return


func _on_lesson_opened() -> void:
	var rookie: MatchStatLine = References.match_stats.line_for(TutorialSetup.FIRST_RIVAL_SLOT)
	var vet: MatchStatLine = References.match_stats.line_for(TutorialSetup.SECOND_RIVAL_SLOT)
	if _lesson <= 13:
		_check(rookie.sends == 0, "lesson %d: the Rookie has sent nothing yet" % _lesson)
		_check(vet.sends == 0, "lesson %d: the Veteran has sent nothing yet" % _lesson)
		_check(!ActionLimits.permits_research(1), "lesson %d: research still shut" % _lesson)
	var builder: Builder = _builder()
	var show: UnitAbility = load(SHOW_BLUEPRINTS) as UnitAbility
	_check(!ActionLimits.permits(show, builder), "lesson %d: blueprint screen forbidden" % _lesson)


func _play_select_builder() -> void:
	if _acted.has("selected"):
		return
	if _shoot("l1_select_builder"):
		return
	_acted["selected"] = true
	_check(TutorialGuide.needs_selecting(References.tutorial_director.current_step()),
		"lesson 1: the builder still wants selecting")
	_check(_pointer_target_name() == "BuilderButton",
		"lesson 1: the HUD arrow is on the builder button (%s)" % _pointer_target_name())
	_check(_world_arrows() == 1, "lesson 1: one world arrow, over the builder (%d)" % _world_arrows())
	var build_menu: UnitAbility = load(BUILD_MENU) as UnitAbility
	_check(!ActionLimits.permits(build_menu, _builder()), "lesson 1: the Build menu is shut")
	References.selection_controller.select_single(_builder())


func _play_build(director: TutorialDirector) -> void:
	var builder: Builder = _builder()
	var area: PlayerArea = References.player_manager.area_for(1)
	var plan: TowerLayout = director.current_step().blueprint()
	if builder == null || area == null || plan == null:
		return

	if !_acted.has("guide"):
		_acted["guide"] = true
		var open: int = _open_cells(plan, area)
		# Deselected: the arrow goes back to the builder, and one more hovers.
		References.selection_controller.select_single(_sender(1))
		_acted["guide_off"] = [_pointer_target_name(), _world_arrows(), open]
		return
	if !_acted.has("guide_on"):
		var off: Array = _acted["guide_off"]
		_check(off[0] == "BuilderButton", "lesson %d: builder not selected, arrow on its button (%s)" % [_lesson, off[0]])
		_check(off[1] == 1, "lesson %d: only the builder arrow while it is not selected (%d)" % [_lesson, off[1]])
		References.selection_controller.select_single(builder)
		_acted["guide_on"] = true
		return
	if !_acted.has("guide_checked"):
		if _shoot("l%d_build_card" % _lesson):
			return
		if !_acted.has("submenu") && _shots:
			_acted["submenu"] = true
			References.unit_panel._on_ability_activated(load(BUILD_MENU) as UnitAbility)
			_shoot("l%d_build_submenu" % _lesson)
			return
		_acted["guide_checked"] = true
		_check(_pointer_target_name().begins_with("CommandSlot"),
			"lesson %d: builder selected, arrow on a command square (%s)" % [_lesson, _pointer_target_name()])
		_check(_world_arrows() == 0,
			"lesson %d: no cell arrows before the tower is in hand (%d)" % [_lesson, _world_arrows()])
		var controller: CommandController = References.command_controller
		controller.activate_ability(_sentry(director))
		_check(controller.is_armed(), "lesson %d: the lesson's tower can be armed" % _lesson)
		_check(_world_arrows() == _open_cells(plan, area),
			"lesson %d: tower in hand, one arrow per open cell (%d)" % [_lesson, _world_arrows()])
		controller.cancel()

	if !_acted.has("forbidden"):
		_acted["forbidden"] = true
		var gold_before: int = _me().gold
		# Some tower on the build menu other than the one this task asks for.
		for other: BuildingStats in AiHand.buildable_towers(builder):
			var other_ability: BuildTowerAbility = AiHand.build_ability(builder, other)
			if other_ability != null && !(other_ability in director.current_step().allowed_abilities):
				_check(!ActionLimits.permits(other_ability, builder), "lesson %d: %s not permitted" % [
					_lesson, other.display_name])
				break
		var off_cell: Vector2i = Vector2i(0, 40)
		_check(!area.can_place(off_cell, Vector2i(2, 2)), "lesson %d: off-blueprint cell refused" % _lesson)
		var sentry: BuildTowerAbility = _sentry(director)
		AiHand.order_build(1, builder, sentry, area.footprint_world_center(off_cell, Vector2i(2, 2)), false)
		for child in area.get_children():
			var tower: Building = child as Building
			var up: UpgradeTowerAbility = null if tower == null else AiHand.cheapest_upgrade(tower)
			if up != null:
				_check(!ActionLimits.permits(up, tower), "lesson %d: upgrade not permitted" % _lesson)
				AiHand.order_upgrade(1, tower, up)
				break
		_acted["gold_before"] = gold_before
		return
	if !_acted.has("checked_gold"):
		_acted["checked_gold"] = true
		_check(_me().gold == int(_acted["gold_before"]),
			"lesson %d: forbidden orders cost nothing (gold %d -> %d)" % [
				_lesson, int(_acted["gold_before"]), _me().gold])
		# At least, not exactly: the waves' Timber Wolves pay bounty on top.
		_check(_me().gold >= _open_cells(plan, area) * 10,
			"lesson %d: gold covers the open cells (%d for %d)" % [
				_lesson, _me().gold, _open_cells(plan, area)])
	if builder.has_pending_build():
		return
	for cell: Vector2i in plan.cells:
		if area.can_place(cell, Vector2i(2, 2)):
			AiHand.order_build(1, builder, _sentry(director), area.footprint_world_center(cell, Vector2i(2, 2)), false)
			return


func _play_wave() -> void:
	if _lesson_ticks % 40 == 0:
		_note("lesson %d: t=%.1fs  %d creeps in lane, player lives %d" % [
			_lesson, _lesson_ticks / 20.0,
			References.player_manager.area_for(1).creeps().size(), _me().lives])


## The tutorial is over: won to the end, or lost with `-- lose`.
func _check_the_end(director: TutorialDirector) -> void:
	var manager: PlayerManager = References.player_manager
	var limits: ActionLimits = _me().limits
	_check(limits != null && limits.restricts_abilities && limits.abilities.is_empty(),
		"end: nothing more can be ordered")
	_check(!limits.allows(load(BUILD_MENU) as UnitAbility), "end: the Build menu is shut")
	var end_panel: MatchEndPanel = get_tree().root.find_child("MatchEndPanel", true, false) as MatchEndPanel
	var defeat: Control = get_tree().root.find_child("TutorialDefeatPanel", true, false) as Control
	var defeat_dim: Control = null if defeat == null else defeat.get_node_or_null("Dim") as Control
	var end_board: Control = null if end_panel == null else end_panel.get_node_or_null("Panel") as Control
	if _lose:
		_check(director.is_defeated(), "defeat: the director says lost")
		_check(_session().is_paused(), "defeat: the world is held")
		_check(defeat_dim != null && defeat_dim.visible, "defeat: the defeat screen is up")
		_check(defeat_dim != null && defeat_dim.mouse_filter == Control.MOUSE_FILTER_STOP,
			"defeat: the screen swallows clicks")
		_check(end_board == null || !end_board.visible, "defeat: no result board over it")
		return
	_check(manager.is_match_over(), "victory: the match is over")
	var creeps: int = 0
	for area: PlayerArea in manager.areas():
		creeps += area.creeps().size()
	_check(creeps == 0, "victory: every creep cleared (%d)" % creeps)
	_check(_me().placement == 1, "victory: the player placed first (%d)" % _me().placement)
	_check(end_board != null && end_board.visible, "victory: the result board is up")
	_check(defeat_dim == null || !defeat_dim.visible, "victory: no defeat screen")


## A moment is up: check the world is held, the camera is on it and the
## panel says it, then press OK after a beat.
func _read_moment(director: TutorialDirector) -> void:
	var moment: TutorialMoment = director.current_moment()
	if !_moments_seen.has(moment.title):
		_moments_seen[moment.title] = _ticks
		_moment_ticks = 0
		_note("moment '%s' fired in lesson %d" % [moment.title, _lesson])
		_check(_session().is_paused(), "moment '%s': the world is held" % moment.title)
		_check(References.rts_camera.is_pinned(), "moment '%s': the camera is pinned" % moment.title)
		_check(director.moment_focus() != Vector3.INF, "moment '%s': it has a creep to light" % moment.title)
		_check(_pointer_target_name() == "<none>", "moment '%s': no button highlighted" % moment.title)
	if _shoot("moment_" + moment.title.to_lower().replace(" ", "_")):
		return
	_moment_ticks += 1
	if _moment_ticks == 20:
		director.dismiss_moment()
		_check(!_session().is_paused(), "moment '%s': OK lets the world go" % moment.title)


## The explanation: every page frames its element with a caption, the world is
## held, the info panel is up and the lesson panel is not. Turn each page.
func _play_explain() -> void:
	var director: TutorialDirector = References.tutorial_director
	var page: TutorialPage = director.current_page()
	if page == null:
		return
	var at: int = director.pages_read()
	if _acted.has("page%d" % at):
		return
	if _shoot("l5_explain_%d" % (at + 1)):
		return
	_acted["page%d" % at] = true
	var wanted: Dictionary = {&"gold": "Gold", &"income_value": "IncomeLabel", &"income_timer": "Timer"}
	_check(_pointer_target_name() == String(wanted.get(page.highlight_key, "?")),
		"explain page %d: border on %s (%s)" % [at + 1, page.highlight_key, _pointer_target_name()])
	_check(_session().is_paused(), "explain page %d: the world is held" % (at + 1))
	var info: Control = get_tree().root.find_child("TutorialInfoPanel", true, false) as Control
	var panel: Control = get_tree().root.find_child("TutorialPanel", true, false) as Control
	_check(info != null && info.visible, "explain page %d: the info panel is up" % (at + 1))
	_check(panel != null && !panel.visible, "explain page %d: the lesson panel is out of the way" % (at + 1))
	# Drawn on the render frame; make sure this frame's caption is current.
	var pointer: TutorialPointer = get_tree().root.find_child("TutorialPointer", true, false) as TutorialPointer
	pointer._process(0.0)
	var caption: Label = get_tree().root.find_child("CaptionLabel", true, false) as Label
	_check(caption != null && caption.is_visible_in_tree() && caption.text == page.caption,
		"explain page %d: captioned '%s'" % [at + 1, "" if caption == null else caption.text])
	if at == 1:
		_check(_me().income == 10, "explain: the five Sheep raised income to 10 (%d)" % _me().income)
	director.acknowledge()


func _play_payout() -> void:
	if _acted.has("seen"):
		return
	if _shoot("l5_payout"):
		return
	_acted["seen"] = true
	_check(_pointer_target_name() == "Timer",
		"payout: border on the income timer (%s)" % _pointer_target_name())
	_check(!_session().is_clock_held(), "payout: the clock runs")


func _play_send() -> void:
	var sender: SendBuilding = _sender(1)
	var sheep: CreepStats = load(SHEEP) as CreepStats
	if sender == null:
		return
	if !_acted.has("checked"):
		if _shoot("l5_send_bar"):
			return
		_acted["checked"] = true
		_check(References.rts_camera.is_pinned(), "send: the camera is pinned on the Rookie's lane")
		_check(!ActionLimits.permits(load(BUILD_MENU) as UnitAbility, _builder()),
			"send: building is shut until the Sheep are sent")
		_check(_pointer_target_name() == "SendTier1",
			"send: sender not selected, border on its button (%s)" % _pointer_target_name())
		_check(sender.stock_for(sheep).count == 5, "send: sheep stock is exactly 5 (%d)" % sender.stock_for(sheep).count)
		_note("send: gold %d (50 granted, the rest bounty and a payout)" % _me().gold)
		for send in AiHand.sends_on(sender):
			if send.creep_stats != sheep:
				_check(!ActionLimits.permits(send, sender), "send: %s not permitted" % send.creep_stats.display_name)
				break
		References.selection_controller.select_single(sender)
		return
	if !_acted.has("slot"):
		if _shoot("l5_sheep_square"):
			return
		_acted["slot"] = true
		_check(_pointer_target_name().begins_with("CommandSlot"),
			"send: sender selected, border on the Sheep square (%s)" % _pointer_target_name())
	var sends: int = int(_acted.get("sends", 0))
	if sends < 6 && _lesson_ticks % 40 == 0:
		_check(sender.stock_for(sheep).count == 5 - sends,
			"send: before send %d the stock is %d, nothing refilled" % [sends + 1, sender.stock_for(sheep).count])
		AiHand.order_send(1, sender, AiHand.send_ability(sender, sheep))
		_acted["sends"] = sends + 1


## The Rookie lesson, played like a person who has just been taught to send:
## every few seconds, the dearest creep the gold covers. No cheats - the point
## is to see how long beating the Rookie really takes.
func _play_rookie() -> void:
	var sender: SendBuilding = _sender(1)
	var rookie: PlayerState = References.player_manager.state_for(TutorialSetup.FIRST_RIVAL_SLOT)
	var rookie_area: PlayerArea = References.player_manager.area_for(TutorialSetup.FIRST_RIVAL_SLOT)
	if !_acted.has("checks"):
		_acted["checks"] = true
		_check(!References.rts_camera.is_pinned(), "rookie: the camera is free again")
		_check(_me().income == 200, "rookie: income set to 200 (%d)" % _me().income)
		var lead: float = _session().unlock_elapsed_seconds() - _session().elapsed_seconds()
		_note("rookie: unlock clock %.1f, match clock %.1f" % [
			_session().unlock_elapsed_seconds(), _session().elapsed_seconds()])
		_check(absf(lead - 120.0) < 1.0, "rookie: unlocks moved 120s ahead (%.1f)" % lead)
		_check(!rookie.standby, "rookie: in the ring")
		var brain: AiPlayer = References.ai_director.brain_for(TutorialSetup.FIRST_RIVAL_SLOT)
		_check(brain.profile().display_name == "Tutorial Rookie", "rookie: plays %s" % brain.profile().display_name)
		var limits: ActionLimits = _me().limits
		_check(limits != null && !limits.restricts_abilities, "rookie: the player is free")
		_check(limits != null && limits.max_upgrade_gold == 1000, "rookie: upgrades over 1000 held back")
		_check(limits.allows(_upgrade_named("upgrade_lesser_cannon_to_cannon")), "rookie: a 1000g upgrade is allowed")
		_check(!limits.allows(_upgrade_named("upgrade_cannon_to_greater_cannon")), "rookie: a dearer upgrade is not")
	if _lose && _moments_seen.has("Life stealing"):
		_me().lives = 0
		_me().lives_changed.emit(0)
		return
	# The Rookie falls long before a Shade or a Treant unlocks, so note when it
	# WOULD have, then keep it standing until both of those moments have fired.
	var waiting: bool = !(_moments_seen.has("Flyers") && _moments_seen.has("Attackers"))
	if rookie.lives <= 6 && waiting:
		if !_acted.has("would_fall"):
			_acted["would_fall"] = true
			_note("rookie: down to %d lives after %ds of real sending" % [rookie.lives, _lesson_ticks / 20])
		rookie.lives = 10
		rookie.lives_changed.emit(10)
	if _lesson_ticks % 100 == 0 && sender != null:
		var best: SendCreepAbility = null
		for send in AiHand.sends_on(sender):
			if send.can_execute(sender) && (best == null || send.creep_stats.gold_cost > best.creep_stats.gold_cost):
				best = send
		if best != null:
			AiHand.order_send(1, sender, best)
	if _lesson_ticks % 1200 == 0:
		_note("rookie t=%ds: their lives %d, my lives %d, gold %d, income %d, unlock clock %.0f" % [
			_lesson_ticks / 20, rookie.lives, _me().lives, _me().gold, _me().income,
			_session().unlock_elapsed_seconds()])
		_note("  rookie towers: %s" % _tower_census(rookie_area))
		var knight: CreepStats = load(KNIGHT) as CreepStats
		var tier2: SendBuilding = _sender(2)
		if tier2 != null:
			_check(tier2.unlock_remaining(knight) > 0.0, "rookie t=%ds: the Knight is still locked (%.0fs)" % [
				_lesson_ticks / 20, tier2.unlock_remaining(knight)])


## The Rookie's towers by type, and the deepest row any of them stands on.
func _tower_census(area: PlayerArea) -> String:
	var counts: Dictionary = {}
	var deepest: int = -1
	for child in area.get_children():
		var tower: Building = child as Building
		if tower == null || tower.stats == null || tower.cell.y < 0:
			continue
		counts[tower.stats.display_name] = int(counts.get(tower.stats.display_name, 0)) + 1
		deepest = maxi(deepest, tower.cell.y)
	_check(deepest <= 12, "rookie builds nothing below row 4 (deepest internal row %d)" % deepest)
	return "%s, deepest internal row %d" % [counts, deepest]


func _upgrade_named(file: String) -> UnitAbility:
	return load("res://Resources/Abilities/Towers/%s_ability.tres" % file) as UnitAbility


func _play_upgrade() -> void:
	if _acted.has("up") && _lesson_ticks % 200 != 0:
		return
	_acted["up"] = true
	var area: PlayerArea = References.player_manager.area_for(1)
	for child in area.get_children():
		var tower: Building = child as Building
		if tower == null:
			continue
		var up: UpgradeTowerAbility = AiHand.cheapest_upgrade(tower)
		if up != null && up.can_execute(tower):
			AiHand.order_upgrade(1, tower, up)
			return


func _play_beat(rival: TutorialStep.Rival, after_ticks: int) -> void:
	var state: PlayerState = References.player_manager.state_for(TutorialSetup.slot_for(rival))
	if !_acted.has("woken"):
		_acted["woken"] = true
		_check(!state.standby, "rival %d woken out of standby" % rival)
		var brain: AiPlayer = References.ai_director.brain_for(TutorialSetup.slot_for(rival))
		_check(brain.profile().display_name.begins_with("Tutorial"), "rival %d plays %s" % [rival, brain.profile().display_name])
	# Keep the player's lane alive while the probe watches: gold for sends.
	if _lesson_ticks % 200 == 0:
		_me().gain(500)
		var sender: SendBuilding = _sender(1)
		for send in AiHand.sends_on(sender):
			if send.can_execute(sender):
				AiHand.order_send(1, sender, send)
	if _lesson_ticks == after_ticks:
		var line: MatchStatLine = References.match_stats.line_for(TutorialSetup.slot_for(rival))
		_note("rival %d after %d ticks: sends=%d lives=%d income=%d towers=%d" % [
			rival, after_ticks, line.sends, state.lives, state.income, line.towers_built])
		_check(line.sends > 0, "rival %d sent creeps once woken" % rival)
		# End it: the probe is not here to win a match.
		state.lives = 0
		state.lives_changed.emit(0)


func _play_research() -> void:
	if !_acted.has("vet"):
		if _shoot("l10_research"):
			return
		_acted["vet"] = true
		var vet: PlayerState = References.player_manager.state_for(TutorialSetup.SECOND_RIVAL_SLOT)
		_check(!vet.standby, "lesson 10: veteran woken")
		_check(ActionLimits.permits_research(1), "lesson 10: research open")
		_check(_pointer_target_name() == "ResearchButton",
			"lesson 10: arrow on the Research Center button (%s)" % _pointer_target_name())
		AiHand.order_ultimate(1, 3)


func _play_core() -> void:
	var builder: Builder = _builder()
	var area: PlayerArea = References.player_manager.area_for(1)
	if !_acted.has("core"):
		_acted["core"] = true
		_me().gain(1000)
		var core: BuildTowerAbility = AiHand.build_ability(builder, load(CORE) as BuildingStats)
		var cell: Vector2i = Vector2i(0, 40)
		AiHand.order_build(1, builder, core, area.footprint_world_center(cell, Vector2i(2, 2)), false)
		return
	if _lesson_ticks % 100 != 0:
		return
	for child in area.get_children():
		var tower: Building = child as Building
		if tower == null || tower.stats == null || tower.stats.resource_path != CORE:
			continue
		for entry in tower.current_abilities():
			var up: UpgradeTowerAbility = entry as UpgradeTowerAbility
			if up != null && up.can_execute(tower):
				AiHand.order_upgrade(1, tower, up)
				return


# --- reading the arrows ------------------------------------------------------

func _pointer_target_name() -> String:
	var pointer: TutorialPointer = get_tree().root.find_child("TutorialPointer", true, false) as TutorialPointer
	if pointer == null:
		return "<no pointer>"
	var target: Control = pointer._resolve()
	return "<none>" if target == null else String(target.name)


func _world_arrows() -> int:
	var arrows: Node = References.tutorial_director.get_node_or_null("WorldArrows")
	if arrows == null:
		return -1
	# Drawn on the render frame; make sure this frame's reading is current.
	(arrows as TutorialWorldArrows)._process(0.0)
	var count: int = 0
	for child in arrows.get_children():
		if (child as Node3D).visible:
			count += 1
	return count


func _open_cells(plan: TowerLayout, area: PlayerArea) -> int:
	var taken: Dictionary = {}
	for child in area.get_children():
		var building: Building = child as Building
		if building != null:
			taken[building.cell] = true
	var open: int = 0
	for cell: Vector2i in plan.cells:
		if !taken.has(cell):
			open += 1
	return open


func _sentry(director: TutorialDirector) -> BuildTowerAbility:
	for ability: UnitAbility in director.current_step().allowed_abilities:
		if ability is BuildTowerAbility:
			return ability as BuildTowerAbility
	return null


func _check(ok: bool, what: String) -> void:
	if ok:
		_passes.append(what)
		print("  PASS  " + what)
	else:
		_fail(what)


func _fail(what: String) -> void:
	_failures.append(what)
	print("  FAIL  " + what)


func _note(what: String) -> void:
	print("  NOTE  " + what)


func _finish() -> void:
	_done = true
	print("PROBE RESULT  lessons reached=%d  passes=%d  failures=%d" % [
		_lesson, _passes.size(), _failures.size()])
	for f in _failures:
		print("  failed: " + f)
	get_tree().quit()


func _session() -> MatchSession:
	return References.match_session


func _me() -> PlayerState:
	return References.player_manager.state_for(1)


func _builder() -> Builder:
	for unit: Unit in _session().live_units():
		var builder: Builder = unit as Builder
		if builder != null && builder.owner_player_id == 1:
			return builder
	return null


func _sender(tier: int) -> SendBuilding:
	var area: PlayerArea = References.player_manager.area_for(1)
	for sender in area.send_buildings():
		if sender.send_tier == tier && !sender.is_sudden_death_tier:
			return sender
	return null
