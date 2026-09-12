class_name SkirmishSetup
extends Control

## Setting up a single player match: how many computer opponents, how hard each
## of them is, and the same rules a lobby host chooses.
##
## **It is the lobby room with nobody else in it**, and deliberately so. The
## settings block is the very same panel - one scene, one script, one set of
## clamps - because a skirmish is a match like any other and a second copy of
## those controls would drift the first time one of them was changed. What is
## different is only the far end of an edit: a lobby sends the block to the
## server and draws what comes back, and this sanitises it here. See
## LobbySettingsPanel.show_local.
##
## There is no ranked skirmish, and the reason is worth stating: ranked means
## two results are comparable, and a result against a computer opponent is not
## comparable with anything. The Ranked tick is left on the panel because it is
## what LOCKS the rules to the defaults, which is a perfectly good thing to want
## in a practice game - it just never reaches a ladder.
##
## Nothing here starts a match by itself. It builds a MatchSetup, parks it on
## MenuNavigation and hands over to the loading screen, exactly as the lobby
## does when the server says go.

@export_group("References")
@export var _title_label: Label
## Parent for the seat rows, rebuilt whenever the roster changes.
@export var _slot_list: VBoxContainer
## How many computer opponents are in the match.
@export var _opponents_spin: SpinBox
## Sets every opponent to one difficulty at once, which is what somebody who
## wants a five player game against Normal actually means.
@export var _all_option: OptionButton
@export var _settings_panel: LobbySettingsPanel
@export var _start_button: Button
@export var _back_button: Button
@export var _hint_label: Label

@export_group("Settings")
@export var _slot_scene: PackedScene

## The roster as it currently stands: one MatchPlayer per seat, slot 1 being the
## person. Held as the real thing rather than as a count and a list of numbers,
## so what is drawn and what the match is started with cannot disagree.
var _players: Array[MatchPlayer] = []
## The rules, edited in place by the settings panel.
var _settings: MatchSettings = null
## Which profile each position in a difficulty dropdown stands for.
##
## Not every profile is an opponent - the tutorial's sparring partner is one of
## them - so a menu position and a profile index are different numbers, and
## anything that treats them as one offers a difficulty nobody should be able to
## pick. See AiConfig.selectable_indices.
var _choices: PackedInt32Array = PackedInt32Array()

var _config: GameConfig:
	get:
		return References.game_config

var _limits: MenuConfig:
	get:
		return References.menu_config

var _ai: AiConfig:
	get:
		return References.ai_config


func _ready() -> void:
	if _limits != null:
		# Once, here, rather than when a player presses the button that turns
		# out to point at nothing. The editor does not maintain path strings.
		_limits.validate()
	if _ai == null || !_ai.validate():
		Log.err("Single player has no usable AI difficulties, see the errors above")

	if _ai != null:
		_choices = _ai.selectable_indices()

	_settings = MatchSettings.defaults(_config)
	# A practice game is not rated and nothing pretends otherwise, so it opens
	# UNLOCKED - the whole point of playing one is usually to try a rule out.
	_settings.is_ranked = false

	_build_roster(_default_opponents())
	_connect_controls()
	_fill_all_option()
	_redraw()
	if _start_button != null:
		_start_button.grab_focus()


func _connect_controls() -> void:
	if _opponents_spin != null:
		_opponents_spin.min_value = 1.0
		_opponents_spin.max_value = float(_max_opponents())
		_opponents_spin.step = 1.0
		_opponents_spin.value_changed.connect(_on_opponents_changed)
	if _all_option != null:
		_all_option.item_selected.connect(_on_all_difficulty_chosen)
	if _start_button != null:
		_start_button.pressed.connect(_on_start_pressed)
	if _back_button != null:
		_back_button.pressed.connect(_on_back_pressed)
	if _settings_panel != null:
		_settings_panel.settings_changed.connect(_on_settings_changed)


func _fill_all_option() -> void:
	if _all_option == null || _ai == null:
		return
	_all_option.clear()
	for entry: String in _ai.names_of(_choices):
		_all_option.add_item(entry)
	_all_option.selected = _position_of(_default_difficulty())


## The roster from scratch, for a given number of opponents.
##
## Rebuilt rather than appended to, because the NAMES carry the difficulty and
## a seat whose difficulty changed has to be renamed with it - and because the
## colours are dealt down the palette in slot order, exactly as a lobby deals
## them when nobody has chosen.
func _build_roster(opponents: int) -> void:
	var wanted: int = clampi(opponents, 1, _max_opponents())
	var kept: Array[int] = []
	for index in range(1, _players.size()):
		kept.append(_players[index].ai_difficulty)

	_players.clear()
	_players.append(MatchPlayer.create(1, _local_name(), 0, 0))
	for index in range(wanted):
		var difficulty: int = kept[index] if index < kept.size() else _default_difficulty()
		var slot: int = index + 2
		_players.append(MatchPlayer.create(
			slot, _ai_name(difficulty, index + 1), 0, slot - 1, difficulty
		))


func _redraw() -> void:
	if _title_label != null:
		_title_label.text = "SINGLE PLAYER"
	if _opponents_spin != null:
		_opponents_spin.set_value_no_signal(float(_players.size() - 1))
	_build_rows()
	if _settings_panel != null:
		_settings_panel.show_local(_settings, _players.size())
	if _hint_label != null:
		_hint_label.text = "%d players, free for all. Everybody sends to their right." \
			% _players.size()


func _build_rows() -> void:
	if _slot_list == null || _slot_scene == null:
		Log.err("SkirmishSetup cannot build rows, the list or the row prefab is missing")
		return

	for child in _slot_list.get_children():
		_slot_list.remove_child(child)
		child.queue_free()

	var names: PackedStringArray = PackedStringArray()
	if _ai != null:
		names = _ai.names_of(_choices)
	for player in _players:
		var row: SkirmishSlot = _slot_scene.instantiate() as SkirmishSlot
		if row == null:
			Log.err("SkirmishSetup row prefab root does not have a SkirmishSlot script")
			return
		_slot_list.add_child(row)
		if player.is_ai():
			row.show_ai(player.slot, player.display_name, _swatch(player),
				names, _position_of(player.ai_difficulty))
			# Bound to the SLOT rather than to the row, so a rebuild cannot
			# leave a handler pointing at the seat that used to be there.
			row.difficulty_chosen.connect(_on_difficulty_chosen.bind(player.slot))
		else:
			row.show_player(player.slot, player.display_name, _swatch(player))


func _swatch(player: MatchPlayer) -> Color:
	var presentation: PresentationConfig = References.presentation_config
	if presentation == null:
		return Color(0.16, 0.17, 0.22, 1.0)
	return presentation.player_color(player.color_index)


# --- edits ----------------------------------------------------------------

func _on_opponents_changed(value: float) -> void:
	_build_roster(int(value))
	_redraw()


## The dropdown reports a POSITION in its own menu; what a seat holds is a
## profile index. See _choices.
func _on_difficulty_chosen(position: int, slot: int) -> void:
	var difficulty: int = _profile_at(position)
	for index in range(_players.size()):
		var player: MatchPlayer = _players[index]
		if player.slot != slot:
			continue
		player.ai_difficulty = difficulty
		player.display_name = _ai_name(difficulty, index)
		break
	_redraw()


## Every opponent set to one difficulty at once.
func _on_all_difficulty_chosen(position: int) -> void:
	var difficulty: int = _profile_at(position)
	for index in range(1, _players.size()):
		_players[index].ai_difficulty = difficulty
		_players[index].display_name = _ai_name(difficulty, index)
	_redraw()


## The settings panel sanitised an edit. Held rather than copied, so what is
## started is what was agreed to on screen.
func _on_settings_changed(settings: MatchSettings) -> void:
	_settings = settings


# --- starting -------------------------------------------------------------

## Builds the match and hands it to the loading screen.
##
## The SAME road a networked match takes from here on: the setup is parked on
## MenuNavigation, the loading screen loads the game scene and warms every unit,
## model and sound the match can spawn, and only then is the world built. A
## single player match pays for that warm-up exactly as a networked one does and
## for the same reason - the alternative is the first of everything being loaded
## the first time it appears, in the middle of play.
func _on_start_pressed() -> void:
	var setup: MatchSetup = MatchSetup.new()
	setup.mode = MatchSetup.Mode.SKIRMISH
	setup.match_id = "skirmish"
	setup.local_slot = 1
	# Its own stream every time, so two skirmishes on the same settings are not
	# the same match. A networked match takes its seed from the server instead.
	setup.rng_seed = randi()
	setup.settings = _settings.duplicate_settings()
	# A copy, so editing this screen after pressing Start - which cannot happen,
	# but is one scene change away from being able to - cannot reach into a
	# match that is already being built.
	for player in _players:
		setup.players.append(MatchPlayer.from_dict(player.to_dict()))

	if !setup.validate():
		Log.err("Single player built a setup that is not usable, see the errors above")
		return

	Log.info("Single player match starting", {
		"players": setup.player_count(),
		"ai": setup.ai_slots(),
		"settings": setup.settings.describe(),
	})
	MenuNavigation.to_match_loading(self, setup)


func _on_back_pressed() -> void:
	MenuNavigation.to_main_menu(self)


# --- lookups --------------------------------------------------------------

## The most opponents a skirmish may hold: one short of the seats the map has,
## since the player takes one.
##
## Read off the LOBBY's ceiling rather than off the map directly, because that
## is the number the rest of the game already calls "how many can play" and it
## is the one held at or under the map's slot count.
func _max_opponents() -> int:
	var limits: MenuConfig = _limits
	var ceiling: int = 12 if limits == null else limits.max_players
	return maxi(1, ceiling - 1)


func _default_opponents() -> int:
	var limits: MenuConfig = _limits
	if limits == null:
		return 1
	return clampi(limits.default_lobby_size - 1, 1, _max_opponents())


func _default_difficulty() -> int:
	return 0 if _ai == null else _ai.default_index()


## A position in a difficulty dropdown as the profile it stands for.
func _profile_at(position: int) -> int:
	if position < 0 || position >= _choices.size():
		return _default_difficulty()
	return _choices[position]


## The other way round, for drawing a seat that already holds a profile.
##
## Falls back to the first entry, so a seat carrying a profile nobody may choose
## still draws something rather than an empty dropdown.
func _position_of(difficulty: int) -> int:
	for position in range(_choices.size()):
		if _choices[position] == difficulty:
			return position
	return 0


## What the player is called in their own single player match.
##
## Their multiplayer name where they have chosen one, because somebody who has
## typed a name has said what they want to be called - and a plain word where
## they have not, rather than making them choose one to play alone.
func _local_name() -> String:
	var chosen: String = UserSettings.player_name
	return "You" if chosen.is_empty() else chosen


## What one opponent is called: its difficulty and which one it is, so a match
## against three Normals does not have three rows reading the same thing.
func _ai_name(difficulty: int, index: int) -> String:
	var profile: AiProfile = null if _ai == null else _ai.profile_for(difficulty)
	if profile == null:
		return "AI %d" % index
	return profile.player_name_pattern % [profile.display_name, index]
