extends SceneTree

## Renders a review scene to a PNG and quits.
##
##   godot --path . --resolution 1600x900
##       --script res://Scripts/Dev/CaptureRunner.gd --
##       res://Scenes/Dev/creep_showcase.tscn out.png [frames]
##
## The other half of "run them rather than screenshotting the editor viewport"
## in PLACEHOLDER_ART.md: the editor's own capture renders these scenes unlit,
## a headless run has no renderer at all, and screenshotting a live match
## catches whatever happened to be walking past. This runs the scene for real,
## waits for it to settle and saves what it looks like.
##
## It knows nothing about any roster, so it works on every showcase scene the
## generator writes and on anything else worth looking at once.

var _out: String = "creep_showcase.png"
var _left: int = 40


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: <scene.tscn> <out.png> [frames]")
		quit(1)
		return

	_out = args[1]
	if args.size() > 2:
		_left = int(args[2])

	var scene: PackedScene = load(args[0]) as PackedScene
	if scene == null:
		print("could not load %s" % args[0])
		quit(1)
		return
	root.add_child(scene.instantiate())


func _process(_delta: float) -> bool:
	_left -= 1
	if _left > 0:
		return false
	var image: Image = root.get_texture().get_image()
	if image == null:
		print("no image")
		return true
	image.save_png(_out)
	print("wrote %s (%dx%d)" % [_out, image.get_width(), image.get_height()])
	return true
