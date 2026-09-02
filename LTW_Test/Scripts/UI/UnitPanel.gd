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
## display_health(): int works here with no changes to this script.

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
## The unit's SECOND RESOURCE, for the towers that have one - mana, or a count
## a passive has banked. Hidden for everything else, which is every Basic tower
## and every creep: a line reading "0 / 0" on all of them would be noise on the
## panel a player looks at most.
@export var _resource_label: Label
## Health and the secondary resource, drawn under the portrait as bars as well
## as written out as numbers. The bar is what is read at a glance mid-fight;
## the numbers are what is read when the player actually wants to know.
@export var _health_bar: StatBar
## Hidden for anything with no second resource, which is every creep, the
## builder and every Basic tower. Its colour is not a property of the prefab:
## the tower answers with it, so mana stays blue and a banked count is violet.
@export var _resource_bar: StatBar
@export var _damage_label: Label
@export var _armor_label: Label
## Attack speed and range. Hidden for anything that cannot attack, so a creep's
## panel does not carry an empty line.
@export var _attack_label: Label
## How much ground one attack covers and how many creeps it strikes. Shown for
## anything that attacks, INCLUDING when the answer to both is nothing: "no
## splash" is a real and important property of a tower, and a line that only
## appeared on the towers that had some would make the ones that do not read as
## if the panel had forgotten to say.
@export var _splash_label: Label
## Shown INSTEAD of the stat lines while the selected tower is busy with
## something on a clock - selling, upgrading, reverting to a Core. The panel
## says one thing at a time, and while a countdown is running that is the one
## thing worth saying. See Building.current_job.
@export var _job_row: Control
@export var _job_icon: TextureRect
@export var _job_label: Label
@export var _job_bar: StatBar
## The row of debuff squares under the stat lines. Follows the same rules the
## stat lines do - one unit only, and off while a countdown is running - so a
## player is never reading a creep's chill next to a tower's sale timer.
@export var _status_bar: StatusBar
@export var _command_grid: GridContainer
@export var _selection_grid: GridContainer
@export var _command_slot_scene: PackedScene
@export var _unit_tile_scene: PackedScene
## The live 3D picture of whichever unit drives the panel. Optional, so a
## stripped-down panel in a test scene still works without one.
@export var _portrait: UnitPortrait
## Put on the card whenever there is something to back out of - an ability
## being aimed, or a submenu that was opened. Optional for the same reason.
@export var _cancel_ability: UnitAbility

var _slots: Array[CommandSlot] = []
## The key each square is currently drawing, in square order.
##
## Kept because it is also the answer to "what does this press do": the letters
## are handed out down the card rather than nailed to a square number, so the
## square a key lands on cannot be worked out from the key alone. What is drawn
## and what is pressed are then the same array, which is the only way they can
## be trusted not to disagree.
var _slot_letters: PackedStringArray = PackedStringArray()
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
## Whether the job row is on screen, which is what the stat lines hide behind.
## Kept because those lines are shown from three places and every one of them
## has to lose to a running countdown.
var _busy: bool = false

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

	if _name_label == null || _health_label == null || _damage_label == null \
			|| _armor_label == null || _resource_label == null \
			|| _resource_bar == null:
		Log.err("UnitPanel is missing one or more of its labels")

	add_to_group(HotkeyAction.READERS_GROUP)
	_build_command_slots()
	_build_selection_tiles()
	clear()


## Redraws the card because a key changed under it - the player rebound one, or
## switched keyboard layout. Called on the whole group by the options screen,
## since nothing about the selection has moved and the card would otherwise go
## on drawing the letter it was built with.
func refresh_hotkeys() -> void:
	_refresh_slots()


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
## is what makes an ability able to claim a fixed square: the last square
## exists even on a card that fills only the first row.
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
	_health_label.text = "%d / %d" % [unit.display_health(), stats.max_health]
	_set_resource_text(unit)
	_set_damage_text(_unit)
	_apply_armor_label()
	_set_attack_text(_unit)
	_refresh_bars()
	_refresh_job()
	if _status_bar != null:
		_status_bar.show_unit(_unit)

	_card_stack = [_unit.current_abilities()]
	_refresh_slots()
	_show_portrait(_unit)
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
	_show_portrait(_unit)

	if _unit != null:
		_health_label.text = "%d / %d" % [_unit.display_health(), _unit.max_health()]
	_set_resource_text(_unit)
	_refresh_bars()
	_refresh_job()
	if _status_bar != null:
		# A group has no room to say whose debuff is whose, and no way to be
		# asked - the row is one unit's or nobody's.
		_status_bar.clear()

	_fill_selection_grid(units)
	_card_stack = [_shared_abilities(units)]
	_refresh_slots()
	visible = true


## Points the portrait at whatever drives the panel. Split out rather than
## called inline, so the null check lives in one place and a panel with no
## portrait wired simply does nothing.
func _show_portrait(unit: Unit) -> void:
	if _portrait != null:
		_portrait.show_unit(unit)


func clear() -> void:
	_detach_units()
	_unit = null
	_group = []
	_card_stack = []
	_busy = false
	if _job_row != null:
		_job_row.visible = false
	if _status_bar != null:
		_status_bar.clear()
	_show_portrait(null)
	visible = false


## Swaps the middle of the panel between the single unit's stats and the grid
## of everything selected.
## Damage, and nothing at all for a unit that has no attack. A creep's panel
## would otherwise carry a "Damage: -" line that only ever says "not this one".
## Must run after _set_group_mode, which reveals every single-unit label.
func _set_damage_text(unit: Unit) -> void:
	if _damage_label == null || unit == null || unit.stats == null:
		return

	_damage_label.visible = unit.stats.attack != null && !_busy
	if unit.stats.attack != null:
		_damage_label.text = _damage_line(unit)


## The damage line for one unit, with everything currently changing it folded
## in. Two different things, and both belong here:
##
##   what the unit has EARNED and keeps - an Alchemist that has devoured a
##   hundred points of damage hits for a hundred more than its stats say, and
##   the panel is where a player finds that out
##   what is REACHING it right now - a Void disc lending it damage, an
##   Obsidian Statue drifting past taking some away
##
## Asked of the UNIT rather than read off its stats, for the same reason the
## armour line is: the number on the resource is the base, and what is standing
## on the field is not always it.
func _damage_line(unit: Unit) -> String:
	var tower: Building = unit as Building
	var bonus: int = 0 if tower == null else tower.permanent_damage_bonus()
	return "Damage:   %s" % unit.stats.damage_text(
		bonus, unit.attack_damage_ratio())


## Keeps it up to date. Polled for the same reason the armour line is: a tower
## that eats damage as it kills is a tower whose damage line moves while a
## player is looking straight at it, and no signal is raised when it does.
func _refresh_damage_label() -> void:
	if _damage_label == null || !_damage_label.visible:
		return
	if _unit == null || !is_instance_valid(_unit) || _unit.stats == null:
		return

	var text: String = _damage_line(_unit)
	if _damage_label.text != text:
		_damage_label.text = text


## Attack speed and range, and nothing at all for a unit that cannot attack.
## Written as APS rather than spelled out, because APS is what the player calls
## it. Must run after _set_group_mode, which reveals every single-unit label.
func _set_attack_text(unit: Unit) -> void:
	if _attack_label == null || unit == null || unit.stats == null:
		return

	var attack: AttackStats = unit.stats.attack
	var showing: bool = attack != null && !_busy
	_attack_label.visible = showing
	if _splash_label != null:
		# Follows the attack line rather than deciding for itself, so the two
		# can never end up with one of them left over from the last unit.
		_splash_label.visible = showing
	if !showing:
		return

	# Both asked of the UNIT, on the same terms the damage and armour lines are:
	# an Earth disc makes a tower swing faster and a Primal disc makes it reach
	# further, and neither is anything its stats file can know about.
	#
	# Written only when it has actually moved, the way the damage line is: this
	# runs every frame now that it is polled, and assigning a Label its own text
	# back re-lays the panel out for nothing.
	var text: String = "Attack:   %s,  %s range" % [
		attack.attack_speed_text(unit.attack_speed_ratio()),
		attack.range_text(unit.attack_range_bonus())
	]
	if _attack_label.text != text:
		_attack_label.text = text
	_set_splash_text(attack)


## Keeps it up to date, polled for the reason the damage and armour lines are:
## a disc going up beside a tower moves both halves of this line while a player
## is looking straight at it, and no signal is raised when it does.
func _refresh_attack_label() -> void:
	if _attack_label == null || !_attack_label.visible:
		return
	if _unit == null || !is_instance_valid(_unit):
		return
	_set_attack_text(_unit)


## The area-and-count line: how much ground one attack covers, and how many
## creeps it hits beyond the one it aimed at.
##
## The multishot count is asked of the UNIT rather than read off the attack,
## because nearly every tower in the roster that hits several creeps does it
## through its ABILITY rather than through its base attack - a Titan Vault's
## own AttackStats says nothing about the ten extra creeps it strikes.
func _set_splash_text(attack: AttackStats) -> void:
	if _splash_label == null:
		return

	var radius: float = attack.splash_radius()
	var splash: String = "None"
	if radius > 0.0:
		splash = "%s cells" % StringUtil.trim_number(radius)

	var extra: int = attack.multishot_targets + _passive_extra_targets()
	var multishot: String = "None" if extra <= 0 else "+%d targets" % extra
	# Guarded like the two lines above it, and for the same reason: this is
	# reached from the attack line, which is polled every frame now.
	var text: String = "Splash:   %s,   Multishot:   %s" % [splash, multishot]
	if _splash_label.text != text:
		_splash_label.text = text


## Further creeps the selected tower's own abilities add to every attack.
func _passive_extra_targets() -> int:
	var tower: Building = _unit as Building
	if tower == null:
		return 0
	var extra: int = 0
	for passive in tower.tower_passives():
		extra += passive.extra_targets(tower)
	return extra


func _set_group_mode(group: bool) -> void:
	if _name_label != null:
		_name_label.visible = !group
	if _resource_label != null && group:
		_resource_label.visible = false
	if _resource_bar != null && group:
		_resource_bar.visible = false
	if _damage_label != null:
		_damage_label.visible = !group
	if _armor_label != null:
		_armor_label.visible = !group
	if _attack_label != null:
		_attack_label.visible = !group
	if _splash_label != null:
		_splash_label.visible = !group
	if _job_row != null:
		_job_row.visible = false
	if _status_bar != null:
		_status_bar.visible = !group
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


func _on_unit_health_changed(_current: float, maximum: int, unit: Unit) -> void:
	# Only the unit driving the portrait owns the big readout, but any unit's
	# tile has to stay honest. The rounded number comes off the unit rather
	# than out of the signal, so every readout rounds the one way.
	if unit == _unit && _health_label != null:
		_health_label.text = "%d / %d" % [unit.display_health(), maximum]
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


## The unit driving the panel, or null when nothing is selected. The first of
## the group when several are.
func shown_unit() -> Unit:
	return _unit


## Whether the card on screen would answer this key: the square it names holds
## an ability that can actually be pressed.
##
## Asked by the Research Center, which is open ON TOP of the card and sees the
## key first. It is the same question _unhandled_key_input asks itself, put
## where somebody else can ask it.
func claims_key(key: Key) -> bool:
	return _ability_for_key(key) != null


## Backs out of one thing.
##
## The armed ability first, then the submenu. Both can be true at once - a
## build order is aimed FROM the build submenu - and in that case the player
## means the order they are aiming, not the menu they opened to reach it. One
## press per thing being backed out of, which is also how Escape already
## behaves.
func _cancel_current() -> void:
	if _armed:
		if _command_controller != null:
			_command_controller.cancel()
		return
	pop_to_root()


## Puts Cancel on the card whenever there is something to back out of.
##
## Placed AFTER the card rather than as part of it, so it cannot be pushed out
## of its square by a busy submenu and its key never moves. Left off entirely
## when there is nothing to cancel, rather than shown greyed out - a card that
## always carries a dead button teaches a player to ignore that square.
func _place_cancel(placed: Array) -> void:
	if _cancel_ability == null:
		return
	if !_armed && !is_in_submenu():
		return

	var slot: int = _cancel_ability.card_slot()
	if slot < 0 || slot >= placed.size():
		slot = placed.size() - 1
	placed[slot] = _cancel_ability


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
	# An armed ability owns the next click, so everything else comes off the
	# card rather than offering buttons that would fight it. The grid keeps its
	# place, so the panel never changes shape mid-order. The card STACK is
	# untouched, which is what lets cancelling drop straight back to what was
	# showing.
	var placed: Array = [] if _armed else _place_card(_current_card())
	placed.resize(_slots.size())
	_place_cancel(placed)

	_slot_letters = _letters_for(placed)
	for index in range(_slots.size()):
		_slots[index].set_ability(placed[index] as UnitAbility, _unit,
			_slot_letters[index])

## One entry per square, null where the card leaves a gap.
##
## Three kinds of claim, settled in that order:
##   1. a square claimed AHEAD of the grid, by an ability that answers to a key
##      of its own and so has to be somewhere fixed - Sell. It wins
##   2. an ordinary square, which is the whole rest of the card
##   3. no square at all, which falls into the first gap left over
##
## The grid is walked in SQUARE ORDER rather than in card order, and that is
## what makes a push read properly: an ability that finds its square taken
## takes the next one along, and the ability that wanted THAT one slides along
## in turn. So a card with one square spent shifts by one from there and stops,
## rather than the displaced ability leaping over its neighbours to the first
## hole it can find. An ability keeps its own key throughout - see
## _letter_for, which reads the square an ability CLAIMED, not the one it
## ended up on.
##
## Two ORDINARY abilities colliding is still an authoring mistake and still
## says so: nothing took that square from either of them, they were both
## authored onto it.
func _place_card(card: Array) -> Array:
	var placed: Array = []
	placed.resize(_slots.size())

	var abilities: Array = _abilities_of(card)
	var floating: Array = []

	for ability: UnitAbility in abilities:
		if ability.claims_slot_first():
			_claim_square(placed, ability)

	for wanted: int in range(placed.size()):
		for ability: UnitAbility in abilities:
			if !ability.claims_slot_first() && ability.card_slot() == wanted:
				_claim_square(placed, ability)

	for ability: UnitAbility in abilities:
		var wanted: int = ability.card_slot()
		if !ability.claims_slot_first() && (wanted < 0 || wanted >= placed.size()):
			floating.append(ability)

	_fill_free_slots(placed, floating)
	return placed


## Everything on a card that is really an ability, so the passes below can walk
## the same list three times without checking for nulls each time.
func _abilities_of(card: Array) -> Array:
	var abilities: Array = []
	for entry in card:
		var ability: UnitAbility = entry as UnitAbility
		if ability != null:
			abilities.append(ability)
	return abilities


## Puts one ability on the square it asked for, or on the next free one along.
##
## Counting ON from the square it wanted rather than from the top of the card,
## and wrapping round the end, so an ability pushed out of the bottom row lands
## beside where it used to be instead of in the top left. A card with nowhere
## left to put it is reported: the ability is off the card, which is the one
## outcome a player would experience as a missing button.
func _claim_square(placed: Array, ability: UnitAbility) -> void:
	var count: int = placed.size()
	if count > 0:
		var wanted: int = clampi(ability.card_slot(), 0, count - 1)
		_report_double_claim(placed[wanted] as UnitAbility, ability, wanted)

		for step in range(count):
			var index: int = (wanted + step) % count
			if placed[index] == null:
				placed[index] = ability
				return

	Log.err("Card has no free square left for an ability", {
		"ability": ability.display_name,
		"slot": ability.card_slot(),
	})


## Giving way to a priority claim is the feature working, and silent. Two
## abilities that both asked for a square the ordinary way is somebody
## authoring the same number twice, and only that is worth a line in the log.
func _report_double_claim(sitting: UnitAbility, ability: UnitAbility, slot: int) -> void:
	if sitting == null || sitting.claims_slot_first() || ability.claims_slot_first():
		return
	Log.err("Two abilities on one card claim the same slot", {
		"slot": slot,
		"kept": sitting.display_name,
		"moved": ability.display_name,
	})


## Drops everything that named no square at all into the gaps left over, from
## the top of the card. An ability that named a taken one was moved already, by
## _push_to_free_slot, which starts from the square it wanted instead.
##
## Anything that still does not fit is reported rather than silently vanishing
## off the card.
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


## The Nth letter of the grid. Empty when no controls config is wired, which
## leaves the card usable by mouse and simply unbound.
func _grid_letter(index: int) -> String:
	var config: ControlsConfig = _controls_config
	if config == null:
		return ""
	return config.grid_letter(index)


## The key each square draws, in square order.
func _letters_for(placed: Array) -> PackedStringArray:
	var letters: PackedStringArray = PackedStringArray()
	letters.resize(placed.size())
	for index in range(placed.size()):
		letters[index] = _letter_for(placed[index] as UnitAbility, index)
	return letters


## The key ONE square draws, which is the ability's rather than the square's.
##
## An ability's key comes from the square it CLAIMED, and it keeps that key
## wherever it ends up sitting. So a command pushed one along by Sell answers
## to the same letter it always has, and every ability that was not pushed is
## left exactly where it was rather than being shuffled to make room. That is
## the whole trade: a card spends a SQUARE on a command with its own key, never
## a key.
##
## The two fallbacks are the square's own letter, for the same reason: an empty
## square and an ability that claimed no square at all have no letter of their
## own to carry, so they take the one they are standing on.
func _letter_for(ability: UnitAbility, square: int) -> String:
	if ability == null:
		return _grid_letter(square)

	var own: String = ability.custom_hotkey_label()
	if !own.is_empty():
		return own

	var claimed: int = ability.card_slot()
	if claimed < 0 || claimed >= _slots.size():
		return _grid_letter(square)
	return _grid_letter(claimed)

func _on_ability_activated(ability: UnitAbility) -> void:
	if ability == null:
		return

	# Card navigation, so it never reaches the command controller. Checked by
	# IDENTITY rather than by type, because the panel was handed this exact
	# resource and nothing else should be able to claim the behaviour.
	if ability == _cancel_ability:
		_cancel_current()
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

	var ability: UnitAbility = _ability_for_key(key.keycode)
	if ability == null:
		return

	_on_ability_activated(ability)
	if ability.repeat_on_hold:
		_begin_hold(ability, key.keycode)
	get_viewport().set_input_as_handled()


## The ability a key press lands on, or null for a key this card does not
## answer. An empty square, and a passive that cannot be pressed, both give
## null rather than swallowing the key.
func _ability_for_key(key: Key) -> UnitAbility:
	if !visible:
		return null

	# Answered off what the card is DRAWING rather than off the config, because
	# an ability carries its key to whatever square it ends up on - so the
	# square a press lands on is not the square its number names. Reading the
	# same array the slots were filled from is also what stops the two ever
	# disagreeing: a key that works is a key a player can see.
	if key == KEY_NONE:
		return null

	for index in range(mini(_slots.size(), _slot_letters.size())):
		var letter: String = _slot_letters[index]
		if letter.is_empty():
			continue
		if OS.find_keycode_from_string(letter.to_upper()) != key:
			continue

		# The square answers, whatever is on it. An empty one and a passive
		# both leave the key alone rather than letting it fall through to
		# another square that happens to draw the same letter.
		var ability: UnitAbility = _slots[index].ability
		if ability == null || ability.targeting == UnitAbility.Targeting.PASSIVE:
			return null
		return ability

	return null


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
	_refresh_damage_label()
	_refresh_attack_label()
	_refresh_resource_label()
	_refresh_bars()
	_refresh_job()

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
## Shows or hides the second-resource line for whatever is on the panel.
##
## Asked of the UNIT rather than of its stats, because what that resource IS is
## not always on the resource: one tower lowers its own mana ceiling as it
## fires (Building.set_max_mana) and one line's bar counts what its ability has
## banked instead of mana it never spends. A unit with no second resource at
## all hides the line entirely.
func _set_resource_text(unit: Unit) -> void:
	if _resource_label == null:
		return
	var resource: TowerResource = _unit_resource(unit)
	_resource_label.visible = resource != null
	if resource != null:
		_resource_label.text = resource.text()
		_resource_label.add_theme_color_override("font_color", resource.text_color)


## Keeps it up to date. Polled rather than driven by a signal for the same
## reason the armour line is: a second resource moves on the simulation tick,
## from a dozen different passives and from the server's own snapshot, and a
## signal per source would mean every new one having to remember to wire itself
## up.
func _refresh_resource_label() -> void:
	if _resource_label == null || !_resource_label.visible:
		return
	var resource: TowerResource = _unit_resource(_unit)
	if resource != null && _resource_label.text != resource.text():
		_resource_label.text = resource.text()


## The second resource of whatever is on the panel, or null when there is none
## to draw - which covers the builder, a Basic tower, an ordinary creep, and a
## selection of more than one unit, since a group has no single bar to read.
##
## Asked of the UNIT rather than of a Building: mana stopped being a tower-only
## thing when the creeps that run a trait on one arrived, and a cast to
## Building here would have quietly hidden every one of their bars.
func _unit_resource(unit: Unit) -> TowerResource:
	if unit == null || !is_instance_valid(unit) || !_group.is_empty():
		return null
	return unit.secondary_resource()


func _refresh_armor_label() -> void:
	if _armor_label == null || !_armor_label.visible:
		return
	_apply_armor_label()


## Writes the armour line and the note that hangs off it, from ONE reading of
## the unit - so the points, the type and the percentage can never be three
## answers taken a frame apart.
func _apply_armor_label() -> void:
	if _armor_label == null || _unit == null || !is_instance_valid(_unit):
		return
	var stats: UnitStats = _unit.stats
	if stats == null:
		return

	var points: int = _armor_points()
	var kind: UnitStats.ArmorType = _armor_type()
	var text: String = "Armor:   %s" % stats.armor_text(points, kind)
	if _armor_label.text != text:
		_armor_label.text = text

	# Godot only offers a tooltip while the text is non-empty, so this doubles
	# as the switch that turns the hover on for units that have armour at all.
	var note: String = _armor_note(points, kind)
	if _armor_label.tooltip_text != note:
		_armor_label.tooltip_text = note


## Armour POINTS the unit really has right now, and the TYPE it counts as.
##
## Both simply ASK THE UNIT now, on either machine. The branch that used to be
## here - authority reads the unit, a client adds the replicated records itself
## - moved into Creep.armor_value() and Building.armor_value(), because the
## panel was not the only reader that needed it: the range circle, the barrels
## and the damage line all ask the unit too, and every one of them would have
## wanted its own copy of the same three lines.
##
## What that also fixed is the note this used to carry, that armour GRANTED by
## an aura was on no wire at all and so read low on a client. It is on the wire
## now, as an ARMOR_LENT record like the one a Holy disc lends a tower.
func _armor_points() -> int:
	return _unit.armor_value()


func _armor_type() -> UnitStats.ArmorType:
	return _unit.armor_type_value()


## What hovering the armour line says: how much of a hit those points actually
## take off, which is the question the number itself does not answer.
##
## The curve has diminishing returns built in, so 5 armour is not five times
## what 1 armour is worth and no player could work the figure out from the
## number on the line. Negative armour reads as a MINUS reduction rather than
## as an increase, so the two halves are one scale running through zero.
func _armor_note(points: int, kind: UnitStats.ArmorType) -> String:
	if kind == UnitStats.ArmorType.INVULNERABLE:
		return "Takes no damage."

	var table: DamageTable = References.damage_table
	if table == null:
		return ""
	return "%s%% damage reduction" % StringUtil.trim_number(
		table.armor_reduction_percent(points), 1)


## The two bars under the portrait. Polled with the numbers they sit above and
## for the same reason: health and mana both move from a dozen places, and a
## signal per source would mean every new one having to remember this panel.
##
## The bar ignores the player's worldspace health bar setting on purpose. That
## setting is about clutter over the field; a panel is something the player
## opened by selecting a unit and is always answering a question they asked.
func _refresh_bars() -> void:
	if !visible || _unit == null || !is_instance_valid(_unit):
		return

	if _health_bar != null:
		_health_bar.set_ratio(_unit.current_health / float(_unit.max_health()))

	# One answer for the bar and the number under it. Asked every frame rather
	# than only when the selection changes, because a tower CAN gain or lose
	# its ceiling mid-match - see Building.set_max_mana - and a bar that
	# appeared without its number would be halfway right.
	var resource: TowerResource = _unit_resource(_unit)
	if _resource_label != null:
		_resource_label.visible = resource != null
	if _resource_bar == null:
		return
	_resource_bar.visible = resource != null
	if resource != null:
		_resource_bar.set_fill_color(resource.fill_color)
		_resource_bar.set_ratio(resource.ratio())


## Swaps the stat lines for the countdown row while the selected tower is busy,
## and swaps them back when it finishes or is called off.
##
## Polled rather than driven off sell_started and its siblings: the progress
## has to be re-read every frame anyway, so a signal would only tell this panel
## something the very next frame was going to tell it regardless.
func _refresh_job() -> void:
	var job: BuildingJob = _current_job()
	var busy: bool = job != null
	if busy != _busy:
		_busy = busy
		_apply_stat_lines()
	if _job_row != null:
		_job_row.visible = busy
	if !busy:
		return

	if _job_icon != null:
		_job_icon.texture = job.icon
	if _job_label != null:
		# Rounded UP, so a countdown never shows a 0 the player then waits on.
		var text: String = "%s (%ds)" % [job.label(), ceili(job.seconds_left)]
		if _job_label.text != text:
			_job_label.text = text
	if _job_bar != null:
		_job_bar.set_ratio(job.progress)


## What the panel's unit is busy with, or null. Never for a group: a countdown
## belongs to one tower, and the group card has no room to say whose.
func _current_job() -> BuildingJob:
	if !visible || !_group.is_empty():
		return null
	var tower: Building = _unit as Building
	if tower == null || !is_instance_valid(tower):
		return null
	return tower.current_job()


## Puts the three stat lines back under their own rules once _busy has changed.
## Damage and attack decide for themselves whether they apply at all - a creep
## has no attack line either way - so both go back through their own setters.
func _apply_stat_lines() -> void:
	if _unit == null || !is_instance_valid(_unit) || _unit.stats == null:
		return
	if !_group.is_empty():
		return

	_set_damage_text(_unit)
	_set_attack_text(_unit)
	if _armor_label != null:
		_armor_label.visible = !_busy
	if _status_bar != null:
		_status_bar.visible = !_busy

func _repeat_interval(config: ControlsConfig) -> float:
	var ramp: float = config.hold_repeat_ramp_seconds
	if ramp <= 0.0:
		return config.hold_repeat_min_interval

	var held: float = maxf(0.0, _held_elapsed - config.hold_repeat_delay)
	var progress: float = clampf(held / ramp, 0.0, 1.0)
	return lerpf(config.hold_repeat_start_interval, config.hold_repeat_min_interval, progress)
