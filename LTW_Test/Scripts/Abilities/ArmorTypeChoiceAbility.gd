class_name ArmorTypeChoiceAbility
extends UnitAbility

## The Ultimate Alchemist's one button: which armour type its attacks alter a
## creep INTO.
##
## unit_data.md 4.8: the Ultimate Alchemist changes the armour type of what it
## hits for a few seconds, and "the armour type to apply is chosen manually on
## the command card and the active choice is displayed there". This is that
## card entry. What it does with the choice is DevourEssencePassive's.
##
## A CYCLE rather than a submenu of six buttons. The choice is one of a short
## list, the card is already crowded, and a player who wants Light presses the
## key until the tooltip says Light - which is one habit rather than a menu to
## learn. The active choice is written in the tooltip's own title, in brackets
## after the name, so the answer to "what is this tower set to" is one hover
## rather than a guess.
##
## The choice is per TOWER and lives on the tower, not here: this resource is
## every Ultimate Alchemist on the field at once, and two of them set to
## different types is exactly what a player would expect.
##
## It is NOT local-only. Which armour type a tower applies changes what the
## damage matrix does, so the server owns it and the press travels down the
## ordinary command road like every other order.

## Key the tower keeps its choice under.
const CHOICE_KEY: String = "alchemist_armor_type"

## The types that may be chosen, in the order the button cycles them.
##
## Unarmored is FIRST, and so is what a freshly built tower alters creeps into
## until somebody presses the key. It is the neutral row rather than a nothing:
## turning a Fortified creep unarmored is a real answer, and starting on a type
## that is never a trap is what makes the default safe to leave alone.
##
## Invulnerable is the one type left out, and it is left out for good: altering
## a creep into it would make the creep untouchable by the whole lane for the
## length of the debuff, which is the opposite of what the ability is for.
const CHOICES: Array[UnitStats.ArmorType] = [
	UnitStats.ArmorType.UNARMORED,
	UnitStats.ArmorType.LIGHT,
	UnitStats.ArmorType.MEDIUM,
	UnitStats.ArmorType.HEAVY,
	UnitStats.ArmorType.FORTIFIED,
	UnitStats.ArmorType.HERO,
]


## The armour type this tower is currently set to apply. Static so the passive
## that applies it does not have to find this resource on the card first.
##
## Asked of the TOWER rather than of its ability_state, because a client has no
## ability_state to read - the press is the server's to run - and would sit
## drawing the default while the server applied something else. The tower knows
## which of the two answers is its own; see Building.ability_choice.
static func chosen_type(tower: Building) -> UnitStats.ArmorType:
	if tower == null:
		return CHOICES[0]
	return CHOICES[posmod(tower.ability_choice(), CHOICES.size())] as UnitStats.ArmorType


## What that type is called, e.g. "Fortified". Static and public because the
## tooltip is not the only thing that ever has to name it.
static func type_name(armor_type: UnitStats.ArmorType) -> String:
	return String(UnitStats.ArmorType.keys()[armor_type]).to_lower().capitalize()


func execute(unit: Unit, _target: AbilityTarget) -> void:
	var tower: Building = unit as Building
	if tower == null:
		return
	tower.ability_state[CHOICE_KEY] = int(tower.ability_state.get(CHOICE_KEY, 0)) + 1
	# The square is rebuilt so its tooltip is, since the tooltip is where the
	# new choice is written and a stale one would be worse than none.
	tower.abilities_changed.emit()


func can_execute(unit: Unit) -> bool:
	var tower: Building = unit as Building
	return tower != null && tower.can_attack()


## Where this tower's choice really lives. Read on the AUTHORITY only, which is
## what Building.ability_choice() guarantees before it asks.
func choice_index(unit: Unit) -> int:
	var tower: Building = unit as Building
	if tower == null:
		return -1
	return int(tower.ability_state.get(CHOICE_KEY, 0))


## Named with the ACTIVE CHOICE after it, so a hover answers what this tower
## will do rather than only what the button is for. The tower comes in because
## the choice is per tower and this resource is shared; with nobody behind it
## the answer is the default, which is what a fresh tower is set to anyway.
func tooltip_data(hotkey_label: String = "",
		unit: Unit = null) -> AbilityTooltipData:
	var data: AbilityTooltipData = super(hotkey_label, unit)
	data.title = "%s  (%s)" % [
		display_name, type_name(chosen_type(unit as Building))
	]
	data.description = ("%s\nPress to cycle through %s."
		% [description, _choice_list()])
	return data


func _choice_list() -> String:
	var names: PackedStringArray = PackedStringArray()
	for entry in CHOICES:
		names.append(type_name(entry))
	return ", ".join(names)
