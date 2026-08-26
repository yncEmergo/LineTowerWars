class_name UnitPanel
extends Control

## Bottom HUD panel describing the currently selected unit.
##
## Shows for exactly one selected unit. A multi-unit selection deliberately
## hides it for now: that case needs its own layout listing the abilities
## shared by the selection and no portrait, which is only worth building once
## there is more than the builder to select.
##
## The command card is a STACK, not a flat list. A submenu ability such as
## Build pushes a new card and cancelling pops back, which is how WC3 shows
## the buildable towers. Designing it in now costs an array; retrofitting it
## later would mean reworking this whole panel.
##
## Units are duck-typed. Anything exposing a stats: UnitStats and a
## current_health: int works here with no changes to this script.

## Command card shape used only when no ControlsConfig is wired. The real
## shape, and the letters that go with it, live there - it is how the player
## drives the game rather than a rule of it.
const FALLBACK_COMMAND_COLUMNS: int = 4
const FALLBACK_COMMAND_ROWS: int = 3

## Multi-selection grid shape. Sized to the space the stat labels occupy, so
## it fits without resizing the panel. Selecting more than this stays legal:
## the extra units simply are not pictured.
const SELECTION_COLUMNS: int = 6
const SELECTION_ROWS: int = 3

@export_group("References")
@export var _name_label: Label
@export var _health_label: Label
@export var _damage_label: Label
@export var _armor_label: Label
## Attack speed and range. Hidden for anything that cannot attack, so a creep's
## panel does not carry an empty line.
@export var _attack_label: Label
@export var _command_grid: GridContainer
@export var _selection_grid: GridContainer
@export var _command_slot_scene: PackedScene
@export var _unit_tile_scene: PackedScene

var _slots: Array[CommandSlot] = []
var _tiles: Array[UnitTile] = []
## Ability whose hotkey is currently held down, for repeat firing.
var _held_ability: UnitAbility = null
## True while an ability is armed and waiting for its target. The card empties
## for as long as it holds, so nothing else can be pressed mid-order.
var _armed: bool = false
var _held_key: Key = KEY_NONE
## Seconds the key has been down, and seconds since the last repeat fired.
var _held_elapsed: float = 0.0
var _since_repeat: float = 0.0
## Cards from root to deepest. The last entry is what the slots show.
var _card_stack: Array = []
## Unit driving the portrait, stats and health. The first of a group.
var _unit: Unit = null
## Every selected unit when more than one is picked, empty otherwise.
var _group: Array = []
## Units whose signals are currently connected, so they can be released again.
var _watched: Array[Unit] = []

## Read on every selection change, so they come through getters onto
## References rather than being wired separately on this node.
var _selection_controller: SelectionController:
	get:
		return References.selection_controller

var _command_controller: CommandController:
	get:
		return References.command_controller

var _controls_config: ControlsConfig:
	get:
		return References.controls_config


func _ready() -> void:
	var selection: SelectionController = _selection_controller
	if selection == null:
		Log.err("UnitPanel found no SelectionController on References, it will never show")
	else:
		selection.selection_changed.connect(_on_selection_changed)

	var commands: CommandController = _command_controller
	if commands == null:
		Log.err("UnitPanel found no CommandController on References, abilities will not fire")
	else:
		# An armed ability resolving or being cancelled drops the card back to
		# the unit's root, the same way leaving a WC3 build menu does.
		commands.ability_armed.connect(_on_ability_armed)
		commands.command_ended.connect(_on_command_ended)

	if _name_label == null || _health_label == null \
			|| _damage_label == null || _armor_label == null:
		Log.err("UnitPanel is missing one or more of its labels")

	_build_command_slots()
	_build_selection_tiles()
	clear()


## Tiles are built once and refilled, like the command slots.
func _build_selection_tiles() -> void:
	if _selection_grid == null || _unit_tile_scene == null:
		Log.err("UnitPanel is missing its selection grid or unit tile scene")
		return

	_selection_grid.columns = SELECTION_COLUMNS

	for tile_index in range(SELECTION_COLUMNS * SELECTION_ROWS):
		var tile: UnitTile = _unit_tile_scene.instantiate() as UnitTile
		if tile == null:
			Log.err("Unit tile scene does not have a UnitTile script")
			return
		tile.name = "UnitTile%d" % tile_index
		tile.unit_clicked.connect(_on_tile_clicked)
		_selection_grid.add_child(tile)
		_tiles.append(tile)


## Slots are claimed once and then refilled, so the card keeps its shape and no
## nodes churn as the selection or the card changes.
##
## The squares themselves are AUTHORED into unit_panel.tscn rather than built
## here, because every unit gets the whole grid whatever it has to put on it,
## so the panel has exactly one width and the editor may as well show it. The
## prefab stays wired as the fallback for a ControlsConfig asking for a shape
## the scene was not authored for.
##
## The grid is always at its full size whatever the current unit offers, which
## is what makes an ability able to claim a fixed square: slot 11 exists even
## on a card that fills only the first row.
func _build_command_slots() -> void:
	if _command_grid == null:
		Log.err("UnitPanel has no command grid assigned")
		return

	var columns: int = FALLBACK_COMMAND_COLUMNS
	var rows: int = FALLBACK_COMMAND_ROWS
	var config: ControlsConfig = _controls_config
	if config != null:
		columns = config.command_columns
		rows = config.command_rows

	_command_grid.columns = columns
	for child in _command_grid.get_children():
		var authored: CommandSlot = child as CommandSlot
		if authored != null:
			_slots.append(authored)
	_fit_slot_count(columns * rows)

	for slot_index in range(_slots.size()):
		_slots[slot_index].name = "CommandSlot%d" % slot_index
		_slots[slot_index].ability_activated.connect(_on_ability_activated)


## Brings the authored squares in line with the shape ControlsConfig asks for:
## frees any the scene has too many of, and makes up any it is short of from
## the prefab.
##
## Loud when it has to do either. The scene matching the config is the normal
## case, and a mismatch means one of the two was changed without the other.
func _fit_slot_count(wanted: int) -> void:
	while _slots.size() > wanted:
		var extra: CommandSlot = _slots.pop_back()
		_command_grid.remove_child(extra)
		extra.queue_free()

	if _slots.size() == wanted:
		return

	if _command_slot_scene == null:
		Log.err("UnitPanel has too few authored squares and no slot scene to add more", {
			"authored": _slots.size(),
			"wanted": wanted,
		})
		return

	Log.warn("Command grid in unit_panel.tscn does not match the configured card shape", {
		"authored": _slots.size(),
		"wanted": wanted,
	})
	while _slots.size() < wanted:
		var slot: CommandSlot = _command_slot_scene.instantiate() as CommandSlot
		if slot == null:
			Log.err("Command slot scene does not have a CommandSlot script")
			return
		_command_grid.add_child(slot)
		_slots.append(slot)

# --- Selection ----------------------------------------------------------

func _on_selection_changed(units: Array) -> void:
	if units.is_empty():
		clear()
	elif units.size() == 1:
		show_unit(units[0])
	else:
		show_group(units)


## Fills the panel from a unit and reveals it.
func show_unit(unit: Variant) -> void:
	if unit == null || _name_label == null:
		clear()
		return

	var stats: UnitStats = unit.stats
	if stats == null:
		Log.err("Selected unit has no stats, cannot fill the unit panel")
		clear()
		return

	_detach_units()
	_unit = unit as Unit
	_group = []
	_attach_units([_unit])
	_set_group_mode(false)

	_name_label.text = stats.display_name
	_health_label.text = "%d / %d" % [int(unit.current_health), stats.max_health]
	_set_damage_text(stats)
	_armor_label.text = "Armor:   %s" % stats.armor_text(unit.armor_value())
	_set_attack_text(stats)

	_card_stack = [_unit.current_abilities()]
	_refresh_slots()
	visible = true


## Fills the panel for a multi-unit selection.
##
## The portrait and health come from the first unit, which is cosmetic - the
## point of the panel here is the grid of what is selected and the abilities
## they all share.
func show_group(units: Array) -> void:
	if units.is_empty():
		clear()
		return

	_detach_units()
	_unit = units[0] as Unit
	# Copied, because the controller keeps mutating the array it handed over
	# when units leave the selection.
	_group = units.duplicate()
	_attach_units(_group)
	_set_group_mode(true)

	if _unit != null:
		_health_label.text = "%d / %d" % [_unit.current_health, _unit.max_health()]

	_fill_selection_grid(units)
	_card_stack = [_shared_abilities(units)]
	_refresh_slots()
	visible = true


func clear() -> void:
	_detach_units()
	_unit = null
	_group = []
	_card_stack = []
	visible = false


## Swaps the middle of the panel between the single unit's stats and the grid
## of everything selected.
## Damage, and nothing at all for a unit that has no attack. A creep's panel
## would otherwise carry a "Damage: -" line that only ever says "not this one".
## Must run after _set_group_mode, which reveals every single-unit label.
func _set_damage_text(stats: UnitStats) -> void:
	if _damage_label == null:
		return

	_damage_label.visible = stats.attack != null
	if stats.attack != null:
		_damage_label.text = "Damage:   %s" % stats.damage_text()


## Attack speed and range, and nothing at all for a unit that cannot attack.
## Written as APS rather than spelled out, because APS is what the player calls
## it. Must run after _set_group_mode, which reveals every single-unit label.
func _set_attack_text(stats: UnitStats) -> void:
	if _attack_label == null:
		return

	var attack: AttackStats = stats.attack
	_attack_label.visible = attack != null
	if attack == null:
		return

	_attack_label.text = "Attack:   %s,  %s range" % [
		attack.attack_speed_text(), attack.range_text()
	]


func _set_group_mode(group: bool) -> void:
	if _name_label != null:
		_name_label.visible = !group
	if _damage_label != null:
		_damage_label.visible = !group
	if _armor_label != null:
		_armor_label.visible = !group
	if _attack_label != null:
		_attack_label.visible = !group
	if _selection_grid != null:
		_selection_grid.visible = group


func _fill_selection_grid(units: Array) -> void:
	if units.size() > _tiles.size():
		Log.info("More units selected than the grid pictures", {
			"selected": units.size(),
			"tiles": _tiles.size(),
		})

	for index in range(_tiles.size()):
		if index < units.size():
			_tiles[index].set_unit(units[index] as Unit)
		else:
			_tiles[index].clear()


## Abilities every selected unit offers, in the first unit's order so the card
## does not reshuffle as the selection changes.
##
## Abilities are shared resources, so identical units reference the very same
## .tres and compare equal without needing an id.
func _shared_abilities(units: Array) -> Array:
	var first: Unit = units[0] as Unit
	if first == null || !is_instance_valid(first):
		return []

	var shared: Array = []
	for ability in first.current_abilities():
		var in_every: bool = true
		for other in units:
			var typed: Unit = other as Unit
			# A unit part-way through being freed is not part of the answer.
			if typed == null || !is_instance_valid(typed) || typed == first:
				continue
			if !typed.current_abilities().has(ability):
				in_every = false
				break
		if in_every:
			shared.append(ability)

	return shared


## Clicking a tile narrows the selection to that unit alone.
func _on_tile_clicked(unit: Unit) -> void:
	var selection: SelectionController = _selection_controller
	if selection != null:
		selection.select_single(unit)


## The panel follows the unit it is showing, so a tower being built reports its
## health climbing and swaps its card the moment it finishes.
## Watches EVERY selected unit, not just the one driving the portrait. Any of
## them finishing construction or starting a sale changes what the group still
## shares, so the card has to be recomputed whichever unit it happened to.
func _attach_units(units: Array) -> void:
	for entry in units:
		var unit: Unit = entry as Unit
		if unit == null || !is_instance_valid(unit):
			continue

		var health_callback: Callable = _on_unit_health_changed.bind(unit)
		if !unit.health_changed.is_connected(health_callback):
			unit.health_changed.connect(health_callback)
		if !unit.abilities_changed.is_connected(_on_unit_abilities_changed):
			unit.abilities_changed.connect(_on_unit_abilities_changed)

		_watched.append(unit)


func _detach_units() -> void:
	for unit in _watched:
		if unit == null || !is_instance_valid(unit):
			continue

		var health_callback: Callable = _on_unit_health_changed.bind(unit)
		if unit.health_changed.is_connected(health_callback):
			unit.health_changed.disconnect(health_callback)
		if unit.abilities_changed.is_connected(_on_unit_abilities_changed):
			unit.abilities_changed.disconnect(_on_unit_abilities_changed)

	_watched.clear()
	_unit = null


func _on_unit_health_changed(current: int, maximum: int, unit: Unit) -> void:
	# Only the unit driving the portrait owns the big readout, but any unit's
	# tile has to stay honest.
	if unit == _unit && _health_label != null:
		_health_label.text = "%d / %d" % [current, maximum]
	_refresh_tile_for(unit)


func _refresh_tile_for(unit: Unit) -> void:
	for tile in _tiles:
		if tile.unit == unit:
			tile.set_unit(unit)
			return


func _on_unit_abilities_changed() -> void:
	if _unit == null:
		return
	# Back to the root card, since a submenu of the old set is stale. A group
	# recomputes what everyone still shares, because one unit changing state
	# can remove an ability from the whole card.
	if _group.is_empty():
		_card_stack = [_unit.current_abilities()]
	else:
		_card_stack = [_shared_abilities(_group)]
	_refresh_slots()


# --- Command card -------------------------------------------------------

## Replaces the visible card, keeping the previous one to come back to.
func push_card(abilities: Array) -> void:
	_card_stack.append(abilities)
	_refresh_slots()


## Returns to the unit's root card.
func pop_to_root() -> void:
	if _card_stack.size() <= 1:
		return
	_card_stack.resize(1)
	_refresh_slots()


## Whether the card is showing a submenu rather than the unit's root card, so
## Escape has something to back out of before it reaches the game menu.
func is_in_submenu() -> bool:
	return _card_stack.size() > 1


func _current_card() -> Array:
	if _card_stack.is_empty():
		return []
	return _card_stack.back()


## Lays a card out across the grid and fills every square from it.
##
## An ability that claimed a slot gets that slot, so a tower's Sell stays at
## the bottom right whatever else is on the card and its key never moves.
## Everything left over falls into the first free square, which is what a
## passive with no key worth pressing wants.
func _refresh_slots() -> void:
	# An armed ability owns the next click, so the card empties rather than
	# offering buttons that would fight it. The grid keeps its place, so the
	# panel never changes shape mid-order. The card STACK is untouched, which
	# is what lets cancelling drop straight back to what was showing.
	var placed: Array = [] if _armed else _place_card(_current_card())
	placed.resize(_slots.size())

	for index in range(_slots.size()):
		_slots[index].set_ability(placed[index], _unit, _hotkey_letter(index))

## One entry per square, null where the card leaves a gap.
##
## Two abilities on the same card claiming the same square is an authoring
## mistake rather than something to resolve quietly: the first one keeps the
## square, the second is reported and dropped in wherever there is room, so the
## card still works and the mistake is visible in the log.
func _place_card(card: Array) -> Array:
	var placed: Array = []
	placed.resize(_slots.size())

	var floating: Array = []
	for entry in card:
		var ability: UnitAbility = entry as UnitAbility
		if ability == null:
			continue

		var wanted: int = ability.slot
		if wanted < 0 || wanted >= placed.size():
			floating.append(ability)
		elif placed[wanted] != null:
			Log.err("Two abilities on one card claim the same slot", {
				"slot": wanted,
				"kept": placed[wanted].display_name,
				"moved": ability.display_name,
			})
			floating.append(ability)
		else:
			placed[wanted] = ability

	_fill_free_slots(placed, floating)
	return placed


## Drops everything that named no square, or named a taken one, into the gaps
## left over. Anything that still does not fit is reported rather than silently
## vanishing off the card.
func _fill_free_slots(placed: Array, floating: Array) -> void:
	var next: int = 0
	for ability in floating:
		while next < placed.size() && placed[next] != null:
			next += 1
		if next >= placed.size():
			Log.warn("Card has more abilities than the grid has squares", {
				"ability": ability.display_name,
				"slots": placed.size(),
			})
			return
		placed[next] = ability


## Letter drawn on a square and pressed to use it. Empty when no controls
## config is wired, which leaves the card usable by mouse and simply unbound.
func _hotkey_letter(slot_index: int) -> String:
	var config: ControlsConfig = _controls_config
	if config == null:
		return ""
	return config.hotkey_letter_for_slot(slot_index)

func _on_ability_activated(ability: UnitAbility) -> void:
	if ability == null:
		return

	match ability.targeting:
		UnitAbility.Targeting.PASSIVE:
			# Nothing to do. Passives exist to be read, not pressed.
			return
		UnitAbility.Targeting.SUBMENU:
			# Pure card navigation, so it never reaches the command controller.
			push_card(ability.submenu_abilities())
		_:
			if _command_controller != null:
				_command_controller.activate_ability(ability)


## An armed ability empties the card until it resolves or is cancelled, so no
## second order can be started while one is being aimed. Held hotkeys are
## dropped too, since the ability they were repeating is no longer on screen.
func _on_ability_armed(_ability: UnitAbility) -> void:
	_armed = true
	_release_hold()
	_refresh_slots()


func _on_command_ended() -> void:
	_armed = false
	pop_to_root()
	# pop_to_root only redraws when the stack actually changed, and an order
	# aimed from the root card leaves it exactly as it was.
	_refresh_slots()
## Ability hotkeys only fire for the card currently on screen, so the same key
## can mean different things on different units, as in WC3.
##
## The key is resolved to a SQUARE and the square's ability is what runs. So
## the letters are a property of the grid rather than of any ability, and a
## card that leaves a square empty leaves its key alone - which is what keeps
## the rest of the game's keys usable while a unit is selected.
##
## Keycodes rather than physical keycodes on purpose: a keycode already follows
## the player's keyboard layout, so the key printed Y on a German board reports
## KEY_Y and lands in the bottom left where the card draws it.
func _unhandled_key_input(event: InputEvent) -> void:
	if !visible:
		return

	var key: InputEventKey = event as InputEventKey
	if key == null || key.echo:
		return

	if !key.pressed:
		# Releasing the held key ends the repeat. The OS repeat is ignored
		# above, because its rate is a desktop setting rather than ours.
		if key.keycode == _held_key:
			_release_hold()
		return

	var config: ControlsConfig = _controls_config
	if config == null:
		return

	var index: int = config.slot_for_key(key.keycode)
	if index < 0 || index >= _slots.size():
		return

	var ability: UnitAbility = _slots[index].ability
	# An empty square, and a passive that cannot be pressed, both leave the key
	# unhandled rather than swallowing it.
	if ability == null || ability.targeting == UnitAbility.Targeting.PASSIVE:
		return

	_on_ability_activated(ability)
	if ability.repeat_on_hold:
		_begin_hold(ability, key.keycode)
	get_viewport().set_input_as_handled()

# --- Hold to repeat -----------------------------------------------------

func _begin_hold(ability: UnitAbility, key: Key) -> void:
	_held_ability = ability
	_held_key = key
	_held_elapsed = 0.0
	_since_repeat = 0.0


func _release_hold() -> void:
	_held_ability = null
	_held_key = KEY_NONE
	_held_elapsed = 0.0
	_since_repeat = 0.0


## Repeats a held ability, accelerating from the start interval to the cap, and
## keeps the armour readout honest while it is at it.
##
## Ramping rather than firing flat out from the first repeat: at ten a second a
## fixed rate would empty a full reserve before the player could react, while a
## slow start leaves room to let go after one or two.
func _process(delta: float) -> void:
	_refresh_armor_label()

	if _held_ability == null:
		return

	# The card can change under a held key, e.g. the selection dies. Dropping
	# the hold is safer than firing an ability that is no longer on screen.
	if !visible || !_current_card().has(_held_ability):
		_release_hold()
		return

	# Live key state as well as the release event, because a key released while
	# another window had focus never reaches _unhandled_key_input.
	if _held_key != KEY_NONE && !Input.is_key_pressed(_held_key):
		_release_hold()
		return

	_held_elapsed += delta
	var config: ControlsConfig = _controls_config
	if config == null || _held_elapsed < config.hold_repeat_delay:
		return

	_since_repeat += delta
	if _since_repeat < _repeat_interval(config):
		return

	_since_repeat = 0.0
	_on_ability_activated(_held_ability)


## Armour is the one stat that moves while a unit simply stands there, because
## an aura can reach it, so it is re-read every frame rather than only when the
## selection changes. Written only on a real change, so the label is not
## rebuilt sixty times a second for a number that has not moved.
func _refresh_armor_label() -> void:
	if _armor_label == null || !_armor_label.visible:
		return
	if _unit == null || !is_instance_valid(_unit) || _unit.stats == null:
		return

	var text: String = "Armor:   %s" % _unit.stats.armor_text(_unit.armor_value())
	if _armor_label.text != text:
		_armor_label.text = text

func _repeat_interval(config: ControlsConfig) -> float:
	var ramp: float = config.hold_repeat_ramp_seconds
	if ramp <= 0.0:
		return config.hold_repeat_min_interval

	var held: float = maxf(0.0, _held_elapsed - config.hold_repeat_delay)
	var progress: float = clampf(held / ramp, 0.0, 1.0)
	return lerpf(config.hold_repeat_start_interval, config.hold_repeat_min_interval, progress)
