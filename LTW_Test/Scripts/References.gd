class_name References
extends Node

## Scene-level access point for shared configs and manager nodes.
##
## Drop one References node into the scene and wire every field in the
## inspector. Anything created at runtime - player areas, units - reaches
## shared state through the static getters instead of walking the tree.
##
## A node listed here may read References itself. Godot 4.7 resolves the
## mutual class_name dependency without complaint, verified by a headless
## import, so there is no need to avoid it.
##
## When a script reads the same entry often, give it a getter property onto
## References rather than wiring the same node again, e.g.
##     var _config: GameConfig:
##         get:
##             return References.game_config

@export_group("References")
@export var _rts_camera: RTSCamera
@export var _selection_controller: SelectionController
@export var _command_controller: CommandController
@export var _selection_box_overlay: SelectionBoxOverlay
@export var _unit_panel: UnitPanel
## The technology screen. Held here because the button that opens it does not
## live inside it: it is a square on the ActionBar, beside the builder and the
## senders, where a player looks for a button. A dedicated server leaves this
## null and nothing asks.
@export var _research_center: ResearchCenter
@export var _player_manager: PlayerManager
## Who is in THIS match, the shared RNG and the unit registry.
@export var _match_session: MatchSession
## Every rule of the technology system, and the far end of the road a Research
## Center press takes. Wired by both match scenes, because the server enforces
## it and a client asks it what to grey out.
@export var _tech_manager: TechManager
## How this match hands out its opening technology, and the draft that holds
## the world still while players choose. Wired by both match scenes, for the
## same reason TechManager is: the server runs it and a client is told about
## it in the snapshot.
@export var _starting_tech: StartingTech
## What HAPPENED in this match, counted for the end screen: gold, sends, kills,
## leaks and where everybody finished. Wired by both match scenes - a dedicated
## server counts a match nobody there will read, which costs a handful of
## integers and keeps the two scenes the same shape.
##
## PRESENTATION-ADJACENT rather than simulation: nothing in it is checksummed
## and nothing reads it back into the world. See MatchStats.
@export var _match_stats: MatchStats
## The computer opponents in this match, or a node that makes none. Wired by
## both match scenes, because a SKIRMISH is a match like any other and the
## server scene has to stay the same shape as the client one.
@export var _ai_director: AiDirector
## The lesson script, when this match is the tutorial. Wired by the client match
## scene only: a dedicated server never teaches anybody anything, and a skirmish
## reaches the same node and is told there is nothing to run.
@export var _tutorial_director: TutorialDirector
## Parent for short lived world effects: move markers, and later hit effects
## and floating damage numbers.
##
## PRESENTATION ONLY. A dedicated server leaves this null and everything that
## uses it steps aside quietly - see multiplayer.md.
@export var _effects_root: Node3D
## Draws the order chains: the waypoints a unit still has to walk to, and the
## grey ghost of every tower ordered and not started yet. Reached from
## OrderQueue, which is a RefCounted with no tree to walk.
@export var _order_overlay: OrderOverlay
## Draws the saved maze plan the player currently has up, over their own zone.
##
## PRESENTATION ONLY, and local from end to end: a blueprint is a file this
## machine wrote and the squares it puts down change nothing. A dedicated
## server leaves this null and the abilities that reach it stand down - see
## multiplayer.md.
@export var _blueprint_overlay: BlueprintOverlay
## The match's one modal yes-or-no box, borrowed by whatever needs to ask
## before doing something that cannot be undone.
##
## Shared rather than one per caller because it is MODAL: only one question can
## be on screen at a time by definition, so a second box would be a second
## thing that must never happen at once. PRESENTATION ONLY; a server has
## nobody to ask.
@export var _confirm_prompt: ConfirmPrompt
## Parent for every unit that is not parented to an area: the builders, and
## the send buildings. Shared because replication spawns into it too, which is
## what moved it here from Main's own @export.
@export var _units_root: Node3D
## Parent for projectiles in flight.
##
## SIMULATION, which is why it is not the effects root. A projectile's travel
## time is gameplay: the target walks while the shot is in the air, and the
## damage lands when it arrives. A server has to fly them exactly as a client
## does, so this exists on both.
@export var _projectiles_root: Node3D

@export_group("Configs")
@export var _game_config: GameConfig
@export var _camera_config: CameraConfig
@export var _controls_config: ControlsConfig
@export var _damage_table: DamageTable
## Where the content this build contains lives, so the ability registry can
## find abilities that are on nobody's card yet.
@export var _content_config: ContentConfig
## Menu flow and lobby screen settings. Only the menu scenes wire this;
## it stays null inside a match.
@export var _menu_config: MenuConfig
## Which entry scene this process opens. Only the boot scene wires this, and
## nothing after it ever reads it again.
@export var _boot_config: BootConfig
## What this build is and when it was made. Wired by the menu scenes, which are
## where it is shown; a match never asks.
@export var _build_info: BuildInfo
## Where the server listens and where a client dials. Wired by every scene
## that can touch the network: the lobby screens and the server.
@export var _network_config: NetworkConfig
## How the local player's view is drawn. PRESENTATION ONLY, so a dedicated
## server leaves it null and everything that reads it falls back to a sane
## look rather than refusing to run - see multiplayer.md.
@export var _presentation_config: PresentationConfig
## Which sound answers which event, and the mixing rules. PRESENTATION ONLY, on
## the same terms as the config above: a dedicated server leaves it null, and
## AudioHub falls silent rather than refusing to run.
@export var _audio_config: AudioConfig
## Every AI difficulty this build contains. Wired by the match scenes and by the
## single player setup screen, which is the one place a player picks one.
@export var _ai_config: AiConfig

static var instance: References

static var rts_camera: RTSCamera:
	get:
		if instance == null:
			return null
		return instance._rts_camera

static var selection_controller: SelectionController:
	get:
		if instance == null:
			return null
		return instance._selection_controller

static var command_controller: CommandController:
	get:
		if instance == null:
			return null
		return instance._command_controller

static var selection_box_overlay: SelectionBoxOverlay:
	get:
		if instance == null:
			return null
		return instance._selection_box_overlay

static var unit_panel: UnitPanel:
	get:
		if instance == null:
			return null
		return instance._unit_panel

static var research_center: ResearchCenter:
	get:
		if instance == null:
			return null
		return instance._research_center

static var player_manager: PlayerManager:
	get:
		if instance == null:
			return null
		return instance._player_manager

static var match_session: MatchSession:
	get:
		if instance == null:
			return null
		return instance._match_session

static var tech_manager: TechManager:
	get:
		if instance == null:
			return null
		return instance._tech_manager

static var starting_tech: StartingTech:
	get:
		if instance == null:
			return null
		return instance._starting_tech

static var tutorial_director: TutorialDirector:
	get:
		if instance == null:
			return null
		return instance._tutorial_director

static var ai_director: AiDirector:
	get:
		if instance == null:
			return null
		return instance._ai_director

static var match_stats: MatchStats:
	get:
		if instance == null:
			return null
		return instance._match_stats

static var effects_root: Node3D:
	get:
		if instance == null:
			return null
		return instance._effects_root

static var order_overlay: OrderOverlay:
	get:
		if instance == null:
			return null
		return instance._order_overlay

static var blueprint_overlay: BlueprintOverlay:
	get:
		if instance == null:
			return null
		return instance._blueprint_overlay

static var confirm_prompt: ConfirmPrompt:
	get:
		if instance == null:
			return null
		return instance._confirm_prompt

static var units_root: Node3D:
	get:
		if instance == null:
			return null
		return instance._units_root

static var projectiles_root: Node3D:
	get:
		if instance == null:
			return null
		return instance._projectiles_root

static var game_config: GameConfig:
	get:
		if instance == null:
			return null
		return instance._game_config

static var camera_config: CameraConfig:
	get:
		if instance == null:
			return null
		return instance._camera_config

static var controls_config: ControlsConfig:
	get:
		if instance == null:
			return null
		return instance._controls_config

static var damage_table: DamageTable:
	get:
		if instance == null:
			return null
		return instance._damage_table

static var content_config: ContentConfig:
	get:
		if instance == null:
			return null
		return instance._content_config

static var menu_config: MenuConfig:
	get:
		if instance == null:
			return null
		return instance._menu_config

static var boot_config: BootConfig:
	get:
		if instance == null:
			return null
		return instance._boot_config

static var network_config: NetworkConfig:
	get:
		if instance == null:
			return null
		return instance._network_config

static var build_info: BuildInfo:
	get:
		if instance == null:
			return null
		return instance._build_info

static var presentation_config: PresentationConfig:
	get:
		if instance == null:
			return null
		return instance._presentation_config

static var audio_config: AudioConfig:
	get:
		if instance == null:
			return null
		return instance._audio_config

static var ai_config: AiConfig:
	get:
		if instance == null:
			return null
		return instance._ai_config

## Claimed on entering the tree rather than in _init, so the static handle
## only ever points at a node that is actually live. _init would also fire
## for a scene that is instantiated but never added.
func _enter_tree() -> void:
	if instance != null && instance != self:
		Log.warn("A second References node entered the tree, replacing the previous instance")
	instance = self


## Cleared on leaving the tree so a reloaded scene never sees a stale handle.
func _exit_tree() -> void:
	if instance == self:
		instance = null
