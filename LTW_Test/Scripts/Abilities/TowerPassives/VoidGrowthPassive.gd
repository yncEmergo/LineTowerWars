class_name VoidGrowthPassive
extends TowerPassive

## Void base towers: the element that SPREADS. A Voidling that has been
## shooting long enough turns one of its neighbours into another Voidling, free.
##
## unit_data.md 4.9: at full mana it transforms a nearby cheap Basic tower into
## a copy of itself, once and once only. The Voidalisk does the same to a
## Voidling, so a lane seeded with one Void tower and left alone grows into a
## row of them - which is the whole identity of the element and the reason it
## is worth its low damage.
##
## The transformation is a free INSTANT swap rather than an upgrade: no gold
## changes hands, no countdown runs, and the target tower is not the one paying
## for it. Building.upgrade_to would charge the owner and start a timer, so
## this uses the same replacement path the far end of an upgrade uses instead.

## Key the once-only flag is kept under.
const SPENT_KEY: String = "void_growth_spent"

@export_group("Void Growth")
## Mana regenerated per second.
@export var regen_per_second: float = 1.0
## Mana gained per attack, on top of the regeneration.
@export var mana_per_attack: float = 1.0
## How far it reaches for something to convert, in player cells.
@export var reach_cells: float = 3.12
## What it turns into. The tower this passive sits on, in practice, which is
## why it is authored rather than derived - a Voidalisk converts a Voidling
## into a Voidalisk, not into whatever the Voidling would have upgraded to.
@export var becomes: BuildingStats
## Which towers may be converted, cheapest first. A Voidling takes the three
## 10g towers; a Voidalisk takes a Voidling.
@export var converts: Array[BuildingStats] = []


func mana_per_second(_tower: Building) -> float:
	return regen_per_second


func on_attack(tower: Building, _target: Unit) -> void:
	tower.gain_mana(mana_per_attack)


func on_tick(tower: Building, _delta: float) -> void:
	if bool(tower.ability_state.get(SPENT_KEY, false)) || !tower.has_full_mana():
		return
	if becomes == null || tower.area == null || !MatchSession.is_authority():
		return

	var victim: Building = _nearest_convertible(tower)
	if victim == null:
		return

	tower.ability_state[SPENT_KEY] = true
	tower.drain_mana()
	victim.transform_into(becomes)
	Log.info("Void growth", {"tower": tower.name, "converted": victim.name})


## The nearest tower in range whose type is one this may take. Walks the area's
## own children, which is where buildings live.
func _nearest_convertible(tower: Building) -> Building:
	var best: Building = null
	var best_distance: float = reach_cells

	for child: Node in tower.area.get_children():
		var other: Building = child as Building
		if other == null || other == tower || !_may_convert(other):
			continue
		var offset: Vector3 = other.global_position - tower.global_position
		var distance: float = Vector2(offset.x, offset.z).length()
		if distance <= best_distance:
			best = other
			best_distance = distance
	return best


## A tower may be taken when it is one of the authored types, it belongs to the
## same player, and it is standing rather than busy being something else.
func _may_convert(other: Building) -> bool:
	if other.is_under_construction() || other.is_selling() || other.is_upgrading():
		return false
	var stats: BuildingStats = other.stats as BuildingStats
	return stats != null && (stats in converts)


func effect_text() -> String:
	var name_text: String = "another Void tower" if becomes == null else becomes.display_name
	return ("Regenerates %s mana per second and gains %s per attack. At full"
		+ " mana it transforms one nearby tower within %s cells into a %s, for"
		+ " free. Happens once.") % [
		StringUtil.trim_number(regen_per_second),
		StringUtil.trim_number(mana_per_attack),
		StringUtil.trim_number(reach_cells),
		name_text,
	]
