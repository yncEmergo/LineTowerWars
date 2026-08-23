class_name AttackStats
extends Resource

## Everything one attack is, assigned to the unit that owns it through
## UnitStats.attack. A unit with none simply cannot attack.
##
## The numbers live here rather than on the unit so a unit that ever gains a
## second attack does not have to grow a second set of damage fields, and so
## the whole attack can be swapped as one piece.
##
## Two things are kept deliberately apart:
##   - delivery is how the hit reaches the target. Exactly one, and the choice
##     of subclass is what answers "is it a projectile", so no flag has to.
##   - effects are what happens once it lands. Any number of them, because a
##     tower that splashes and slows is two entries rather than a new class.
## Flags for both would be a combination of booleans nobody can read.

## How a tower picks which creep to shoot.
enum TargetPriority {
	## Furthest along its route, the classic tower defence choice.
	FIRST,
	## Nearest to the tower.
	CLOSEST,
	## Most current health.
	STRONGEST,
	## Least current health.
	WEAKEST,
}

## Bits of target_types. A tower that hits neither can never fire.
const TARGET_GROUND: int = 1
const TARGET_AIR: int = 2

@export_group("Damage")
## Rolled fresh for every attack, so a tower's output varies the way it does in
## the original.
@export var damage_min: int = 1
@export var damage_max: int = 1
## Looked up against the target's armour type, see Config/DamageTable.gd.
@export var damage_type: DamageTable.DamageType = DamageTable.DamageType.NORMAL
## Whether this attack counts as AREA damage, which some creeps resist.
##
## A plain flag rather than a resource, because it is not a choice between
## behaviours - it is a label on the damage this attack deals, and the thing
## that reads it is the defender. True for a cannon or a stomper, whose whole
## point is covering ground, and it covers the primary hit as well as the
## splash around it.
##
## Multishot is deliberately NOT area damage: it picks several single targets
## rather than covering ground. Any SplashEffect always counts as area damage
## whatever this says, since that is what a splash is. See game_rules.md.
@export var is_aoe_damage: bool = false

@export_group("Timing")
## Attacks per second, so a bigger number is faster. Shown as APS in the UI.
@export var attacks_per_second: float = 1.0

@export_group("Targeting")
## Measured in player cells from the tower's centre to the creep's, which is
## the same as world units because cell_size is 1.0.
@export var attack_range: float = 4.0
@export_flags("Ground", "Air") var target_types: int = TARGET_GROUND | TARGET_AIR
@export var target_priority: TargetPriority = TargetPriority.FIRST
## Further creeps struck alongside the primary target, so 2 means 3 creeps in
## total. 0 is an ordinary single target attack.
## NOT BUILT: nothing reads this yet, see game_rules.md.
@export var multishot_targets: int = 0

@export_group("Delivery")
## How the hit travels. Instant lands at once, a projectile flies there first.
@export var delivery: AttackDelivery
## What happens where it lands, applied in order. Empty is a plain single
## target hit.
@export var effects: Array[AttackEffect] = []


## Seconds between attacks. An attack speed of zero or less would divide by
## zero, so it is read as "never attacks" instead.
func cooldown_seconds() -> float:
	if attacks_per_second <= 0.0:
		return INF
	return 1.0 / attacks_per_second


## One attack's damage before the armour matrix touches it.
##
## The generator comes in rather than being reached for, so the roll is part of
## the match's one shared random stream and every machine gets the same number
## for the same shot. See MatchSession.match_rng().
func roll_damage(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(mini(damage_min, damage_max), maxi(damage_min, damage_max))


func can_hit_ground() -> bool:
	return (target_types & TARGET_GROUND) != 0


func can_hit_air() -> bool:
	return (target_types & TARGET_AIR) != 0


## Damage range as shown in the UI panel, e.g. "12 - 15".
func damage_text() -> String:
	return "%d - %d" % [damage_min, damage_max]


## Damage type as shown in the UI panel, e.g. "Piercing".
func damage_type_text() -> String:
	return DamageTable.damage_type_text(damage_type)


## Attack speed as shown in the UI panel, e.g. "0.75 APS". Named APS rather
## than spelled out, because that is what the player reads it as.
func attack_speed_text() -> String:
	return "%s APS" % StringUtil.trim_number(attacks_per_second)


## Range as shown in the UI panel, in player cells.
func range_text() -> String:
	return StringUtil.trim_number(attack_range)


## Reports every scene path this attack reaches that does not resolve. Called
## at boot by the stats resource that owns the attack.
func validate(owner_name: String) -> bool:
	var complete: bool = true

	if delivery != null && !delivery.validate(owner_name):
		complete = false

	for effect: AttackEffect in effects:
		if effect != null && !effect.validate(owner_name):
			complete = false

	return complete
