class_name DiscUpgradeAbility
extends UpgradeTowerAbility

## The upgrade that morphs a technology disc into the next one up.
##
## An UpgradeTowerAbility in every structural way - it names the disc above it
## by its stats, it runs the same in-place countdown, it can never be refused
## for want of room - and it exists as a subclass for two rules the towers do
## not have.
##
## AN ELEMENT COUNT, NOT AN ID. A tower is gated on one technology and says so
## with `required_tech_id`. A disc is gated on HOW MANY of an element's three
## technologies its owner has bought: the first morph needs the Basic one, the
## Advanced disc needs at least two of the three, and the Ultimate needs all
## three (unit_data.md 5.1). There is no single id that means "two of three",
## so this asks the count instead. The base class's `required_tech_id` is left
## at 0 on every disc upgrade and the whole gate lives here.
##
## ONE ULTIMATE PER ELEMENT. A player may own only one Ultimate disc of each
## element (11.0a), which is the disc half of "you cannot fill the whole maze
## with the best thing". Counted over the owner's own area rather than stored
## on the player, because a stored tally has to be kept in step with every way
## a disc can arrive or leave - a morph up, a morph down, a sale - and getting
## one of those wrong leaves a player permanently unable to build something
## they do not own.
##
## Both checks are re-asked when the order arrives, exactly as gold is: a
## second Ultimate can be finished between the button lighting up and the click.

@export_group("Disc requirement")
## Which element's technologies this counts. Ignored when the count below is 0.
@export var required_element: TechDefinition.Element = TechDefinition.Element.ARCANE
## How many of that element's three technologies the owner must have bought:
## 1 for an element disc, 2 for an Advanced one, 3 for an Ultimate. 0 for an
## upgrade that needs none, which no disc upgrade currently is.
@export var required_element_techs: int = 0
## Whether the owner may only have ONE of what this morphs into, anywhere in
## their area. True on the ten Ultimate discs and nothing else.
@export var unique_per_player: bool = false


## Greyed out for everything an upgrade is normally greyed out for, plus the
## two rules above. The base class answers the busy test, the gold and its own
## `required_tech_id`, which discs leave at 0.
func can_execute(unit: Unit) -> bool:
	if !super(unit):
		return false
	return _owner_has_element(unit) && !_already_owns_one(unit)


## The gold and the technology are checked here again on arrival for the same
## reason Building.upgrade_to re-checks the gold: the card can light a button
## up a moment before the world stops allowing it.
func execute(unit: Unit, target: AbilityTarget) -> void:
	if unit == null:
		return
	if !_owner_has_element(unit) || _already_owns_one(unit):
		Log.warn("Disc upgrade refused, its requirement is no longer met", {
			"disc": unit.name, "ability": display_name,
		})
		return
	super(unit, target)


## Whether the ordering player has bought enough of this element.
##
## True when nothing is required, and true when there is no technology manager
## at all - a bare test scene has to stay usable, the same allowance
## TowerOrderAbility._owner_has_tech makes.
func _owner_has_element(unit: Unit) -> bool:
	if required_element_techs <= 0:
		return true
	var manager: TechManager = References.tech_manager
	if manager == null || unit == null:
		return true
	return manager.element_tech_count(unit.owner_player_id,
		required_element) >= required_element_techs


## Whether this player already has one of what this would build.
##
## Walks the owner's own area, which is where every disc they own stands. By
## unit_type_id rather than by element, so the rule is exactly "one of THIS
## disc" and an Ultimate Fire disc has nothing to say about an Ultimate Ice one.
func _already_owns_one(unit: Unit) -> bool:
	if !unique_per_player || tower_stats == null || unit == null:
		return false
	if unit.area == null || !is_instance_valid(unit.area):
		return false

	var wanted: int = tower_stats.unit_type_id
	for child: Node in unit.area.get_children():
		var disc: Disc = child as Disc
		if disc == null || disc == unit:
			continue
		# What a disc is BECOMING counts too, or two of them started in the
		# same second would both be allowed and both finish.
		if disc.stats != null && disc.stats.unit_type_id == wanted:
			return true
		var becoming: BuildingStats = disc.upgrade_target()
		if becoming != null && becoming.unit_type_id == wanted:
			return true
	return false


## What this morph is waiting on, as a line for its tooltip. Replaces the base
## class's single-technology line, which a disc never uses.
func _tech_requirement_text() -> String:
	if required_element_techs <= 0:
		return ""

	var element: String = TechDefinition.element_name_of(required_element)
	if required_element_techs >= 3:
		return "Requires all three %s technologies." % element
	if required_element_techs == 2:
		return "Requires at least two of the three %s technologies." % element
	return "Requires the basic %s technology." % element


## Adds the one-per-player rule to the card, where it is worth a line: a player
## looking at a greyed Ultimate needs to know it is greyed because they already
## have one rather than because they cannot pay.
func tooltip_data(hotkey_label: String = "",
		unit: Unit = null) -> AbilityTooltipData:
	var data: AbilityTooltipData = super(hotkey_label, unit)
	if unique_per_player:
		data.add_special("Limit", "You may own only one of these at a time.")
	return data
