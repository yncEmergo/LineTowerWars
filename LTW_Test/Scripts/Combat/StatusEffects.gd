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
##
## Slow is the one that is not simply "a magnitude": the source game states
## every slow as "X% per hit, up to Y%", so a chill ACCUMULATES towards its own
## cap as a creep is hit again and again. Two towers chilling one creep each
## have their own cap, and the creep takes the worst of them - see `slow_ratio`.

## Slow the game applies when an effect does not name its own duration, in
## seconds. unit_data.md 1.3.
const DEFAULT_SLOW_SECONDS: float = 4.0

## How much of a second a stun has to have left to count. Below this it is
## expiring on this very tick and a creep should be walking again.
const EPSILON: float = 0.0001

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
## Poison stored on this creep, and how many stacks of it. Unholy 1.
var _poison_damage: float = 0.0
var _poison_stacks: int = 0
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


func _init(creep: Creep) -> void:
	_creep = creep


# --- questions ------------------------------------------------------------

## Share of its normal speed this creep moves at right now, 0 to 1.
##
## The WORST chill on it wins rather than the sum: two towers each slowing 40%
## leave a creep at 60% speed, not at 20%. That is the WC3 convention and it is
## what stops a lane of one tower type stopping a pack dead.
func move_ratio() -> float:
	if _stun_left > EPSILON || _paralyze_left > EPSILON:
		return 0.0

	var worst: float = 0.0
	for key in _chills:
		worst = maxf(worst, (_chills[key] as Chill).amount)
	return clampf(1.0 - worst, 0.0, 1.0)


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
	return int(_armor_eroded + _armor_delta)


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
## is chill(source, 0.055, 0.30, seconds). The source key is what gives each
## tower type its own cap; two Lesser Liches share one, which is deliberate and
## matches the source game treating a slow as a property of the ability.
func chill(source: String, per_hit: float, cap: float, seconds: float) -> void:
	if !_may_write() || per_hit <= 0.0 || cap <= 0.0:
		return

	var entry: Chill = _chills.get(source) as Chill
	if entry == null:
		entry = Chill.new()
		_chills[source] = entry

	entry.cap = maxf(entry.cap, cap)
	entry.amount = minf(entry.amount + per_hit, entry.cap)
	entry.seconds_left = maxf(entry.seconds_left, maxf(seconds, 0.0))


## Applies a flat slow that does not accumulate: the magnitude is the whole of
## it and re-applying only refreshes the window. Holy 2's Luminous Grasp.
func slow(source: String, amount: float, seconds: float) -> void:
	if !_may_write() || amount <= 0.0:
		return

	var entry: Chill = _chills.get(source) as Chill
	if entry == null:
		entry = Chill.new()
		_chills[source] = entry

	entry.cap = maxf(entry.cap, amount)
	entry.amount = maxf(entry.amount, amount)
	entry.seconds_left = maxf(entry.seconds_left, maxf(seconds, 0.0))


## Extends every chill currently on the creep, which is what the Lich line's
## "slow duration increased by N seconds" does. Never shortens one.
func extend_slows(seconds: float) -> void:
	if !_may_write() || seconds <= 0.0:
		return
	for key in _chills:
		var entry: Chill = _chills[key] as Chill
		if entry.seconds_left > EPSILON:
			entry.seconds_left += seconds


## Holds the creep still and stops it acting. The longer of the two wins, so a
## short stun landing on a long one cannot cut it short.
func stun(seconds: float) -> void:
	if _may_write():
		_stun_left = maxf(_stun_left, maxf(seconds, 0.0))


## Pins a flyer where it is and lets ground towers reach it. Water 1.
func paralyze(seconds: float) -> void:
	if _may_write():
		_paralyze_left = maxf(_paralyze_left, maxf(seconds, 0.0))


## Eats armour for the rest of the creep's life, never below the floor.
##
## The floor is the EFFECT's, not the creep's, which is why it comes in: most
## erosion stops at 0 and the Divineshroom line pushes to -3. Measured against
## the creep's own armour so two towers eroding it cannot each drive it to the
## floor separately.
func erode_armor(amount: float, floor_value: float) -> void:
	if !_may_write() || amount <= 0.0 || _creep == null:
		return

	var base: float = 0.0 if _creep.stats == null else float(_creep.stats.armor)
	var lowest: float = floor_value - base
	_armor_eroded = maxf(_armor_eroded - amount, minf(lowest, 0.0))


## Changes armour points for a fixed window. The strongest change wins for as
## long as either would have lasted, so a weaker one cannot cut a stronger one
## short by landing a moment later.
func change_armor(delta: float, seconds: float) -> void:
	if !_may_write():
		return
	if absf(delta) >= absf(_armor_delta) || _armor_delta_left <= EPSILON:
		_armor_delta = delta
	_armor_delta_left = maxf(_armor_delta_left, maxf(seconds, 0.0))


## Makes the creep take more SPELL damage from everything, for a window.
func amplify_spell(amount: float, seconds: float) -> void:
	if !_may_write() || amount <= 0.0:
		return
	_spell_amp = maxf(_spell_amp, amount)
	_spell_amp_left = maxf(_spell_amp_left, seconds)


## Makes the creep take more PHYSICAL damage from everything, for a window.
func amplify_physical(amount: float, seconds: float) -> void:
	if !_may_write() || amount <= 0.0:
		return
	_physical_amp = maxf(_physical_amp, amount)
	_physical_amp_left = maxf(_physical_amp_left, seconds)


## Slows the creep's own attacks and weakens them. Both at once because the one
## thing that does it - Ultimate Titan Vault's aura - does both, and splitting
## them would mean two timers that always expire together.
func weaken_attack(speed_share: float, damage_share: float, seconds: float) -> void:
	if !_may_write():
		return
	if speed_share > 0.0:
		_attack_slow = maxf(_attack_slow, speed_share)
		_attack_slow_left = maxf(_attack_slow_left, seconds)
	if damage_share > 0.0:
		_damage_slow = maxf(_damage_slow, damage_share)
		_damage_slow_left = maxf(_damage_slow_left, seconds)


## Sets the creep alight for `seconds`, dealing `per_second` Spell Damage.
## Sources ADD, unlike everything else here: two fires burn twice as fast.
func burn(per_second: float, seconds: float) -> void:
	if !_may_write() || per_second <= 0.0 || seconds <= 0.0:
		return
	_burn_per_second += per_second
	_burn_left = maxf(_burn_left, seconds)


## Stores poison on the creep and answers how many stacks it now carries.
## Unholy 1 explodes it at a cap, which is the caller's rule rather than this
## one's - here it only accumulates.
func add_poison(damage: float) -> int:
	if !_may_write() || damage <= 0.0:
		return _poison_stacks
	_poison_damage += damage
	_poison_stacks += 1
	return _poison_stacks


## Empties the stored poison and answers what was in it, so the caller can deal
## it. Zero when there was none.
func take_poison() -> int:
	var stored: int = int(_poison_damage)
	_poison_damage = 0.0
	_poison_stacks = 0
	return stored


## Alters the creep's armour type for a window, once per type per creep.
## Answers whether it took - Ultimate Alchemist's card shows the choice, and a
## creep already altered to that type refuses it rather than refreshing.
func alter_armor_type(armor_type: int, seconds: float) -> bool:
	if !_may_write() || _armor_types_used.has(armor_type):
		return false
	_armor_types_used[armor_type] = true
	_armor_type_override = armor_type
	_armor_type_left = maxf(seconds, 0.0)
	return true


## Shuts an effect out of this creep for a while. The caller checks is_immune()
## first; this is what it calls once it has actually fired.
func set_immune(key: String, seconds: float) -> void:
	if _may_write():
		_immunities[key] = maxf(float(_immunities.get(key, 0.0)), seconds)


# --- the tick -------------------------------------------------------------

## Advances every countdown and deals whatever burning is due. Called by the
## creep on the fixed tick, on the authority only.
##
## Answers whether anything is still running, so a creep that has been clean
## for a tick can drop the whole object and go back to costing nothing.
func advance(delta: float) -> bool:
	_stun_left = maxf(0.0, _stun_left - delta)
	_paralyze_left = maxf(0.0, _paralyze_left - delta)
	_armor_delta_left = maxf(0.0, _armor_delta_left - delta)
	_spell_amp_left = maxf(0.0, _spell_amp_left - delta)
	_physical_amp_left = maxf(0.0, _physical_amp_left - delta)
	_attack_slow_left = maxf(0.0, _attack_slow_left - delta)
	_damage_slow_left = maxf(0.0, _damage_slow_left - delta)
	_armor_type_left = maxf(0.0, _armor_type_left - delta)

	_advance_chills(delta)
	_advance_immunities(delta)
	_advance_burn(delta)
	return _is_running()


## A chill that runs out is FORGOTTEN rather than left at zero, so the tower
## that applied it starts accumulating from nothing again next time - which is
## what "up to 40%" means once the creep has walked out of range and back in.
func _advance_chills(delta: float) -> void:
	var expired: Array = []
	for key in _chills:
		var entry: Chill = _chills[key] as Chill
		entry.seconds_left -= delta
		if entry.seconds_left <= 0.0:
			expired.append(key)
	for key in expired:
		_chills.erase(key)


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


## Whether anything at all is still ticking. Permanent erosion counts, because
## dropping the object would hand the creep its armour back.
func _is_running() -> bool:
	if !_chills.is_empty() || !_immunities.is_empty():
		return true
	if _armor_eroded < 0.0 || _poison_stacks > 0 || !_armor_types_used.is_empty():
		return true
	var timers: float = maxf(maxf(_stun_left, _paralyze_left), maxf(_burn_left, _armor_delta_left))
	return maxf(timers, maxf(_spell_amp_left, _physical_amp_left)) > EPSILON


## Only the authority decides what a status did, for the same reason only it
## decides what a hit did. A client's creep is wherever the snapshot puts it,
## so a chill applied here would be a slow the server never agreed to.
func _may_write() -> bool:
	return MatchSession.is_authority()
