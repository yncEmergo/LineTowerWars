class_name TowerStatus
extends RefCounted

## Everything a CREEP can leave on a tower.
##
## The mirror of StatusEffects, which is everything a tower can leave on a
## creep, and it exists because tiers 3 and 4 are where the traffic starts
## going the other way. Four traits in that roster reach into the defender's
## maze rather than only surviving it:
##
##   Wicked Curse       a dying Harpy slows three towers for ten seconds
##   Annihilation Aura  an Obsidian Statue weakens every tower it walks past
##   Mana Drain         a Chaos Warden empties a tower and keeps what it took
##   Volatile Death     a dying Phoenix simply damages them, which needs
##                      nothing here - damage already has a path
##
## DELIBERATELY MUCH SMALLER than StatusEffects, and it should stay that way.
## A creep is the thing this game applies effects to and its status set is a
## wall of them; a tower is on the receiving end of four. Two timed shares and
## a set of "not again for N seconds" gates is the whole of it, and anything
## that wants a fifth should ask whether it is really a tower effect first.
##
## One of these per TOWER, created lazily the first time something touches it.
## A tower nothing has cursed pays nothing: not a tick, not an allocation. The
## overwhelming majority of towers in a match are in that case.
##
## AUTHORITY ONLY, enforced at the door exactly as StatusEffects does it. A
## client draws the tower the server sent it, so a curse applied locally would
## be a slow the server never agreed to. See multiplayer.md 3.4.

## How much of a second an effect has to have left to count. Below this it is
## expiring on this very tick.
const EPSILON: float = 0.0001

## Share taken off this tower's attack SPEED, and how long is left of it. The
## strongest wins for as long as either would have lasted, so a weaker curse
## landing a moment later cannot cut a stronger one short.
var _speed_share: float = 0.0
var _speed_left: float = 0.0
## ability_id of the passive behind the winning value, so the row a client
## draws carries the curse's own icon. Kept beside the value rather than in a
## dictionary because there are two of these, not fourteen.
var _speed_source: int = StatusEntry.NO_SOURCE
## Share taken off this tower's attack DAMAGE, and how long is left. An aura
## keeps this alive by re-applying it every tick, which is what makes walking
## out of one restore the tower a fraction of a second later.
var _damage_share: float = 0.0
var _damage_left: float = 0.0
var _damage_source: int = StatusEntry.NO_SOURCE
## key -> seconds before that effect may touch this tower again. Mana Drain's
## "only once every 7 seconds on the same tower" and anything shaped like it.
var _immunities: Dictionary = {}


## Multiplier on how fast this tower attacks, below 1 being slower.
func attack_speed_ratio() -> float:
	if _speed_left <= EPSILON:
		return 1.0
	return clampf(1.0 - _speed_share, 0.05, 1.0)


## Multiplier on how hard this tower hits, below 1 being weaker.
func attack_damage_ratio() -> float:
	if _damage_left <= EPSILON:
		return 1.0
	return clampf(1.0 - _damage_share, 0.0, 1.0)


## Whether an effect keyed like this may fire on this tower right now.
func is_immune(key: String) -> bool:
	return _immunities.has(key)


## Everything on this tower, as the panel and the wire read it.
##
## The read side, exactly as StatusEffects.entries() is for a creep: the fields
## above are shaped for the simulation, and this flattens them into the one
## record a debuff row and a snapshot both understand. Two of them, because two
## is all a creep can leave on a tower - see the class docstring, and keep it
## that way.
func entries() -> Array[StatusEntry]:
	var list: Array[StatusEntry] = []
	if _speed_left > EPSILON:
		list.append(StatusEntry.make(StatusEntry.Kind.ATTACK_SLOWED,
			_speed_source, _speed_share, _speed_left))
	if _damage_left > EPSILON:
		list.append(StatusEntry.make(StatusEntry.Kind.ATTACK_WEAKENED,
			_damage_source, _damage_share, _damage_left))
	return list


## Slows the tower's attacks for a window. Harpy Windwitch's Wicked Curse.
##
## Takes the SOURCE for the reason every write into StatusEffects does: the row
## the player reads wants the curse's own icon beside it, and the only thing
## that knows which passive is behind this is the passive itself.
func curse_speed(share: float, seconds: float, source: UnitAbility = null) -> void:
	if share <= 0.0 || seconds <= 0.0 || !_may_write():
		return
	if share >= _speed_share || _speed_left <= EPSILON:
		_speed_source = StatusEntry.NO_SOURCE if source == null else source.ability_id
	_speed_share = maxf(_speed_share, share)
	_speed_left = maxf(_speed_left, seconds)


## Weakens the tower's attacks for a window. Obsidian Statue's Annihilation
## Aura, which re-applies a short one every tick it is in range.
func weaken_damage(share: float, seconds: float, source: UnitAbility = null) -> void:
	if share <= 0.0 || seconds <= 0.0 || !_may_write():
		return
	# The strongest in flight wins, and it is re-read from zero once the last
	# one has expired - so two Statues are worth one Statue, and walking out of
	# one restores the tower rather than leaving it at the worse of the two
	# forever. The source moves with the value it belongs to.
	if share >= _damage_share || _damage_left <= EPSILON:
		_damage_share = share
		_damage_source = StatusEntry.NO_SOURCE if source == null else source.ability_id
	_damage_left = maxf(_damage_left, seconds)


## Shuts an effect out of this tower for a while. The caller checks is_immune()
## first; this is what it calls once it has actually fired.
func set_immune(key: String, seconds: float) -> void:
	if seconds <= 0.0 || !_may_write():
		return
	_immunities[key] = maxf(float(_immunities.get(key, 0.0)), seconds)


## Advances every countdown, and answers whether anything is still running - so
## a tower that has been clean for a tick drops the whole object and goes back
## to costing nothing.
func advance(delta: float) -> bool:
	_speed_left = maxf(0.0, _speed_left - delta)
	if _speed_left <= 0.0:
		_speed_share = 0.0
		_speed_source = StatusEntry.NO_SOURCE
	_damage_left = maxf(0.0, _damage_left - delta)
	if _damage_left <= 0.0:
		_damage_share = 0.0
		_damage_source = StatusEntry.NO_SOURCE

	var expired: Array = []
	for key in _immunities:
		var left: float = float(_immunities[key]) - delta
		if left <= 0.0:
			expired.append(key)
		else:
			_immunities[key] = left
	for key in expired:
		_immunities.erase(key)

	return _speed_left > EPSILON || _damage_left > EPSILON || !_immunities.is_empty()


func _may_write() -> bool:
	return MatchSession.is_authority()
