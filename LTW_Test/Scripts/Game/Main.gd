class_name Main
extends Node3D

## Prototype entry point.
##
## Places one player area per player and gives the local player a builder, then
## hands the camera its panning bounds.
##
## An area is a whole prefab - ground, grid and send building - so this only
## has to say how many and where, never what one is made of.
##
## WHO is playing comes from a MatchSetup, handed over by the lobby. Run this
## scene straight from the editor and it stands a single player one in from
## GameConfig, so that workflow is unchanged. Balance values still live on
## GameConfig; only the player list moved. See multiplayer.md.
##
## Every player gets a builder, not just the local one, because the server has
## to simulate all of them.

@export_group("Settings")
## Set on the dedicated server scene. A server simulates every lane and plays
## none of them, so it takes no slot, draws nothing and expects no camera or
## HUD. Milestone 1 replaces this with the dedicated_server feature tag.
@export var _dedicated_server: bool = false

@export_group("References")
@export var _areas_root: Node3D
## Prefab for one player's whole playing area: the walkable zones, the grid
## over the buildable part and the send building on the strip above it.
@export var _area_scene: PackedScene
## Prefab for the builder unit. Visuals and node layout live in the scene.
@export var _builder_scene: PackedScene

var _areas: Array[PlayerArea] = []


func _ready() -> void:
	var config: GameConfig = References.game_config
	if config == null:
		Log.err("Main cannot start, no GameConfig on References")
		return
	if _areas_root == null || References.units_root == null:
		Log.err("Main is missing its Areas or Units root reference")
		return

	var session: MatchSession = References.match_session
	if session == null:
		Log.err("Main found no MatchSession on References, a match cannot start")
		return

	var setup: MatchSetup = _take_setup(config)
	if !setup.validate():
		Log.err("Main is starting a match with a broken setup, see the errors above")
	# Slots are handed out by area_origin, which wraps past the last column and
	# would stack row three on top of row one. Loud here rather than as two
	# players silently sharing a lane.
	if setup.player_count() > config.map_slot_count():
		Log.err("More players than the map has slots, areas will overlap", {
			"players": setup.player_count(),
			"slots": config.map_slot_count(),
		})
	session.begin(setup)

	# Once, here, rather than on every hit of every fight: a broken damage
	# matrix has to be loud, and per-hit logging would drown the log instead.
	if References.damage_table == null:
		Log.err("Main found no DamageTable on References, armour types do nothing")
	else:
		References.damage_table.validate()

	# Same idea for the command card: a hotkey row too short for the grid
	# leaves squares the player cannot reach, which is invisible in play.
	if References.controls_config != null:
		References.controls_config.validate()
	elif !_dedicated_server:
		Log.err("Main found no ControlsConfig on References, the card has no hotkeys")

	# Before anything that might spend gold.
	if References.player_manager != null:
		References.player_manager.create_states(setup, config)
	else:
		Log.err("Main found no PlayerManager on References, there is no economy")

	_create_areas(setup)
	var builders: Array[Builder] = _create_builders(setup)
	_configure_camera(config)

	# After the areas and the builders exist, so it walks the real content graph
	# rather than a guess at it. Any builder reaches the same tower cards, so
	# the first one is enough even when this client owns none of them.
	var probe: Builder = null if builders.is_empty() else builders[0]
	_validate_content(probe)

	var local_builder: Builder = _find_builder(builders, setup.local_slot)
	if local_builder != null && References.rts_camera != null:
		References.rts_camera.center_on(local_builder.global_position)

	Log.info("Match ready", {
		"players": setup.player_count(),
		"local_slot": setup.local_slot,
		"seed": setup.rng_seed,
		"starting_lives": config.starting_lives(setup.player_count()),
	})

	# 2.5: every machine built this world from the same setup, and this is how
	# they find out whether they really did. Does nothing at all off the
	# network, so a single player run pays for none of it.
	MatchStart.report_world_checksum(WorldChecksum.of(setup, _areas, session))


## The setup handed over by the lobby, or a single player stand-in when this
## scene was opened directly. Taken rather than read: the handoff is cleared as
## it is consumed, so a later direct run cannot inherit the last lobby.
func _take_setup(config: GameConfig) -> MatchSetup:
	var setup: MatchSetup = MenuNavigation.take_pending_match()
	if setup == null:
		Log.info("Main found no pending match, standing in a single player setup")
		setup = MatchSetup.from_config(config)

	if _dedicated_server:
		# Slot 0 means "watching everything, playing nothing", which is what
		# makes every is-this-mine test answer no and every presentation step
		# stand aside.
		setup.local_slot = 0
	return setup


## One prefab per player. Every area brings its own send building, so the send
## ring already works the moment areas stop being one player's own.
func _create_areas(setup: MatchSetup) -> void:
	if _area_scene == null:
		Log.err("Main has no player area scene assigned")
		return

	for player in setup.players:
		if player == null:
			continue
		var area: PlayerArea = _area_scene.instantiate() as PlayerArea
		if area == null:
			Log.err("Player area scene root does not have a PlayerArea script")
			return
		_areas_root.add_child(area)
		area.setup(player.slot)
		_areas.append(area)
		# So the send ring can find it. Areas are registered after the states
		# exist, which is why PlayerManager keeps the two apart.
		if References.player_manager != null:
			References.player_manager.register_area(area)


## One builder per player in the match. The server owns all of them; a client
## only commands its own, but every machine has to simulate the lot.
func _create_builders(setup: MatchSetup) -> Array[Builder]:
	var builders: Array[Builder] = []
	for player in setup.players:
		if player == null:
			continue
		var builder: Builder = _create_builder(player.slot)
		if builder != null:
			builders.append(builder)
	return builders


func _find_builder(builders: Array[Builder], player_id: int) -> Builder:
	for builder in builders:
		if builder != null && builder.owner_player_id == player_id:
			return builder
	return null


func _create_builder(player_id: int) -> Builder:
	if _builder_scene == null:
		Log.err("Main has no builder scene assigned")
		return null

	var area: PlayerArea = _find_area(player_id)
	if area == null:
		Log.err("No area found for player", player_id)
		return null

	var builder: Builder = _builder_scene.instantiate() as Builder
	if builder == null:
		Log.err("Builder scene root does not have a Builder script")
		return null

	References.units_root.add_child(builder)
	builder.setup(player_id, area)
	return builder


func _find_area(player_id: int) -> PlayerArea:
	for area in _areas:
		if area.player_id == player_id:
			return area
	return null


## Clamps camera panning to the whole map plus a margin.
##
## The MAP, not the areas that happen to exist: the slot grid is the same size
## whoever turned up, so a 1v1 pans over the same world a full house does and
## the empty slots are black ground. GameConfig.map_bounds is the one answer to
## how big that is, shared with the minimap.
func _configure_camera(config: GameConfig) -> void:
	# A machine playing no slot draws nothing, so having no camera is correct
	# rather than broken. One that DOES play a slot and has no camera is broken.
	var camera: RTSCamera = References.rts_camera
	if camera == null:
		if !_dedicated_server:
			Log.err("Main found no RTSCamera on References")
		return

	var margin: float = 0.0
	var camera_config: CameraConfig = References.camera_config
	if camera_config != null:
		margin = camera_config.bounds_margin

	var bounds: Rect2 = config.map_bounds().grow(margin)

	# The camera aims at the centre of the screen, so the top bound is the send
	# building's own row rather than the far edge of its strip. Panning fully up
	# then puts the sender in the middle of the view instead of off the bottom.
	var top: float = config.send_zone_start_z() + config.send_zone_depth() * 0.5
	camera.set_focus_bounds(Rect2(bounds.position.x, top, bounds.size.x, bounds.end.y - top))


## Walks everything a match can reach and reports every scene path that does
## not resolve.
##
## Resources name their scenes by path now, and the editor does NOT rewrite a
## path string when a scene is moved or renamed. Without this a renamed prefab
## stays invisible until a player presses that one button mid match, so the
## whole content graph is checked once, here, at boot.
##
## The two roots are the two things a player commands: the builder, which
## reaches every tower through its build menu, and the send building, which
## reaches every creep through its card. One shared seen set across both, so a
## resource on both cards is reported once rather than twice.
func _validate_content(builder: Builder) -> void:
	var seen: Dictionary = {}
	var complete: bool = true
	var roots: Array[UnitStats] = []

	if builder != null && builder.stats != null:
		complete = builder.stats.validate(seen) && complete
		roots.append(builder.stats)

	for area in _areas:
		var send_building: SendBuilding = area.send_building()
		if send_building != null && send_building.stats != null:
			complete = send_building.stats.validate(seen) && complete
			roots.append(send_building.stats)

	# The same two roots, walked again for a different question: not "does this
	# path resolve" but "what can a command name". Built here rather than from a
	# hand-kept list so it cannot fall out of step with the content.
	complete = _build_registries(roots) && complete

	if !complete:
		Log.err("Content check failed, see the errors above. Some buttons will not work")


func _build_registries(roots: Array[UnitStats]) -> bool:
	var session: MatchSession = References.match_session
	if session == null:
		return true

	# Before the build, not after: a folder that has moved makes the registry
	# quietly SHORTER, and a short registry looks exactly like a client running
	# different content. That has to be a message, not a mystery.
	var complete: bool = true
	var content: ContentConfig = References.content_config
	if content == null:
		Log.err("Main found no ContentConfig on References, abilities on no card get no ids")
		complete = false
	else:
		complete = content.validate() && complete

	var registry: AbilityRegistry = session.abilities()
	registry.build(roots)

	# Every unit type in the build, not only the ones something spawns, for the
	# same reason the abilities are scanned whole: an id has to be unique across
	# everything authored (D12).
	var types: UnitTypeRegistry = session.unit_types()
	types.build("" if content == null else content.unit_stats_folder)

	# Scanned the same way and for the same reason, with one difference worth
	# knowing: a technology is on no card, so there is no walk that could ever
	# reach one and the scan is not a second net but the only one.
	var techs: TechRegistry = session.techs()
	techs.build("" if content == null else content.tech_folder)

	Log.info("Registries built", {
		"abilities": registry.count(),
		"unit_types": types.count(),
		"technologies": techs.count(),
	})
	return registry.validate() && types.validate() && techs.validate() && complete
