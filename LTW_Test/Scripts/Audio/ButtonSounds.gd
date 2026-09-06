class_name ButtonSounds
extends Node

## Drop this under a button to CHANGE what that button sounds like. Its absence
## is what "normal" means - every BaseButton in the project already clicks
## without one. See ButtonSoundBinder.
##
## **This is an override marker, not the thing that makes a button audible**,
## and that is the one way it differs from the version it came from. There it
## was the carrier: a button was silent until somebody added the node. With 58
## buttons across 19 scenes that is 58 hand edits and a 59th button that gets
## forgotten - silently, with no error, just a button that does not click, which
## is the wrong failure mode for something whose entire job is feedback.
##
## Inverted, the count goes the other way: nothing to author for the ordinary
## case, and a node only where a button genuinely differs. A Send button that
## should thunk rather than click. A key-capture row that should say nothing at
## all while it is waiting for a keystroke.
##
## A plain Node, not a Control. The original had to be a Control because it
## carried an invisible second Button to catch clicks on a disabled one - Godot
## emits no `pressed` for those. It turns out `gui_input` fires on a disabled
## button anyway, measured on 4.7.2, so the catcher and the two "has to be
## called externally" methods that resized it are all gone. A Node has no
## layout, so this cannot disturb the button it is under.

@export_group("Settings")
## Whether this button makes a sound when pressed.
@export var use_click: bool = true
## Whether it makes one when the mouse enters it. Worth turning off for a dense
## grid the mouse crosses on the way to somewhere else.
@export var use_hover: bool = true
## Whether a press that landed while DISABLED says so.
@export var use_refused: bool = true

@export_group("Overrides")
## Played instead of AudioConfig.ui_click_path. Empty keeps the default.
@export_file("*.wav", "*.ogg") var click_path: String = ""
## Played instead of AudioConfig.ui_hover_path. Empty keeps the default.
@export_file("*.wav", "*.ogg") var hover_path: String = ""
## Played instead of AudioConfig.ui_refused_path. Empty keeps the default.
@export_file("*.wav", "*.ogg") var refused_path: String = ""


## The marker under this button, or null when it has none.
##
## Looked up when the button is USED rather than when it is wired, deliberately.
## A scene's nodes enter the tree parent first, so at the moment the binder sees
## a Button its own children may not have arrived yet - and a button built in
## code could gain this node at any point afterwards. One scan of a handful of
## children per click costs nothing and cannot be wrong.
##
## A NAME COLLISION COST A DEBUGGING CYCLE HERE, and the shape of it is worth
## more than this method is. Called `on()` at first, it failed to PARSE with
## "Static function on() not found in base ButtonSounds" - in a file that
## plainly declares it. The cause was not the name: the reference copy this
## class was rewritten from, sitting under ReferenceFilesFromOtherProjects,
## still declared `class_name ButtonSounds` too, and the global class cache
## had resolved that identifier to THAT file. Every call was reaching a
## different class than the one being read.
##
## Two things make it nasty. It CASCADES: ButtonSoundBinder then failed to
## compile, AudioHub could not call ButtonSoundBinder.new(), and the visible
## symptom was 26 buttons found and 0 bound - three layers from the cause. And
## it is UNSTABLE: which of two files claiming one class_name wins the cache
## depends on scan order, so an isolation test "proved" the name was at fault
## on a run where this file happened to win. A negative result only counts if
## the test exercised the right case, and that one did not.
##
## The lesson for the next class rewritten from that folder: comment the
## original out FIRST. An orphaned class_name in an unreferenced file is not
## inert - Godot scans it, and it competes.
static func find_marker(button: BaseButton) -> ButtonSounds:
	for child: Node in button.get_children():
		var marker: ButtonSounds = child as ButtonSounds
		if marker != null:
			return marker
	return null
