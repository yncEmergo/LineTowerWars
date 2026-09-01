class_name LobbySettingsPanel
extends PanelContainer

## The match rules, shown in the lobby room: what everybody starts with, which
## creeps are in it, how the opening technology is dealt, and how players are
## named on screen.
##
## **Everybody sees it, only the host edits it** (multiplayer.md 8.2). That is
## one line here - every control is disabled for a player who is not the host -
## and it is a courtesy rather than a check: the server refuses a settings
## change from anybody else, exactly as it refuses a Start from anybody else.
##
## It owns nothing. What it draws is whatever the server last pushed through
## the `Lobby` autoload, and a change is a request that comes back as a new
## lobby. So a host's own edit takes the same round trip everybody else's copy
## does, and a value the server clamped is drawn as the clamped one rather than
## as what was typed.
##
## The LIVES row is the one that moves on its own: left alone it follows the
## player count (game_rules.md - a fixed pool split between everybody), so it
## redraws whenever somebody joins or leaves. The moment the host types a
## number over it, it stays put. `Defaults` puts it back.

@export_group("References")
@export var _lives_spin: SpinBox
@export var _lives_label: Label
@export var _gold_spin: SpinBox
@export var _research_spin: SpinBox
@export var _income_spin: SpinBox
@export var _interval_spin: SpinBox
@export var _ranked_check: CheckButton
@export var _creeps_option: OptionButton
@export var _lanes_check: CheckButton
@export var _tech_option: OptionButton
@export var _modifier_option: OptionButton
## Puts every rule back to what GameConfig says, including the lives row's
## "follow the player count".
@export var _defaults_button: Button
## Says who may edit, so a player who is not the host is told rather than left
## wondering why nothing responds.
@export var _hint_label: Label

## The settings as last pushed by the server. Edited into a copy and sent; never
## changed in place, so what is on screen is always what the server agreed to.
var _settings: MatchSettings = MatchSettings.new()
var _player_count: int = 1
var _editable: bool = false
## True while the controls are being filled in from the server's answer, so
## writing a value into a SpinBox does not read back as the host typing it.
var _applying: bool = false

var _config: GameConfig:
	get:
		return References.game_config

var _limits: MenuConfig:
	get:
		return References.menu_config


func _ready() -> void:
	_fill_choices()
	_apply_limits()
	_connect_controls()


## Draws a lobby's rules, and says whether this machine may change them.
##
## The player count comes off the lobby rather than being counted here, because
## it is what the automatic lives row follows - a lobby of two shares the pool
## two ways.
func show_lobby(lobby: LobbyInfo, is_host: bool) -> void:
	if lobby == null:
		return
	_settings = lobby.settings
	_player_count = maxi(1, lobby.player_count())
	# Locked for everybody once the countdown starts: the rules become final at
	# the same moment the roster does, and the server refuses a change from
	# then on. See LobbyService.request_settings.
	_editable = is_host && !lobby.is_starting && !lobby.is_in_progress
	_redraw()


# --- drawing --------------------------------------------------------------

func _redraw() -> void:
	_applying = true
	_draw_resources()
	_draw_gameplay()
	_draw_editability()
	_applying = false


func _draw_resources() -> void:
	if _lives_spin != null:
		_lives_spin.value = _settings.lives_for(_player_count, _config)
	if _lives_label != null:
		# The row says WHY it is that number, since it is the one that moves
		# without anybody touching it.
		_lives_label.text = "Lives (auto)" if _settings.has_auto_lives() else "Lives"
	if _gold_spin != null:
		_gold_spin.value = _settings.starting_gold
	if _research_spin != null:
		_research_spin.value = _settings.free_technologies
	if _income_spin != null:
		_income_spin.value = _settings.starting_income
	if _interval_spin != null:
		_interval_spin.value = _settings.income_interval


func _draw_gameplay() -> void:
	if _ranked_check != null:
		_ranked_check.button_pressed = _settings.is_ranked
	if _lanes_check != null:
		_lanes_check.button_pressed = _settings.random_lanes
	if _creeps_option != null:
		_creeps_option.selected = int(_settings.creep_set)
	if _tech_option != null:
		_tech_option.selected = int(_settings.tech_mode)
	if _modifier_option != null:
		_modifier_option.selected = int(_settings.modifier)


## A ranked match is played on the defaults, so everything but the technology
## mode is dead even for the host - which is what the rule MEANS, rather than
## something enforced only when the message reaches the server.
func _draw_editability() -> void:
	var unlocked: bool = _editable && !_settings.is_locked()
	_set_enabled(_lives_spin, unlocked)
	_set_enabled(_gold_spin, unlocked)
	_set_enabled(_research_spin, unlocked)
	_set_enabled(_income_spin, unlocked)
	_set_enabled(_interval_spin, unlocked)
	_set_enabled(_creeps_option, unlocked)
	_set_enabled(_lanes_check, unlocked)
	_set_enabled(_modifier_option, unlocked)
	_set_enabled(_defaults_button, _editable && !_settings.is_locked())
	# The two the host always keeps: whether it is ranked at all, and how the
	# opening technology is dealt.
	_set_enabled(_ranked_check, _editable)
	_set_enabled(_tech_option, _editable)

	if _hint_label == null:
		return
	if !_editable:
		_hint_label.text = "Only the host can change these."
	elif _settings.is_locked():
		_hint_label.text = "Ranked: fixed rules. Turn it off to customise."
	else:
		_hint_label.text = "Custom game - this match is not rated."


# --- edits ----------------------------------------------------------------

## Every control ends here: the whole block is sent, and what comes back is
## what gets drawn. Nothing is applied locally on the way past.
func _send() -> void:
	if _applying || !_editable:
		return
	Lobby.set_settings(_gather())


## The settings the controls currently describe, as a copy. A copy because the
## one held is the server's answer, and editing that in place would leave the
## screen showing a change that was never agreed to.
func _gather() -> MatchSettings:
	var settings: MatchSettings = _settings.duplicate_settings()
	if _ranked_check != null:
		settings.is_ranked = _ranked_check.button_pressed
	if _lanes_check != null:
		settings.random_lanes = _lanes_check.button_pressed
	if _creeps_option != null:
		settings.creep_set = _creeps_option.selected as MatchSettings.CreepSet
	if _tech_option != null:
		settings.tech_mode = _tech_option.selected as MatchSettings.TechMode
	if _modifier_option != null:
		settings.modifier = _modifier_option.selected as MatchSettings.Modifier
	if _gold_spin != null:
		settings.starting_gold = int(_gold_spin.value)
	if _research_spin != null:
		settings.free_technologies = int(_research_spin.value)
	if _income_spin != null:
		settings.starting_income = int(_income_spin.value)
	if _interval_spin != null:
		settings.income_interval = _interval_spin.value
	return settings


## Typing a life total is what turns the automatic one off, so it is read
## separately from everything else: the value in the box is what the rule
## currently works out to, and only a CHANGE to it means anything.
func _on_lives_changed(value: float) -> void:
	if _applying || !_editable:
		return
	var settings: MatchSettings = _gather()
	settings.lives_per_player = int(value)
	Lobby.set_settings(settings)


func _on_defaults_pressed() -> void:
	if !_editable:
		return
	var settings: MatchSettings = _settings.duplicate_settings()
	settings.reset_to_defaults(_config)
	# reset_to_defaults switches Ranked back on, which is right for a fresh
	# lobby and wrong for a host who has deliberately left it: they asked for
	# the numbers back, not for the mode to change under them.
	settings.is_ranked = _settings.is_ranked
	settings.tech_mode = _settings.tech_mode
	Lobby.set_settings(settings)


# --- one-off setup --------------------------------------------------------

func _fill_choices() -> void:
	_fill_option(_creeps_option, MatchSettings.CREEP_SET_NAMES)
	_fill_option(_tech_option, MatchSettings.TECH_MODE_NAMES)
	_fill_option(_modifier_option, MatchSettings.MODIFIER_NAMES)


func _fill_option(option: OptionButton, names: Array[String]) -> void:
	if option == null:
		return
	option.clear()
	for name_text in names:
		option.add_item(name_text)


## The ceilings a host may push a custom game to, which live on MenuConfig - a
## lobby rule rather than a match one. The server clamps to the same numbers,
## so a spin box that cannot go higher and a request that would be cut down
## agree by construction.
func _apply_limits() -> void:
	var limits: MenuConfig = _limits
	if limits == null:
		Log.warn("LobbySettingsPanel found no MenuConfig, its controls are unbounded")
		return
	# Step ONE, even though the automatic total is always a multiple of five: a
	# SpinBox snaps to min + n * step, so a coarser step would redraw the rule's
	# own answer as the nearest number it happens to allow. It showed 201.
	_set_range(_lives_spin, 1.0, float(limits.max_lives_per_player), 1.0)
	_set_range(_gold_spin, 0.0, float(limits.max_starting_gold), 10.0)
	_set_range(_research_spin, 0.0, float(limits.max_free_technologies), 1.0)
	_set_range(_income_spin, 0.0, float(limits.max_starting_income), 5.0)
	_set_range(_interval_spin, limits.min_income_interval, limits.max_income_interval, 1.0)


func _set_range(spin: SpinBox, low: float, high: float, step: float) -> void:
	if spin == null:
		return
	spin.min_value = low
	spin.max_value = high
	spin.step = step


func _connect_controls() -> void:
	if _lives_spin != null:
		_lives_spin.value_changed.connect(_on_lives_changed)
	for spin: SpinBox in [_gold_spin, _research_spin, _income_spin, _interval_spin]:
		if spin != null:
			spin.value_changed.connect(_on_value_changed)
	for check: CheckButton in [_ranked_check, _lanes_check]:
		if check != null:
			check.toggled.connect(_on_toggled)
	for option: OptionButton in [_creeps_option, _tech_option, _modifier_option]:
		if option != null:
			option.item_selected.connect(_on_item_selected)
	if _defaults_button != null:
		_defaults_button.pressed.connect(_on_defaults_pressed)


## Three signatures for one answer. Godot hands a different argument to each
## kind of control and none of them is read: the whole block is gathered off
## the controls either way.
func _on_value_changed(_value: float) -> void:
	_send()


func _on_toggled(_pressed: bool) -> void:
	_send()


func _on_item_selected(_index: int) -> void:
	_send()


func _set_enabled(control: Control, enabled: bool) -> void:
	if control == null:
		return
	var spin: SpinBox = control as SpinBox
	if spin != null:
		spin.editable = enabled
		return
	var button: BaseButton = control as BaseButton
	if button != null:
		button.disabled = !enabled
