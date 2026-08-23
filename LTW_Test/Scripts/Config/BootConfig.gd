class_name BootConfig
extends Resource

## How the process decides what it is, and where the server starts.
## Stored as Resources/Config/boot_config.tres, reached via References.boot_config.
##
## Read once, by the boot scene, before anything else exists. The same line of
## code selects client or server in the editor and in an exported build, so
## there is no if-debug-build special case anywhere - see multiplayer.md.
##
## Only the SERVER's entry scene is named here. The client's is
## MenuConfig.main_menu_scene_path, which already exists and is already the one
## authority on where the menus start. Copying it into a second .tres would give
## a renamed scene two files to be fixed in, and the editor rewrites neither.

@export_group("Scenes")
## The dedicated server's entry scene. Never loaded by a client.
@export_file("*.tscn") var server_scene_path: String = ""
## The scene the server opens when a match begins: the same match with no
## camera, HUD, controllers or effects root. The client's equivalent is
## MenuConfig.game_scene_path, and the two are deliberately different scenes
## rather than one scene with half its nodes switched off.
@export_file("*.tscn") var server_match_scene_path: String = ""

@export_group("Settings")
## Launch argument that forces the server, checked alongside the
## dedicated_server feature tag.
##
## The tag is the clean answer and the one an exported server build carries.
## The argument is what you need in order to start a SECOND server on another
## port, or to force the role on a machine whose tags you do not control.
##
## Godot treats an unrecognised argument before "--" as an engine argument and
## complains, so pass it after one:  godot -- --server
@export var server_argument: String = "--server"


func validate() -> bool:
	var complete: bool = true
	complete = _validate_path(server_scene_path, "server_scene_path") && complete
	complete = _validate_path(server_match_scene_path, "server_match_scene_path") && complete
	return complete


func _validate_path(path: String, field_name: String) -> bool:
	if SceneUtil.exists(path):
		return true
	Log.err("BootConfig path does not resolve", {"field": field_name, "path": path})
	return false
