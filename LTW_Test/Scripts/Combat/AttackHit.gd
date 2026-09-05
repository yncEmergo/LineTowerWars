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
## WHOEVER fired, tower or creep, on the same terms and with the same warning:
## it may be gone by the time this lands, so every read is guarded.
##
## `source` above is this narrowed to a Building, and stays separate because
## nearly everything that reads it wants a tower and would otherwise cast on
## every line. What this one is for is the traffic going the OTHER way: a
## static tower returns a multiple of the damage back at the creep that hit it,
## and there is no other way to know which creep that was. See TowerBuffs.
var attacker: Unit = null
## How far the attack that fired this shot reaches, in cells.
##
## Carried on the hit rather than looked up from the source, because one creep
## in the roster dodges by REACH - Quickness only works against towers shooting
## from 900 away or more - and a splash or a rocket has no tower to ask. Zero
## for anything that was not fired by an attack, which dodges nothing.
var attack_range: float = 0.0
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
	if _dodged(target):
		return

	var dealt: int = target.resolve_damage(damage, damage_type, is_aoe)
	target.take_damage(damage, damage_type, is_aoe)
	_return_fire(target, dealt)

	var tower: Building = _live_source()
	if tower == null:
		return
	# BEFORE on_hit, which is the contract on the two hooks: a passive that
	# reads its own debuff back - Frostbitten asks how deep the chill now is -
	# has to be looking at this hit's contribution rather than the last one's.
	debuff(target)
	for passive in passives:
		passive.on_hit(tower, target, dealt, is_primary)
	var boons: TowerBuffs = tower.buffs_or_null()
	if boons != null:
		boons.on_tower_hit(tower, target, damage_type, dealt)
	if !target.is_alive():
		for passive in passives:
			passive.on_kill(tower, target)


## What a STATIC tower does back to the creep that just hit it.
##
## Here rather than in Building.take_damage because take_damage is handed an
## amount and a type and no attacker at all - by design, since the defender is
## where everything about the defender is worked out and nothing else in the
## game has ever needed to know who was swinging. A Lightning disc does, and
## this is the one place both ends of a hit are in scope at once.
func _return_fire(target: Unit, dealt: int) -> void:
	var tower: Building = target as Building
	if tower == null || attacker == null || !is_instance_valid(attacker):
		return
	var boons: TowerBuffs = tower.buffs_or_null()
	if boons != null:
		boons.on_tower_hurt(tower, attacker, dealt)


## Damage from one of this attack's EFFECTS rather than from the attack itself,
## and the kill credit that comes with it. Every splash goes through here.
##
## The four halves of a hit are deliberately split, and a splash gets three of
## them. A passive's on_hit is stated per SHOT - a poison stack worth a share
## of the damage, a bonus banked per swing, mana gained by attacking - and
## running it over a splash would pay a tower once per creep standing about,
## which is why a splash has never run one and still does not.
##
## The DEBUFF is the other way round and is why apply_debuffs exists: a chill
## or an eaten armour point is stated per creep, so everything the blast
## covered gets it. A Warden that ate the armour of only the creep it aimed at
## would be describing an attack nobody watching it could recognise.
##
## AREA DAMAGE is the fourth and the newest, and it is on_hit's missing half
## rather than a second copy of it: a share stated "of the damage dealt" means
## the whole blast for a tower whose shot IS a blast. See on_area_hit, which
## says why the two hooks stay apart.
##
## A KILL is the other way round again: unit_data.md says "per creep killed"
## and means whoever finished it, and a splash tower that finished a creep with
## its splash finished it. An Alchemist that only counted what its own shell
## landed on would grow at a fraction of the rate the source describes, because
## splash is how it kills.
##
## Already-dead creeps are skipped rather than damaged, so an effect walking a
## list cannot pay a tower twice for the same body.
func splash_onto(creep: Creep, amount: int, damage_type: DamageTable.DamageType,
		is_area: bool = true) -> void:
	if creep == null || !is_instance_valid(creep) || !creep.is_alive():
		return

	var tower: Building = _live_source()
	# Asked BEFORE the hit lands, for the reason _strike asks it there: a creep
	# on its last point still took the whole blast as far as anything reading
	# the figure is concerned, and the armour this same shot is about to eat
	# must not be taken off the number the shot itself is measured by.
	#
	# It costs one more resolve per creep the blast covered, which is the same
	# walk take_damage is about to make - the price of the primary hit's own
	# figure, paid per creep instead of once. Skipped entirely for a shot whose
	# tower has been sold, since there is nothing left to hand it to.
	var dealt: int = 0 if tower == null else creep.resolve_damage(amount, damage_type, is_area)

	creep.take_damage(amount, damage_type, is_area)
	debuff(creep)

	if tower == null:
		return
	for passive in passives:
		passive.on_area_hit(tower, creep, dealt)
	if creep.is_alive():
		return
	for passive in passives:
		passive.on_kill(tower, creep)


## Puts this attack's debuffs on one creep: what the tower's own passives
## chill, erode or amplify, and then what a technology disc is lending it.
##
## Called for every creep the attack touched at all - the one it aimed at, the
## ones a multishot picked up, and everything the splash covered - so it is the
## one place in the pipeline that does not care how a creep was caught.
##
## The disc goes last, after the tower's own, so a tower that already chills
## applies its own chill and the disc's under two separate caps rather than one
## merged into the other. See TowerBuffs.
##
## Silent when the tower has been sold mid-flight: a shot still lands and still
## splashes, but there is nothing left to attribute a debuff to.
func debuff(target: Unit) -> void:
	var tower: Building = _live_source()
	if tower == null:
		return

	for passive in passives:
		passive.apply_debuffs(tower, target)
	var boons: TowerBuffs = tower.buffs_or_null()
	if boons != null:
		boons.apply_debuffs(target)


## The tower that fired, or null if it has been sold, destroyed or upgraded
## since. Every use of `source` goes through here.
## Whether the target simply got out of the way, which one creep in the roster
## can and nothing else does.
##
## Only the DIRECT hit is dodgeable. A splash, a burn or an on-hit effect
## lands whatever happened to the shot that carried it - dodging an area is not
## a thing the source game lets anything do, and a creep that shrugged off
## every effect on the map at fifty percent would not be a dodge.
##
## Rolled on the match RNG, for the reason every roll in the simulation is: two
## machines running the same match have to miss the same shots or their worlds
## part company on the first one.
func _dodged(target: Unit) -> bool:
	var creep: Creep = target as Creep
	if creep == null || attack_range <= 0.0:
		return false

	var chance: float = creep.dodge_chance_against(attack_range)
	if chance <= 0.0:
		return false
	return MatchSession.match_rng().randf() < chance


func _live_source() -> Building:
	if source == null || !is_instance_valid(source):
		return null
	return source
