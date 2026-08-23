class_name MenuNavigation

## Every scene change outside a running match, in one place - the menus, the
## loading screen, and the server's own two scenes.
##
## A menu button ends here rather than calling change_scene_to_file itself, so
## the res:// paths live only on MenuConfig and a dead path is reported the same
## way from every screen.
##
## pending_lobby is the one piece of state that has to survive a scene change:
## which lobby the room screen is about to show. It is static only because there
## is no networking layer yet to own it. Whatever backend we pick will hold the
## live lobby instead and this goes away - see multiplayer.md.

## The lobby the room screen should display, handed over across the scene change.
static var pending_lobby: LobbyInfo = null
## The match the game scene should build, handed over the same way. Consumed
## once by take_pending_match() so a later direct run of Main.tscn cannot
## silently inherit the players of whatever lobby ran last.
static var pending_match: MatchSetup = null
## One line for the screen we are about to land on to explain why we are there:
## "The host left the lobby", and in 1.8 every other way a connection can end.
## Consumed once, for the same reason as pending_match.
static var pending_notice: String = ""


static func to_main_menu(from: Node) -> void:
	var config: MenuConfig = _config()
	if config != null:
		_change_scene(from, config.main_menu_scene_path)


static func to_lobby_browser(from: Node) -> void:
	pending_lobby = null
	var config: MenuConfig = _config()
	if config != null:
		_change_scene(from, config.lobby_browser_scene_path)


static func to_lobby_room(from: Node, lobby: LobbyInfo) -> void:
	pending_lobby = lobby
	var config: MenuConfig = _config()
	if config != null:
		_change_scene(from, config.lobby_room_scene_path)


## The screen shown between the start handshake and the match: the threaded
## load of the game scene, and who is still loading it. It reads what it needs
## off the `MatchStart` autoload, so there is nothing to hand over.
static func to_match_loading(from: Node) -> void:
	var config: MenuConfig = _config()
	if config != null:
		_change_scene(from, config.match_loading_scene_path)


## The server changing its own scene: into a match, and back out of it when
## the match is over.
##
## The path is an ARGUMENT rather than read from BootConfig here, because the
## way back is called from inside the match scene - where References answers
## with the match's own node and has never heard of a BootConfig. The caller
## reads both paths once, while the server entry scene is still up.
static func to_server_scene(from: Node, path: String, setup: MatchSetup = null) -> void:
	pending_match = setup
	_change_scene(from, path)


## setup is null for a plain single player run, which makes the game scene
## stand one in for itself.
static func to_game(from: Node, setup: MatchSetup = null) -> void:
	pending_match = setup
	var config: MenuConfig = _config()
	if config != null:
		_change_scene(from, config.game_scene_path)


## The pending match, cleared as it is handed over. Null when the game scene
## was opened directly rather than from a lobby.
static func take_pending_match() -> MatchSetup:
	var setup: MatchSetup = pending_match
	pending_match = null
	return setup


## The notice for this screen, cleared as it is handed over, so a message about
## one visit cannot reappear on the next.
static func take_pending_notice() -> String:
	var notice: String = pending_notice
	pending_notice = ""
	return notice


static func quit_game(from: Node) -> void:
	var tree: SceneTree = from.get_tree()
	if tree == null:
		Log.err("MenuNavigation cannot quit, the caller is not in the tree", from.name)
		return
	tree.quit()


static func _config() -> MenuConfig:
	var config: MenuConfig = References.menu_config
	if config == null:
		Log.err("MenuNavigation found no MenuConfig on References, no menu button works")
	return config


static func _change_scene(from: Node, path: String) -> void:
	SceneUtil.change_scene(from, path, "MenuNavigation")
