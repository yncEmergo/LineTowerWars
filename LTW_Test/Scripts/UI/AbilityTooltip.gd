class_name AbilityTooltip
extends PanelContainer

## Hover tooltip for one command slot.
##
## Laid out like the WC3 original, top to bottom: name and hotkey, the price
## row, then the income a use grants, then the stats of whatever it produces,
## and last the passives that unit brings. Every block hides itself when the
## ability left it empty, so Move shows two lines and a creep send shows the
## full card without either needing a scene of its own.
##
## Built fresh per hover by CommandSlot._make_custom_tooltip, filled from the
## AbilityTooltipData the ability hands over, then thrown away.
##
## The blocks are RichTextLabels rather than one label per value, because a
## stat line is two colours and the number of lines changes per ability. Only
## the placeholder colours live here, every value comes off the data.

const TITLE_COLOR: Color = Color(1.0, 0.85, 0.35)
const HOTKEY_COLOR: Color = Color(0.85, 0.87, 0.92)
## Used for the "Health:" half of a stat line and for "Income:".
const LABEL_COLOR: Color = Color(1.0, 0.85, 0.35)
const VALUE_COLOR: Color = Color(0.92, 0.93, 0.96)
## Passives read green, the way WC3 marks an ability rather than a number.
const SPECIAL_COLOR: Color = Color(0.44, 0.89, 0.46)

## Gap between the entries of the price row, as spaces. Wide enough to read as
## two separate readouts once they are icons rather than words.
const PRICE_SEPARATOR: String = "    "

@export_group("References")
@export var _title_label: RichTextLabel
## Price row: the gold one use costs and the population one creep takes.
@export var _price_label: RichTextLabel
@export var _separator: Control
@export var _income_label: RichTextLabel
## Stats sit in two columns rather than one list, so four of them cost two
## lines instead of four.
@export var _stats_row: Control
@export var _stats_left: RichTextLabel
@export var _stats_right: RichTextLabel
@export var _specials_label: RichTextLabel
@export var _description_label: RichTextLabel


## Godot wraps a custom tooltip in a PopupPanel that paints its own background,
## which showed as a dark frame spilling past this panel's border in game. The
## editor never shows it, because nothing wraps the scene there. Blanking the
## wrapper's style leaves only the background this panel draws itself.
func _ready() -> void:
	var wrapper: PopupPanel = get_parent() as PopupPanel
	if wrapper == null:
		return
	wrapper.add_theme_stylebox_override("panel", StyleBoxEmpty.new())


## Fills every block and hides the ones this ability had nothing for.
func show_data(data: AbilityTooltipData) -> void:
	if data == null:
		Log.err("AbilityTooltip was given no data to show")
		return

	_fill_title(data)
	_fill_price(data)
	_fill_income(data)
	_fill_stats(data)
	_fill_specials(data)
	_fill_description(data)


func _fill_description(data: AbilityTooltipData) -> void:
	if data.description.is_empty():
		_fill(_description_label, "")
		return
	_fill(_description_label, _colored(data.description, VALUE_COLOR))


func _fill_title(data: AbilityTooltipData) -> void:
	var line: String = _colored(data.title, TITLE_COLOR)
	if !data.hotkey.is_empty():
		line += " " + _colored("(%s)" % data.hotkey, HOTKEY_COLOR)
	_fill(_title_label, line)


## Cost of one use first, then what one creep of it takes up, per game_rules.md
## on sending. The rule above hides the row entirely for a free ability, which
## is also what drops the divider under it.
func _fill_price(data: AbilityTooltipData) -> void:
	var parts: PackedStringArray = PackedStringArray()
	if data.gold_cost >= 0:
		parts.append(_stat_line("Cost", str(data.gold_cost)))
	if data.population >= 0:
		parts.append(_stat_line("Population", str(data.population)))

	var line: String = PRICE_SEPARATOR.join(parts)
	_fill(_price_label, line)
	if _separator != null:
		_separator.visible = !line.is_empty()


func _fill_income(data: AbilityTooltipData) -> void:
	if data.income_gain < 0:
		_fill(_income_label, "")
		return
	_fill(_income_label, _stat_line("Income", "+%d" % data.income_gain))


## Entries fill left, right, left, right, so the four creep stats read across
## as health next to armour and speed next to bounty, rather than down a list.
func _fill_stats(data: AbilityTooltipData) -> void:
	var left: PackedStringArray = PackedStringArray()
	var right: PackedStringArray = PackedStringArray()

	for index in range(data.stats.size()):
		var entry: PackedStringArray = data.stats[index]
		var line: String = _stat_line(entry[0], entry[1])
		if index % 2 == 0:
			left.append(line)
		else:
			right.append(line)

	_fill(_stats_left, "\n".join(left))
	_fill(_stats_right, "\n".join(right))
	if _stats_row != null:
		_stats_row.visible = !left.is_empty()


func _fill_specials(data: AbilityTooltipData) -> void:
	var blocks: PackedStringArray = PackedStringArray()
	for entry in data.specials:
		var block: String = _colored(entry[0], SPECIAL_COLOR)
		if !entry[1].is_empty():
			block += "\n" + _colored(entry[1], VALUE_COLOR)
		blocks.append(block)
	_fill(_specials_label, "\n\n".join(blocks))


## An empty block is hidden rather than left blank, so the tooltip closes up
## around what the ability actually had to say instead of growing gaps.
func _fill(label: RichTextLabel, text: String) -> void:
	if label == null:
		Log.err("AbilityTooltip is missing one of its labels")
		return
	label.visible = !text.is_empty()
	label.text = text


func _stat_line(label: String, value: String) -> String:
	return "%s %s" % [_colored("%s:" % label, LABEL_COLOR), _colored(value, VALUE_COLOR)]


func _colored(text: String, color: Color) -> String:
	return "[color=#%s]%s[/color]" % [color.to_html(false), text]
