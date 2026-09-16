class_name FocusPolicy
extends RefCounted

## THIS GAME'S UI HAS NO KEYBOARD FOCUS. Tab moves nothing, Enter presses
## nothing, and a clicked button keeps no focus ring. A control is worked with
## the MOUSE or with its own hotkey, and those are the only two ways in.
##
## HOW IT IS DONE, and why it is not 58 hand edits. Every menu and HUD scene
## sets `focus_behavior_recursive = 1` (FOCUS_BEHAVIOR_DISABLED) on its ROOT,
## which turns focus off for that node and every Control under it - including
## the ones instanced into it at runtime, and including the button somebody
## adds to the scene next year. Godot walks that flag up the Control parent
## chain, so one line per scene covers the whole subtree. A prefab whose root
## is itself a Button carries the same line, so it is covered wherever it is
## instanced.
##
## **The chain BREAKS at a non-Control node**, measured on 4.7.2 - a plain Node
## or a CanvasLayer between two Controls stops it. That is why match_hud.tscn
## carries the line on each of its Control children rather than once at the top:
## its root is a CanvasLayer.
##
## THE ONE EXCEPTION IS TYPING, which cannot work without focus. A LineEdit or
## a SpinBox opts back in with `focus_behavior_recursive = 2`
## (FOCUS_BEHAVIOR_ENABLED) and `focus_mode = 1` (FOCUS_CLICK): clicking it
## starts typing, and nothing that is not a click can reach it.
##
## Nothing here runs unless a SpinBox asks for it. See the method below for the
## single case a .tscn cannot state for itself.


## Makes a SpinBox reachable by CLICK ONLY, its editor included.
##
## A SpinBox is two controls: the one the .tscn names, and a LineEdit INTERNAL
## to it that takes the typing. `focus_mode` authored on the outer one does not
## reach the inner one - it stays FOCUS_ALL - so Tab pressed inside one text
## field still lands on the editor of the next SpinBox along. That is the last
## thing Tab can do in this game, and this is what closes it.
##
## Call it once, from the screen that owns the spin. Harmless on null.
static func click_only(spin: SpinBox) -> void:
	if spin == null:
		return
	spin.focus_mode = Control.FOCUS_CLICK
	spin.get_line_edit().focus_mode = Control.FOCUS_CLICK
