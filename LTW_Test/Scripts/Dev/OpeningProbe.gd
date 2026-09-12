class_name OpeningProbe
extends Node

## SCAFFOLDING. Drives a single player match through one of the openings and
## through the end of a match, headless, and prints what happened.
##
## Delete this and Scenes/Dev when the opening work is finished - see CLAUDE.md.
##
## Run it as:
##   godot --path <project> --headless Scenes/Dev/opening_probe.tscn -- --opening random
##   ... -- --opening draft
##   ... -- --opening end

@export var _game_scene: PackedScene

var _mode: String = "random"
var _frames: int = 0
var _killed: bool = false
var _summary_taken: bool = false


func _ready() -> void:
	# ALWAYS, or the probe stops counting exactly while the thing it is
	# watching is holding the world - which reads as an opening that never
	# happened rather than as one it could not see.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mode = _argument("--opening", "random")
	# Loaded directly: the probe runs BEFORE the match scene is added, so the
	# References node that would answer for it does not exist yet.
	var config: GameConfig = load("res://Resources/Config/game_config.tres") as GameConfig
	var setup: MatchSetup = MatchSetup.from_config(config)
	# Two players, so the ring and the end condition both mean something.
	setup.players.clear()
	setup.players.append(MatchPlayer.create(1, "Probe One"))
	setup.players.append(MatchPlayer.create(2, "Probe Two"))
	setup.local_slot = 1
	setup.rng_seed = 12345

	match _mode:
		"random":
			setup.settings.tech_mode = MatchSettings.TechMode.RANDOM
		"draft":
			setup.settings.tech_mode = MatchSettings.TechMode.DRAFT
		_:
			setup.settings.tech_mode = MatchSettings.TechMode.PICK

	MenuNavigation.pending_match = setup
	if _game_scene == null:
		print("PROBE FAIL: no game scene assigned")
		return
	add_child(_game_scene.instantiate())
	print("PROBE start mode=", _mode)


func _physics_process(_delta: float) -> void:
	_frames += 1
	var opening: StartingTech = References.starting_tech
	var session: MatchSession = References.match_session
	if opening == null || session == null:
		return

	if _frames % 10 == 0:
		print("PROBE t=%d paused=%s holding=%s draft=%s reveal=%s left=%.1f rolled=%s" % [
			_frames, session.is_paused(), opening.is_holding(), opening.is_drafting(),
			opening.is_revealing(), opening.seconds_left(), _rolled_name(opening),
		])

	if _mode == "end":
		_drive_end()
	if _frames > int(_argument("--frames", "400")):
		_report()
		get_tree().quit()


## Kills player 2 outright once the world is moving, which is the shortest road
## to a settled match: PlayerManager gives them a placement on the next tick,
## the survivor takes first, and match_ended fires.
func _drive_end() -> void:
	if _killed || _frames < 60:
		return
	var manager: PlayerManager = References.player_manager
	if manager == null:
		return
	var victim: PlayerState = manager.state_for(2)
	if victim == null:
		return
	victim.lives = 0
	_killed = true
	print("PROBE killed player 2 at t=", _frames)


func _report() -> void:
	var opening: StartingTech = References.starting_tech
	var manager: PlayerManager = References.player_manager
	var stats: MatchStats = References.match_stats
	print("PROBE report mode=", _mode)
	print("PROBE   holding=", opening != null && opening.is_holding())
	print("PROBE   rolled=", _rolled_name(opening))
	if manager != null:
		print("PROBE   over=", manager.is_match_over(),
			" p1_place=", _placement(manager, 1), " p2_place=", _placement(manager, 2))
	if stats == null:
		print("PROBE   NO MatchStats")
		return

	var record: MatchSummary = stats.summary()
	if record == null:
		print("PROBE   summary=none")
		return
	_summary_taken = true
	print("PROBE   summary winner=", record.winner_slot,
		" length=", record.duration_text(), " lines=", record.lines.size())
	for line in record.lines:
		print("PROBE   line slot=", line.slot, " place=", line.placement_text(),
			" lives=", line.lives_left, " towers=", line.towers_built,
			" sent=", line.creeps_sent, " killed=", line.creeps_killed,
			" income_gold=", line.gold_from_income,
			" ultimates=", line.ultimates)


func _placement(manager: PlayerManager, slot: int) -> int:
	var state: PlayerState = manager.state_for(slot)
	return -1 if state == null else state.placement


func _rolled_name(opening: StartingTech) -> String:
	if opening == null || opening.rolled_tech() == null:
		return "-"
	return opening.rolled_tech().ultimate_name


func _argument(flag: String, fallback: String) -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index in range(args.size() - 1):
		if args[index] == flag:
			return args[index + 1]
	return fallback
