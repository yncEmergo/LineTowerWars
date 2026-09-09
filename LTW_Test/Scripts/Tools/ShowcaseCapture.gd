class_name ShowcaseCapture
extends Node

## Saves a PNG of the scene it is sitting in, then quits.
##
## KEPT, not scaffolding, and it sits beside IconGen3D for the same reason
## that one does: it has to RUN INSIDE GODOT, because saving a picture means
## rendering one. The SCENES it photographs are throwaway and live in
## Scenes/Dev; the thing that photographs them is wanted again every time a
## roster or the style changes.
##
## It was written because the last one had been deleted as scaffolding and
## the review it exists for - PLACEHOLDER_ART.md section 9, look at it -
## then needed it rebuilt from the docstring that described it.
##
## It is a NODE IN THE SCENE rather than a `--script` main loop, and that is
## the whole reason it works. A `--script` loop gets no autoloads and no global
## class table, so every model that carries an animation component would fail
## to resolve one and the review scene would come up as a field of bare meshes
## - a picture of nothing, which is worse than no picture because it looks like
## an answer. Run as an ordinary scene, everything is exactly what the game
## loads.
##
## IT MUST RUN WINDOWED. Baking an image means rendering one, and a headless
## run installs the dummy driver - so the capture comes back black with no
## error anywhere. Same family of trap as reading a MultiMesh transform back
## under --headless, which CLAUDE.md has the long version of.
##
##     godot --path . --resolution 1600x900 \
##         res://Scenes/Dev/showcase_archer.tscn -- shot.png
##
## With no `--` argument it does nothing at all, so a showcase scene opened by
## hand in the editor is unaffected by its presence.

## Frames to let pass before the shot. Three things need them and the slowest
## decides: the shaders compile on first draw, the model animations settle from
## whatever pose they were authored at, and Godot needs at least one full frame
## in the buffer to read back.
const SETTLE_FRAMES: int = 12


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		return
	_capture(args[0])


func _capture(path: String) -> void:
	for _index: int in range(SETTLE_FRAMES):
		await get_tree().process_frame

	var image: Image = get_viewport().get_texture().get_image()
	if image == null:
		Log.err("ShowcaseCapture got no image back from the viewport", path)
		get_tree().quit(1)
		return

	var error: int = image.save_png(path)
	if error != OK:
		Log.err("ShowcaseCapture could not write its PNG", "%s (%d)" % [path, error])
		get_tree().quit(1)
		return

	print("captured %s (%dx%d)" % [path, image.get_width(), image.get_height()])
	get_tree().quit(0)
