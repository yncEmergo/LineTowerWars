class_name ShotProbe
extends Node

## SCAFFOLDING. Opens a screen, waits a few frames for it to lay itself out, and
## writes a PNG.
##
## It exists because the only other way to look at a layout is to open the
## editor, and a headless run has no renderer at all - so a screen that parses,
## boots and reports no errors can still be a stack of controls on top of each
## other. Delete this and Scenes/Dev when the work is done; see CLAUDE.md.
##
## Run it WINDOWED:
##   godot --path <project> Scenes/Dev/shot_probe.tscn -- --scene <res path> --out <png>

## Frames to wait before the shot. A Control's rect is not final until the
## layout has settled, and a scene that instances others needs a few more.
const SETTLE_FRAMES: int = 30

@export var _fallback_scene: PackedScene

var _frames: int = 0
var _out: String = ""
var _shot: bool = false


func _ready() -> void:
	_out = _argument("--out", "user://shot.png")
	# Parks a match before the scene opens, for the screens that read one off
	# MenuNavigation - which is the road every OFFLINE match takes.
	if _argument("--setup", "") == "skirmish":
		MenuNavigation.pending_match = _skirmish_setup()
	elif _argument("--setup", "") == "tutorial":
		MenuNavigation.pending_match = TutorialSetup.create(
			load("res://Resources/Config/game_config.tres") as GameConfig,
			load("res://Resources/Config/ai_config.tres") as AiConfig
		)

	var path: String = _argument("--scene", "")
	var scene: PackedScene = _fallback_scene
	if !path.is_empty():
		scene = load(path) as PackedScene
	if scene == null:
		print("SHOT FAIL: no scene")
		return
	add_child(scene.instantiate())


func _process(_delta: float) -> void:
	_frames += 1
	if _shot || _frames < SETTLE_FRAMES:
		return
	_shot = true

	var image: Image = get_viewport().get_texture().get_image()
	var error: Error = image.save_png(_out)
	print("SHOT %s error=%d size=%s" % [_out, error, image.get_size()])
	get_tree().quit()


func _argument(flag: String, fallback: String) -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index in range(args.size() - 1):
		if args[index] == flag:
			return args[index + 1]
	return fallback


## A two player skirmish, built the way the setup screen builds one.
func _skirmish_setup() -> MatchSetup:
	var config: GameConfig = load("res://Resources/Config/game_config.tres") as GameConfig
	var setup: MatchSetup = MatchSetup.new()
	setup.mode = MatchSetup.Mode.SKIRMISH
	setup.match_id = "skirmish"
	setup.local_slot = 1
	setup.rng_seed = 4242
	setup.settings = MatchSettings.defaults(config)
	setup.settings.is_ranked = false
	setup.players.append(MatchPlayer.create(1, "You", 0, 0))
	setup.players.append(MatchPlayer.create(2, "Normal AI 1", 0, 1, 1))
	return setup
