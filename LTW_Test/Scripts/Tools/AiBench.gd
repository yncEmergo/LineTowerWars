class_name AiBench
extends Node

## Plays computer opponents against each other and reports what happened.
##
##   godot --path . --headless res://Scenes/Tools/ai_bench.tscn -- a=hard b=normal
##   godot --path . --headless res://Scenes/Tools/ai_bench.tscn -- players=4 minutes=25
##
## **The question it answers is "is this difficulty actually harder than that
## one", and there is no other way to ask it.** A profile is a dozen numbers -
## three spending floors, a send beat, a maze, an Ultimate - and what they add
## up to is a match, not a sum. Reading them is guessing; playing them is not.
##
## KEPT TOOLING rather than scaffolding, on the same terms as PerfBench and
## IconGen3D: the question is asked again every time a difficulty is retuned,
## every time the roster changes what a tower is worth, and every time somebody
## argues that Hard is too easy. See CLAUDE.md under Project structure.
##
## It plays a REAL MATCH - the ordinary match scene, the ordinary economy, the
## ordinary send ring - with every seat taken by a profile and nobody watching.
## Nothing in it is a model of the game.
##
## **It runs the engine flat out rather than in real time.** A twenty-five
## minute match takes twenty-five minutes at twenty ticks a second and nobody
## is going to wait for that, so the physics rate is raised for the run and put
## back afterwards. Nothing in the simulation reads the engine's rate - the
## whole delta refactor is what made that safe (MatchSession._sim_ticks_per_second)
## - so a match played fast is the same match.

## Match scene to instance underneath the bench. The CLIENT one, deliberately:
## the server scene wires no HUD and no camera, and an AI reads neither, but a
## bench that measured a different scene from the one players run would be
## answering a slightly different question every time one of them changed.
const MATCH_SCENE: String = "res://Scenes/Main.tscn"

## How fast to run the engine. Twenty is real time; anything above it is the
## same match in less of your afternoon.
const DEFAULT_SPEED: int = 20

@export_group("Settings")
@export var _ai_config: AiConfig
@export var _game_config: GameConfig

var _minutes: float = 25.0
var _speed: int = DEFAULT_SPEED
var _authored_rate: int = 60
var _started_msec: int = 0
var _done: bool = false


func _ready() -> void:
	# Immune to anything that holds the world - a technology reveal at the start
	# of the match - so the bench's own clock is not stopped by the match it is
	# watching.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_minutes = maxf(0.5, _number("minutes", 25.0))
	_speed = maxi(DEFAULT_SPEED, int(_number("speed", 240.0)))

	var setup: MatchSetup = _build_setup()
	if setup == null:
		get_tree().quit()
		return

	_authored_rate = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = _speed
	_started_msec = Time.get_ticks_msec()

	print("AI BENCH  %d players, %s minutes, engine at %d Hz" % [
		setup.player_count(), StringUtil.trim_number(_minutes, 1), _speed,
	])
	for player in setup.players:
		print("  slot %d  %s" % [player.slot, player.display_name])

	MenuNavigation.pending_match = setup
	var scene: PackedScene = load(MATCH_SCENE) as PackedScene
	if scene == null:
		print("AI BENCH FAILED: the match scene did not load")
		_finish()
		return
	add_child(scene.instantiate())


## The roster: every seat an AI, at whatever difficulties were asked for.
##
## `a=` and `b=` name the first two by their profile's display name, which is
## what somebody comparing two difficulties actually types. `players=` fills the
## rest with the first of them, so a four player free for all is one argument.
func _build_setup() -> MatchSetup:
	if _ai_config == null || _game_config == null:
		print("AI BENCH FAILED: no AiConfig or GameConfig wired on the bench")
		return null

	var first: int = _difficulty(_text("a", "Normal"))
	var second: int = _difficulty(_text("b", _text("a", "Normal")))
	if first < 0 || second < 0:
		return null

	var count: int = clampi(int(_number("players", 2.0)), 2, 12)
	var setup: MatchSetup = MatchSetup.new()
	setup.mode = MatchSetup.Mode.SKIRMISH
	setup.match_id = "ai_bench"
	# SLOT 0: nobody is playing, so nothing is drawn for anybody and every
	# is-this-mine test answers no. The bench is a spectator with no camera.
	setup.local_slot = 0
	setup.rng_seed = int(_number("seed", float(randi())))
	setup.settings = MatchSettings.defaults(_game_config)
	setup.settings.is_ranked = false
	# Lanes in the order they were asked for, so "a beat b" means what it says.
	setup.settings.random_lanes = false

	for slot in range(1, count + 1):
		var difficulty: int = second if slot == 2 else first
		var profile: AiProfile = _ai_config.profile_for(difficulty)
		var label: String = "?" if profile == null else profile.display_name
		setup.players.append(MatchPlayer.create(
			slot, "%s %d" % [label, slot], 0, slot - 1, difficulty
		))
	return setup


## Ends the run when the match is decided or the clock runs out.
##
## The MATCH clock rather than a wall clock, so "twenty-five minutes" means
## twenty-five minutes of play however fast the engine was driven - which is the
## only reading that is comparable between two runs.
func _physics_process(_delta: float) -> void:
	if _done:
		return

	var session: MatchSession = References.match_session
	var manager: PlayerManager = References.player_manager
	if session == null || manager == null:
		return

	if manager.is_match_over() || session.elapsed_seconds() >= _minutes * 60.0:
		_finish()


## Prints the result and leaves.
##
## Read off MatchStats, which counted every one of these for the end screen
## anyway - so the bench adds no accounting of its own and cannot disagree with
## what a player would have been shown.
func _finish() -> void:
	_done = true
	set_physics_process(false)
	Engine.physics_ticks_per_second = _authored_rate

	var stats: MatchStats = References.match_stats
	var record: MatchSummary = null if stats == null else stats.take_summary()
	var real: float = float(Time.get_ticks_msec() - _started_msec) / 1000.0

	if record == null:
		print("AI BENCH: no record was kept of that match")
		get_tree().quit()
		return

	print("")
	print("AI BENCH RESULT  %s of play in %s real seconds%s" % [
		record.duration_text(), StringUtil.trim_number(real, 1),
		"  (Sudden Death)" if record.reached_sudden_death else "",
	])
	_print_table(record)
	get_tree().quit()


## One line per player, in finishing order.
##
## Columns chosen for the one question the bench is asked: whether a difficulty
## is really harder. Lives and placement say who won; income and sends say how
## they were playing; towers say what they spent it on.
func _print_table(record: MatchSummary) -> void:
	print("  %-4s %-22s %5s %8s %8s %7s %7s %7s" % [
		"", "player", "lives", "income", "spent", "towers", "sent", "killed",
	])
	for line in record.lines:
		print("  %-4s %-22s %5d %8s %8s %7d %7d %7d" % [
			line.placement_text(), line.display_name, line.lives_left,
			StringUtil.compact_number(line.peak_income),
			StringUtil.compact_number(line.gold_spent()),
			line.towers_built, line.creeps_sent, line.creeps_killed,
		])
		if !line.ultimates.is_empty():
			print("       %s" % ", ".join(line.ultimates))


## A profile's index, by the display name its .tres carries.
##
## By NAME rather than by index, because an index is a position in a list and
## the point of typing one here is to say which DIFFICULTY - see
## AiConfig.selectable_indices for why the two are different numbers.
func _difficulty(wanted: String) -> int:
	for index in range(_ai_config.count()):
		var profile: AiProfile = _ai_config.profile_for(index)
		if profile != null && profile.display_name.to_lower() == wanted.to_lower():
			return index

	var names: PackedStringArray = _ai_config.names()
	print("AI BENCH FAILED: no difficulty called '%s'. There is: %s" % [
		wanted, ", ".join(names),
	])
	return -1


## One `name=value` argument, or the fallback. The same shape PerfBench reads
## its own with, so both benches are driven the same way.
func _text(key: String, fallback: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(key + "="):
			return argument.substr(key.length() + 1)
	return fallback


func _number(key: String, fallback: float) -> float:
	var found: String = _text(key, "")
	return fallback if found.is_empty() else found.to_float()
