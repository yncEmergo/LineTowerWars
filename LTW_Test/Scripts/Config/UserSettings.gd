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
## PRESENTATION AND IDENTITY, and never the SIMULATION. That is a hard line
## rather than a coincidence: a dedicated server never opens this screen and
## must run the same match whatever is in the file, so nothing here may ever
## decide what happens in one - see multiplayer.md.
##
## The player's NAME lives here for the same reason the rest does. It is typed
## on this machine by whoever is sitting at it, it has to survive being closed,
## and it is a thing to DISPLAY rather than a claim anybody may trust: the
## server sanitises whatever a client states about itself and the peer id
## remains the identity. LobbyIdentity is what reads it.

## Where the player's choices are kept. user:// rather than res://, because
## res:// is read-only in an exported build.
const FILE_PATH: String = "user://settings.cfg"

const SECTION_PROFILE: String = "profile"
const SECTION_VIDEO: String = "video"
const SECTION_AUDIO: String = "audio"
const SECTION_GAMEPLAY: String = "gameplay"
const SECTION_HOTKEYS: String = "hotkeys"

## The one key in the hotkeys section that is NOT a binding, so reading the
## bindings back can skip it rather than inventing an action called
## "keyboard_layout".
const KEYBOARD_LAYOUT_KEY: String = "keyboard_layout"

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
## Shadows on by default: the game is meant to be looked at, and with the sun's
## cast distance trimmed to what the camera can actually see they are no longer
## the several-times-the-scene cost they used to be. This is the escape hatch
## for a machine that still cannot afford them - see SunLight.
const DEFAULT_SHADOWS_ENABLED: bool = true

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

## Which letters the two grids draw on their bottom row. Pinned for the same
## reason as the enums above.
##
## The rows themselves are authored EUROPEAN on ControlsConfig and this swaps Y
## and Z out of them, which is the whole difference between the two boards for
## a game whose keys are letters. Godot reports a keycode that already follows
## the player's own layout, so the key printed Y answers KEY_Y on either board -
## what changes is which of the two letters sits where the bottom left of the
## command card wants it.
enum KeyboardLayout {
	## QWERTZ. Y is the bottom left letter key.
	EUROPEAN = 0,
	## QWERTY. Z is.
	AMERICAN = 1,
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

## What each layout is called on screen, in KeyboardLayout order. Here rather
## than typed into the scene, for the same reason AUDIO_NAMES is.
const KEYBOARD_LAYOUT_NAMES: Array[String] = ["European", "American"]

const DEFAULT_WINDOW_MODE: WindowMode = WindowMode.WINDOWED
const DEFAULT_HEALTH_BAR_DISPLAY: HealthBarDisplay = HealthBarDisplay.ALWAYS
const DEFAULT_KEYBOARD_LAYOUT: KeyboardLayout = KeyboardLayout.EUROPEAN

## What this player calls themselves in multiplayer, or empty when they have
## never chosen. EMPTY IS MEANINGFUL: it is what makes the lobby browser ask,
## and it is why this has no factory default the way everything else here does.
## Written through LobbyIdentity.choose_name, which is where the rules are.
static var player_name: String = ""

static var window_mode: WindowMode = DEFAULT_WINDOW_MODE
static var shadows_enabled: bool = DEFAULT_SHADOWS_ENABLED
static var health_bar_display: HealthBarDisplay = DEFAULT_HEALTH_BAR_DISPLAY
static var audio_muted: bool = DEFAULT_AUDIO_MUTED
static var keyboard_layout: KeyboardLayout = DEFAULT_KEYBOARD_LAYOUT

## Linear 0-1 per channel, indexed by AudioChannel. Read through volume().
static var _volumes: PackedFloat32Array = PackedFloat32Array()

## What the player bound each rebindable action to, by HotkeyAction.action_id.
##
## An action is in here ONLY once the player has touched it, which is what
## separates the two answers that look alike: no entry means "whatever the
## action was authored with", while an entry holding an empty string means the
## player deliberately took its key away. Read through hotkey_override(), which
## keeps that distinction, and reset by REMOVING the entry rather than by
## writing the default into it.
static var _hotkeys: Dictionary = {}


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

	player_name = str(file.get_value(SECTION_PROFILE, "player_name", ""))
	window_mode = _read_enum(file, SECTION_VIDEO, "window_mode",
		DEFAULT_WINDOW_MODE, WindowMode.size()) as WindowMode
	health_bar_display = _read_enum(file, SECTION_GAMEPLAY, "health_bar_display",
		DEFAULT_HEALTH_BAR_DISPLAY, HealthBarDisplay.size()) as HealthBarDisplay
	shadows_enabled = bool(file.get_value(SECTION_VIDEO, "shadows",
		DEFAULT_SHADOWS_ENABLED))
	audio_muted = bool(file.get_value(SECTION_AUDIO, "muted", DEFAULT_AUDIO_MUTED))

	for channel: int in range(AUDIO_KEYS.size()):
		var raw: float = float(file.get_value(SECTION_AUDIO, AUDIO_KEYS[channel],
			DEFAULT_VOLUME))
		_volumes[channel] = clampf(raw, 0.0, 1.0)

	keyboard_layout = _read_enum(file, SECTION_HOTKEYS, KEYBOARD_LAYOUT_KEY,
		DEFAULT_KEYBOARD_LAYOUT, KeyboardLayout.size()) as KeyboardLayout
	_read_hotkeys(file)


## Every binding in the file, whatever this build happens to contain.
##
## Deliberately not filtered against the actions that exist: an id the game no
## longer carries costs one dictionary entry nobody reads, while dropping it
## would throw a player's binding away the moment a build they are testing is
## missing a .tres. It goes back out on the next save exactly as it came in.
static func _read_hotkeys(file: ConfigFile) -> void:
	_hotkeys.clear()
	if !file.has_section(SECTION_HOTKEYS):
		return

	for action_id: String in file.get_section_keys(SECTION_HOTKEYS):
		if action_id == KEYBOARD_LAYOUT_KEY:
			continue
		_hotkeys[action_id] = str(file.get_value(SECTION_HOTKEYS, action_id, ""))


## Writes every value out. Called by each setter rather than by a save button:
## a change applies the moment it is made, so there is nothing to roll back and
## nothing to confirm.
static func save_to_disk() -> void:
	var file: ConfigFile = ConfigFile.new()
	file.set_value(SECTION_PROFILE, "player_name", player_name)
	file.set_value(SECTION_VIDEO, "window_mode", int(window_mode))
	file.set_value(SECTION_VIDEO, "shadows", shadows_enabled)
	file.set_value(SECTION_GAMEPLAY, "health_bar_display", int(health_bar_display))
	file.set_value(SECTION_AUDIO, "muted", audio_muted)
	for channel: int in range(AUDIO_KEYS.size()):
		file.set_value(SECTION_AUDIO, AUDIO_KEYS[channel], _volumes[channel])
	file.set_value(SECTION_HOTKEYS, KEYBOARD_LAYOUT_KEY, int(keyboard_layout))
	for action_id: String in _hotkeys:
		file.set_value(SECTION_HOTKEYS, action_id, str(_hotkeys[action_id]))

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


## The sun already standing in a match is refreshed by the CALLER, for the same
## reason the health bars are: this class holds no tree and has never heard of a
## light. OptionsMenu does that part, through SunLight.GROUP.
static func set_shadows_enabled(value: bool) -> void:
	if value == shadows_enabled:
		return
	shadows_enabled = value
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


## Which board the two grids read their bottom row off. Live only in the sense
## that ControlsConfig asks every time it looks a letter up, so nothing already
## drawn has to be told - the next refresh of a card carries the new letters.
static func set_keyboard_layout(layout: KeyboardLayout) -> void:
	if layout == keyboard_layout:
		return
	keyboard_layout = layout
	save_to_disk()


## What a layout is called on screen.
static func keyboard_layout_name(layout: KeyboardLayout) -> String:
	var index: int = int(layout)
	if index < 0 || index >= KEYBOARD_LAYOUT_NAMES.size():
		return "Layout %d" % index
	return KEYBOARD_LAYOUT_NAMES[index]


## Whether the player has bound this action themselves. False leaves the
## action's own authored default standing - see HotkeyAction.current_key().
static func has_hotkey_override(action_id: String) -> bool:
	return !action_id.is_empty() && _hotkeys.has(action_id)


## What the player bound an action to, or empty for one they cleared. Ask
## has_hotkey_override() first: empty is also what an untouched action answers
## here, and the two mean opposite things.
static func hotkey_override(action_id: String) -> String:
	if !_hotkeys.has(action_id):
		return ""
	return str(_hotkeys[action_id])


## Binds an action, or - with an empty key - takes its key away entirely.
##
## Whether the key is one the game can ACCEPT is not decided here. This class
## holds no grid and has never heard of a command card; ControlsConfig owns that
## question and the options screen asks it before anything reaches this far.
static func set_hotkey_override(action_id: String, key: String) -> void:
	if action_id.is_empty():
		Log.err("UserSettings was told to bind an action with no id")
		return
	if _hotkeys.has(action_id) && str(_hotkeys[action_id]) == key:
		return
	_hotkeys[action_id] = key
	save_to_disk()


## Puts an action back on its authored default by FORGETTING the player's
## choice, which is not the same as binding that default explicitly: the day the
## default moves, a forgotten action follows it and a re-bound one does not.
static func clear_hotkey_override(action_id: String) -> void:
	if !_hotkeys.has(action_id):
		return
	_hotkeys.erase(action_id)
	save_to_disk()


## The same for every action at once, for the options screen's reset.
static func clear_all_hotkey_overrides() -> void:
	if _hotkeys.is_empty():
		return
	_hotkeys.clear()
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
