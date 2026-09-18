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
var _shot_name: String = ""
var _shot_frames: int = 0
var _shots_taken: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_shots = "shots" in OS.get_cmdline_user_args()
	var setup: MatchSetup = TutorialSetup.create(_game_config, _ai_config)
	MenuNavigation.pending_match = setup
	Engine.physics_ticks_per_second = SPEED
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
			_note("tutorial finished after lesson %d, %d gaps between lessons seen" % [
				_lesson, _gaps_seen])
			_check(_gaps_seen > 0, "lessons waited out their delay")
			_finish()
		return

	if director.is_between_lessons() != _was_between:
		_was_between = director.is_between_lessons()
		if _was_between:
			_gaps_seen += 1
	if director.is_between_lessons():
		return

	if director.lesson_number() != _lesson:
		_lesson = director.lesson_number()
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


func _play(director: TutorialDirector) -> void:
	match _lesson:
		1:
			_play_select_builder()
		2, 4:
			_play_build(director)
		3, 5:
			_play_wave()
		6:
			_play_send()
		8:
			_play_upgrade()
		9:
			_play_beat(TutorialStep.Rival.FIRST, 1200)
		10:
			_play_research()
		11:
			_play_core()
		12:
			_play_beat(TutorialStep.Rival.SECOND, 1200)


func _on_lesson_opened() -> void:
	var rookie: MatchStatLine = References.match_stats.line_for(TutorialSetup.FIRST_RIVAL_SLOT)
	var vet: MatchStatLine = References.match_stats.line_for(TutorialSetup.SECOND_RIVAL_SLOT)
	if _lesson <= 9:
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
		_check(off[1] == int(off[2]) + 1, "lesson %d: %d cell arrows + 1 builder arrow (%d)" % [_lesson, off[2], off[1]])
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
		_check(_world_arrows() == _open_cells(plan, area),
			"lesson %d: one arrow per open cell (%d)" % [_lesson, _world_arrows()])

	if !_acted.has("forbidden"):
		_acted["forbidden"] = true
		var gold_before: int = _me().gold
		var archer: BuildTowerAbility = AiHand.build_ability(builder, load(ARCHER) as BuildingStats)
		_check(!ActionLimits.permits(archer, builder), "lesson %d: archer not permitted" % _lesson)
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


func _play_send() -> void:
	var sender: SendBuilding = _sender(1)
	var sheep: CreepStats = load(SHEEP) as CreepStats
	if sender == null:
		return
	if !_acted.has("checked"):
		if _shoot("l6_send_bar"):
			return
		_acted["checked"] = true
		_check(_pointer_target_name() == "SendTier1",
			"lesson 6: sender not selected, arrow on its button (%s)" % _pointer_target_name())
		_check(sender.stock_for(sheep).count == 4, "lesson 6: sheep stock is exactly 4 (%d)" % sender.stock_for(sheep).count)
		_note("lesson 6: gold %d (40 granted, the rest wave bounty)" % _me().gold)
		for send in AiHand.sends_on(sender):
			if send.creep_stats != sheep:
				_check(!ActionLimits.permits(send, sender), "lesson 6: %s not permitted" % send.creep_stats.display_name)
				break
		References.selection_controller.select_single(sender)
		return
	if !_acted.has("slot"):
		if _shoot("l6_sheep_square"):
			return
		_acted["slot"] = true
		_check(_pointer_target_name().begins_with("CommandSlot"),
			"lesson 6: sender selected, arrow on the Sheep square (%s)" % _pointer_target_name())
	var sends: int = int(_acted.get("sends", 0))
	if sends < 6 && _lesson_ticks % 40 == 0:
		_check(sender.stock_for(sheep).count == 4 - sends,
			"lesson 6: before send %d the stock is %d, nothing refilled" % [sends + 1, sender.stock_for(sheep).count])
		AiHand.order_send(1, sender, AiHand.send_ability(sender, sheep))
		_acted["sends"] = sends + 1


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
