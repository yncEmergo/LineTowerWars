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
## file owns the players, the cache and the budget, and nothing else. WHICH
## match event sounds like what is MatchAudio's, not this file's.
##
## THREE WAYS TO PLAY A SOUND, and picking between them is the one decision a
## caller here actually makes:
##
##   play_at()     DIEGETIC. It happens at a POINT in the world and is heard
##                 from where the camera is standing: a tower firing, a shell
##                 landing, a creep dying. 3D, on the SFX bus, and the only one
##                 of the three that pays the voice budget - because it is the
##                 only one a full maze can ask for a thousand times a second.
##
##   play_event()  EXTRADIEGETIC. It is about the MATCH rather than about a
##                 place in it: a life lost, income arriving, a placement the
##                 world refused. Flat, on the SFX bus, and deliberately NOT
##                 positional - the whole point of these is that they are heard
##                 while the player is looking somewhere else, which is most of
##                 the time. Attenuating one by distance would silence exactly
##                 the moments it exists for.
##
##   play_ui()     THE INTERFACE. A click, a hover, a press on a greyed-out
##                 button. Flat, on the UI bus, so a player who wants the
##                 clicks down without turning the game down has a slider that
##                 does it.
##
## The line between the last two is worth stating because it is easy to get
## wrong: play_ui is about a CONTROL the player operated, play_event about
## something that happened in the match. A build refused for want of gold is an
## event; a press on a disabled button is interface. They are separate sounds
## on separate buses for that reason.

## Buses, spelled exactly as Resources/Config/default_bus_layout.tres names
## them. By NAME and never by index, the same rule UserSettings follows: the
## layout's order is not a contract and reordering it must not silently move
## every sound in the game onto the wrong channel.
const BUS_UI: StringName = &"UI"
const BUS_SFX: StringName = &"SFX"
const BUS_MUSIC: StringName = &"Music"

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

## The flat pool, shared by play_ui and play_event.
##
## ONE pool rather than one per bus, because a player's bus is a property set
## when it is claimed and an idle player belongs to nobody. Two pools would be
## two caps to author and two ways to run out while the other sat empty, for a
## distinction that lasts only as long as one sound.
var _flat_players: Array[AudioStreamPlayer] = []
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

	# Owned on the same terms and for the same reason: the match events have to
	# be heard from a node that outlives a match scene - a leak arrives on an
	# autoload's signal - and adding a second [autoload] line is a change that
	# breaks a running editor. See MatchAudio.
	var events: MatchAudio = MatchAudio.new()
	events.name = "MatchAudio"
	add_child(events)


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
	_play_flat(path, BUS_UI, min_gap_seconds)


## A match event with no place in the world: a life lost, income arriving, a
## build the world refused. Flat, SFX bus, no distance and no budget.
##
## **NOT POSITIONAL, and that is the whole point of it being separate from
## play_at().** These are the sounds a player is meant to hear while looking at
## a different lane - that is what they are FOR - so attenuating one by how far
## the camera happens to be from where it happened would silence it at exactly
## the moment it mattered. A leak in your own maze is news wherever you are
## looking.
##
## On SFX rather than UI because it is not the interface: a player who turns
## the clicks down has not asked to stop being told they are losing.
static func play_event(path: String, min_gap_seconds: float = -1.0) -> void:
	_play_flat(path, BUS_SFX, min_gap_seconds)


## A sample of what one CHANNEL sounds like, played on that channel's own bus.
##
## The options screen and nothing else. It exists because four of the six
## sliders move a bus that nothing in a menu ever plays through - SFX, Music,
## Speech and Atmo are all silent there - so without it two thirds of the audio
## options are indistinguishable from broken, whatever they are actually doing
## to the mixer. A slider a player cannot hear is a slider that does not work,
## however correct the number underneath it is.
##
## Takes the bus by NAME rather than the intent the other three are named for,
## because the intent here IS the bus: the caller is asking to hear that
## channel, not to play a sound that happens to live on it.
static func play_preview(path: String, bus: StringName,
		min_gap_seconds: float = -1.0) -> void:
	_play_flat(path, bus, min_gap_seconds)


## The body of the three above. A flat voice on the named bus.
static func _play_flat(path: String, bus: StringName, min_gap_seconds: float) -> void:
	if instance == null || instance._silent || path.is_empty():
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

	var player: AudioStreamPlayer = instance._claim_flat_player()
	if player == null:
		return
	player.bus = bus
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
	# FIRST, and it belongs first rather than being left to stream() below.
	# This is the hottest call in the whole file - every shot of every tower in
	# every lane arrives here - and an unset path is how a sound is turned off,
	# so the common case must not pay for the camera lookup and the distance
	# maths to find out it had nothing to play.
	if path.is_empty():
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
	var clip_set: AudioClipSet = audio as AudioClipSet
	return  clip_set.volume_offset_db if  clip_set != null else 0.0


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


## An idle flat voice, or null when the cap is reached.
##
## No nearest-wins rule here, unlike the world pool below: a flat sound has no
## distance to be ranked by, and running out of these means something is asking
## far more often than a player can act. Dropping the newest is the honest
## answer to that.
func _claim_flat_player() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _flat_players:
		if !player.playing:
			return player

	var config: AudioConfig = _config
	var cap: int = config.budget_flat_voices if config != null else 8
	if _flat_players.size() >= cap:
		return null

	var fresh: AudioStreamPlayer = AudioStreamPlayer.new()
	_flat_players.append(fresh)
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
		fresh.bus = BUS_SFX
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
		_music_player.bus = BUS_MUSIC
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
