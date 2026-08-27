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
## key until the square says Light - which is one habit rather than a menu to
## learn. The active choice is drawn in the square's own name, so it is visible
## without hovering.
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
## Invulnerable is left out because it would make a creep untouchable, and
## Unarmored is left out because it is the neutral row and altering something
## into it is never worth a press. What is left is the five real matchups.
const CHOICES: Array[UnitStats.ArmorType] = [
	UnitStats.ArmorType.LIGHT,
	UnitStats.ArmorType.MEDIUM,
	UnitStats.ArmorType.HEAVY,
	UnitStats.ArmorType.FORTIFIED,
	UnitStats.ArmorType.HERO,
]


## The armour type this tower is currently set to apply. Static so the passive
## that applies it does not have to find this resource on the card first.
static func chosen_type(tower: Building) -> UnitStats.ArmorType:
	if tower == null:
		return CHOICES[0]
	var index: int = int(tower.ability_state.get(CHOICE_KEY, 0))
	return CHOICES[posmod(index, CHOICES.size())] as UnitStats.ArmorType


func execute(unit: Unit, _target: AbilityTarget) -> void:
	var tower: Building = unit as Building
	if tower == null:
		return
	tower.ability_state[CHOICE_KEY] = int(tower.ability_state.get(CHOICE_KEY, 0)) + 1
	# The square draws the new choice in its own name, so the card has to be
	# rebuilt for the press to be visible at all.
	tower.abilities_changed.emit()


func can_execute(unit: Unit) -> bool:
	var tower: Building = unit as Building
	return tower != null && tower.can_attack()


## Named with the active choice in it, so the card shows what the tower will do
## without anything having to be hovered.
func tooltip_data(hotkey_label: String = "") -> AbilityTooltipData:
	var data: AbilityTooltipData = super(hotkey_label)
	data.description = ("%s\nPress to cycle through %s."
		% [description, _choice_list()])
	return data


func _choice_list() -> String:
	var names: PackedStringArray = PackedStringArray()
	for entry in CHOICES:
		names.append(_type_name(entry))
	return ", ".join(names)


static func _type_name(armor_type: UnitStats.ArmorType) -> String:
	return String(UnitStats.ArmorType.keys()[armor_type]).to_lower().capitalize()
