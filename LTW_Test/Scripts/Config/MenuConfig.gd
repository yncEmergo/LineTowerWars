class_name MenuConfig
extends Resource

## Menu flow settings: which scene each menu button leads to, plus the numbers
## and strings the menu screens read.
## Stored as Resources/Config/menu_config.tres, reached via References.menu_config.
##
## Scenes are named by res:// PATH rather than held as PackedScene exports, the
## same rule the stats resources follow. A PackedScene inside a .tres is a hard
## load-time dependency, so one missing target would null every property of this
## file. A path also keeps the whole 3D game out of the main menu's own load,
## which a PackedScene export would drag in at boot.
##
## The editor does NOT rewrite a path string when a scene moves or is renamed,
## so validate() checks every path once, when a menu screen opens.

@export_group("Scenes")
@export_file("*.tscn") var main_menu_scene_path: String = ""
@export_file("*.tscn") var lobby_browser_scene_path: String = ""
@export_file("*.tscn") var lobby_room_scene_path: String = ""
## The playable scene. Currently the 1v1 prototype test scene.
@export_file("*.tscn") var game_scene_path: String = ""
## Shown between pressing Start and the match beginning: the threaded load of
## the game scene, and who is still loading it.
@export_file("*.tscn") var match_loading_scene_path: String = ""

@export_group("Branding")
## Working title. The game has no name yet, so every screen reads it from here
## instead of spelling it out.
@export var game_title: String = "LINE TOWER WARS"
@export var version_text: String = "prototype"

@export_group("Lobby")
## Free for all only, no team modes, see game_rules.md. Two is the smallest
## real match, which is also the prototype's 1v1.
@export var min_players: int = 2
## Seats one lobby opens at most. Must stay at or under the map's slot count,
## GameConfig.area_columns * area_rows, or the extra players get no lane -
## Main says so at boot when it happens. Not read off GameConfig directly
## because the menus never wire one.
@export var max_players: int = 12
## Slots a freshly created lobby opens with.
@export var default_lobby_size: int = 2
## Pattern for the name a new lobby is offered, given the host's display name.
@export var default_lobby_name_pattern: String = "%s's Game"
@export var max_lobby_name_length: int = 32

@export_group("Match settings")
## Ceilings on what the host may set a match to in the lobby, checked on the
## SERVER when the settings arrive (MatchSettings.sanitise).
##
## Here rather than on GameConfig, because they are not match rules: GameConfig
## says what a match STARTS from, and these say how far a host may push it in
## the room. A ranked match never reaches any of them - it is played on the
## defaults - so these only ever bound a custom game.
@export var max_lives_per_player: int = 500
## Never above GameConfig.gold_cap: a host who types a number the match will
## silently trim has been told a lie by the room.
@export var max_starting_gold: int = 9999999
@export var max_free_technologies: int = 30
@export var max_starting_income: int = 1000000
## Seconds. A floor as well as a ceiling: an income interval of zero is a
## payout every tick, which is not a fast match but a broken one.
@export var min_income_interval: float = 1.0
@export var max_income_interval: float = 300.0

## How long the lobby browser waits for the server to answer a create or join
## before telling the player it heard nothing.
##
## A refusal already comes back as a message, so this is only for the case
## where NOTHING comes back - the request left and no answer, refusal included,
## ever arrived. That is what a client and server running different code looks
## like: Godot routes an rpc by its INDEX in the method list, so two builds
## whose @rpc sets differ silently deliver a call to the wrong function and
## nobody replies. Without this the browser sits on "Creating lobby..." for
## ever with the real error only in the log. Cost an hour on 2026-09-04.
##
## Generous on purpose. It is not a latency budget, it is the point at which
## silence stops being worth waiting through.
@export var lobby_request_timeout_seconds: float = 8.0

@export_group("Starting a match")
## Seconds between the host pressing Start and the match handshake beginning
## (D24). Everyone in the lobby watches the same number, because the countdown
## runs on the SERVER and is announced to the room.
@export var start_countdown_seconds: float = 5.0
## How long the server waits for every client to report its match scene loaded
## before starting without whoever is missing (D15).
##
## A client that has not answered by then was not merely slow, it has crashed
## or hung: the scene is a second or two of loading, not a minute. Starting
## without them beats making everyone else wait for a machine that is gone.
@export var load_timeout_seconds: float = 60.0
## How long the server holds a match open for a player who has gone quiet
## before declaring them gone (D13, and the user's call on 2026-08-23).
##
## This is NOT a reconnect window - out is out - it is a hold against a brief
## hiccup costing somebody a ranked game. It sits ON TOP of the roughly 5.6 s
## ENet itself takes to notice a hard-killed client, so a real crash resolves
## in about fifteen. A DELIBERATE leave skips it entirely, because a client
## that says goodbye is telling us it is not coming back.
@export var disconnect_grace_seconds: float = 10.0

## Reports every scene path that does not resolve, all at once, rather than one
## at a time by whichever button a player happens to press first.
func validate() -> bool:
	var complete: bool = true
	complete = _validate_path(main_menu_scene_path, "main_menu_scene_path") && complete
	complete = _validate_path(lobby_browser_scene_path, "lobby_browser_scene_path") && complete
	complete = _validate_path(lobby_room_scene_path, "lobby_room_scene_path") && complete
	complete = _validate_path(game_scene_path, "game_scene_path") && complete
	complete = _validate_path(match_loading_scene_path, "match_loading_scene_path") && complete
	return complete


## The name a new lobby is offered, given who is hosting it.
func default_lobby_name(host_name: String) -> String:
	if default_lobby_name_pattern.is_empty():
		return host_name
	return default_lobby_name_pattern % host_name


func _validate_path(path: String, field_name: String) -> bool:
	if SceneUtil.exists(path):
		return true
	Log.err("MenuConfig path does not resolve", {"field": field_name, "path": path})
	return false
