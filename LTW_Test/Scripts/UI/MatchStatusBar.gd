class_name MatchStatusBar
extends PanelContainer

## What the local player has right now, across the top middle of the screen:
## gold, living population against the cap, and the countdown to the next
## income payout.
##
## Each number is named by an icon rather than a word, which is what keeps the
## bar short enough to sit in the middle of the screen without crowding what is
## under it. The icons carry tooltips, since a picture on its own is only
## obvious once you already know what it means.
##
## Three numbers rather than one, because they answer three different questions
## a player asks constantly - can I afford this, can I send more, and how long
## until I can afford more - and they belong together because a send spends the
## first, fills the second and is paid for by the third.
##
## Gold follows a signal; population and the countdown are POLLED, and that is
## deliberate. Population changes whenever any creep anywhere spawns, dies,
## leaks or is recycled, and the countdown changes continuously - wiring
## signals for either would mean touching every one of those paths to report
## something only a label cares about.
##
## Connects on a deferred call rather than straight away, because the player
## states are created in Main._ready, which runs after every child's _ready.

const GOLD_COLOR: Color = Color(1.0, 0.84, 0.32, 1.0)
const POPULATION_COLOR: Color = Color(0.72, 0.78, 0.88, 1.0)
const INCOME_COLOR: Color = Color(0.62, 0.86, 0.55, 1.0)
## How often the polled halves are re-read. Four times a second is smooth
## enough for a countdown shown in whole seconds and cheap enough to walk the
## unit registry for.
const REFRESH_SECONDS: float = 0.25

@export_group("References")
@export var _gold_label: Label
@export var _population_label: Label
@export var _income_label: Label
## The icon beside each number, painted from the same constant as the label it
## belongs to so the pair can never drift apart.
@export var _gold_icon: TextureRect
@export var _population_icon: TextureRect
@export var _timer_icon: TextureRect

var _state: PlayerState
var _elapsed: float = 0.0

var _manager: PlayerManager:
	get:
		return References.player_manager


func _ready() -> void:
	_paint(_gold_label, _gold_icon, GOLD_COLOR)
	_paint(_population_label, _population_icon, POPULATION_COLOR)
	_paint(_income_label, _timer_icon, INCOME_COLOR)
	_connect_state.call_deferred()


func _connect_state() -> void:
	var manager: PlayerManager = _manager
	if manager == null:
		Log.err("MatchStatusBar found no PlayerManager on References")
		return

	_state = manager.local_state()
	if _state == null:
		# A dedicated server plays no slot, which is not a fault. Nothing here
		# has anything to show, so it says nothing.
		return

	_state.gold_changed.connect(_on_gold_changed)
	_on_gold_changed(_state.gold)
	_refresh_polled()


func _process(delta: float) -> void:
	if _state == null:
		return
	_elapsed += delta
	if _elapsed < REFRESH_SECONDS:
		return
	_elapsed = 0.0
	_refresh_polled()


func _on_gold_changed(gold: int) -> void:
	if _gold_label != null:
		_gold_label.text = str(gold)


func _refresh_polled() -> void:
	var manager: PlayerManager = _manager
	if manager == null:
		return

	if _population_label != null:
		_population_label.text = "%d / %d" % [
			manager.population_for(_state.player_id), _population_cap(),
		]

	if _income_label != null:
		# Rounded UP, so the last part-second still reads as 1 rather than
		# sitting on 0 while nothing has been paid yet.
		_income_label.text = "%ds" % ceili(manager.seconds_until_income())


func _population_cap() -> int:
	var config: GameConfig = References.game_config
	return 100 if config == null else config.population_cap


func _paint(label: Label, icon: TextureRect, color: Color) -> void:
	if label != null:
		label.add_theme_color_override("font_color", color)
	if icon != null:
		icon.modulate = color
