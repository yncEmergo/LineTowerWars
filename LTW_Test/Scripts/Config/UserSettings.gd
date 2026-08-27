class_name UserSettings
extends RefCounted

## Everything the player chose in the options menu, and the file it survives in.
##
## The one place in the project where a setting deliberately does NOT live in a
## .tres. A .tres is authored data and ships read-only inside an export, while
## these are written at runtime, on this machine, by whoever is sitting at it.
## They go to user://settings.cfg instead, and the DEFAULT_ constants below are
## the factory defaults a fresh install starts from - not a tuning knob.
##
## Static rather than an autoload: nothing is routed to it and it holds no node,
## so the boot scene, the options menu and every health bar reach the same
## static vars without one. Adding an autoload would also mean editing
## [autoload] in project.godot, which breaks a running editor - see CLAUDE.md.
##
## PRESENTATION ONLY, all of it, and that is a hard line rather than a
## coincidence. A dedicated server never opens this screen and must run the same
## match whatever is in the file, so nothing here may ever be read by the
## simulation - see multiplayer.md.

## Where the player's choices are kept. user:// rather than res://, because
## res:// is read-only in an exported build.
const FILE_PATH: String = "user://settings.cfg"

const SECTION_VIDEO: String = "video"
const SECTION_AUDIO: String = "audio"
const SECTION_GAMEPLAY: String = "gameplay"

## Settings-file key per channel, in AudioChannel order. Spelled out rather than
## derived from the enum name so renaming a channel never orphans what a player
## has already saved.
const AUDIO_KEYS: Array[String] = [
	"master", "ui", "sfx", "music", "speech", "atmo",
]

## What each channel is called on screen, same order. Here rather than typed
## into the prefab six times, so a rename has one place to happen.
const AUDIO_NAMES: Array[String] = [
	"Master Volume", "UI", "SFX", "Music", "Speech", "Atmo",
]

const DEFAULT_VOLUME: float = 0.8
const DEFAULT_AUDIO_MUTED: bool = false

## How the game window is presented.
##
## The numbers are pinned because they are written to the settings file as ints,
## so reordering the list would silently change what an already saved file means.
enum WindowMode {
	## A resizable window with a title bar.
	WINDOWED = 0,
	## A borderless window the size of the screen. Godot's WINDOW_MODE_FULLSCREEN,
	## which despite the name does not take exclusive control of the display, so
	## alt-tabbing away is instant.
	WINDOWED_FULLSCREEN = 1,
	## Exclusive fullscreen: the display is ours and its mode is switched.
	FULLSCREEN = 2,
}

## When a unit's worldspace health bar is drawn. Pinned for the same reason.
enum HealthBarDisplay {
	ALWAYS = 0,
	## Only once the unit has lost health, and hidden again if it is healed full.
	WHEN_DAMAGED = 1,
	NEVER = 2,
}

## The mixer channels the options screen offers. Pinned for the same reason.
##
## There is no AudioServer bus behind any of them yet - see set_volume().
enum AudioChannel {
	MASTER = 0,
	UI = 1,
	SFX = 2,
	MUSIC = 3,
	SPEECH = 4,
	ATMO = 5,
}

const DEFAULT_WINDOW_MODE: WindowMode = WindowMode.WINDOWED
const DEFAULT_HEALTH_BAR_DISPLAY: HealthBarDisplay = HealthBarDisplay.ALWAYS

static var window_mode: WindowMode = DEFAULT_WINDOW_MODE
static var health_bar_display: HealthBarDisplay = DEFAULT_HEALTH_BAR_DISPLAY
static var audio_muted: bool = DEFAULT_AUDIO_MUTED

## Linear 0-1 per channel, indexed by AudioChannel. Read through volume().
static var _volumes: PackedFloat32Array = PackedFloat32Array()


## Runs the first time anything touches this class, which is early enough that
## no reader has to remember to load first.
static func _static_init() -> void:
	_reset_volumes()
	load_from_disk()


## Replaces every value with what the player last saved. A missing key and a
## missing file both leave the factory default standing, so a first run and a
## half-written file behave the same.
static func load_from_disk() -> void:
	var file: ConfigFile = ConfigFile.new()
	var result: Error = file.load(FILE_PATH)
	if result == ERR_FILE_NOT_FOUND || result == ERR_FILE_CANT_OPEN:
		# Nobody has opened the options screen on this machine yet.
		return
	if result != OK:
		Log.warn("UserSettings could not read its file, defaults stand", {
			"path": FILE_PATH,
			"error": result,
		})
		return

	window_mode = _read_enum(file, SECTION_VIDEO, "window_mode",
		DEFAULT_WINDOW_MODE, WindowMode.size()) as WindowMode
	health_bar_display = _read_enum(file, SECTION_GAMEPLAY, "health_bar_display",
		DEFAULT_HEALTH_BAR_DISPLAY, HealthBarDisplay.size()) as HealthBarDisplay
	audio_muted = bool(file.get_value(SECTION_AUDIO, "muted", DEFAULT_AUDIO_MUTED))

	for channel: int in range(AUDIO_KEYS.size()):
		var raw: float = float(file.get_value(SECTION_AUDIO, AUDIO_KEYS[channel],
			DEFAULT_VOLUME))
		_volumes[channel] = clampf(raw, 0.0, 1.0)


## Writes every value out. Called by each setter rather than by a save button:
## a change applies the moment it is made, so there is nothing to roll back and
## nothing to confirm.
static func save_to_disk() -> void:
	var file: ConfigFile = ConfigFile.new()
	file.set_value(SECTION_VIDEO, "window_mode", int(window_mode))
	file.set_value(SECTION_GAMEPLAY, "health_bar_display", int(health_bar_display))
	file.set_value(SECTION_AUDIO, "muted", audio_muted)
	for channel: int in range(AUDIO_KEYS.size()):
		file.set_value(SECTION_AUDIO, AUDIO_KEYS[channel], _volumes[channel])

	var result: Error = file.save(FILE_PATH)
	if result != OK:
		Log.err("UserSettings could not write its file", {
			"path": FILE_PATH,
			"error": result,
		})


## Pushes the stored window mode onto the actual window.
##
## Called once at boot and again on every change. A headless process steps
## aside: it has no window, and a dedicated server must never be reshaped by a
## file some player edited.
static func apply_window_mode() -> void:
	if DisplayServer.get_name() == "headless":
		return

	match window_mode:
		WindowMode.WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		WindowMode.WINDOWED_FULLSCREEN:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		WindowMode.FULLSCREEN:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_:
			Log.err("UserSettings has a window mode it does not know", window_mode)


static func set_window_mode(mode: WindowMode) -> void:
	if mode == window_mode:
		return
	window_mode = mode
	apply_window_mode()
	save_to_disk()


## Live health bars are refreshed by the CALLER rather than here: this class
## holds no tree and has never heard of a unit. OptionsMenu does that part.
static func set_health_bar_display(mode: HealthBarDisplay) -> void:
	if mode == health_bar_display:
		return
	health_bar_display = mode
	save_to_disk()


## Linear 0-1, ignoring the mute flag. Ask audio_muted separately.
static func volume(channel: AudioChannel) -> float:
	var index: int = int(channel)
	if index < 0 || index >= _volumes.size():
		Log.err("UserSettings was asked for a volume channel it does not have", index)
		return DEFAULT_VOLUME
	return _volumes[index]


## Stores a channel's level.
##
## Deliberately does NOT touch AudioServer. There is not a sound in the build
## yet and therefore no bus layout to aim at, so wiring one here would be
## guessing at names nothing has claimed. When audio arrives this is the one
## function that has to learn about buses - everything else already asks it.
static func set_volume(channel: AudioChannel, value: float) -> void:
	var index: int = int(channel)
	if index < 0 || index >= _volumes.size():
		Log.err("UserSettings was told to set a volume channel it does not have", index)
		return
	var clamped: float = clampf(value, 0.0, 1.0)
	if is_equal_approx(clamped, _volumes[index]):
		return
	_volumes[index] = clamped
	save_to_disk()


static func set_audio_muted(value: bool) -> void:
	if value == audio_muted:
		return
	audio_muted = value
	save_to_disk()


## What a channel is called on screen.
static func audio_channel_name(channel: AudioChannel) -> String:
	var index: int = int(channel)
	if index < 0 || index >= AUDIO_NAMES.size():
		return "Channel %d" % index
	return AUDIO_NAMES[index]


static func _reset_volumes() -> void:
	_volumes.resize(AUDIO_KEYS.size())
	_volumes.fill(DEFAULT_VOLUME)


## An int off disk that has to land inside an enum. Anything outside the range
## falls back to the default rather than leaving the game in a state no branch
## of a match statement covers.
static func _read_enum(file: ConfigFile, section: String, key: String,
		fallback: int, count: int) -> int:
	var raw: int = int(file.get_value(section, key, fallback))
	if raw < 0 || raw >= count:
		Log.warn("UserSettings read a value outside its range, using the default", {
			"key": "%s/%s" % [section, key],
			"value": raw,
		})
		return fallback
	return raw
