class_name AttackHit
extends RefCounted

## One attack in flight, from the moment the tower fires until it lands.
##
## Carries copies of everything the hit needs rather than a handle on the tower
## that fired it. A projectile can be halfway to its target when its tower is
## sold, and that shot still has to land: holding the tower would either crash
## or quietly swallow the damage.
##
## The one exception is `source`, which IS the tower and is allowed to be gone
## by the time this lands - every use of it is guarded, because an elemental
## tower's passive has to be able to bank what its own shot just did. A hit
## whose tower has been sold still lands and still splashes; what it no longer
## does is feed anything back.
##
## Created fresh per attack, so unlike the resources it copies from, this one is
## allowed to hold state.

## Rolled once when the tower fires, so every creep caught by the same shot
## takes the same roll rather than each rolling its own.
##
## What actually lands can be MORE than this: a passive's bonus is worked out
## against the creep being struck and so cannot be known until the shot
## arrives. See resolve().
var damage: int = 0
var damage_type: DamageTable.DamageType = DamageTable.DamageType.NORMAL
## Whether this counts as area damage, which some creeps resist. Copied off the
## attack when it fires rather than asked of it later, for the same reason the
## damage roll is: the tower may be gone by the time the shot lands.
var is_aoe: bool = false
## Applied in order once the hit lands. Shared resources, never modified.
var effects: Array[AttackEffect] = []
## Area the attack happened in, which is what splash and chain search.
var area: PlayerArea
## Who fired. Not used for damage, since a tower shoots every creep in its own
## area whoever sent it, but kill credit and future effects want it.
var attacker_player_id: int = 1
## Where the attacker STOOD when it fired, on the ground.
##
## Copied rather than reached for, like everything else here: the tower can be
## sold while the shot is still in the air. Two things need it - an effect that
## radiates from the tower instead of from the impact (SelfSplashEffect), and an
## impact visual that has to know which way the hit came from.
var attacker_position: Vector3 = Vector3.ZERO
## The tower that fired, or null. May have been sold mid flight, so every read
## of it goes through _live_source().
var source: Building = null
## The source tower's passives, copied so they survive it being sold. They are
## shared resources and hold no state, so copying them costs a reference each.
var passives: Array[TowerPassive] = []
## Whether this is the creep the tower actually aimed at, as opposed to one
## picked up alongside it by a multishot. Splash is not covered by this: a
## splash never runs a passive's on_hit at all - see splash_onto().
var is_primary: bool = true


## Lands the hit: the target takes the damage its passives worked out, then
## every effect gets its turn at the impact point.
##
## target may be null when the creep died mid flight. The effects still run,
## because a cannon orb that arrives a moment late should still splash the
## crowd standing where its target was.
##
## The order is a rule. The passives' bonus is folded in FIRST, so a splash
## measured off `damage` covers the ground with what the shot really did rather
## than with what it was worth before its tower's ability spoke. The passives'
## on_hit runs LAST, after the creep has taken the damage, because nearly every
## one of them is stated in unit_data.md as a share "of the damage dealt".
func resolve(target: Unit, impact_point: Vector3) -> void:
	var landed: bool = target != null && is_instance_valid(target) && target.is_alive()
	if landed:
		damage = _with_bonus(target)
		_apply_type_override(target)
		_strike(target)

	for effect: AttackEffect in effects:
		if effect != null:
			effect.apply(self, target, impact_point)


## The roll plus whatever the tower's passives add for this particular creep.
## Never below 1: an attack that lands at all does something.
func _with_bonus(target: Unit) -> int:
	var tower: Building = _live_source()
	if tower == null:
		return damage

	var total: int = damage
	for passive in passives:
		total += passive.bonus_damage(tower, target, damage)
	return maxi(1, total)


## Lets a passive deal this one attack as a different damage type. Only the
## first answer is taken - two passives fighting over one attack's type is an
## authoring mistake, not something to resolve at runtime.
func _apply_type_override(target: Unit) -> void:
	var tower: Building = _live_source()
	if tower == null:
		return
	for passive in passives:
		var wanted: int = passive.damage_type_for(tower, target)
		if wanted >= 0:
			damage_type = wanted as DamageTable.DamageType
			return


## Deals the damage and tells the tower's passives what it cost, so the ones
## stated as a share "of the damage dealt" have a real number to work from.
##
## The cost is asked for BEFORE the hit lands rather than measured from the
## health that changed, because a creep on its last point still took the whole
## hit as far as every ability that reads it is concerned - and measuring it
## the other way would make a poison stack shrink against a dying creep.
func _strike(target: Unit) -> void:
	var dealt: int = target.resolve_damage(damage, damage_type, is_aoe)
	target.take_damage(damage, damage_type, is_aoe)

	var tower: Building = _live_source()
	if tower == null:
		return
	for passive in passives:
		passive.on_hit(tower, target, dealt, is_primary)
	if !target.is_alive():
		for passive in passives:
			passive.on_kill(tower, target)


## Damage from one of this attack's EFFECTS rather than from the attack itself,
## and the kill credit that comes with it. Every splash goes through here.
##
## The two halves of a hit are deliberately split. A passive's on_hit is stated
## per creep the tower STRUCK - a poison stack, a share of armour eaten - and
## running it over a splash would hand a whole crowd what was meant for one
## creep, which is why a splash has never run one. A KILL is the other way
## round: unit_data.md says "per creep killed" and means whoever finished it,
## and a splash tower that finished a creep with its splash finished it. An
## Alchemist that only counted what its own shell landed on would grow at a
## fraction of the rate the source describes, because splash is how it kills.
##
## Already-dead creeps are skipped rather than damaged, so an effect walking a
## list cannot pay a tower twice for the same body.
func splash_onto(creep: Creep, amount: int, damage_type: DamageTable.DamageType,
		is_area: bool = true) -> void:
	if creep == null || !is_instance_valid(creep) || !creep.is_alive():
		return

	creep.take_damage(amount, damage_type, is_area)
	if creep.is_alive():
		return

	var tower: Building = _live_source()
	if tower == null:
		return
	for passive in passives:
		passive.on_kill(tower, creep)


## The tower that fired, or null if it has been sold, destroyed or upgraded
## since. Every use of `source` goes through here.
func _live_source() -> Building:
	if source == null || !is_instance_valid(source):
		return null
	return source
