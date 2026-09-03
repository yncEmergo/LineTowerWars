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
##
## The ORDER is creation order and means nothing - FIRST is 0 because it was
## written first, not because it is the default. A .tres stores the int, so do
## not reorder these.
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

## What an attack goes after at all, which is a different question to the
## ground-versus-air one below.
##
## An enum rather than a flag field, because the two are EXCLUSIVE and nothing
## in the game targets both: a tower shoots the creeps walking its area and an
## attacker creep chews on the towers standing in it. Nothing anywhere shoots
## its own side, so there is no hostility question here either.
enum TargetClass {
	## Creeps walking the area. Every tower, and the default.
	CREEPS,
	## Towers standing in the area. The attacker creeps, and only them - the
	## builder and technology discs are never valid targets, which is enforced
	## by their being invulnerable rather than by anything here. See
	## unit_data.md 1.5.
	BUILDINGS,
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
## Seconds between an attack STARTING and its damage landing.
##
## The window an attack animation plays in: a hammer rises and falls, a barrel
## rocks back, a crystal charges. The tower commits at the start of it - it has
## picked its target and cannot pick another - and the damage lands at the end.
##
## **It comes OUT of the attack period, never on top of it.** A 1 APS tower with
## a 0.1s windup still attacks once a second: the cooldown starts ticking when
## the windup does, so what changes is when in the second the damage lands, not
## how often. A windup that added to the cooldown would make every animation a
## silent balance change, and nobody would ever be able to tell which of the two
## numbers a tower's real rate came from.
##
## 0 lands the damage the instant the tower fires, which is what everything
## without an animation wants.
@export var windup_seconds: float = 0.0

@export_group("Targeting")
@export var target_class: TargetClass = TargetClass.CREEPS
## Whether this unit looks for something to shoot with NO order at all.
##
## True for everything that defends by standing there - every tower - and for
## an attacker creep, which was sent to chew on a maze and needs no further
## instruction once it arrives. It is the whole of what a tower does.
##
## False for a unit that only ever fights when it is TOLD to, which is the
## builder. A hammer that swung at whatever wandered past would stop the
## builder dead in the middle of a maze the player was laying out, over four
## damage nobody asked for - and the builder is the one unit whose time is the
## player's rather than the simulation's.
##
## It never refuses an ORDER, and an attack-move still hunts: what it turns off
## is picking a fight unasked. See AttackComponent._may_acquire.
@export var auto_acquire: bool = true
## Measured in player cells from the tower's centre to the creep's, which is
## the same as world units because cell_size is 1.0.
@export var attack_range: float = 4.0
## Whether this reach is worth DRAWING on the ground when an attack is aimed
## or Show Ranges is pressed.
##
## True for everything that is placed, which is the whole point of a range
## circle: where a tower goes is decided by what it can cover, so a player
## aiming one is asking exactly this question.
##
## False for a reach that answers nothing. The builder's hammer is the case it
## exists for - a melee swing barely wider than the unit itself, on a unit that
## WALKS, so the circle is a ring drawn on its own feet that tells the player
## nothing they could act on. Presentation on the stats file rather than a rule
## in the overlay, because whether a reach is worth showing is a property of
## that attack and nothing else can know it.
@export var shows_range: bool = true
@export_flags("Ground", "Air") var target_types: int = TARGET_GROUND | TARGET_AIR
## CLOSEST by default, because it is the only priority whose answer differs
## from tower to tower. Every other one ranks the CREEPS - furthest along,
## most health, least health - so a line of towers coming off cooldown in the
## same tick all score the same creep best and empty into it together while
## the rest of the wave walks past. Nearest is measured FROM THE TOWER, so a
## row of them spreads across a wave on its own with nothing coordinating it.
@export var target_priority: TargetPriority = TargetPriority.CLOSEST
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


## The windup this attack can actually serve, which is never longer than the
## gap between attacks.
##
## Clamped rather than reported as an error every tick, because the failure is
## silent and strange otherwise: a windup longer than the cooldown would have a
## tower start its next attack before the last one landed, and the two would
## queue up until it was permanently behind. validate() is what says so once.
func windup_seconds_clamped() -> float:
	return clampf(windup_seconds, 0.0, cooldown_seconds())


## One attack's damage before the armour matrix touches it.
##
## The generator comes in rather than being reached for, so the roll is part of
## the match's one shared random stream and every machine gets the same number
## for the same shot. See MatchSession.match_rng().
func roll_damage(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(mini(damage_min, damage_max), maxi(damage_min, damage_max))


## Whether this attack goes after buildings rather than creeps, which is the
## attacker creeps and nothing else.
func hits_buildings() -> bool:
	return target_class == TargetClass.BUILDINGS


func can_hit_ground() -> bool:
	return (target_types & TARGET_GROUND) != 0


func can_hit_air() -> bool:
	return (target_types & TARGET_AIR) != 0


## Damage range as shown in the UI panel, e.g. "12 - 15".
##
## `bonus` is whole points a unit's own abilities have added to it for good, so
## what is written is what the tower standing on the field actually rolls -
## which is the same rule the armour line follows. 0 for everything that has
## grown into nothing, which is nearly every unit in the game.
func damage_text(bonus: int = 0, ratio: float = 1.0) -> String:
	return "%d - %d" % [scaled_damage(damage_min, bonus, ratio),
		scaled_damage(damage_max, bonus, ratio)]


## One end of the damage range as the tower actually deals it.
##
## The order is the pipeline's, not a convenience: AttackComponent scales the
## ROLL by the ratio and AttackHit adds the passive bonus to what comes out, so
## a tower standing in a Void disc with an Alchemist's banked damage hits for
## (roll x 1.24) + 300 rather than for (roll + 300) x 1.24. Written the other
## way round the panel would quote a number the tower never deals.
##
## Public so the panel can work out what a temporary ratio is WORTH - the
## difference between this answer with the disc and without it - without
## rebuilding that order for itself.
func scaled_damage(damage: int, bonus: int, ratio: float) -> int:
	return int(round(float(damage) * maxf(0.0, ratio))) + bonus


## Damage type as shown in the UI panel, e.g. "Piercing".
func damage_type_text() -> String:
	return DamageTable.damage_type_text(damage_type)


## Attack speed as shown in the UI panel, e.g. "0.75 APS". Named APS rather
## than spelled out, because that is what the player reads it as.
##
## `ratio` is everything currently making the unit swing faster or slower, and
## it is taken as an argument for exactly the reason armor_text() takes its
## points: this resource describes the TYPE, and a tower standing in an Earth
## disc - or cursed by a Harpy - is not it. 1.0 is a tower nothing is reaching,
## which is what a build tooltip describing a tower that does not exist yet
## wants.
func attack_speed_text(ratio: float = 1.0) -> String:
	return "%s APS" % StringUtil.trim_number(
		attacks_per_second * maxf(0.0, ratio))


## Range as shown in the UI panel, in player cells.
## The widest area this attack covers, in cells, or 0 for one that hits a
## single creep. Read off the EFFECTS rather than stored, because which of them
## an attack carries is the answer - a splash measured from the impact and one
## measured from the tower are both area, and a tower with neither has none.
func splash_radius() -> float:
	var widest: float = 0.0
	for effect: AttackEffect in effects:
		var splash: SplashEffect = effect as SplashEffect
		if splash != null:
			widest = maxf(widest, splash.radius)
		var blast: SelfSplashEffect = effect as SelfSplashEffect
		if blast != null:
			widest = maxf(widest, blast.radius)
	return widest


## `bonus` is reach lent to the unit in cells, on the same terms as the ratio
## above: a Primal disc standing nearby is the only thing that grants any.
func range_text(bonus: float = 0.0) -> String:
	return StringUtil.trim_number(attack_range + maxf(0.0, bonus))


## What this attack can shoot at, as shown in the UI, e.g. "Ground, Air".
##
## Worth a line of its own rather than being left implicit, because the anti-air
## branch cannot hit ground AT ALL and a player who does not read that before
## paying for one has bought a tower that never fires. "None" is authoring
## damage nobody can take, which validate() reports at boot.
func target_types_text() -> String:
	# The ground-versus-air flags describe creeps, and a tower is neither, so
	# an attack aimed at buildings answers the question it was actually asked.
	if hits_buildings():
		return "Towers"
	if can_hit_ground() && can_hit_air():
		return "Ground, Air"
	if can_hit_air():
		return "Air only"
	if can_hit_ground():
		return "Ground only"
	return "None"


## Reports an attack that could never fire at anything. Cheap to author by
## accident - target_types is a flag field and zero is a legal value for it -
## and completely silent in play, since the tower simply stands there.
func validate_targets(owner_name: String) -> bool:
	# Only a creep is ground or air. An attack on buildings passes whatever the
	# flags say, since nothing reads them on that path.
	if hits_buildings() || target_types != 0:
		return true
	Log.err("Attack can hit neither ground nor air and could never fire", owner_name)
	return false


## Reports every scene path this attack reaches that does not resolve. Called
## at boot by the stats resource that owns the attack.
func validate(owner_name: String) -> bool:
	var complete: bool = validate_targets(owner_name)

	if windup_seconds > cooldown_seconds():
		Log.err("Attack windup is longer than the gap between attacks", {
			"owner": owner_name,
			"windup": windup_seconds,
			"cooldown": cooldown_seconds(),
		})
		complete = false

	if delivery != null && !delivery.validate(owner_name):
		complete = false

	for effect: AttackEffect in effects:
		if effect != null && !effect.validate(owner_name):
			complete = false

	return complete
