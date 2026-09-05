class_name DamageTable
extends Resource

## Everything that stands between an attack's raw roll and the health a unit
## actually loses.
##
## Two separate questions, and keeping them apart is the point:
##   - armour TYPE indexes the damage matrix. Every attack carries a damage
##     type and every damageable unit an armour type, and the pair decides what
##     SHARE of the attack lands: 1.25 is a quarter more, 0.66 a third less.
##   - armour POINTS are a number on the unit that reduces whatever the matrix
##     left, on a curve with diminishing returns. Negative points amplify it.
## A creep can therefore be resistant to a damage type and thinly armoured at
## the same time, which is what auras and armour buffs act on.
##
## Stored as Resources/Config/damage_table.tres, and written out in
## game_rules.md so the table can be read without opening the editor.
##
## The matrix rows live in the .tres and deliberately not as script defaults. A
## default that matched the file would be stripped from that file the next time
## the editor saved it, which would quietly move the balancing numbers into
## here. The armour curve constants are not a table, so they keep their
## defaults.

## What an attack deals. Chaos currently reads 1.0 against every armour type,
## but that is a balancing value like any other and not a rule, so nothing may
## shortcut it as "ignores armour".
##
## Order matters. Every row of the table lists its multipliers in this order.
enum DamageType {
	MAGIC,
	CHAOS,
	NORMAL,
	PIERCING,
	SIEGE,
	## The one type that is NOT physical: it ignores the matrix above and a
	## unit's armour points entirely, and is resisted only by a trait that says
	## so. Almost every tower ABILITY deals it and no tower's basic attack
	## does. See unit_data.md 1.1.
	##
	## Last in the enum deliberately, so every row of the matrix is still
	## exactly PHYSICAL_TYPE_COUNT long and no authored damage_type shifts.
	SPELL,
}

## Used when a row has not been filled in, so a half configured table deals
## plain damage rather than none. validate() is what reports the gap.
## How many times the negative-armour curve is multiplied out at most.
## See armor_multiplier - past this the curve is flat.
const MAX_ARMOR_STEPS: int = 64
const DEFAULT_MULTIPLIER: float = 1.0

## How many damage types go through the armour matrix, which is every one of
## them except SPELL. It is the length every row of the table must have, and it
## is why SPELL sits last in the enum rather than anywhere else.
const PHYSICAL_TYPE_COUNT: int = 5

@export_group("Armor Rows")
## One multiplier per damage type, in DamageType order. Empty means unset.
@export var unarmored: PackedFloat32Array = PackedFloat32Array()
@export var light: PackedFloat32Array = PackedFloat32Array()
@export var medium: PackedFloat32Array = PackedFloat32Array()
@export var heavy: PackedFloat32Array = PackedFloat32Array()
@export var fortified: PackedFloat32Array = PackedFloat32Array()
@export var hero: PackedFloat32Array = PackedFloat32Array()

@export_group("Armor Points")
## What one point of positive armour is worth before diminishing returns.
## 0.06 is the WC3 figure, so 1 point is 5.7% and 10 points 37.5%.
@export var armor_reduction_per_point: float = 0.06
## Base of the amplification curve for negative armour. 0.94 makes -1 armour
## take 6% more and -10 armour 46% more, never quite reaching double.
@export var negative_armor_base: float = 0.94


## Share of an attack's damage that lands, e.g. 1.5 for siege into fortified.
func multiplier(damage_type: DamageType, armor_type: UnitStats.ArmorType) -> float:
	# Invulnerable is not a row in the matrix, it is the absence of damage.
	# take_damage() already stops before this, so this is only a second line.
	if armor_type == UnitStats.ArmorType.INVULNERABLE:
		return 0.0

	# Spell damage does not index the matrix at all. Full damage against every
	# armour type, and only an explicit trait takes any of it back off.
	if is_spell(damage_type):
		return DEFAULT_MULTIPLIER

	var row: PackedFloat32Array = _row_for(armor_type)
	var index: int = int(damage_type)
	if index < 0 || index >= row.size():
		return DEFAULT_MULTIPLIER
	return row[index]


## Share of the damage that survives a unit's armour POINTS.
##
##   positive: 1 - (armor * 0.06) / (1 + 0.06 * armor)
##   negative: 2 - 0.94 ^ -armor
##
## The positive half has diminishing returns built in, so armour never reaches
## immunity however much of it is stacked. The negative half is the mirror: it
## amplifies without ever quite doubling. Both read exactly 1.0 at zero, which
## is where the two halves meet.
##
## **The negative half multiplies in a LOOP rather than calling `pow`, and that
## is a determinism fix.** `pow` is not specified by IEEE-754: glibc and the
## Windows UCRT are each entitled to be a ulp out, and under lockstep the peer
## group is Windows clients against a Linux server. This sits in the live damage
## pipeline, so a single ulp there is a creep that dies on one machine and lives
## on another. Repeated multiplication is plain IEEE arithmetic and is exact
## everywhere. Armour is an int over a small range, so the loop is the cheap
## answer as well as the correct one.
##
## The value moves by a few ulp against what `pow` returned. That is far below
## anything a player could see and far above nothing, which is the trade.
func armor_multiplier(armor: int) -> float:
	if armor == 0:
		return 1.0

	if armor > 0:
		var points: float = float(armor) * armor_reduction_per_point
		return 1.0 - points / (1.0 + armor_reduction_per_point * float(armor))

	# Bounded because the exponent comes from gameplay and a debuff stack has no
	# hard ceiling of its own. By 64 the curve has long since flattened onto its
	# asymptote, so anything past it is the same answer more slowly.
	var steps: int = mini(-armor, MAX_ARMOR_STEPS)
	var factor: float = 1.0
	for _i: int in range(steps):
		factor *= negative_armor_base
	return 2.0 - factor


## Share of the damage this many armour points takes OFF, as a percentage.
##
## The reading of armor_multiplier() rather than a second formula, because the
## panel writing "23.1%" next to a 5 and the pipeline taking 23.1% off a hit
## must be the same curve or the number is a lie. Negative for negative armour,
## where the same curve amplifies instead of reducing - which is what the minus
## sign in front of it means.
func armor_reduction_percent(armor: int) -> float:
	return (1.0 - armor_multiplier(armor)) * 100.0


## Damage actually dealt, run through the whole pipeline in the order
## game_rules.md sets out:
##   roll -> damage matrix -> the target's own resistances -> armour points
##        -> flat block
##
## Percentages resolve before flat points on purpose. A flat block is meant to
## blunt many small hits rather than one big one, and putting it last is what
## makes that true.
##
## Rounded to whole points because health is whole points. An attack that lands
## at all always does at least 1, so even a fully blocked hit is weak rather
## than free.
func apply(amount: int, damage_type: DamageType, armor_type: UnitStats.ArmorType,
		armor: int = 0, taken_ratio: float = 1.0, block: int = 0) -> int:
	if amount <= 0 || armor_type == UnitStats.ArmorType.INVULNERABLE:
		return 0

	var scaled: float = float(amount) * multiplier(damage_type, armor_type)
	if scaled <= 0.0:
		return 0

	scaled *= maxf(0.0, taken_ratio)
	# Armour POINTS are skipped for spell damage as well as the matrix. A creep
	# resists a spell by carrying a resistance trait, never by being armoured -
	# which is what makes a heavily armoured Boss worth hitting with one.
	if !is_spell(damage_type):
		scaled *= armor_multiplier(armor)
	scaled -= float(maxi(0, block))

	return maxi(1, roundi(scaled))


## Whether a damage type bypasses the armour matrix and armour points.
##
## Static and asked by name rather than compared inline, so the one place that
## decides what "not physical" means is here rather than at every call site
## that has to branch on it.
static func is_spell(damage_type: DamageType) -> bool:
	return damage_type == DamageType.SPELL


## Name of a damage type as shown in the UI, e.g. "Piercing".
## Static, because naming a type needs no table: an attack can say what it deals
## without anything having been wired up yet.
## Lowercased before capitalising, because capitalize() would otherwise split an
## all caps enum name on every letter.
static func damage_type_text(damage_type: DamageType) -> String:
	return String(DamageType.keys()[damage_type]).to_lower().capitalize()


## Logs every row that is missing or the wrong length, and answers whether the
## table is complete. Meant to be called once at boot rather than per hit, so a
## broken table is reported without flooding the log during a fight.
func validate() -> bool:
	var expected: int = PHYSICAL_TYPE_COUNT
	var complete: bool = true

	for armor_type: int in UnitStats.ArmorType.values():
		if armor_type == UnitStats.ArmorType.INVULNERABLE:
			continue
		var row: PackedFloat32Array = _row_for(armor_type)
		if row.size() == expected:
			continue

		Log.err("Damage table row is missing entries", {
			"armor": String(UnitStats.ArmorType.keys()[armor_type]),
			"found": row.size(),
			"expected": expected,
		})
		complete = false

	return complete


## Named per armour type rather than indexed by the enum's value, so reordering
## ArmorType can never silently shift every row by one.
func _row_for(armor_type: UnitStats.ArmorType) -> PackedFloat32Array:
	var row: PackedFloat32Array = PackedFloat32Array()

	match armor_type:
		UnitStats.ArmorType.UNARMORED:
			row = unarmored
		UnitStats.ArmorType.LIGHT:
			row = light
		UnitStats.ArmorType.MEDIUM:
			row = medium
		UnitStats.ArmorType.HEAVY:
			row = heavy
		UnitStats.ArmorType.FORTIFIED:
			row = fortified
		UnitStats.ArmorType.HERO:
			row = hero

	return row
