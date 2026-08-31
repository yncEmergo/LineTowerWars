class_name LightBurstPassive
extends TowerPassive

## Holy 1, the whole Divineshroom line: the dedicated anti-air path, which pays
## for hitting nothing on the ground with the deepest debuff in the game.
##
## unit_data.md 4.4: every hit slows and takes armour, and the armour it takes
## can push a creep BELOW ZERO, down to -3 - which is the only thing in the
## game that does, and is why a Divineshroom standing behind anything else
## makes everything else hit harder. The Ultimate adds healing for the towers
## around it, out of the damage it deals.
##
## Negative armour amplifies rather than reduces (game_rules.md), so -3 is
## worth about 17% more damage from everything on the field at once.

@export_group("Light Burst")
## Movement taken per hit, as a share.
@export var slow_per_hit: float = 0.0333
## The most this tower's chill may reach.
@export var slow_cap: float = 0.40
## How long it lasts.
@export var slow_seconds: float = 4.0
## The key the chill accumulates under.
@export var chill_source: String = "divineshroom"
## Armour eaten per hit, permanently.
@export var armor_per_hit: float = 0.12
## How far down it may go. -3 on every tier, and it is the one effect in the
## game that goes below zero at all.
@export var armor_floor: float = -3.0

@export_group("Divine Spores")
## Share of the damage dealt that is healed back into nearby towers, or 0 on
## the tiers that heal nothing.
@export var tower_heal_share: float = 0.0
## How far that healing reaches, in player cells.
@export var heal_cells: float = 2.34


func on_hit(tower: Building, target: Unit, dealt: int, _is_primary: bool) -> void:
	var status: StatusEffects = status_of(target)
	if status != null:
		status.chill(self, chill_source, slow_per_hit, slow_cap, slow_seconds)
		status.erode_armor(self, armor_per_hit, armor_floor)
	_heal_towers(tower, dealt)


## Heals the towers standing around this one, itself included: it is a friendly
## structure inside its own radius and the source excludes nothing.
##
## Walks the area's own children, which is where buildings live - creeps have a
## root of their own. See TargetFinder.
func _heal_towers(tower: Building, dealt: int) -> void:
	if tower_heal_share <= 0.0 || tower.area == null:
		return

	var amount: int = int(round(float(dealt) * tower_heal_share))
	if amount <= 0:
		return

	for child: Node in tower.area.get_children():
		var other: Building = child as Building
		if other == null || !other.is_alive():
			continue
		var offset: Vector3 = other.global_position - tower.global_position
		if Vector2(offset.x, offset.z).length() <= heal_cells:
			other.heal(amount)


func effect_text() -> String:
	var text: String = ("Each hit slows by %s%% up to %s%% and permanently"
		+ " takes %s armor, down to %s. Armor can be pushed below zero, which"
		+ " makes every later hit on that creep land harder.") % [
		StringUtil.trim_number(slow_per_hit * 100.0),
		StringUtil.trim_number(slow_cap * 100.0),
		StringUtil.trim_number(armor_per_hit),
		StringUtil.trim_number(armor_floor),
	]
	if tower_heal_share > 0.0:
		text += " Heals towers within %s cells for %s%% of the damage dealt." % [
			StringUtil.trim_number(heal_cells),
			StringUtil.trim_number(tower_heal_share * 100.0)]
	return text


## The healing radius, on the tier that heals. The tiers below reach nothing
## and answer 0 rather than drawing a circle that does nothing.
func display_radius(_unit: Unit) -> float:
	return heal_cells if tower_heal_share > 0.0 else 0.0
