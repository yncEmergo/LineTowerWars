class_name TutorialProbe
extends Node

## SCAFFOLDING - delete with Scenes/Dev/tutorial_probe.tscn when the tutorial
## work is done. Plays the whole tutorial headless through the real order road
## and prints what each lesson ACTUALLY did, including the orders the restricted
## lessons must refuse.
##
##   godot --path . --headless res://Scenes/Dev/tutorial_probe.tscn

const MATCH_SCENE: String = "res://Scenes/Main.tscn"
const ARCHER: String = "res://Resources/UnitStats/Towers/lesser_archer_stats.tres"
const CORE: String = "res://Resources/UnitStats/Towers/elemental_core_stats.tres"
const SHEEP: String = "res://Resources/UnitStats/Creeps/sheep_stats.tres"
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var setup: MatchSetup = TutorialSetup.create(_game_config, _ai_config)
	MenuNavigation.pending_match = setup
	Engine.physics_ticks_per_second = SPEED
	Engine.max_physics_steps_per_frame = 64
	add_child((load(MATCH_SCENE) as PackedScene).instantiate())
	print("PROBE started")


func _physics_process(_delta: float) -> void:
	if _done:
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
			_note("tutorial finished after lesson %d" % _lesson)
			_finish()
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
	match _lesson:
		1, 2:
			_play_build(director)
		3:
			_play_wave()
		4:
			_play_send()
		6:
			_play_upgrade()
		7:
			_play_beat(TutorialStep.Rival.FIRST, 1200)
		8:
			_play_research()
		9:
			_play_core()
		10:
			_play_beat(TutorialStep.Rival.SECOND, 1200)


func _play_build(director: TutorialDirector) -> void:
	var builder: Builder = _builder()
	var area: PlayerArea = director.local_area()
	var plan: TowerLayout = director.current_step().blueprint()
	if builder == null || area == null || plan == null:
		return

	if !_acted.has("forbidden"):
		_acted["forbidden"] = true
		var gold_before: int = _me().gold
		# An archer is not on this lesson's list.
		var archer: BuildTowerAbility = AiHand.build_ability(builder, load(ARCHER) as BuildingStats)
		_check(!ActionLimits.permits(archer, builder), "lesson %d: archer not permitted" % _lesson)
		# A sentry off the blueprint.
		var off: Vector2i = Vector2i(0, 40)
		_check(!area.can_place(off, Vector2i(2, 2)), "lesson %d: off-blueprint cell refused" % _lesson)
		var sentry: BuildTowerAbility = director.current_step().allowed_abilities[0] as BuildTowerAbility
		AiHand.order_build(1, builder, sentry, area.footprint_world_center(off, Vector2i(2, 2)), false)
		# An upgrade on any tower standing that has one on its card.
		for child in area.get_children():
			var tower: Building = child as Building
			var up: UpgradeTowerAbility = null if tower == null else AiHand.cheapest_upgrade(tower)
			if up != null:
				_check(!ActionLimits.permits(up, tower), "lesson %d: upgrade %s not permitted" % [_lesson, up.display_name])
				AiHand.order_upgrade(1, tower, up)
				break
		_acted["gold_before"] = gold_before
		return
	if !_acted.has("checked_gold"):
		_acted["checked_gold"] = true
		_check(_me().gold == int(_acted["gold_before"]),
			"lesson %d: forbidden orders cost nothing (gold %d -> %d)" % [
				_lesson, int(_acted["gold_before"]), _me().gold])
		_check(builder.has_pending_build() == false, "lesson %d: off-blueprint order not taken" % _lesson)
	if builder.has_pending_build():
		return
	var sentry_ability: BuildTowerAbility = director.current_step().allowed_abilities[0] as BuildTowerAbility
	for cell: Vector2i in plan.cells:
		if area.can_place(cell, Vector2i(2, 2)):
			AiHand.order_build(1, builder, sentry_ability, area.footprint_world_center(cell, Vector2i(2, 2)), false)
			return


func _on_lesson_opened() -> void:
	var rookie: MatchStatLine = References.match_stats.line_for(TutorialSetup.FIRST_RIVAL_SLOT)
	var vet: MatchStatLine = References.match_stats.line_for(TutorialSetup.SECOND_RIVAL_SLOT)
	if _lesson <= 7:
		_check(rookie.sends == 0, "lesson %d: the Rookie has sent nothing yet" % _lesson)
	if _lesson <= 7:
		_check(vet.sends == 0, "lesson %d: the Veteran has sent nothing yet" % _lesson)
		_check(References.player_manager.sends_into(1) == TutorialSetup.FIRST_RIVAL_SLOT,
			"lesson %d: the player sends into the Rookie" % _lesson)
	if _lesson == 5:
		var in_rookie_lane: int = 0
		for creep in References.player_manager.area_for(TutorialSetup.FIRST_RIVAL_SLOT).creeps():
			if creep.owner_player_id == 1:
				in_rookie_lane += 1
		_note("lesson 5: %d of the player's creeps are walking the Rookie's lane" % in_rookie_lane)
	if _lesson <= 7:
		_check(!ActionLimits.permits_research(1), "lesson %d: research still shut" % _lesson)


func _play_wave() -> void:
	if !_acted.has("wave"):
		_acted["wave"] = true
		var area: PlayerArea = References.tutorial_director.local_area()
		_check(area.creeps().size() > 0, "lesson 3: a wave was spawned (%d creeps)" % area.creeps().size())
	if _lesson_ticks % 20 == 0:
		_note("lesson 3: t=%.1fs  %d creeps left, player lives %d" % [_lesson_ticks / 20.0, References.tutorial_director.local_area().creeps().size(), _me().lives])


func _play_send() -> void:
	var sender: SendBuilding = _sender(1)
	var sheep: CreepStats = load(SHEEP) as CreepStats
	if sender == null:
		return
	if !_acted.has("checked"):
		_acted["checked"] = true
		_check(sender.stock_for(sheep).count == 4, "lesson 4: sheep stock is exactly 4 (%d)" % sender.stock_for(sheep).count)
		_check(_me().gold == 40, "lesson 4: gold is exactly 40 (%d)" % _me().gold)
		# Something else on the card must be refused.
		for send in AiHand.sends_on(sender):
			if send.creep_stats != sheep:
				_check(!ActionLimits.permits(send, sender), "lesson 4: %s not permitted" % send.creep_stats.display_name)
				break
		return
	var sends: int = int(_acted.get("sends", 0))
	if sends < 6 && _lesson_ticks % 40 == 0:
		_check(sender.stock_for(sheep).count == 4 - sends,
			"lesson 4: before send %d the stock is %d, nothing refilled" % [sends + 1, sender.stock_for(sheep).count])
		AiHand.order_send(1, sender, AiHand.send_ability(sender, sheep))
		_acted["sends"] = sends + 1


func _play_upgrade() -> void:
	if _acted.has("up") && _lesson_ticks % 200 != 0:
		return
	_acted["up"] = true
	var area: PlayerArea = References.tutorial_director.local_area()
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
		_acted["vet"] = true
		var vet: PlayerState = References.player_manager.state_for(TutorialSetup.SECOND_RIVAL_SLOT)
		_check(!vet.standby, "lesson 8: veteran woken")
		_check(ActionLimits.permits_research(1), "lesson 8: research open")
		AiHand.order_ultimate(1, 3)


func _play_core() -> void:
	var builder: Builder = _builder()
	var area: PlayerArea = References.tutorial_director.local_area()
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
