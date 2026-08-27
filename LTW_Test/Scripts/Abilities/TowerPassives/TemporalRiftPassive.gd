class_name TemporalRiftPassive
extends TowerPassive

## Void 1, the whole Harbinger line: the tower that takes a creep's PROGRESS
## rather than its health.
##
## unit_data.md 4.9: at full mana it marks a random creep in range; a few
## seconds later that creep is dragged back to where it was standing when it
## was marked, and takes a share of its maximum health as Spell Damage. Half
## the mana comes back if it dies while waiting.
##
## Being sent backwards is what makes it worth its price. Against a Tier 4
## creep with an enormous health pool the damage barely registers, and having
## to walk a third of the maze again is worth several towers' output.
##
## The Ultimate also converts the Greater Harbingers standing near it into more
## Ultimates on a slow clock, which is the same "Void spreads" idea as the base
## towers - just with the most expensive tower in the element.

const MARK_KEY: String = "rift_target"
const DELAY_KEY: String = "rift_delay"
const CONVERT_KEY: String = "rift_convert"

@export_group("Temporal Rift")
## Mana regenerated per second.
@export var regen_per_second: float = 10.0
## How far it reaches to mark a creep, in player cells.
@export var radius_cells: float = 2.34
## Seconds between marking a creep and dragging it back.
@export var delay_seconds: float = 3.0
## Share of the creep's MAXIMUM health dealt as Spell Damage.
@export var health_share: float = 0.02
## Flat Spell Damage on top of that.
@export var flat_damage: int = 300
## Seconds before the same creep may be marked again.
@export var creep_cooldown: float = 9.0
## Share of the mana handed back when the creep dies during the delay.
@export var refund_share: float = 0.5

@export_group("Whispers of the Void")
## Movement taken when it lands, ignoring every slow resistance, or 0 on the
## tiers that only damage.
@export var slow_amount: float = 0.0
## Seconds between one nearby Greater Harbinger being converted and the next,
## or 0 on the tiers that convert nothing.
@export var convert_seconds: float = 0.0
## What a converted tower becomes, and what may be converted.
@export var becomes: BuildingStats
@export var converts: Array[BuildingStats] = []
## How far that reaches, in player cells.
@export var convert_cells: float = 3.9


func mana_per_second(_tower: Building) -> float:
	return regen_per_second


func on_tick(tower: Building, delta: float) -> void:
	_advance_rift(tower, delta)
	_advance_conversion(tower, delta)


## The rift, in two halves: marking a creep when the mana is full, and
## collecting on it when the delay runs out.
##
## The mark is remembered by UNIT ID and the position is remembered separately,
## so a creep that dies mid-delay simply fails to resolve and nothing here
## keeps a freed node alive.
func _advance_rift(tower: Building, delta: float) -> void:
	if !tower.ability_state.has(MARK_KEY):
		_try_mark(tower)
		return

	var left: float = float(tower.ability_state.get(DELAY_KEY, 0.0)) - delta
	tower.ability_state[DELAY_KEY] = left
	if left > 0.0:
		return

	var session: MatchSession = References.match_session
	var id: int = int(tower.ability_state[MARK_KEY])
	tower.ability_state.erase(MARK_KEY)

	var creep: Creep = null if session == null else session.unit_for(id) as Creep
	if creep == null || !is_instance_valid(creep) || !creep.is_alive():
		# It died while waiting, so half the mana comes back.
		tower.gain_mana(float(tower.max_mana) * refund_share)
		return
	_collect(creep)


func _try_mark(tower: Building) -> void:
	if !tower.has_full_mana() || tower.area == null || tower.stats == null:
		return

	var creep: Creep = HitPattern.random_in_radius(
		tower.area, tower.global_position, radius_cells, tower.stats.attack)
	if creep == null || creep.status().is_immune(resource_path):
		return

	creep.status().set_immune(resource_path, creep_cooldown)
	tower.drain_mana()
	tower.ability_state[MARK_KEY] = creep.unit_id
	tower.ability_state[DELAY_KEY] = delay_seconds


## Drags the creep back and hurts it.
##
## Being "returned to its previous location" is Creep.set_back_along_path,
## which walks the trail the creep has already covered and drops it on the most
## recent point still clear. That is a better answer than remembering one
## position: the maze may have been built into meanwhile, and a creep put back
## inside a tower would be stuck there.
func _collect(creep: Creep) -> void:
	creep.set_back_along_path()

	var damage: int = flat_damage + int(round(float(creep.max_health()) * health_share))
	creep.take_damage(damage, DamageTable.DamageType.SPELL)
	if slow_amount > 0.0 && creep.is_alive():
		creep.status().slow(resource_path, slow_amount, StatusEffects.DEFAULT_SLOW_SECONDS)


## The Ultimate's own half: one nearby Greater Harbinger becomes an Ultimate
## every so often, free. Nothing happens on the tiers that author no clock.
func _advance_conversion(tower: Building, delta: float) -> void:
	if convert_seconds <= 0.0 || becomes == null || tower.area == null:
		return

	var left: float = float(tower.ability_state.get(CONVERT_KEY, convert_seconds)) - delta
	if left > 0.0:
		tower.ability_state[CONVERT_KEY] = left
		return
	tower.ability_state[CONVERT_KEY] = convert_seconds

	for child: Node in tower.area.get_children():
		var other: Building = child as Building
		if other == null || other == tower || !((other.stats as BuildingStats) in converts):
			continue
		var offset: Vector3 = other.global_position - tower.global_position
		if Vector2(offset.x, offset.z).length() <= convert_cells:
			other.transform_into(becomes)
			return


func effect_text() -> String:
	var text: String = ("Regenerates %s mana per second. At full mana it marks"
		+ " a random creep within %s cells; %ss later that creep is returned to"
		+ " where it came from and takes %s%% of its maximum health plus %s as"
		+ " Spell Damage. Once every %ss per creep, and %d%% of the mana is"
		+ " refunded if it dies waiting.") % [
		StringUtil.trim_number(regen_per_second),
		StringUtil.trim_number(radius_cells),
		StringUtil.trim_number(delay_seconds),
		StringUtil.trim_number(health_share * 100.0),
		StringUtil.compact_number(flat_damage),
		StringUtil.trim_number(creep_cooldown),
		int(round(refund_share * 100.0)),
	]
	if slow_amount > 0.0:
		text += " It is also slowed by %s%%, ignoring all slow resistance." \
			% StringUtil.trim_number(slow_amount * 100.0)
	if convert_seconds > 0.0:
		text += " Every %ss a nearby Greater Harbinger becomes an Ultimate." \
			% StringUtil.trim_number(convert_seconds)
	return text
