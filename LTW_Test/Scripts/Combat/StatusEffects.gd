class_name StatusEffects
extends RefCounted

## Everything an elemental tower can leave ON a creep: chill, stun, poison,
## eaten armour, burning, and the amplifications that make somebody else's
## damage land harder.
##
## One of these per CREEP, created lazily the first time something is applied.
## A creep that nothing has touched pays nothing for it - not a tick, not an
## allocation - which matters because the vast majority of creeps in a maze are
## walking past towers that have no status to give.
##
## **The creep owns it and the towers write into it.** That is the same split
## the damage pipeline already has: an attacker states what it does, and the
## defender is where everything about the defender is worked out. A tower's
## passive calls `chill()` and never learns what the creep did with it.
##
## AUTHORITY ONLY, and enforced at the door rather than at forty call sites:
## every mutator returns immediately on a client. A client draws a creep where
## the server says it is, so a slow it applied locally would fight the
## snapshot; see multiplayer.md 3.4.
##
## Three shapes of thing live here and they are deliberately different:
##
##   TIMED       a slow, a stun, an amplification. A magnitude and a countdown.
##               Re-applying refreshes the countdown rather than stacking a
##               second copy, which is the WC3 convention
##   PERMANENT   eroded armour. No countdown at all - it is gone for the rest
##               of the creep's life, down to a floor the effect names
##   COUNTED     poison stacks, and the "once every N seconds" immunities. A
##               number and a gate rather than a magnitude
##   GRIPPED     an aura's hold. A stack count that climbs while a tower is
##               reaching the creep and drains once one stops, which every
##               effect that aura applies is then scaled by
##
## Slow is the one that is not simply "a magnitude": the source game states
## every slow as "X% per hit, up to Y%", so a chill ACCUMULATES towards its own
## cap as a creep is hit again and again. Two towers chilling one creep each
## have their own cap, and the creep takes the worst of them - see `slow_ratio`.
##
## Every mutator also names the ABILITY applying it, which nothing in the
## simulation reads: it is what lets the unit panel draw a picture next to a
## debuff. See `_owners` for how that survives the merges the rules above
## deliberately do, and `entries()` for the flat list the HUD reads.

## Slow the game applies when an effect does not name its own duration, in
## seconds. unit_data.md 1.3.
const DEFAULT_SLOW_SECONDS: float = 4.0

## How much of a second a stun has to have left to count. Below this it is
## expiring on this very tick and a creep should be walking again.
const EPSILON: float = 0.0001

## How long a STATED slow holds its value before a weaker statement may replace
## it. Longer than an aura's beat so a tower restating the same number never
## fights itself, short enough that losing the strongest tower in a line shows
## up immediately. See Chill.stated.
const RESTATE_SECONDS: float = 0.75

## One accumulating chill, keyed by whoever is applying it.
##
## A CLASS rather than three parallel dictionaries because the three numbers
## are meaningless apart: a percentage with no cap over-slows, and a cap with
## no countdown never wears off.
class Chill extends RefCounted:
	## How much slower the creep is right now, 0 to 1.
	var amount: float = 0.0
	## The most this source may ever reach, 0 to 1.
	var cap: float = 0.0
	## Seconds left before it wears off entirely.
	var seconds_left: float = 0.0
	## ability_id of whatever last added to it, so the HUD can picture it. Not
	## the cap key, which is authored per LINE and is a rule rather than a name.
	var source_id: int = StatusEntry.NO_SOURCE
	## Seconds since `amount` was last raised, for a slow that is STATED on a
	## beat rather than accumulated - an aura restates what its stack pile is
	## worth several times a second.
	##
	## What it buys is that a LOWER statement can take over once whatever set
	## the higher one has stopped saying it: sell the Ultimate Sludge and the
	## Lesser standing beside it takes the slow down to its own within a beat,
	## rather than the creep keeping the dead tower's number for as long as it
	## stays in range. "The highest in that line AT THE TIME" is the rule; this
	## is the "at the time" half of it.
	var stated: float = 0.0


## One aura's hold on this creep, keyed by whichever ability is applying it.
##
## A CLASS for the same reason Chill is: the count means nothing without the
## clock that drains it, and splitting them into parallel dictionaries is how
## one of them ends up not being cleaned up.
class Grip extends RefCounted:
	## How many stacks are held, up to the game's ceiling.
	var stacks: int = 0
	## Seconds since a tower last reached this creep with this aura. Reset by
	## every touch, INCLUDING one that could add nothing because the creep was
	## already at full - an aura still holding on is still holding on.
	var idle: float = 0.0
	## Counts up towards the next stack lost, once the idle window has passed.
	var draining: float = 0.0
	## ability_id of the aura holding on, for the HUD.
	var source_id: int = StatusEntry.NO_SOURCE


## The creep this is attached to. Held rather than passed in, because a status
## that has to be given its own creep every call is one somebody will
## eventually hand the wrong one.
var _creep: Creep
## source key -> Chill. Per SOURCE so two towers do not share one cap, which is
## what makes "up to 40%" mean anything at all.
var _chills: Dictionary = {}
## Seconds left of being unable to move or act at all.
var _stun_left: float = 0.0
## Seconds left of being held in place while still able to be shot as though on
## the ground. Water 1's paralyze - see `is_paralyzed`.
var _paralyze_left: float = 0.0
## Armour points removed for the rest of this creep's life. Always <= 0.
var _armor_eroded: float = 0.0
## Temporary armour change, and how long is left of it. One slot rather than a
## list: every effect that uses it states an absolute figure for a fixed window
## and the strongest wins, so a list would only ever be summed wrongly.
var _armor_delta: float = 0.0
var _armor_delta_left: float = 0.0
## Extra share of SPELL damage taken, e.g. 0.15 for +15%.
var _spell_amp: float = 0.0
var _spell_amp_left: float = 0.0
## Extra share of PHYSICAL damage taken.
var _physical_amp: float = 0.0
var _physical_amp_left: float = 0.0
## Attacks are slowed by this share while it lasts, for the aura that reduces a
## creep's own attack speed.
var _attack_slow: float = 0.0
var _attack_slow_left: float = 0.0
## Share taken off this creep's attack damage while it lasts.
var _damage_slow: float = 0.0
var _damage_slow_left: float = 0.0
## Burning: total spell damage per second, and how long is left. Sources are
## summed rather than kept apart, because a creep on fire twice burns twice as
## fast and nothing about that needs to know which tower lit it.
var _burn_per_second: float = 0.0
var _burn_left: float = 0.0
## Fraction of a health point burning has built up but not dealt yet, so a
## trickle below 1 point a tick still hurts.
var _burn_carry: float = 0.0
## Mana taken off this creep per second while it lasts, and how long is left.
## The BEST rate wins rather than the sum, on the same reasoning mend() and
## haste() use: this is a state a creep is in - its regeneration crystalized -
## rather than damage arriving, so two towers holding it there hold it once.
##
## Only a creep whose traits run on a pool has any to lose. One is taken off
## the pool by CreepMana.siphon, which carries its fraction the way burning
## does, so a third of a point a second still drains at a 20 Hz tick.
var _mana_drain_per_second: float = 0.0
var _mana_drain_left: float = 0.0
## Poison stored on this creep, and how many stacks of it. Unholy 1.
var _poison_damage: float = 0.0
var _poison_stacks: int = 0
## The ceiling those stacks are held under, which is the count the tower that
## last poisoned this creep detonates at. Kept so the HUD can write "7 / 10"
## and so a second Gravedigger cannot push the pile past it - see add_poison.
var _poison_max_stacks: int = 0
## Armour type this creep has been altered to, or -1 for its own. Ultimate
## Alchemist.
var _armor_type_override: int = -1
var _armor_type_left: float = 0.0
## Armour types this creep has ALREADY been altered to once, so the Ultimate
## Alchemist cannot cycle one creep through the same weakness twice.
var _armor_types_used: Dictionary = {}
## key -> seconds left before that effect may touch this creep again. The
## "once every 8 seconds" rules, all of them, in one place.
var _immunities: Dictionary = {}

## Every aura currently gripping this creep, keyed by the ability applying it.
## See Grip and touch_aura.
var _grips: Dictionary = {}

## Seconds left of hearing no friendly aura at all. The Arcane disc, and the
## one thing in the game that takes an effect AWAY from a creep rather than
## putting one on it - see deny_auras.
var _aura_denied_left: float = 0.0
## Seconds added to every slow APPLIED while this is running, and how long it
## has left. See lengthen_slows.
var _slow_bonus: float = 0.0
var _slow_bonus_left: float = 0.0

## StatusEntry.Kind -> ability_id of whatever currently owns that effect.
##
## Presentation only: nothing in the simulation reads it, and it decides nothing
## about what an effect is worth. It exists so the panel can draw an ICON for a
## debuff, which needs a name for something the rules deliberately merged - one
## burn however many towers lit it, the strongest amplification whoever cast it.
## The winner of that merge is what gets recorded, so the picture and the number
## beside it always describe the same tower.
##
## One dictionary rather than a field per effect: an owner is written by every
## mutator and read only by `entries()`, so a stale key for an effect that has
## since worn off is never looked at and costs nothing to leave lying there.
var _owners: Dictionary = {}


## Share of a harmful effect's clock this creep serves, and share of a chill's
## magnitude that lands on it.
##
## Read ONCE, here, off the creep's own passives. A creep cannot gain or lose a
## passive while it walks, so re-asking on every application would be the same
## answer computed forty times a second - and this object is built lazily, so a
## creep nothing has ever touched never even asks. See CreepPassive.
var _duration_ratio: float = 1.0
var _chill_ratio: float = 1.0
## A FURTHER share of a COLD slow that lands, on top of the one above. Read the
## same way and for the same reason.
##
## Frost is the only kind of slow anything in the roster resists SPECIFICALLY,
## which is what this is: the spell resistances shrug off an Ice tower and an
## Ice disc and nothing else. See CreepPassive.cold_taken_ratio.
var _cold_ratio: float = 1.0
## The longest any harmful effect may run on this creep whatever it asked for,
## or 0 for no ceiling. Read off the passives with the two ratios above and for
## the same reason - it cannot change while the creep walks.
var _duration_cap: float = 0.0
## The most this creep may ever be slowed, whatever has piled up on it. 1.0 is
## no ceiling. Goblin Engineering is the only thing that lowers it.
var _max_slow: float = 1.0

## Damage waiting to be eaten before any of it reaches the creep's health, and
## whichever ability put it there.
##
## A POOL rather than a countdown: a shield is spent rather than served, so it
## is the one thing here with no clock at all. Sources ADD, because two shields
## on one creep are two shields.
var _shield: float = 0.0
## The most it has ever held, which is what a shield BAR is drawn against - the
## background behind the fill is how much of it has already been spent.
##
## Kept rather than derived, because nothing else remembers it: a shield is a
## pool with no clock, and once a hit has eaten half of one there is no other
## record of how big it was. Reset to zero the moment the pool empties, so a
## creep that is shielded again starts a fresh bar rather than one that looks
## nine tenths gone.
var _shield_max: float = 0.0
## Seconds left of taking no damage whatever. Elune's Grace is the only thing
## that grants one, and it is a window rather than a pool.
var _ward_left: float = 0.0
## Extra share of movement speed, and how long is left of it. The mirror of a
## chill, and kept apart from one so that being hasted and being slowed at once
## resolves to somewhere between the two rather than to whichever landed last.
var _haste: float = 0.0
var _haste_left: float = 0.0
## Health restored per second by an effect somebody put ON this creep, as
## opposed to an aura standing over it or its own regeneration. Sources take
## the BEST rather than adding, exactly as an aura does.
var _mend_per_second: float = 0.0
var _mend_left: float = 0.0
## Armour points GIVEN to this creep for the rest of its life, kept PER
## SOURCE. Always >= 0, and kept apart from the erosion above so that a floor
## meant for one cannot clamp the other.
##
## Per source because the two traits that grant it are unrelated and only one
## of them has a ceiling: Spiritual Aid may raise any one creep by at most
## twelve points over its whole life, and the Crypt Fiend's Ethereal Aura has
## no limit at all. A single shared total would have a Crypt Fiend's gifts
## spend the Spirit Walker's allowance, which is a rule neither trait states.
var _armor_granted: Dictionary = {}
## Their sum, kept alongside so armor_delta() does not walk the dictionary on
## every hit.
var _armor_granted_total: float = 0.0


func _init(creep: Creep) -> void:
	_creep = creep
	if creep == null:
		return
	for passive in creep.passives():
		_duration_ratio *= passive.harmful_duration_ratio()
		_chill_ratio *= passive.chill_taken_ratio()
		_cold_ratio *= passive.cold_taken_ratio()
		_max_slow = minf(_max_slow, passive.max_slow_share())
		var cap: float = passive.harmful_duration_cap()
		if cap > 0.0:
			_duration_cap = cap if _duration_cap <= 0.0 else minf(_duration_cap, cap)


# --- questions ------------------------------------------------------------

## Share of its normal speed this creep moves at right now, 0 to 1.
##
## Slows from DIFFERENT sources MULTIPLY, and slows from the same one do not.
## Two towers of different lines each taking 40% leave a creep at 36% speed
## rather than at 60% or at 20%: each one takes its share of what is left, so
## piling more on always helps and never stops the creep dead.
##
## Within one source key there is a single accumulating chill, so a whole line
## of Sludge Monstrosities is ONE slow however many of them are grinding - the
## strongest cap in that line is what it climbs to. That is what a "path" means
## here, and it is why the key is AUTHORED per line rather than taken off the
## .tres: which towers share a slow is a balance decision, and reading it off
## the resource would give every tier its own and let a line stack with itself.
## See the chill() note below.
func move_ratio() -> float:
	if _stun_left > EPSILON || _paralyze_left > EPSILON:
		return 0.0

	var moving: float = 1.0
	for key in _chills:
		moving *= 1.0 - (_chills[key] as Chill).amount
	# The creep's own ceiling on being slowed, applied to the PILE rather than
	# to each chill as it lands: "cannot be slowed by more than 25%" is a
	# statement about the total, and clamping each application instead would
	# let four towers reach 100% a quarter at a time.
	return clampf(1.0 - minf(1.0 - moving, _max_slow), 0.0, 1.0)


## Whether the creep is held still and cannot act. Stun and paralyze both, from
## a mover's point of view - the difference between them is only what may shoot
## at the creep meanwhile.
func is_held() -> bool:
	return _stun_left > EPSILON || _paralyze_left > EPSILON


func is_stunned() -> bool:
	return _stun_left > EPSILON


## A paralyzed FLYER is pinned to the spot and may be shot at as though it were
## walking the ground, which is the whole point of Water 1's paralyze - it
## hands a lane of ground towers a target they could never otherwise reach.
func is_paralyzed() -> bool:
	return _paralyze_left > EPSILON


## Armour points to add to the creep's own: what has been permanently eaten,
## plus whatever temporary change is running. Negative reduces.
##
## Rounded towards zero rather than floored, so eroding 0.1 nine times has not
## yet cost a whole point and eroding it ten times has. Armour is an integer
## everywhere else in the game and this is where the fraction stops.
func armor_delta() -> int:
	return int(_armor_eroded + _armor_granted_total + _armor_delta)


## The armour TYPE this creep counts as right now, or -1 to use its own.
func armor_type_override() -> int:
	return _armor_type_override if _armor_type_left > EPSILON else -1


## Multiplier on damage of this kind, above 1 being more damage taken.
func damage_taken_ratio(is_spell: bool) -> float:
	if is_spell:
		return 1.0 + (_spell_amp if _spell_amp_left > EPSILON else 0.0)
	return 1.0 + (_physical_amp if _physical_amp_left > EPSILON else 0.0)


## Multiplier on how fast this creep attacks, below 1 being slower. Only the
## attacker creeps have an attack for it to act on.
func attack_speed_ratio() -> float:
	if _attack_slow_left <= EPSILON:
		return 1.0
	return clampf(1.0 - _attack_slow, 0.05, 1.0)


## Multiplier on how hard this creep hits, below 1 being weaker.
func attack_damage_ratio() -> float:
	if _damage_slow_left <= EPSILON:
		return 1.0
	return clampf(1.0 - _damage_slow, 0.0, 1.0)


## How slowed this creep is by one particular source, 0 to 1. What a tower asks
## before deciding whether its own chill has reached its cap - Ultimate Lich's
## Frostbitten is exactly that question.
func chill_amount(source: String) -> float:
	var entry: Chill = _chills.get(source) as Chill
	return 0.0 if entry == null else entry.amount


## Whether the creep is taking no damage at all right now. Elune's Grace, and
## nothing else in the roster.
func is_warded() -> bool:
	return _ward_left > EPSILON


## Whether this creep is currently deaf to every friendly aura around it.
##
## The Arcane disc and nothing else. Read by Creep._refresh_aura, which is the
## one place a creep hears its packmates at all, so denying it there is the
## whole of the effect and no aura has to know it exists.
func is_aura_denied() -> bool:
	return _aura_denied_left > EPSILON


## Armour points somebody has GIVEN this creep for good.
##
## Takes the SOURCE, because the one trait that asks is asking about its own
## allowance rather than about how thick the creep has become: Spiritual Aid
## reads this to decide whether it may grant another point, and a Crypt Fiend
## standing in the same pack must not spend that allowance for it. Null asks
## for the whole, which is what a readout would want.
func granted_armor(source: UnitAbility = null) -> float:
	if source == null:
		return _armor_granted_total
	return float(_armor_granted.get(source.resource_path, 0.0))


## Damage the shield in front of this creep's health still holds.
func shield_points() -> float:
	return _shield


## The most that shield has ever held, or 0 when there is none. What the bar is
## drawn against.
func shield_max() -> float:
	return _shield_max


## Multiplier on this creep's movement speed from anything HASTENING it, which
## is one packmate's trait and nothing a tower ever does. Never below 1.
func haste_ratio() -> float:
	return 1.0 + _haste if _haste_left > EPSILON else 1.0


## Health restored per second by whatever is mending this creep, which is a
## packmate's shield rather than an aura or its own regeneration.
func mend_per_second() -> float:
	return _mend_per_second if _mend_left > EPSILON else 0.0


## Whether an effect keyed like this may fire on this creep right now. The
## other half of every "once every N seconds" rule in unit_data.md section 4.
func is_immune(key: String) -> bool:
	return float(_immunities.get(key, 0.0)) > EPSILON


func poison_stacks() -> int:
	return _poison_stacks


func poison_damage() -> int:
	return int(_poison_damage)


# --- what a tower does to a creep ------------------------------------------

## Adds one hit of an accumulating chill and refreshes its window.
##
## `per_hit` and `cap` are shares, so unit_data.md's "-5.5% per hit up to -30%"
## is chill(ability, key, 0.055, 0.30, seconds, cold).
##
## THE KEY IS THE PATH. Every tier of one upgrade line authors the same one, so
## a Lesser and an Ultimate Sludge Monstrosity feed ONE accumulating chill that
## climbs to whichever of them has the higher cap - they do not stack, and the
## stronger simply wins. Different lines are different keys and multiply
## against each other; see move_ratio.
##
## The key stays separate from the ability rather than being derived from it,
## because it is AUTHORED: which towers share a slow is a balance decision a
## .tres makes, and reading it off the resource would give every TIER its own
## and let a line stack with itself.
##
## `cold` says this is FROST - an Ice tower or an Ice disc - which is the only
## kind of slow anything in the roster resists specifically.
func chill(source: UnitAbility, key: String, per_hit: float, cap: float,
		seconds: float, cold: bool) -> void:
	if !_may_write() || per_hit <= 0.0 || cap <= 0.0:
		return

	# The creep's own resistance blunts the chill and its cap together. Blunting
	# only what lands would leave the cap where it was, and a resistant creep
	# would still reach the full slow eventually - just later, which is the
	# opposite of what resisting a slow means.
	var blunt: float = _slow_ratio(cold)
	var entry: Chill = _chill_for(source, key)
	entry.cap = maxf(entry.cap, cap * blunt)
	entry.amount = minf(entry.amount + per_hit * blunt, entry.cap)
	# An ACCUMULATING chill only ever climbs, so it holds its own claim on the
	# key for as long as it is being fed - see Chill.stated.
	entry.stated = 0.0
	entry.seconds_left = maxf(entry.seconds_left, _slow_seconds(seconds))


## Applies a flat slow that does not accumulate: the magnitude is the whole of
## it and re-applying only refreshes the window. Holy 2's Luminous Grasp.
func slow(source: UnitAbility, key: String, amount: float, seconds: float,
		cold: bool) -> void:
	if !_may_write() || amount <= 0.0:
		return

	var blunted: float = amount * _slow_ratio(cold)
	var entry: Chill = _chill_for(source, key)
	entry.cap = maxf(entry.cap, blunted)
	# The strongest statement wins while it is still being made, and a weaker
	# one takes over once the stronger has gone quiet for a beat. See
	# Chill.stated.
	if blunted >= entry.amount || entry.stated >= RESTATE_SECONDS:
		entry.amount = blunted
		entry.stated = 0.0
	entry.seconds_left = maxf(entry.seconds_left, _slow_seconds(seconds))


## Share of a slow that lands on this creep: what it resists of every slow, and
## what it resists of frost on top when the slow is one.
##
## Both ways of applying a slow go through it, so a trait that says "cannot be
## slowed" cannot be walked around by an effect that took the other route.
func _slow_ratio(cold: bool) -> float:
	return _chill_ratio * _cold_ratio if cold else _chill_ratio


## The chill accumulating under one cap key, created on the spot the first time
## a tower reaches this creep with it. Shared by both ways of applying one.
func _chill_for(source: UnitAbility, key: String) -> Chill:
	var entry: Chill = _chills.get(key) as Chill
	if entry == null:
		entry = Chill.new()
		_chills[key] = entry
	entry.source_id = _id_of(source)
	return entry


## An aura reaching this creep for one beat. Answers the share of that aura's
## full strength it should now be applying, 0 to 1.
##
## THE CALLER SCALES ITS OWN EFFECTS BY THE ANSWER. This owns how tight the
## grip is and knows nothing about what the aura does with it, which is the same
## split every other effect here follows - a tower states what it does and the
## creep works out what that came to.
##
## Keyed by the PATH rather than by the tower or by one .tres, so every tower
## feeding it feeds ONE pile: two Sludge Monstrosities standing over a creep
## stack it twice as fast, and a Lesser and an Ultimate of the same line are
## still the one aura rather than two. Two different lines are two grips and
## never interfere. The key is authored, exactly as the chill key is - see
## chill() for why.
func touch_aura(source: UnitAbility, key: String) -> float:
	if !_may_write() || source == null || key.is_empty():
		return 0.0

	var grip: Grip = _grips.get(key) as Grip
	if grip == null:
		grip = Grip.new()
		_grips[key] = grip
	# Whoever last fed it owns the icon, the way a merged chill does.
	grip.source_id = _id_of(source)

	# The touch resets the drain whether or not it could add anything, so a
	# creep sitting at full stacks never starts losing them while it stands
	# there.
	grip.idle = 0.0
	grip.draining = 0.0
	# One stack per touch, and the tower's own beat is what makes that one per
	# `aura_stack_seconds`. Two towers touching means two stacks in that time.
	grip.stacks = mini(_stack_ceiling(), grip.stacks + 1)
	return aura_share(key)


## The share of an aura's strength currently held, without touching it. For
## anything that has to read a grip it is not the one feeding.
func aura_share(key: String) -> float:
	var ceiling: int = _stack_ceiling()
	return 0.0 if ceiling <= 0 else clampf(
		float(aura_stacks(key)) / float(ceiling), 0.0, 1.0)


## How many stacks of one aura are held, for an effect stated PER STACK rather
## than as a share of a full grip - a Sludge Monstrosity's slow is "this much
## per stack, up to that much", so it wants the count and not the fraction.
func aura_stacks(key: String) -> int:
	var grip: Grip = _grips.get(key) as Grip
	return 0 if grip == null else grip.stacks


## Makes every slow APPLIED FROM NOW ON last longer, for a window. What "slow
## duration is increased by an additional N sec" means.
##
## Forward-looking rather than a top-up of what is already on the creep, and
## that is not a detail: an aura reaching in to add two seconds to every running
## chill twice a second would make every slow on anything standing in it
## permanent. Lengthening slows as they ARE APPLIED gives the number the source
## states and cannot run away.
func lengthen_slows(source: UnitAbility, seconds: float, window: float) -> void:
	if !_may_write() || seconds <= 0.0:
		return
	_own(StatusEntry.Kind.SLOWS_LENGTHENED, source)
	_slow_bonus = maxf(_slow_bonus, seconds)
	_slow_bonus_left = maxf(_slow_bonus_left, window)


## Holds the creep still and stops it acting. The longer of the two wins, so a
## short stun landing on a long one cannot cut it short.
func stun(source: UnitAbility, seconds: float) -> void:
	if _may_write():
		_own(StatusEntry.Kind.STUNNED, source)
		_stun_left = maxf(_stun_left, _harmful_seconds(seconds))


## Pins a flyer where it is and lets ground towers reach it. Water 1.
func paralyze(source: UnitAbility, seconds: float) -> void:
	if _may_write():
		_own(StatusEntry.Kind.PARALYZED, source)
		_paralyze_left = maxf(_paralyze_left, _harmful_seconds(seconds))


## Eats armour for the rest of the creep's life, never below the floor.
##
## The floor is the EFFECT's, not the creep's, which is why it comes in: most
## erosion stops at 0 and the Divineshroom line pushes to -3. Measured against
## the creep's own armour so two towers eroding it cannot each drive it to the
## floor separately.
func erode_armor(source: UnitAbility, amount: float, floor_value: float) -> void:
	if !_may_write() || amount <= 0.0 || _creep == null:
		return

	_own(StatusEntry.Kind.ARMOR_ERODED, source)
	var base: float = 0.0 if _creep.stats == null else float(_creep.stats.armor)
	var lowest: float = floor_value - base
	_armor_eroded = maxf(_armor_eroded - amount, minf(lowest, 0.0))


## Changes armour points for a fixed window. The strongest change wins for as
## long as either would have lasted, so a weaker one cannot cut a stronger one
## short by landing a moment later.
func change_armor(source: UnitAbility, delta: float, seconds: float) -> void:
	if !_may_write():
		return
	if absf(delta) >= absf(_armor_delta) || _armor_delta_left <= EPSILON:
		_armor_delta = delta
		_own(StatusEntry.Kind.ARMOR_CHANGED, source)
	_armor_delta_left = maxf(_armor_delta_left, _harmful_seconds(seconds))


## Makes the creep take more SPELL damage from everything, for a window.
func amplify_spell(source: UnitAbility, amount: float, seconds: float) -> void:
	if !_may_write() || amount <= 0.0:
		return
	if amount >= _spell_amp || _spell_amp_left <= EPSILON:
		_own(StatusEntry.Kind.SPELL_VULNERABLE, source)
	_spell_amp = maxf(_spell_amp, amount)
	_spell_amp_left = maxf(_spell_amp_left, _harmful_seconds(seconds))


## Makes the creep take more PHYSICAL damage from everything, for a window.
func amplify_physical(source: UnitAbility, amount: float, seconds: float) -> void:
	if !_may_write() || amount <= 0.0:
		return
	if amount >= _physical_amp || _physical_amp_left <= EPSILON:
		_own(StatusEntry.Kind.PHYSICALLY_VULNERABLE, source)
	_physical_amp = maxf(_physical_amp, amount)
	_physical_amp_left = maxf(_physical_amp_left, _harmful_seconds(seconds))


## Slows the creep's own attacks and weakens them. Both at once because the one
## thing that does it - Ultimate Titan Vault's aura - does both, and splitting
## them would mean two timers that always expire together.
func weaken_attack(source: UnitAbility, speed_share: float, damage_share: float,
		seconds: float) -> void:
	if !_may_write():
		return
	if speed_share > 0.0:
		if speed_share >= _attack_slow || _attack_slow_left <= EPSILON:
			_own(StatusEntry.Kind.ATTACK_SLOWED, source)
		_attack_slow = maxf(_attack_slow, speed_share)
		_attack_slow_left = maxf(_attack_slow_left, _harmful_seconds(seconds))
	if damage_share > 0.0:
		if damage_share >= _damage_slow || _damage_slow_left <= EPSILON:
			_own(StatusEntry.Kind.ATTACK_WEAKENED, source)
		_damage_slow = maxf(_damage_slow, damage_share)
		_damage_slow_left = maxf(_damage_slow_left, _harmful_seconds(seconds))


## Sets the creep alight for `seconds`, dealing `per_second` Spell Damage.
## Sources ADD, unlike everything else here: two fires burn twice as fast.
func burn(source: UnitAbility, per_second: float, seconds: float) -> void:
	if !_may_write() || per_second <= 0.0 || seconds <= 0.0:
		return
	_own(StatusEntry.Kind.BURNING, source)
	_burn_per_second += per_second
	_burn_left = maxf(_burn_left, _harmful_seconds(seconds))


## Crystalizes the creep's mana regeneration: `per_second` points off its pool
## for `seconds`, or nothing at all for a creep that has no pool.
##
## Ice 2's Ultimate, and the only thing in the game that reaches a creep's mana.
## Refused for a creep with none rather than sitting on it invisibly, so the
## debuff row never shows a player an effect that is doing nothing.
func drain_mana(source: UnitAbility, per_second: float, seconds: float) -> void:
	if !_may_write() || per_second <= 0.0 || seconds <= 0.0:
		return
	if _creep == null || !is_instance_valid(_creep) || _creep.mana() == null:
		return
	if per_second >= _mana_drain_per_second || _mana_drain_left <= EPSILON:
		_mana_drain_per_second = per_second
		_own(StatusEntry.Kind.MANA_DRAINED, source)
	_mana_drain_left = maxf(_mana_drain_left, _harmful_seconds(seconds))


## Stores poison on the creep and answers how many stacks it now carries.
##
## The CEILING is enforced here rather than by the caller, and that is the
## whole point of the poison living on the creep: ten stacks is ten stacks from
## ANY Gravedigger, so two of them shooting one creep fill one pile instead of
## each keeping a count of their own. A hit that arrives at the ceiling is
## simply wasted, which is what unit_data.md's "up to 10 stacks" means - the
## alternative had a creep sitting on thirty stacks whenever the tower that got
## it there was still inside its own explosion cooldown.
##
## The caller still owns WHEN it goes off, since that is its cooldown and its
## explosion; this only refuses to stack any higher.
func add_poison(source: UnitAbility, damage: float, max_stacks: int) -> int:
	if !_may_write() || damage <= 0.0 || max_stacks <= 0:
		return _poison_stacks
	_poison_max_stacks = maxi(_poison_max_stacks, max_stacks)
	if _poison_stacks >= max_stacks:
		return _poison_stacks
	_own(StatusEntry.Kind.POISONED, source)
	_poison_damage += damage
	_poison_stacks += 1
	return _poison_stacks


## Empties the stored poison and answers what was in it, so the caller can deal
## it. Zero when there was none.
func take_poison() -> int:
	var stored: int = int(_poison_damage)
	_poison_damage = 0.0
	_poison_stacks = 0
	_poison_max_stacks = 0
	return stored


## Alters the creep's armour type for a window, once per type per creep.
## Answers whether it took - Ultimate Alchemist's card shows the choice, and a
## creep already altered to that type refuses it rather than refreshing.
func alter_armor_type(source: UnitAbility, armor_type: int, seconds: float) -> bool:
	if !_may_write() || _armor_types_used.has(armor_type):
		return false
	_own(StatusEntry.Kind.ARMOR_TYPE_ALTERED, source)
	_armor_types_used[armor_type] = true
	_armor_type_override = armor_type
	_armor_type_left = _harmful_seconds(seconds)
	return true


## Shuts an effect out of this creep for a while. The caller checks is_immune()
## first; this is what it calls once it has actually fired.
func set_immune(key: String, seconds: float) -> void:
	if _may_write():
		_immunities[key] = maxf(float(_immunities.get(key, 0.0)), seconds)


# --- the readout ----------------------------------------------------------

## Puts damage in front of the creep's health, to be eaten before any of it
## reaches the bar. Sources ADD: two shields on one creep are two shields.
##
## A POOL rather than a countdown, which is the whole difference between this
## and the ward below - a shield is spent, a ward is served. Nothing here
## decides what a shield is worth; Abyssal Carapace converts nine tenths of a
## Behemoth into one and the creep spends it a hit at a time.
func absorb(source: UnitAbility, amount: float) -> void:
	if amount <= 0.0 || !_may_write():
		return
	_shield += amount
	# Sources ADD here too, so two shields on one creep make one bar twice as
	# long rather than a second one starting part-spent.
	_shield_max += amount
	_own(StatusEntry.Kind.SHIELDED, source)
	# The bar is built the first time there is one to draw rather than with the
	# health bar, so this is where the authority learns it has one. A client is
	# told the same thing by the snapshot; see Unit.refresh_shield_bar.
	if _creep != null && is_instance_valid(_creep):
		_creep.refresh_shield_bar()


## Takes what it can out of the shield and answers what is LEFT to reach the
## health. Called by the creep once a hit has been fully resolved, so what a
## shield eats is the damage that would really have landed.
##
## Deliberately not a question the damage pipeline asks: a shield is not a
## resistance and must not be folded in with the ratios, or a creep behind one
## would take a share of every hit forever instead of none of the first few.
func spend_shield(landed: float) -> float:
	if landed <= 0.0 || _shield <= 0.0 || !_may_write():
		return maxf(0.0, landed)

	var eaten: float = minf(_shield, landed)
	_shield -= eaten
	if _shield < 0.001:
		_shield = 0.0
		_shield_max = 0.0
	return landed - eaten


## Makes the creep untouchable for a window. The longer of the two wins, so a
## short ward landing on a long one cannot cut it short.
##
## NOT the invulnerable armour type, which is permanent and also refuses heals.
## A warded creep still regenerates, is still shot at and is still slowed - it
## simply takes nothing off its health while the window runs.
func ward(source: UnitAbility, seconds: float) -> void:
	if seconds <= 0.0 || !_may_write():
		return
	if seconds > _ward_left:
		_ward_left = seconds
		_own(StatusEntry.Kind.WARDED, source)


## Cuts the creep off from every friendly aura for a window, the longer of the
## two winning exactly as a ward does.
##
## Half of what an Arcane disc does to whatever walks over it, and the other
## half is an ordinary amplify_spell. Stated in unit_data.md 5.2 as one effect
## with one duration, and it is applied as two because the two halves are
## already separate machinery: one is a share of incoming spell damage and the
## other is a creep not listening to its neighbours.
##
## It reaches the aura a creep HEARS, never the ones it gives - a Kodo Beast
## walking over an Arcane disc goes on hastening the pack around it and simply
## stops hearing its own. That is what "cannot benefit from friendly auras"
## says, and doing it the other way would make the disc a debuff on a wave
## rather than on a creep.
func deny_auras(source: UnitAbility, seconds: float) -> void:
	if seconds <= 0.0 || !_may_write():
		return
	seconds = _harmful_seconds(seconds)
	if seconds > _aura_denied_left:
		_aura_denied_left = seconds
		_own(StatusEntry.Kind.AURA_DENIED, source)


## Speeds the creep up for a window. The strongest wins for as long as either
## would have lasted, exactly as an armour change does.
##
## Deliberately NOT run through _harmful_seconds: this is a gift from a
## packmate, and a creep that shrugs off harmful effects must not also shrug
## off a friendly one.
func haste(source: UnitAbility, amount: float, seconds: float) -> void:
	if amount <= 0.0 || seconds <= 0.0 || !_may_write():
		return
	if amount >= _haste || _haste_left <= EPSILON:
		_haste = amount
		_own(StatusEntry.Kind.HASTED, source)
	_haste_left = maxf(_haste_left, seconds)


## Heals the creep over a window. The best rate wins rather than the sum, on
## the same reasoning auras do not stack: two Ogre Magi shielding one creep
## should be worth one shield and a spare.
func mend(source: UnitAbility, per_second: float, seconds: float) -> void:
	if per_second <= 0.0 || seconds <= 0.0 || !_may_write():
		return
	if per_second >= _mend_per_second || _mend_left <= EPSILON:
		_mend_per_second = per_second
		_own(StatusEntry.Kind.REGENERATING, source)
	_mend_left = maxf(_mend_left, seconds)


## Drops every chill on the creep outright, which is what "removes chill and
## slow" means: the towers that applied them start accumulating from nothing
## again, exactly as they would have if the creep had walked out of range.
##
## Ultimate Lich's Frostbite is a chill like any other and goes with the rest,
## which is what unit_data.md 6.6 asks Earth Shield to do.
func clear_slows() -> void:
	if !_may_write():
		return
	_chills.clear()


## Halves every chill currently on the creep, cap and all, so a tower that had
## reached its ceiling has to climb back to it. Regenerative Flesh, once per
## creep, at half health.
func halve_slows() -> void:
	if !_may_write():
		return
	for key in _chills:
		var entry: Chill = _chills[key] as Chill
		entry.amount *= 0.5
		entry.cap *= 0.5


## Gives back armour a tower has eaten, never past what the creep started with.
## Answers whether any was actually restored, so a trait that only fires on a
## creep below its base armour can gate on the attempt.
func restore_armor(amount: float) -> bool:
	if amount <= 0.0 || _armor_eroded >= 0.0 || !_may_write():
		return false
	_armor_eroded = minf(0.0, _armor_eroded + amount)
	return true


## Adds armour for the rest of the creep's life. The Crypt Fiend's aura, which
## hands out two points at a time to one creep near it, and the Spirit Walker's
## Spiritual Aid, which hands out one.
##
## Kept apart from the erosion rather than added into it, so a tower eroding
## down to a floor and an aura granting upwards cannot clamp each other. Kept
## per SOURCE for the reason `_armor_granted` records: the two traits that
## grant it do not share a ceiling.
func bless_armor(source: UnitAbility, amount: float) -> void:
	if amount <= 0.0 || source == null || !_may_write():
		return
	var key: String = source.resource_path
	_armor_granted[key] = float(_armor_granted.get(key, 0.0)) + amount
	_armor_granted_total += amount
	_own(StatusEntry.Kind.ARMOR_GRANTED, source)


## Every debuff on this creep right now, flattened into one list of records the
## HUD can draw without knowing that a chill is kept per source, a burn is kept
## merged and eroded armour is kept with no clock at all.
##
## Built fresh on each call rather than maintained: the panel asks about ONE
## creep a few times a second, and a list kept in step as effects come and go
## would be a second copy of everything above that could disagree with it.
##
## The order is FIXED - chills, then grips, then the rest in Kind order - so a
## row of icons does not reshuffle under the player's cursor when one of them
## wears off. The dictionary keys are sorted for the same reason: insertion
## order changes when a chill expires and is applied again.
func entries() -> Array[StatusEntry]:
	var list: Array[StatusEntry] = []
	_append_chills(list)
	_append_grips(list)
	_append_held(list)
	_append_armor(list)
	_append_amplifications(list)
	_append_over_time(list)
	_append_boons(list)
	return list


func _append_chills(list: Array[StatusEntry]) -> void:
	var keys: Array = _chills.keys()
	keys.sort()
	for key in keys:
		var entry: Chill = _chills[key] as Chill
		list.append(StatusEntry.make(StatusEntry.Kind.SLOWED, entry.source_id,
			entry.amount, entry.seconds_left))


## A grip is drawn with NO countdown, because it has none: it lasts exactly as
## long as a tower keeps reaching the creep, and what a player wants off it is
## the stack count.
func _append_grips(list: Array[StatusEntry]) -> void:
	var keys: Array = _grips.keys()
	keys.sort()
	var ceiling: int = _stack_ceiling()
	for key in keys:
		var grip: Grip = _grips[key] as Grip
		list.append(StatusEntry.make(StatusEntry.Kind.GRIPPED, grip.source_id,
			0.0, StatusEntry.PERMANENT, grip.stacks, ceiling))


func _append_held(list: Array[StatusEntry]) -> void:
	if _stun_left > EPSILON:
		list.append(_record(StatusEntry.Kind.STUNNED, 0.0, _stun_left))
	if _paralyze_left > EPSILON:
		list.append(_record(StatusEntry.Kind.PARALYZED, 0.0, _paralyze_left))
	if _slow_bonus_left > EPSILON:
		list.append(_record(StatusEntry.Kind.SLOWS_LENGTHENED, _slow_bonus,
			_slow_bonus_left))


func _append_armor(list: Array[StatusEntry]) -> void:
	if _armor_eroded < 0.0:
		list.append(_record(StatusEntry.Kind.ARMOR_ERODED, _armor_eroded,
			StatusEntry.PERMANENT))
	if _armor_granted_total > 0.0:
		list.append(_record(StatusEntry.Kind.ARMOR_GRANTED, _armor_granted_total,
			StatusEntry.PERMANENT))
	if _armor_delta_left > EPSILON && !is_zero_approx(_armor_delta):
		list.append(_record(StatusEntry.Kind.ARMOR_CHANGED, _armor_delta,
			_armor_delta_left))
	if _armor_type_left > EPSILON:
		list.append(_record(StatusEntry.Kind.ARMOR_TYPE_ALTERED,
			float(_armor_type_override), _armor_type_left))


func _append_amplifications(list: Array[StatusEntry]) -> void:
	if _spell_amp_left > EPSILON:
		list.append(_record(StatusEntry.Kind.SPELL_VULNERABLE, _spell_amp,
			_spell_amp_left))
	if _physical_amp_left > EPSILON:
		list.append(_record(StatusEntry.Kind.PHYSICALLY_VULNERABLE, _physical_amp,
			_physical_amp_left))
	if _attack_slow_left > EPSILON:
		list.append(_record(StatusEntry.Kind.ATTACK_SLOWED, _attack_slow,
			_attack_slow_left))
	if _damage_slow_left > EPSILON:
		list.append(_record(StatusEntry.Kind.ATTACK_WEAKENED, _damage_slow,
			_damage_slow_left))
	# Not strictly an amplification, and here anyway: the Arcane disc applies
	# it in the same breath as the spell vulnerability above it, and a player
	# reading the row wants the two halves of one disc next to each other.
	if _aura_denied_left > EPSILON:
		list.append(_record(StatusEntry.Kind.AURA_DENIED, 0.0, _aura_denied_left))


## Poison carries no countdown either: it sits on the creep until whatever put
## it there detonates it, so its number is the damage stored and its stacks are
## how many hits went into that.
func _append_over_time(list: Array[StatusEntry]) -> void:
	if _burn_left > EPSILON:
		list.append(_record(StatusEntry.Kind.BURNING, _burn_per_second, _burn_left))
	if _mana_drain_left > EPSILON:
		list.append(_record(StatusEntry.Kind.MANA_DRAINED,
			_mana_drain_per_second, _mana_drain_left))
	if _poison_stacks > 0:
		list.append(StatusEntry.make(StatusEntry.Kind.POISONED,
			_owner_of(StatusEntry.Kind.POISONED), _poison_damage,
			StatusEntry.PERMANENT, _poison_stacks, _poison_max_stacks))


## The four effects on this creep that are not a tower's doing: a shield it
## converted out of itself, a ward, a haste and a heal a packmate handed it.
##
## Drawn in the same row as the rest deliberately. What the panel is answering
## is "what is on this creep", and a creep that is untouchable for the next ten
## seconds is by far the most important thing on it.
func _append_boons(list: Array[StatusEntry]) -> void:
	if _ward_left > EPSILON:
		list.append(_record(StatusEntry.Kind.WARDED, 0.0, _ward_left))
	# No countdown: a shield is SPENT rather than served, so what a player
	# wants off it is how much of it is left.
	if _shield > 0.0:
		list.append(_record(StatusEntry.Kind.SHIELDED, _shield,
			StatusEntry.PERMANENT))
	if _haste_left > EPSILON:
		list.append(_record(StatusEntry.Kind.HASTED, _haste, _haste_left))
	if _mend_left > EPSILON:
		list.append(_record(StatusEntry.Kind.REGENERATING, _mend_per_second,
			_mend_left))


## One record for an effect kept as a plain value and a countdown, which is most
## of them, with whichever ability currently owns it attached.
func _record(kind: StatusEntry.Kind, magnitude: float, seconds: float) -> StatusEntry:
	return StatusEntry.make(kind, _owner_of(kind), magnitude, seconds)


# --- who applied what -----------------------------------------------------

## Records the ability an effect should be PICTURED as coming from. Called by
## whichever mutator won the merge, never by one whose value was thrown away.
func _own(kind: StatusEntry.Kind, source: UnitAbility) -> void:
	_owners[kind] = _id_of(source)


func _owner_of(kind: StatusEntry.Kind) -> int:
	return int(_owners.get(kind, StatusEntry.NO_SOURCE))


## An ability's authored id, or NO_SOURCE for anything that named none. Static
## because it asks nothing of the creep this is attached to.
static func _id_of(source: UnitAbility) -> int:
	return StatusEntry.NO_SOURCE if source == null else source.ability_id


# --- the tick -------------------------------------------------------------

## Advances every countdown and deals whatever burning is due. Called by the
## creep on the fixed tick, on the authority only.
##
## Answers whether anything is still running, so a creep that has been clean
## for a tick can drop the whole object and go back to costing nothing.
func advance(delta: float) -> bool:
	_advance_grips(delta)
	_stun_left = maxf(0.0, _stun_left - delta)
	_paralyze_left = maxf(0.0, _paralyze_left - delta)
	_armor_delta_left = maxf(0.0, _armor_delta_left - delta)
	_spell_amp_left = maxf(0.0, _spell_amp_left - delta)
	_physical_amp_left = maxf(0.0, _physical_amp_left - delta)
	_attack_slow_left = maxf(0.0, _attack_slow_left - delta)
	_damage_slow_left = maxf(0.0, _damage_slow_left - delta)
	_slow_bonus_left = maxf(0.0, _slow_bonus_left - delta)
	_armor_type_left = maxf(0.0, _armor_type_left - delta)
	_ward_left = maxf(0.0, _ward_left - delta)
	_haste_left = maxf(0.0, _haste_left - delta)
	_aura_denied_left = maxf(0.0, _aura_denied_left - delta)

	_advance_chills(delta)
	_advance_immunities(delta)
	_advance_burn(delta)
	_advance_mend(delta)
	_advance_mana_drain(delta)
	return _is_running()


## A chill that runs out is FORGOTTEN rather than left at zero, so the tower
## that applied it starts accumulating from nothing again next time - which is
## what "up to 40%" means once the creep has walked out of range and back in.
func _advance_chills(delta: float) -> void:
	var expired: Array = []
	for key in _chills:
		var entry: Chill = _chills[key] as Chill
		entry.stated += delta
		entry.seconds_left -= delta
		if entry.seconds_left <= 0.0:
			expired.append(key)
	for key in expired:
		_chills.erase(key)


## Drains every aura grip nothing has renewed lately.
##
## The idle window comes FIRST and the drain only starts after it, which is
## what makes a grip linger: a creep crossing a gap between two towers of the
## same aura, or briefly outrunning one, keeps what it had rather than starting
## again from nothing.
func _advance_grips(delta: float) -> void:
	if _grips.is_empty():
		return

	var config: GameConfig = References.game_config
	var idle_window: float = 1.0 if config == null else config.aura_idle_seconds
	var per_stack: float = 0.5 if config == null else maxf(0.01, config.aura_decay_seconds)

	var empty: Array = []
	for key in _grips:
		var grip: Grip = _grips[key] as Grip
		grip.idle += delta
		if grip.idle < idle_window:
			continue

		grip.draining += delta
		while grip.draining >= per_stack && grip.stacks > 0:
			grip.draining -= per_stack
			grip.stacks -= 1
		if grip.stacks <= 0:
			empty.append(key)
	for key in empty:
		_grips.erase(key)


func _advance_immunities(delta: float) -> void:
	var expired: Array = []
	for key in _immunities:
		var left: float = float(_immunities[key]) - delta
		if left <= 0.0:
			expired.append(key)
		else:
			_immunities[key] = left
	for key in expired:
		_immunities.erase(key)


## Burning deals SPELL damage, so it goes through the creep's spell resistances
## and ignores its armour entirely - see game_rules.md.
##
## The fraction is carried between ticks rather than rounded away, exactly as
## creep regeneration does, so 5 damage a second still burns at a 20 Hz tick.
func _advance_burn(delta: float) -> void:
	if _burn_left <= 0.0:
		_burn_per_second = 0.0
		_burn_carry = 0.0
		return

	_burn_left -= delta
	if _creep == null || !is_instance_valid(_creep) || !_creep.is_alive():
		return

	_burn_carry += _burn_per_second * delta
	var whole: int = int(_burn_carry)
	if whole > 0:
		_burn_carry -= float(whole)
		_creep.take_damage(whole, DamageTable.DamageType.SPELL)

	if _burn_left <= 0.0:
		_burn_per_second = 0.0
		_burn_carry = 0.0


## Heals whatever is mending the creep. The mirror of burning above, and it
## carries its fraction between ticks for the same reason: the creep's health
## is a float, so a trickle below a point a tick still banks where it lands.
func _advance_mend(delta: float) -> void:
	if _mend_left <= 0.0:
		_mend_per_second = 0.0
		return

	_mend_left -= delta
	if _creep != null && is_instance_valid(_creep) && _creep.is_alive():
		_creep.heal(_mend_per_second * delta)
	if _mend_left <= 0.0:
		_mend_per_second = 0.0


## Takes the crystalized mana off the pool. The third of the over-time effects
## and the quietest: the carry lives on CreepMana rather than here, because the
## pool is what a regeneration is also writing into and the two have to net.
func _advance_mana_drain(delta: float) -> void:
	if _mana_drain_left <= 0.0:
		_mana_drain_per_second = 0.0
		return

	_mana_drain_left -= delta
	if _creep != null && is_instance_valid(_creep) && _creep.is_alive():
		var pool: CreepMana = _creep.mana()
		if pool != null:
			pool.siphon(_mana_drain_per_second, delta)
	if _mana_drain_left <= 0.0:
		_mana_drain_per_second = 0.0


## How long a harmful timed effect really runs on this creep, once its own
## resistance has been applied.
##
## Every timed mutator above goes through it EXCEPT the two that apply a slow,
## so a creep that shortens harmful durations shortens all the rest of them -
## stun, burn, amplification, eaten armour - rather than only the ones somebody
## remembered to route through here. The slow lengthening is deliberately NOT
## folded in: that acts on slows alone and rides the funnel below.
func _harmful_seconds(seconds: float) -> float:
	var served: float = maxf(seconds, 0.0) * _duration_ratio
	# The ceiling comes after the share, which is the order Regenerative Flesh
	# states it in: two thirds off, and then never more than a second and a
	# half whatever is left.
	return served if _duration_cap <= 0.0 else minf(served, _duration_cap)


## How long a SLOW runs on this creep, which is the one harmful window the
## creep's duration resistance never touches.
##
## A creep resists a slow with chill_taken_ratio(), cold_taken_ratio() and
## max_slow_share(), and with nothing else. Shortening the window as well would be charging it
## twice for one trait: the Dragonspawn already takes half of every chill, and
## a quarter-length window on top of that left it untouched by the two aura
## slows in the game - a Sludge Monstrosity steps its chill every 1.5s and a
## Titan Vault re-applies its own every beat, so a window cut to a fraction of
## a second expired before the next step could build on it. What "resists
## magic" means for a slow is that it lands smaller, not that it falls off
## early. See unit_data.md 6.6 and game_rules.md.
##
## What it IS folded in with is whatever is currently lengthening slows on this
## creep, which acts on slows alone and so has nowhere else to live. Applied at
## the moment a slow lands and never afterwards - see lengthen_slows.
func _slow_seconds(seconds: float) -> float:
	var base: float = maxf(seconds, 0.0)
	if base <= 0.0 || _slow_bonus_left <= EPSILON:
		return base
	return base + _slow_bonus


## How many stacks an aura may hold on one creep, from the game's own rules.
func _stack_ceiling() -> int:
	var config: GameConfig = References.game_config
	return 5 if config == null else maxi(1, config.aura_max_stacks)


## Whether anything at all is still ticking. Permanent erosion counts, because
## dropping the object would hand the creep its armour back, and so does an
## aura grip, because dropping that would hand the creep a fresh start on the
## next tower it walked past.
func _is_running() -> bool:
	if !_chills.is_empty() || !_immunities.is_empty() || !_grips.is_empty():
		return true
	if _armor_eroded < 0.0 || _poison_stacks > 0 || !_armor_types_used.is_empty():
		return true
	# A shield and granted armour both count for the same reason erosion does:
	# dropping the object would quietly hand back what is stored in it.
	if _armor_granted_total > 0.0 || _shield > 0.0:
		return true
	var timers: float = maxf(maxf(_stun_left, _paralyze_left), maxf(_burn_left, _armor_delta_left))
	timers = maxf(timers, maxf(_spell_amp_left, _physical_amp_left))
	timers = maxf(timers, maxf(_ward_left, maxf(_haste_left, _mend_left)))
	timers = maxf(timers, maxf(_aura_denied_left, _mana_drain_left))
	# The two that weaken the creep's OWN attack. Nothing in the roster leaves
	# either of them standing alone today - both arrive from an aura, whose
	# grip is caught above - but a countdown missing from this list is an
	# effect that vanishes on the tick after it lands, with nothing to see.
	timers = maxf(timers, maxf(_attack_slow_left, _damage_slow_left))
	return maxf(timers, _slow_bonus_left) > EPSILON


## Only the authority decides what a status did, for the same reason only it
## decides what a hit did. A client's creep is wherever the snapshot puts it,
## so a chill applied here would be a slow the server never agreed to.
func _may_write() -> bool:
	return MatchSession.is_authority()
