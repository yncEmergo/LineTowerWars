class_name AudioHub
extends Node

## The one thing in the project that plays a sound.
##
## An AUTOLOAD, because music has to survive a scene change and a node inside a
## match scene cannot. Everything reaches it through the statics below, so no
## caller ever holds a reference to it and References does not carry one.
##
## **Every static here is safe to call when the autoload is absent.** A
## class_name is a global identifier and a static resolves without an instance,
## so `AudioHub.play_ui(...)` from a scene running under a bare `--script` run,
## from a headless probe, or from a build where the [autoload] line has not
## landed yet, is a no-op rather than a crash. That is deliberate: audio is
## presentation, and presentation must never be able to stop a simulation.
##
## PRESENTATION, NEVER SIMULATION. Nothing in this file may be read by anything
## that advances the world. It uses wall-clock milliseconds for its rate limits
## and the camera for its budget, both of which differ between two machines
## running the same match - which is exactly why no gameplay answer may depend
## on them. Under lockstep every client simulates every lane, so gameplay code
## MAY call in here freely; the relay simulates nothing and is headless, so it
## never does. See multiplayer.md.
##
## WHAT IT IS NOT. It holds no per-sound settings: how loud a tower's shot is
## lives on that tower's stats, and the mixing rules live on AudioConfig. This
## file owns the players, the cache and the budget, and nothing else.

## The autoload, or null everywhere else. Never assume it.
static var instance: AudioHub

## Loaded streams by res:// path.
##
## ONE cache for the whole game, and it belongs here rather than on each config
## for a reason worth keeping: in Phase 2 a tower's fire sound is a path on its
## AttackStats and a creep's death sound a path on its CreepStats, and every one
## of those wants the same cache. A per-config cache would be a dozen caches
## that never see each other's entries.
static var _cache: Dictionary = {}

## Wall-clock milliseconds each path was last started at, for the rate limits.
static var _last_started_ms: Dictionary = {}

var _ui_players: Array[AudioStreamPlayer] = []
var _world_players: Array[AudioStreamPlayer3D] = []
var _music_player: AudioStreamPlayer = null
var _music_path: String = ""
var _music_tween: Tween = null
## True on a process with no output device, where every call returns early.
var _silent: bool = false

var _config: AudioConfig:
	get:
		return References.audio_config


func _ready() -> void:
	instance = self
	_silent = DisplayServer.get_name() == "headless"
	# Music must keep playing while the match is paused, and the fade tween
	# must keep running with it. An autoload inherits the root's mode, which
	# stops on pause like everything else.
	process_mode = Node.PROCESS_MODE_ALWAYS

	if _silent:
		return
	# Owned rather than a second autoload: it is only ever wanted where this is
	# wanted, and adding a line to [autoload] is a change that breaks a running
	# editor. See CLAUDE.md.
	var binder: ButtonSoundBinder = ButtonSoundBinder.new()
	binder.name = "ButtonSoundBinder"
	add_child(binder)


# --- asking ----------------------------------------------------------------

## Whether a sound played right now would be heard.
##
## False on a headless process and before the autoload exists. Callers do not
## normally ask - every play function checks for itself - but a caller doing
## expensive work to DECIDE what to play should ask first.
static func is_available() -> bool:
	return instance != null && !instance._silent


## The stream at a res:// path, loaded once and kept.
##
## Returns null for an empty path without complaining, because an unset
## @export_file is how a sound is deliberately turned off. A path that is set
## and does not load is a different thing and says so.
static func stream(path: String) -> AudioStream:
	if path.is_empty():
		return null
	if _cache.has(path):
		return _cache[path]

	var loaded: Resource = null
	if ResourceLoader.exists(path):
		loaded = load(path)
	var audio: AudioStream = loaded as AudioStream
	if audio == null:
		Log.err("AudioHub could not load a sound", path)
	# Cached even when null, so a broken path costs one failed load and one log
	# line rather than one of each per shot for the rest of the match.
	_cache[path] = audio
	return audio


## Loads these paths now, so nothing has to load one mid-match.
##
## **Why this exists at all, given the streams are tiny.** They are named by
## PATH and loaded lazily, which is what stops a tower's stats resource dragging
## its audio in behind it - so without this the FIRST shot of each tower type
## pays a file load during a match. Individually trivial, and precisely the
## class of hitch the load screen exists to remove. Called from the load screen
## with the same list it warms everything else from.
static func warm(paths: PackedStringArray) -> void:
	if instance == null || instance._silent:
		return
	for path: String in paths:
		stream(path)


# --- playing ---------------------------------------------------------------

## An interface sound: a click, a hover, a refusal. 2D, no position, UI bus.
##
## `min_gap_seconds` overrides the config's same-sound gap for this one call,
## which is what hover needs - a mouse crossing a command card touches a dozen
## buttons in a few frames and every one of them asks.
static func play_ui(path: String, min_gap_seconds: float = -1.0) -> void:
	if instance == null || instance._silent:
		return
	var audio: AudioStream = stream(path)
	if audio == null:
		return

	var config: AudioConfig = instance._config
	var gap: float = min_gap_seconds
	if gap < 0.0:
		gap = config.budget_same_sound_gap if config != null else 0.04
	if !_claim_gap(path, gap):
		return

	var player: AudioStreamPlayer = instance._claim_ui_player()
	if player == null:
		return
	player.stream = audio
	player.volume_db = _offset_db(audio)
	player.play()


## A sound somewhere in the world. 3D, SFX bus, and subject to the budget.
##
## Three things can stop this before a voice is spent, in the order they are
## cheapest to check: the sound is too far from the camera to matter, the same
## sound already played a moment ago, or every voice is busy with something
## closer. See _claim_world_player().
static func play_at(path: String, position: Vector3, min_gap_seconds: float = -1.0) -> void:
	if instance == null || instance._silent:
		return
	var config: AudioConfig = instance._config
	if config == null:
		return

	var camera: Camera3D = instance.get_viewport().get_camera_3d() if instance.is_inside_tree() else null
	if camera != null:
		var away: float = camera.global_position.distance_to(position)
		if away > config.world_max_distance:
			return

	var audio: AudioStream = stream(path)
	if audio == null:
		return

	var gap: float = min_gap_seconds
	if gap < 0.0:
		gap = config.budget_same_sound_gap
	if !_claim_gap(path, gap):
		return

	var player: AudioStreamPlayer3D = instance._claim_world_player(position, camera, config)
	if player == null:
		return

	player.global_position = position
	player.stream = audio
	player.max_distance = config.world_max_distance
	player.unit_size = config.world_unit_size
	var level: float = _offset_db(audio)
	if camera != null && !_is_on_screen(camera, position):
		level += config.world_offscreen_db
	player.volume_db = level
	player.play()


## Switches the music. Same path twice is ignored, so a scene that re-enters
## does not restart the track it is already playing.
static func play_music(path: String) -> void:
	if instance == null || instance._silent:
		return
	if path == instance._music_path:
		return
	instance._music_path = path
	instance._change_music(stream(path))


static func stop_music() -> void:
	if instance == null:
		return
	instance._music_path = ""
	instance._change_music(null)


# --- the budget ------------------------------------------------------------

## Whether enough time has passed since this exact sound last started.
##
## THE DEDUPE THAT MAKES A FULL MAZE SURVIVABLE. Forty towers of one type firing
## on one twenty-per-second tick is forty requests for one .wav inside a
## millisecond. Playing all forty does not sound like forty shots - it sounds
## like one shot forty times as loud, because they are phase-identical and sum.
## One gets through and the rest are dropped, which is both cheaper and closer
## to what it should sound like.
static func _claim_gap(path: String, gap_seconds: float) -> bool:
	if gap_seconds <= 0.0:
		return true
	var now: int = Time.get_ticks_msec()
	var last: int = int(_last_started_ms.get(path, -1000000))
	if now - last < int(gap_seconds * 1000.0):
		return false
	_last_started_ms[path] = now
	return true


## Decibels this stream asks to be shifted by, which only an AudioClipSet does.
static func _offset_db(audio: AudioStream) -> float:
	var set: AudioClipSet = audio as AudioClipSet
	return set.volume_offset_db if set != null else 0.0


## Whether a world point is inside the camera's view.
##
## CAMERA PROJECTION MATHS, not a physics query - same as
## SelectionController.unit_at, and for the same hard reason. See CLAUDE.md.
static func _is_on_screen(camera: Camera3D, position: Vector3) -> bool:
	if camera.is_position_behind(position):
		return false
	var screen: Vector2 = camera.unproject_position(position)
	var size: Vector2 = camera.get_viewport().get_visible_rect().size
	# Generous at the edges: a sound just off screen is still something the
	# player is looking at the consequences of.
	var margin: float = size.x * 0.15
	return screen.x > -margin && screen.x < size.x + margin \
		&& screen.y > -margin && screen.y < size.y + margin


func _claim_ui_player() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _ui_players:
		if !player.playing:
			return player

	var config: AudioConfig = _config
	var cap: int = config.budget_ui_voices if config != null else 8
	if _ui_players.size() >= cap:
		return null

	var fresh: AudioStreamPlayer = AudioStreamPlayer.new()
	fresh.bus = &"UI"
	_ui_players.append(fresh)
	add_child(fresh)
	return fresh


## A world voice for a sound at this point, or null to drop it.
##
## **NEAREST TO THE CAMERA WINS.** When every voice is busy the new sound takes
## one only if it is closer than the furthest thing currently playing. That is
## the whole lane-audibility rule: with twelve lanes running, the voices end up
## spent on the lane being looked at without anything having to know what a lane
## is.
func _claim_world_player(position: Vector3, camera: Camera3D,
		config: AudioConfig) -> AudioStreamPlayer3D:
	for player: AudioStreamPlayer3D in _world_players:
		if !player.playing:
			return player

	if _world_players.size() < config.budget_world_voices:
		var fresh: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		fresh.bus = &"SFX"
		# Godot's own falloff past unit_size. Inverse rather than the default,
		# which is far too aggressive for a camera this high.
		fresh.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		_world_players.append(fresh)
		add_child(fresh)
		return fresh

	if camera == null:
		return null

	var eye: Vector3 = camera.global_position
	var mine: float = eye.distance_squared_to(position)
	var furthest: AudioStreamPlayer3D = null
	var furthest_away: float = mine
	for player: AudioStreamPlayer3D in _world_players:
		var away: float = eye.distance_squared_to(player.global_position)
		if away > furthest_away:
			furthest_away = away
			furthest = player

	if furthest == null:
		return null
	furthest.stop()
	return furthest


# --- music -----------------------------------------------------------------

## Crosses to a new track, or to silence when handed null.
##
## A DIP rather than a true crossfade: down to nothing, swap, back up. A real
## crossfade needs two players and a rule for what happens when a third change
## arrives mid-fade, and the only music changes this game has are menu to match
## and back - moments where a dip is not merely acceptable but is what a player
## expects. Revisit if music ever changes DURING a match.
func _change_music(audio: AudioStream) -> void:
	var config: AudioConfig = _config
	var fade: float = config.music_fade_seconds if config != null else 1.5

	if _music_player == null:
		_music_player = AudioStreamPlayer.new()
		_music_player.bus = &"Music"
		add_child(_music_player)

	if _music_tween != null && _music_tween.is_valid():
		_music_tween.kill()

	if fade <= 0.0 || !_music_player.playing:
		_music_player.stream = audio
		_music_player.volume_db = 0.0
		if audio != null:
			_music_player.play()
		else:
			_music_player.stop()
		return

	_music_tween = create_tween()
	# The match can be paused while this runs, and a stopped tween would leave
	# the music at whatever volume the dip had reached.
	_music_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_music_tween.tween_property(_music_player, "volume_db", -40.0, fade * 0.5)
	_music_tween.tween_callback(func() -> void:
		_music_player.stream = audio
		if audio != null:
			_music_player.play()
		else:
			_music_player.stop())
	if audio != null:
		_music_tween.tween_property(_music_player, "volume_db", 0.0, fade * 0.5)
