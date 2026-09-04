class_name TowerBuffs
extends RefCounted

## Everything a technology DISC can grant a tower.
##
## The third of the three "what is currently on this unit" objects, and it is
## deliberately shaped like the other two. StatusEffects is everything a tower
## can leave on a creep; TowerStatus is the four things a creep can leave on a
## tower; this is what a disc lends the towers standing around it. Same rules
## in all three: the unit OWNS the object, whoever is applying the effect
## writes into it and never learns what was done with it, it is built lazily so
## a tower nothing is reaching pays nothing at all, and every mutator stands
## aside on a client.
##
## **Everything here is an AURA, so everything here EXPIRES.** A disc re-grants
## its whole set every quarter second to every tower it reaches, and each grant
## carries a window comfortably longer than that gap - so a tower inside the
## radius never flickers, and a tower whose disc has just been sold loses the
## lot a fraction of a second later without anything having to tell it. There
## is no "remove" call and there must not be one: a disc that has stopped
## reaching a tower is a disc that has stopped calling, which is the same thing.
##
## **The strongest grant wins, and that is the Primal stacking rule** rather
## than an implementation convenience. unit_data.md 5.2 records it as a real
## bug fixed in 12.3a: a weak disc must never override the bonus of a stronger
## one standing beside it. Taking the maximum makes that true for every effect
## here at once, so no disc has to know what the others are doing, and two
## Ultimate Holy discs are worth exactly one.
##
## What is NOT here is anything a disc does to a CREEP. The Arcane and Fire
## discs trigger on the creep that walks over them and reach no tower at all,
## so they go straight to that creep's StatusEffects like any other source.

## Every boon a disc can hand out, one entry per number rather than per disc.
##
## Split this finely on purpose: two elements can want the same knob at
## different strengths - and the reader wants one answer, not a list to resolve
## - so the merge has to happen per NUMBER. An element that granted a bundle
## would be merged as a bundle and the strongest disc for one of its numbers
## would drag the rest of its own along with it.
enum Kind {
	## Share added to attack speed, 0.08 for +8%. Earth.
	SPEED,
	## Cells added to attack range. Primal.
	RANGE,
	## Armour points added. Holy.
	ARMOR,
	## Share added to the tower's own health regeneration, 1.65 for +165%.
	## Holy again, and the one number of that disc that stops climbing.
	REGEN,
	## Mana points per second. Water.
	MANA,
	## Share added to attack damage, 0.08 for +8%. Void.
	DAMAGE,
	## Share of the target's movement taken per hit, and the floor those hits
	## accumulate towards. Ice, and the only boon that is two numbers - a chill
	## per hit with no cap is not a chill, it is a stop.
	CHILL,
	CHILL_CAP,
	## Armour points eroded off the creep, permanently, per hit. Unholy.
	EROSION,
	## Share of the Physical damage dealt that the tower heals for. Lightning.
	HEAL,
	## Multiple of the damage an attacking creep just did that is dealt back to
	## it. Lightning: 5.0 is 500%.
	RETURN,
	## Chance that same creep is stunned for STUN_SECONDS. Lightning.
	STUN,
}

## How long an attacking creep is stunned by a static tower it hit.
##
## A constant rather than a per-tier number because unit_data.md 5.2 gives all
## three Lightning tiers the same two seconds - only the CHANCE climbs - and a
## number authored three times that is the same three times drifts.
const STUN_SECONDS: float = 2.0

## Which StatusEntry kind each boon is drawn and SENT as.
##
## A table rather than a match, because entries() is otherwise one loop: every
## boon here is "one number, granted for as long as the disc keeps reaching",
## so the only thing that differs between them is which row they draw as.
##
## CHILL_CAP has an entry of its own rather than riding CHILL's, because a
## template carries at most one "%s" - see StatusEntry.TEMPLATES - and the cap
## is genuinely a second number a player wants: a chill per hit with no floor
## named is not a figure anybody can act on.
const ENTRY_KINDS: Dictionary = {
	Kind.SPEED: StatusEntry.Kind.ATTACK_HASTENED,
	Kind.RANGE: StatusEntry.Kind.RANGE_EXTENDED,
	Kind.ARMOR: StatusEntry.Kind.ARMOR_LENT,
	Kind.REGEN: StatusEntry.Kind.REGEN_RAISED,
	Kind.MANA: StatusEntry.Kind.MANA_GRANTED,
	Kind.DAMAGE: StatusEntry.Kind.ATTACK_EMPOWERED,
	Kind.CHILL: StatusEntry.Kind.CHILLING_ATTACKS,
	Kind.CHILL_CAP: StatusEntry.Kind.CHILL_FLOOR,
	Kind.EROSION: StatusEntry.Kind.ERODING_ATTACKS,
	Kind.HEAL: StatusEntry.Kind.LIFESTEALING,
	Kind.RETURN: StatusEntry.Kind.RETURNING_DAMAGE,
	Kind.STUN: StatusEntry.Kind.STUNNING_ATTACKERS,
}

## How much of a second a boon has to have left to count. Below this it is
## expiring on this very tick.
const EPSILON: float = 0.0001

## Kind -> the strongest value granted while its window is open.
var _values: Dictionary = {}
## Kind -> seconds left of that value.
var _left: Dictionary = {}
## Kind -> the disc passive that granted the winning value.
##
## Presentation and keying rather than rules, the same job StatusEffects._owners
## does: the chill a tower applies has to be keyed by whoever is behind it so
## two discs do not share one cap, and the panel wants a picture to draw beside
## the boon.
var _sources: Dictionary = {}


## Grants one boon for a window, or refreshes it. The strongest value wins for
## as long as either would have lasted, so a weaker disc reaching a tower a
## moment later can never cut a stronger one short.
##
## The value is re-read from nothing once its window has closed, which is what
## makes walking a disc out of range restore the tower rather than leaving it
## on the better of the two figures forever - the same shape TowerStatus uses
## for the Annihilation Aura.
func grant(kind: Kind, value: float, seconds: float, source: UnitAbility) -> void:
	if value <= 0.0 || seconds <= 0.0 || !_may_write():
		return

	var current: float = float(_values.get(kind, 0.0))
	if value >= current || float(_left.get(kind, 0.0)) <= EPSILON:
		_values[kind] = value
		_sources[kind] = source
	_left[kind] = maxf(float(_left.get(kind, 0.0)), seconds)


## The strongest value of one boon right now, or 0 when nothing is granting it.
func value_of(kind: Kind) -> float:
	if float(_left.get(kind, 0.0)) <= EPSILON:
		return 0.0
	return float(_values.get(kind, 0.0))


## The disc passive behind the winning value, or null. Used as the SOURCE key
## when a boon has to be applied through StatusEffects, so two discs chilling
## one creep keep their own caps.
func source_of(kind: Kind) -> UnitAbility:
	if float(_left.get(kind, 0.0)) <= EPSILON:
		return null
	return _sources.get(kind, null) as UnitAbility


## Everything a disc is lending this tower, as the panel and the wire read it.
##
## The read side, the same job StatusEffects.entries() and TowerStatus.entries()
## do for the other two objects, and the reason a client can draw any of this at
## all: none of it is worked out anywhere but the authority, so before this the
## whole disc system reached no client and a tower standing in a Primal disc had
## its circle drawn at its own reach.
##
## Drawn with NO COUNTDOWN - PERMANENT - which is the same call
## StatusEffects._append_grips makes and for the same reason. These windows are
## an implementation detail of how a disc keeps its grip: it re-grants the lot
## four times a second, so the number left is always about a second and says
## nothing a player could use. What it really lasts is "while the tower stands
## here", and no clock draws that honestly.
##
## Iterated over ENTRY_KINDS rather than over _values, so the ORDER is this
## file's and not a dictionary's insertion order - which would differ between
## two towers that were reached by the same discs in a different order, and put
## the rows in a different place on each.
func entries() -> Array[StatusEntry]:
	var list: Array[StatusEntry] = []
	for kind: Kind in ENTRY_KINDS:
		var value: float = value_of(kind)
		if value <= 0.0:
			continue
		var source: UnitAbility = source_of(kind)
		list.append(StatusEntry.make(
			ENTRY_KINDS[kind],
			StatusEntry.NO_SOURCE if source == null else source.ability_id,
			value,
			StatusEntry.PERMANENT))
	return list


## Multiplier on how fast the tower attacks. Above 1 is faster.
func attack_speed_ratio() -> float:
	return 1.0 + value_of(Kind.SPEED)


## Multiplier on how hard the tower hits. Above 1 is harder.
func attack_damage_ratio() -> float:
	return 1.0 + value_of(Kind.DAMAGE)


## Cells added to the tower's reach.
func attack_range_bonus() -> float:
	return value_of(Kind.RANGE)


## Armour points added to the tower's own.
func armor_bonus() -> int:
	return int(round(value_of(Kind.ARMOR)))


## Share added to the tower's health regeneration, 0 for none.
func regen_share() -> float:
	return value_of(Kind.REGEN)


## Mana points per second granted to the tower, 0 for none.
func mana_per_second() -> float:
	return value_of(Kind.MANA)


## The DEBUFF a disc lends the tower's attacks: the chill, and the armour it
## eats. Applied to every creep the attack touched, splash included, which is
## the same rule TowerPassive.apply_debuffs states and for the same reason.
##
## Runs after the tower's own passives, so a tower that both chills on its own
## and stands in an Ice disc applies two chills under two caps - which is what
## unit_data.md means by two sources having their own, see StatusEffects.
func apply_debuffs(target: Unit) -> void:
	if !_may_write():
		return
	var creep: Creep = target as Creep
	if creep == null:
		return
	_apply_chill(creep)
	_apply_erosion(creep)


## What a disc gives the TOWER out of a hit it has just landed, which today is
## the share of it the tower heals for. The debuff half is apply_debuffs above.
##
## `dealt` is what the hit actually cost the creep once the whole pipeline had
## run, the same figure TowerPassive.on_hit is handed, because every share in
## 5.2 is stated against the damage dealt.
func on_tower_hit(tower: Building, _target: Unit,
		damage_type: DamageTable.DamageType, dealt: int) -> void:
	if tower == null || !_may_write():
		return
	_apply_lifesteal(tower, damage_type, dealt)


## What a STATIC tower does back to the creep that just hit it: a multiple of
## the damage returned, and a chance of a stun on top.
##
## The damage is Spell Damage, so it ignores armour entirely. That is the whole
## character of the number: unit_data.md 5.2 states the return at 500% to 1000%
## of what the creep just did, and running a figure that size back through the
## matrix would make an Ultimate Lightning disc worth wildly different amounts
## against two creeps that hit equally hard.
##
## `dealt` is what the creep's attack actually cost the tower, so a tower
## standing in a Holy disc's armour returns less - it took less.
func on_tower_hurt(tower: Building, attacker: Unit, dealt: int) -> void:
	if tower == null || dealt <= 0 || !_may_write():
		return
	var creep: Creep = attacker as Creep
	if creep == null || !creep.is_alive():
		return

	var share: float = value_of(Kind.RETURN)
	if share > 0.0:
		creep.take_damage(maxi(1, int(round(float(dealt) * share))),
			DamageTable.DamageType.SPELL, false)

	var chance: float = value_of(Kind.STUN)
	if chance <= 0.0 || !creep.is_alive():
		return
	# On the match RNG like every roll in the simulation, so two machines
	# running the same match stun the same creeps. See AttackHit._dodged.
	if MatchSession.match_rng().randf() < chance:
		creep.status().stun(source_of(Kind.STUN), STUN_SECONDS)


## Advances every window, and answers whether anything is still running - so a
## tower a disc has stopped reaching drops the whole object and goes back to
## costing nothing per tick.
func advance(delta: float) -> bool:
	if _left.is_empty():
		return false

	var expired: Array = []
	for kind in _left:
		var left: float = float(_left[kind]) - delta
		if left <= 0.0:
			expired.append(kind)
		else:
			_left[kind] = left

	for kind in expired:
		_left.erase(kind)
		_values.erase(kind)
		_sources.erase(kind)

	return !_left.is_empty()


## The chill an Ice disc lends the tower's attacks.
##
## Keyed by the DISC rather than by the tower, which is what makes the cap mean
## what unit_data.md says: every tower standing in one Ultimate Ice disc feeds
## one accumulating chill towards one -36%, rather than each of them opening a
## cap of its own and stacking twelve of them onto a creep.
##
## It names no duration of its own, so it takes the game's shared one. 5.2
## states the disc chill as a per-hit share and a cap and says nothing about
## how long it holds, which is exactly the case StatusEffects.DEFAULT_SLOW_SECONDS
## exists for - see unit_data.md 1.3.
func _apply_chill(creep: Creep) -> void:
	var per_hit: float = value_of(Kind.CHILL)
	if per_hit <= 0.0:
		return
	var source: UnitAbility = source_of(Kind.CHILL)
	if source == null:
		return
	creep.status().chill(source, source.resource_path, per_hit,
		value_of(Kind.CHILL_CAP), StatusEffects.DEFAULT_SLOW_SECONDS, true)


## The armour an Unholy disc's attacks eat, permanently, down to zero.
##
## Zero rather than into the negatives, which is what "down to 0" in 5.2 says
## and is the one place a disc differs from the elemental towers that erode -
## the Divineshroom line carries on past it and says so.
func _apply_erosion(creep: Creep) -> void:
	var amount: float = value_of(Kind.EROSION)
	if amount <= 0.0:
		return
	creep.status().erode_armor(source_of(Kind.EROSION), amount, 0.0)


## The share of its own PHYSICAL damage a static tower heals for.
##
## Physical only, and that is unit_data.md 5.2's word rather than a
## simplification: the number is stated as a share "of the Physical Damage
## dealt", so a Spell Damage tower standing in a Lightning disc heals for
## nothing. Normal, Piercing, Siege and Chaos are all physical; Spell is the
## one damage type that sits outside the armour matrix, see DamageTable.
func _apply_lifesteal(tower: Building, damage_type: DamageTable.DamageType,
		dealt: int) -> void:
	var share: float = value_of(Kind.HEAL)
	if share <= 0.0 || dealt <= 0:
		return
	if damage_type == DamageTable.DamageType.SPELL:
		return
	tower.heal(float(dealt) * share)


func _may_write() -> bool:
	return MatchSession.is_authority()
