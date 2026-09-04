class_name Creep
extends MobileUnit

## A sent creep walking one player's maze from the spawn zone to the end zone.
##
## Creeps never path individually. The area keeps one distance field to the end
## zone, and a creep reads a whole route out of it once and then commits to it.
##
## Committing is the point. A creep walks the route it set out on however much
## the maze changes around it, and only re-routes at the moment it arrives at
## the first tower actually standing in that route. So building behind a creep
## never redirects it, sealing off the path it was going to take does not turn
## it around early, and a tower placed in front of one only matters when the
## creep reaches it. See game_rules.md.
##
## Ownership is the sender, not the player whose maze it is walking. That is
## already how Unit defines it, and it is what pays the life steal to the right
## player when this creep leaks.
##
## Three kinds of creep walk out of this one class, and the split is in the
## stats rather than in a subclass because everything else about them - health,
## auras, bounty, the leak, the revive - is identical:
##
##   ordinary   commits to a route and walks it, as described above
##   flying     ignores the maze entirely and flies straight down the lane at a
##              fixed height, reachable only by a tower that can hit air
##   attacker   goes after the towers instead of past them, and is the one
##              creep its owner can command. Left alone it walks to the nearest
##              tower and destroys it, and never advances on its own - so it
##              only ever leaks because somebody told it to
##
## Not controllable otherwise: a creep can be clicked and inspected but takes
## no orders, per game_rules.md.

## Emitted when the creep reaches the end zone, before the leak is resolved.
signal reached_end()

## How many points of walked route a creep remembers, and how far apart they
## are recorded. Together that is roughly the last 24 world units, far more
## than a tower footprint is wide.
const TRAIL_LIMIT: int = 96
const TRAIL_SPACING: float = 0.25

## How long a creep may fail to get closer to its next step before it gives up
## and re-reads the route from where it actually stands.
const STALL_SECONDS: float = 1.5

## Step count reported by a creep that has no route at all, large enough that it
## always sorts behind every creep that does. See steps_to_exit().
const NO_ROUTE_STEPS: int = 1 << 24

## How often the auras standing around a creep are re-read, in seconds. The
## same beat an attacker re-picks the tower it is marching on, for the same
## reason: neither answer can change fast enough for a quarter second to show.
const AURA_REFRESH_SECONDS: float = 0.25

## How fast a flyer climbs to and settles at its cruising height, in world
## units per second. Purely visual, since nothing is ever measured vertically.
const CLIMB_SPEED: float = 2.0

## Stands for "no cell", for the goal of a route that does not exist. Negative
## on both axes, so it can never be a cell the grid really holds.
const OFF_GRID: Vector2i = Vector2i(-1, -1)

## The distance below which two points in a crowding test are the same point:
## two creeps with no direction between them to be pushed apart along, and two
## ordered points that are the same order. See _away_from and has_arrived_at.
const CROWD_MIN_AXIS: float = 0.0001

## How much further apart than their personal space two creeps may stand and
## still count as touching. Slack rather than an exact test because _hold_apart
## parks a pair at exactly that distance, and floating point puts them a hair
## either side of it. See _is_crowd_blocked.
const CROWD_CONTACT_SLACK: float = 1.1

## Whether this creep stopped short of its ordered point because the crowd was
## already standing on it, and the point it stopped short of. Cleared by the
## next walk it is given - see has_arrived_at.
var _crowd_settled: bool = false
var _crowd_settled_point: Vector3 = Vector3.ZERO

## Route the creep committed to, as internal cells in walking order.
var _path: Array[Vector2i] = []
## Which cell of that route the creep is currently walking towards.
var _path_index: int = 0
## Route to a COMMANDED point, and which cell of it the creep is walking
## towards. Kept apart from _path above rather than sharing it, because the two
## answer different questions and would overwrite each other: _path is the way
## to the exit and is what steps_to_exit reports to every tower's target
## ranking, and this is the way to wherever somebody sent the creep.
var _order_path: Array[Vector2i] = []
var _order_index: int = 0
## Internal cell _order_path was planned to, or OFF_GRID when there is no route
## in hand. What keeps a CHASE affordable: an attack order re-aims its walk at
## its quarry every single tick, and every one of those that lands in the cell
## already routed to reads the route in hand instead of sweeping the grid
## again. See _plan_order_route.
var _order_goal: Vector2i = OFF_GRID
## Route already covered, newest last, for being set back along it.
var _trail: Array[Vector3] = []

## Closest the creep has been to its current step, and how long it has been no
## closer than that.
var _stall_distance: float = INF
var _stall_elapsed: float = 0.0

## Passives read off this creep's stats once, since they are asked on every hit.
var _passives: Array[CreepPassive] = []
## Whether any of this creep's passives gives out an aura, read off them once.
## Almost never true, which is the whole value of asking: an area's aura sweep
## visits the creeps that emit one instead of every creep standing nearby.
var _emits_aura: bool = false
## Once-only passives that have already fired, e.g. a revive that was used up.
## Per creep, because the passive resource is shared by every creep of the type
## and so may hold no state of its own.
var _spent: Dictionary = {}
## What the auras currently in range are worth, all refreshed together on a
## slow timer. Auras do not stack, so each of these is the BEST one in range
## rather than the sum, and every creep grants its own to itself.
var _aura_armor: int = 0
var _aura_move_ratio: float = 1.0
var _aura_attack_ratio: float = 1.0
var _aura_damage_ratio: float = 1.0
var _aura_regen: float = 0.0
## Whether any of this creep's passives says towers should ignore it. Read once
## rather than per target scan, since a creep cannot gain a passive mid-walk.
var _skittering: bool = false
## Whether this creep walks THROUGH towers, reading none of the occupancy grid
## and going straight down the lane. Half of what Ethereal means, and read once
## with the rest for the same reason.
var _ethereal: bool = false
## Whether this creep is deaf to every aura, its own included. One creep in the
## roster is - see CreepPassive.ignores_auras.
var _aura_deaf: bool = false
## The best chance any of its passives gives it of dodging, and the shortest
## reach a tower must have for that to apply. Both 0 for everything but one
## creep, and read once so a target scan pays nothing for the question.
var _dodge_chance: float = 0.0
## The tower an unordered attacker creep is marching on, and the countdown to
## re-picking it. Null for every creep that is not an attacker.
var _march_target: Building = null
var _march_elapsed: float = 0.0
## Starts at the interval so the very first physics frame reads the auras
## rather than leaving a freshly spawned creep unbuffed for a quarter second.
##
## That head start is also why the sweep has to be PHASED afterwards: every
## creep begins its clock full, so a wave that spawned on one tick came due on
## one tick forever after. See _aura_phase.
var _aura_elapsed: float = AURA_REFRESH_SECONDS
## Whether this creep's sweep has been spread off the tick it spawned on yet.
var _aura_phased: bool = false
## How many HEAVY physical hits have landed on this creep over its whole life -
## it only ever grows, and nothing resets it: not a heal, not a revive, and not
## being recycled into the next player's maze, which deliberately keeps the
## health the creep arrived with and so should keep what has been worn off it
## too. Hardened Skin reads its eroded armour back out of this, which is what
## lets that passive stay the shared stateless resource every other one is.
var _heavy_hits_taken: int = 0
## What counts as heavy, read off this creep's own passives once. 0 for every
## creep in the game but one, and those pay nothing for the question.
var _heavy_hit_threshold: float = 0.0
## The mana pool one of this creep's traits runs on, or null for a creep whose
## stats give it none - which is nearly all of them. Built once on spawn, so a
## creep with no mana trait allocates nothing and ticks nothing. See CreepMana.
var _mana: CreepMana = null
## Clocks owned by this creep's passives, keyed by the passive applying one.
##
## Here rather than on the passive for the reason _spent is: one
## bombardment.tres is every Siege Engine on the field, so a countdown stored
## there would be all of theirs at once. Sparse - a creep with no timed passive
## never puts an entry in it. See advance_passive_clock().
var _passive_clocks: Dictionary = {}
## Everything an elemental tower has left on this creep - chill, stun, eaten
## armour, poison, burning - or null while nothing has touched it.
##
## Created on demand and DROPPED again the moment it runs dry, so the ordinary
## case of a creep walking past towers that give no status costs nothing at
## all. See Combat/StatusEffects.gd.
var _status: StatusEffects = null
## Seconds left before a delayed revive brings this creep back, or -1 when it
## is not down at all. A down creep is out of health but not gone.
var _revive_countdown: float = -1.0
## Share of its maximum health it will come back with.
var _revive_ratio: float = 0.0
## The shaft of light standing over the spot while it waits.
var _revive_light: ReviveLight = null
## What has hurt this creep and by how much, for the one trait that resists
## whichever damage type has hurt it most. Null for every other creep, and
## built by the passive rather than here - see CreepWarding.
var _warding: CreepWarding = null
## The dive this creep is in the middle of, or null - which is every creep in
## the game but a Phoenix that has just been aimed. See CreepDive.
var _dive: CreepDive = null

var _creep_stats: CreepStats:
	get:
		return stats as CreepStats


func _ready() -> void:
	# BEFORE super(), which is where a unit fills its health bar: a creep's
	# real ceiling is worked out from its passives - one of them converts its
	# armour into health - so a creep that had not collected them yet would be
	# started at the number in its stats file and spend its whole life short of
	# its own maximum. See max_health() below.
	if stats != null && _creep_stats == null:
		Log.err("Creep needs CreepStats but got plain UnitStats", name)
	_collect_passives()
	super()
	# Null for nearly every creep, which is what keeps a pack of Sheep from
	# carrying a pool none of them can use. See CreepMana.
	_mana = CreepMana.of(_creep_stats)
	if is_flying():
		# Placed at cruising height rather than climbing from the floor, so a
		# flyer is never briefly a ground unit standing inside a tower.
		global_position.y = _creep_stats.fly_height
		reset_physics_interpolation()


## Places a freshly sent creep. sender_id is the player who paid for it, which
## is not the owner of the maze it walks once sending across areas exists.
func spawn(sender_id: int, target_area: PlayerArea, world_pos: Vector3) -> void:
	setup(sender_id, target_area)
	global_position = Vector3(world_pos.x, _ground_height(), world_pos.z)
	# Placed, not moved: without this the interpolator would streak it in from
	# wherever it was last drawn, which for a fresh creep is the world origin.
	reset_physics_interpolation()
	_trail = [global_position]
	_replan()
	# After the creep is placed and routed, so a trait that reads its own
	# maximum health or hands it a shield is looking at a finished creep. Only
	# a fresh SEND reaches here - a recycled creep goes through _recycle_into
	# and must not be handed a second shield for leaking.
	for passive in _passives:
		passive.on_spawn(self)


## Creeps take no orders, so a right click on one does nothing and a selection
## box never picks it up. See game_rules.md.
func is_controllable() -> bool:
	return _creep_stats != null && _creep_stats.is_attacker


func body_radius() -> float:
	if _creep_stats == null:
		return 0.18
	return _creep_stats.body_radius


## Only towers that can hit air may target a flyer, and no tower ever blocks
## one: a flyer reads none of the occupancy grid.
func is_flying() -> bool:
	return _creep_stats != null && _creep_stats.is_flying


## Whether towers should ignore this creep while anything else is in range.
## Cached off its passives, see SkitteringPassive.
func is_skittering() -> bool:
	return _skittering


## Whether this creep walks through towers rather than around them. Ethereal,
## and nothing else in the roster.
func is_ethereal() -> bool:
	return _ethereal


## Whether this creep reads the maze at all. A flyer and an ethereal creep both
## go straight down the lane and neither has a route to walk, so everything
## that asks about one asks this rather than naming either.
func ignores_maze() -> bool:
	return is_flying() || _ethereal


## The chance an attack from a tower reaching this far simply misses, 0 to 1.
## The BEST passive wins rather than the sum, so two dodges on one creep could
## never make it untouchable.
func dodge_chance_against(attack_range: float) -> float:
	if _dodge_chance <= 0.0:
		return 0.0
	var best: float = 0.0
	for passive in _passives:
		best = maxf(best, passive.dodge_chance(attack_range))
	return best


## An attacker creep takes orders and goes after towers; nothing else does
## either. Both follow from the same stats flag, so they can never disagree.
func is_attacker() -> bool:
	return _creep_stats != null && _creep_stats.is_attacker


## Height this creep's origin sits at: cruising height for a flyer, the ground
## for everything else. Asked wherever a position is written rather than
## assumed zero, which is what keeps a flyer off the floor after a leak.
func _ground_height() -> float:
	return _creep_stats.fly_height if is_flying() else 0.0


## The ledger of what has hurt this creep and by how much, created the first
## time something asks for it.
##
## Lazily like the status set and for the same reason: one trait in the roster
## reads it and every other creep in a maze should allocate nothing. The
## passive fills it and reads it back; nothing here knows what it is for.
func warding() -> CreepWarding:
	if _warding == null:
		_warding = CreepWarding.new()
	return _warding


## Its own speed, with whatever aura is standing over it and whatever a tower
## has chilled it with folded in.
##
## The two multiply rather than one winning: an aura is the pack helping itself
## and a chill is a tower fighting it, and a creep that is both buffed and
## slowed should end up somewhere between the two.
## How fast this creep is actually travelling right now, in cells per second.
##
## The public face of _move_speed() below, and the only thing that needs one:
## one trait in the roster picks the SLOWEST creep near it, which is a question
## about what a creep is doing rather than about what its file says. See
## WindRushPassive.
## Whether the creep is in the middle of an aimed dive, which suspends
## everything else it would be doing. One creep in the roster can be.
func is_diving() -> bool:
	return _dive != null


## Starts a dive along the direction of a point. Answers whether one really
## began, so the ability can hold its cooldown for an order that was aimed at
## the spot the creep is standing on.
##
## The numbers all come from the ABILITY rather than from here, which is the
## same split every other trait follows: the resource owns what a dive is worth
## and the creep owns the one in progress. See DiveAbility.
func begin_dive(point: Vector3, reach: float, seconds: float,
		damage_per_second: float, damage_radius: float) -> bool:
	var dive: CreepDive = CreepDive.toward(self, point, reach, seconds,
		damage_per_second, damage_radius)
	if dive == null:
		return false

	# A dive replaces whatever the creep was doing outright: a Phoenix marching
	# on a tower and then aimed somewhere else is aimed somewhere else.
	if order_queue != null:
		order_queue.clear()
	_march_target = null
	_dive = dive
	return true


## Calls a dive off where it stands and hands the creep its armour back.
##
## The armour is the SOURCE'S own reward for stopping one (unit_data.md 6.6),
## and it is what makes cancelling a real decision rather than a mistake being
## undone: a Phoenix that has been shot at all the way down a maze can trade
## the rest of its dive for the armour a maze has eaten off it.
##
## Answers whether anything was actually called off, so a plain Stop on a
## Phoenix that is not diving says nothing about armour.
func cancel_dive() -> bool:
	if _dive == null:
		return false

	_dive = null
	var effects: StatusEffects = status_or_null()
	if effects != null:
		# In FULL rather than by a number: there is no ceiling to overshoot,
		# since restore_armor never takes the creep above what it started with.
		effects.restore_armor(INF)
	return true


## A dive writing the creep where the arc says it is. Only CreepDive calls it,
## and it is the one place in the game a creep position is set rather than
## stepped towards - see that class for why.
func dive_to(point: Vector3, facing: Vector3) -> void:
	global_position = area.clamp_point(point) if area != null else point
	global_position.y = _ground_height()
	if facing.length_squared() > 0.0001:
		face_instantly(global_position + facing)


## A fresh walk is a fresh answer, so whatever the creep settled for last time
## is forgotten here rather than being carried into the new order.
##
## It also takes a ROUTE, so a commanded creep goes round the maze instead of
## pressing into it - the same pathfinding one walking to the exit reads, asked
## for a point somebody picked instead of for the end zone.
##
## Planned only when the destination lands in a DIFFERENT CELL from the one
## already routed to. An attack order re-aims its walk at its quarry on every
## tick, and sweeping the grid twenty times a second for a tower that has not
## moved would be work for nothing.
func move_to(world_target: Vector3) -> void:
	_crowd_settled = false
	super(world_target)

	# Nothing that ignores the maze reads the occupancy grid at all, so there
	# is nothing for it to route around and the straight line IS the route.
	if area == null || ignores_maze():
		_clear_order_route()
		return

	var goal: Vector2i = area.world_to_internal_cell(_target_position)
	if goal != _order_goal:
		_plan_order_route(goal)


## A creep that stopped short of an ordered point because the crowd was already
## standing on it counts as having ARRIVED there. It is as near as the rule
## will ever let it get, and the point it was aimed at is now under somebody.
##
## Without this an attack-move never finishes: it asks this every tick to
## decide whether to keep walking, so the creep is sent back at a point it
## cannot reach, gives up again, and the chain behind it never starts.
func has_arrived_at(world_point: Vector3) -> bool:
	if super(world_point):
		return true
	if !_crowd_settled || area == null:
		return false

	# The point it settled for and no other: this is asked about whatever a
	# task happens to be aimed at, and having given up on one spot says nothing
	# about any other. Clamped on the way in for the reason the base class
	# clamps - an order past the edge is a point the creep can never stand on.
	var offset: Vector3 = area.clamp_point(world_point) - _crowd_settled_point
	offset.y = 0.0
	return offset.length() <= CROWD_MIN_AXIS


## Halting a creep also calls off a dive, which is what makes Stop the way a
## player ends one - and what pays the armour back for doing so.
##
## The route goes with the walk. A creep told to go somewhere it has already
## been sent must plan again from where it now stands, and holding a spent
## route would answer that question with the old one.
func stop() -> void:
	super()
	_clear_order_route()
	cancel_dive()


func current_move_speed() -> float:
	if _creep_stats == null:
		return 0.0
	if !MatchSession.is_authority():
		# A client has neither the StatusEffects nor the aura scan, and both are
		# in the records the server sent for this creep. Its own ceiling on
		# being slowed is not, and need not be: that follows from its passives,
		# which every machine has. Same split armor_value() makes.
		return _creep_stats.move_speed * StatusEntry.move_speed_ratio_in(
			StatusEntry.for_unit(self), _slow_ceiling())
	return _move_speed()


## The most this creep may ever be slowed, whatever has piled up on it, from
## its own passives. 1.0 is no ceiling, which is every creep but one.
func _slow_ceiling() -> float:
	var ceiling: float = 1.0
	for passive in _passives:
		ceiling = minf(ceiling, passive.max_slow_share())
	return ceiling


func _move_speed() -> float:
	var ratio: float = 1.0 if _status == null else _status.move_ratio()
	var hasted: float = 1.0 if _status == null else _status.haste_ratio()
	return _creep_stats.move_speed * _aura_move_ratio * ratio * hasted


## How hard this creep's own attack lands, which only the attacker creeps have
## anything for. Its packmates' aura, whatever a tower has weakened it with,
## and whatever its own passives say, all multiplied - the same shape
## attack_speed_ratio() above has.
func attack_damage_ratio() -> float:
	var own: float = 1.0
	for passive in _passives:
		own *= passive.attack_damage_ratio(self)
	if !MatchSession.is_authority():
		return own * StatusEntry.attack_damage_ratio_in(StatusEntry.for_unit(self))
	var weakened: float = 1.0 if _status == null else _status.attack_damage_ratio()
	return _aura_damage_ratio * weakened * own


## Attack speed is an aura's business too, and only an attacker creep has an
## attack for it to act on. See Combat/AttackComponent.gd.
func attack_speed_ratio() -> float:
	if !MatchSession.is_authority():
		return StatusEntry.attack_speed_ratio_in(StatusEntry.for_unit(self))
	var slowed: float = 1.0 if _status == null else _status.attack_speed_ratio()
	return _aura_attack_ratio * slowed


## An ordered move means MOVE: the creep walks and does not stop to fight, the
## way it does in any RTS. An attack order clears the move rather than fighting
## it, see AttackAbility.
func can_attack() -> bool:
	if _status != null && _status.is_held():
		return false
	return super() && !is_moving()


## Route steps left to walk, which is how towers rank targets: fewer steps means
## closer to leaking, so the lowest number is the creep "first in line".
##
## Read off the route the creep committed to rather than off the area's field,
## because that is the way this creep is actually going. A creep that took the
## long way round genuinely is further from the exit than the field would say.
##
## A creep with no route left counts as furthest away, so one standing stalled
## can never jump to the front of every tower's list at once.
func steps_to_exit() -> int:
	# Nothing that ignores the maze has a route to read, so it answers with the
	# rows it has left to cross - which is the same question in the same units.
	if ignores_maze():
		return _rows_to_exit()
	if _path.is_empty() || _path_index >= _path.size():
		return NO_ROUTE_STEPS
	return _path.size() - _path_index


## Internal rows between this creep and the end zone, never below zero.
func _rows_to_exit() -> int:
	if area == null:
		return NO_ROUTE_STEPS
	var row: int = area.world_to_internal_cell(global_position).y
	return maxi(0, area.build_zone_row_end() - row)


## Walks back along the route this creep already covered and drops it on the
## most recent point that is still clear.
##
## A tower going up on a creep therefore costs it progress, rather than pushing
## it sideways to the nearest gap: sideways would often be past the very wall
## the creep was walking around, turning a tower into a free shortcut for it.
func set_back_along_path() -> void:
	for index in range(_trail.size() - 1, -1, -1):
		if !area.is_point_free(_trail[index]):
			continue
		var point: Vector3 = _trail[index]
		# Everything after this point was walked into the new building, so it
		# is no longer route the creep has covered.
		_trail.resize(index + 1)
		_teleport_to(point)
		return

	# Nothing in the history is clear, which a creep built on in its first few
	# frames can hit. The nearest gap is all that is left.
	_teleport_to(area.nearest_free_point(global_position))


## Teleports this creep back to a point it was standing on earlier.
##
## For anything that takes a creep's PROGRESS rather than its health: the point
## is remembered when the effect starts and collected on seconds later, so what
## the creep loses is exactly the ground it covered in between.
##
## A DIFFERENT QUESTION from set_back_along_path above, and mixing the two up
## costs the whole effect. That one asks "something has been built on top of
## me, where is the last place I fitted" and walks the trail for the most
## recent point still clear - which, for a creep that is simply walking, is
## where it is standing right now. This one already knows where it is going and
## only has to check that the spot still exists.
##
## It also works for a FLYER, which the trail walk cannot: a flyer records no
## trail at all, so asking it to walk one back would send it to wherever it
## spawned.
func send_back_to(point: Vector3) -> void:
	var destination: Vector3 = point
	if !area.is_point_free(destination):
		# Something went up there while the creep was walking away from it.
		# The nearest gap keeps it near where it was meant to land rather than
		# cancelling the effect, and a creep put inside a tower would be stuck.
		destination = area.nearest_free_point(destination)
	_teleport_to(destination)
	# Everything between here and where it was taken from is ground it has to
	# cover again, so it is no longer route this creep has walked.
	_trail = [global_position]


# --- Passives -----------------------------------------------------------

## Reads the creep's passives off its stats once. Cached because they are asked
## on every hit and every frame, not because the list is expensive to build.
func _collect_passives() -> void:
	_passives.clear()
	if _creep_stats == null:
		return

	_skittering = false
	_ethereal = false
	_aura_deaf = false
	_emits_aura = false
	_dodge_chance = 0.0
	_heavy_hit_threshold = 0.0
	for entry in _creep_stats.abilities:
		var passive: CreepPassive = entry as CreepPassive
		if passive != null:
			_passives.append(passive)
			_skittering = _skittering || passive.is_skittering()
			_ethereal = _ethereal || passive.is_ethereal()
			_aura_deaf = _aura_deaf || passive.ignores_auras()
			_emits_aura = _emits_aura || passive.grants_aura()
			# Asked with an unreachable range, so what comes back is the BEST
			# this creep could ever dodge - a gate rather than an answer. The
			# real question is asked with the attacker's own reach, and only
			# on a creep this said yes for. See dodge_chance_against().
			_dodge_chance = maxf(_dodge_chance, passive.dodge_chance(INF))
			# The FIRST passive to name one wins, the same rule an attack's
			# damage type override follows: two passives disagreeing about what
			# counts as a heavy hit is an authoring mistake rather than
			# something to resolve on every hit.
			if _heavy_hit_threshold <= 0.0:
				_heavy_hit_threshold = passive.heavy_hit_threshold()


## Whether a once-only passive has already fired on THIS creep.
##
## The record lives here rather than on the passive because the passive is one
## shared resource standing in for every creep of its type: a flag stored on it
## would be spent for all of them the moment any single one used it.
func has_spent(passive: CreepPassive) -> bool:
	return _spent.has(passive)


## How many times a once-only passive has fired on THIS creep.
##
## A count rather than a flag, because one trait in the roster has two separate
## uses of its own - Elune's Grace wards on the first hit and again at half
## health - and two records for one passive would otherwise want two keys
## somebody has to invent and keep unique.
func spend_count(passive: CreepPassive) -> int:
	return int(_spent.get(passive, 0))


func spend(passive: CreepPassive) -> void:
	_spent[passive] = spend_count(passive) + 1


## Whether this creep is dead but not yet gone: out of health and waiting on a
## revive.
##
## A down creep does not move, is not shot at - it has no health, so every
## target search already skips it - grants and receives no auras, is walked
## straight through, and cannot be clicked. It is only still in the tree
## because something is going to stand it back up.
func is_down() -> bool:
	return _revive_countdown >= 0.0


## Puts the creep down for a while, to be brought back when the wait runs out.
##
## Called from a passive's on_death, so it must not free anything: the creep
## has to survive the call that would otherwise have removed it. A delay of
## zero or less brings it straight back, which keeps an instant revive possible
## without a second path through here.
func begin_revive(delay: float, health_ratio: float) -> void:
	_revive_ratio = clampf(health_ratio, 0.0, 1.0)

	if delay <= 0.0:
		_finish_revive()
		return

	_revive_countdown = delay
	# Hiding the root takes the body, the nose, the selection ring and the
	# health bar with it, so nothing has to be listed here by name. The light
	# is parented to the effects root rather than to this creep, which is what
	# keeps it visible while the creep is not.
	visible = false
	_show_revive_light(delay)


## Puts a CLIENT's copy of this creep down, or stands it back up.
##
## begin_revive() and _finish_revive() are SIMULATION and run on the authority
## alone, so without this a client was never told any of it happened: the creep
## stayed on screen, stood still with an empty health bar for the whole wait and
## then walked off again, with no light over the spot. Everything the server
## knew was right; none of it was drawn.
##
## Costs one BIT on the wire, not a field - see ReplicationService.FLAG_DOWN.
## How long the wait lasts is not sent at all, because the creep's own passive
## is authored data this machine already has.
##
## Idempotent: the snapshot repeats the flag twenty times a second and only the
## EDGES do anything.
func set_replicated_down(down: bool) -> void:
	if down == is_down():
		return

	if down:
		# Held at the authored length rather than counted down, since
		# _advance_revive is behind the authority gate and never runs here. It
		# is what makes is_down() true, which the click test below reads too.
		_revive_countdown = _down_seconds()
		visible = false
		_show_revive_light(_revive_countdown)
		return

	_revive_countdown = -1.0
	visible = true
	if is_instance_valid(_revive_light):
		_revive_light.finish()
	_revive_light = null


## The longest any of this creep's passives puts it down for. 0 for every creep
## that cannot be revived, which is all but one of them.
func _down_seconds() -> float:
	var longest: float = 0.0
	for passive in _passives:
		longest = maxf(longest, passive.down_seconds())
	return longest


## A creep waiting on a revive cannot be clicked: it is not on screen, and a
## panel describing something invisible reads as a bug rather than as a corpse.
func selection_radius() -> float:
	if is_down():
		return 0.0
	return super()


## Counts the wait down. Runs instead of everything else a creep normally does,
## since a down creep neither walks nor takes part in anything.
func _advance_revive(delta: float) -> void:
	_revive_countdown -= delta
	if _revive_countdown <= 0.0:
		_finish_revive()


func _show_revive_light(seconds: float) -> void:
	var root: Node3D = References.effects_root
	if root == null:
		return

	_revive_light = ReviveLight.new()
	_revive_light.name = "ReviveLight"
	root.add_child(_revive_light)
	_revive_light.place_at(global_position)
	_revive_light.play(seconds)


## Stands the creep back up.
##
## Deliberately not heal(), which refuses to touch a unit that is already down -
## that is what keeps a stray acolyte burst from quietly doing a revive's job.
##
## The route it committed to is kept rather than replanned. A tower built over
## it while it lay there is handled the same way it would be for any creep: the
## next step is tested before it is walked, and only then does it re-route.
func _finish_revive() -> void:
	_revive_countdown = -1.0
	visible = true
	_reset_stall()

	if is_instance_valid(_revive_light):
		_revive_light.finish()
	_revive_light = null

	var restored: float = float(max_health()) * _revive_ratio
	_set_health(maxf(1.0, restored))
	Log.debug("Creep revived", {"creep": name, "health": display_health()})
## This creep's passives, whole.
##
## Handed out rather than answered one question at a time, because two things
## want the whole list: a creep reading the auras standing around it asks each
## of THOSE creeps' passives everything at once, and the status set asks its
## own creep's for the resistances it has to apply.
##
## Every passive is offered, not only the ones that grant something: a passive
## with no aura answers each question with its neutral default, and filtering
## here would mean knowing which of them count.
func passives() -> Array[CreepPassive]:
	return _passives


## Its own armour, whatever the auras standing around it are worth, whatever
## its own passives have worn off it, and whatever an elemental tower has eaten
## out of it.
func armor_value() -> int:
	var own: int = super() + _passive_armor_delta()
	if !MatchSession.is_authority():
		# A client has neither the StatusEffects nor the aura scan, and both of
		# them are in the records the server sent for this creep. Its own
		# passives are not, and need not be: they follow from its stats, which
		# every machine has.
		return own + StatusEntry.armor_delta_in(StatusEntry.for_unit(self))
	var eaten: int = 0 if _status == null else _status.armor_delta()
	return own + _aura_armor + eaten


## Its authored ceiling, with whatever its own passives do to it.
##
## Only one trait in the roster moves it - Bone Shield converts every point of
## base armour into 4% more health - and it has to be answered HERE rather than
## in the stats file, because the answer is worked out from another stat.
func max_health() -> int:
	var ratio: float = 1.0
	for passive in _passives:
		ratio *= passive.max_health_ratio(self)
	if is_equal_approx(ratio, 1.0):
		return super()
	return maxi(1, int(round(float(super()) * ratio)))


## What this creep's OWN passives have done to its armour, which so far is
## Hardened Skin wearing away and nothing else.
##
## Summed rather than best-of, on the same reasoning the resistances are: the
## best-of rule belongs to AURAS, which are what several creeps standing
## together would otherwise stack. These are the creep's own and there is only
## ever one of each.
func _passive_armor_delta() -> int:
	var delta: int = 0
	for passive in _passives:
		delta += passive.armor_delta(self)
	return delta


## How many single physical hits have landed on this creep at or above its own
## heavy-hit threshold. Read by a passive whose effect is measured in them, see
## HardenedSkinPassive.
func heavy_hits_taken() -> int:
	return _heavy_hits_taken


## Counts the hit above, then lets the ordinary pipeline run.
##
## ONE HIT AT A TIME, and that is the whole rule: what is counted is whether
## THIS blow landed hard enough, never how much has added up. A creep whose
## armour only yields to heavy hits is not worn down by a thousand small ones,
## which is what makes stripping it a question of bringing the right towers
## rather than of waiting.
##
## Measured as the health the creep ACTUALLY LOST rather than as the raw amount
## the attacker rolled, so every armour point, every resistance and every
## amplification standing on the creep has already been applied - a hit that is
## heavy on paper and lands for a scratch does not count. It is also the only
## one of the two readings that is the number the player watches leave the
## health bar. Read off the health rather than by resolving the hit a second
## time, because resolve_damage() is what a tooltip quotes a matchup with and
## must stay free of side effects.
##
## Nothing is recorded on a client, a hit on an invulnerable unit or a creep
## already down, because in all three cases no health moves - the guards are
## super()'s and this needs none of its own. A revive that fires inside the same
## call restores health, so the floor keeps the killing blow from reading as a
## heal.
func take_damage(amount: int, damage_type: DamageTable.DamageType,
		is_aoe: bool = false) -> void:
	var before: float = current_health
	super(amount, damage_type, is_aoe)

	var lost: float = maxf(0.0, before - current_health)
	# Nothing landed, so nothing happened: a hit on a client, on an
	# invulnerable creep or on one already down reaches here having moved no
	# health, and neither the counter nor the passives below may act on it.
	if lost <= 0.0:
		return

	for passive in _passives:
		passive.on_damage_taken(self, lost, damage_type)

	if _heavy_hit_threshold <= 0.0 || DamageTable.is_spell(damage_type):
		return
	if lost >= _heavy_hit_threshold:
		_heavy_hits_taken += 1


## Everything on this creep: what towers have left on it, and what its
## packmates' auras are lending it while it walks beside them. See
## Unit.status_entries() for why this is virtual.
##
## The AURA HALF is the part that was on no wire at all before, which is the
## gap the armour line has carried a note about since it was written: a creep
## standing in one read low on a client because nothing told it. The four
## numbers an aura moves are the same four a technology disc moves on a tower,
## so they go out as the same records.
##
## They carry NO SOURCE, unlike everything else here. An aura value is a
## maximum taken over every passive of every packmate in range, and which of
## them won is not kept - so a row draws its title's first letter rather than an
## icon. Worth a per-aura source field on this class the day that reads badly;
## it is not worth five today.
func status_entries() -> Array[StatusEntry]:
	var list: Array[StatusEntry] = []
	if _status != null:
		list.append_array(_status.entries())

	if _aura_armor > 0:
		list.append(StatusEntry.make(StatusEntry.Kind.ARMOR_LENT,
			StatusEntry.NO_SOURCE, float(_aura_armor), StatusEntry.PERMANENT))
	if _aura_move_ratio > 1.0:
		list.append(StatusEntry.make(StatusEntry.Kind.HASTED,
			StatusEntry.NO_SOURCE, _aura_move_ratio - 1.0, StatusEntry.PERMANENT))
	if _aura_attack_ratio > 1.0:
		list.append(StatusEntry.make(StatusEntry.Kind.ATTACK_HASTENED,
			StatusEntry.NO_SOURCE, _aura_attack_ratio - 1.0, StatusEntry.PERMANENT))
	if _aura_damage_ratio > 1.0:
		list.append(StatusEntry.make(StatusEntry.Kind.ATTACK_EMPOWERED,
			StatusEntry.NO_SOURCE, _aura_damage_ratio - 1.0, StatusEntry.PERMANENT))
	if _aura_regen > 0.0:
		list.append(StatusEntry.make(StatusEntry.Kind.REGENERATING,
			StatusEntry.NO_SOURCE, _aura_regen, StatusEntry.PERMANENT))
	return list


## Its own armour type, unless something has altered it. Ultimate Alchemist is
## the only thing that does, and only for a few seconds at a time.
func armor_type_value() -> UnitStats.ArmorType:
	if !MatchSession.is_authority():
		# A tower's alteration is on the wire; the creep's own trait below is
		# not and does not need to be. Asked here rather than in the panel, so
		# resolve_damage's tooltip and the Armor line cannot disagree.
		return StatusEntry.armor_type_in(
			StatusEntry.for_unit(self), _own_armor_type())
	if _status != null:
		var altered: int = _status.armor_type_override()
		if altered >= 0:
			return altered as UnitStats.ArmorType
	return _own_armor_type()


## What this creep would count as with nothing altering it: its own trait, or
## the type on its stats.
##
## Split out because both branches above need it - a tower's alteration WINS
## over the creep's own trait, so the trait is the fallback either way, and the
## client's branch has to hand that same fallback to armor_type_in. A Kodo that
## has gone into War Stance permanently counts as Hero armour, and a few
## seconds of an Alchemist's choice on top of that is exactly what the
## Alchemist is for.
func _own_armor_type() -> UnitStats.ArmorType:
	for passive in _passives:
		var wanted: int = passive.armor_type_override(self)
		if wanted >= 0:
			return wanted as UnitStats.ArmorType
	return super.armor_type_value()


## The mana pool this creep runs a trait on, or null when it has no such trait.
##
## Unlike status(), this never creates one on demand: whether a creep has mana
## at all is decided by its stats and cannot change mid-match, so a caller
## asking for a pool that is not there is asking the wrong creep.
func mana() -> CreepMana:
	return _mana


## The mana pool, drawn under the portrait as a bar and a number exactly as a
## tower's is. Null for every creep without one, which hides the line.
##
## Panel only, deliberately: a creep carries no worldspace resource bar. A
## tower's mana bar hangs over one building the player placed, where a bar over
## every creep in a pack of three would be a row of blue lines walking down the
## lane.
func secondary_resource() -> TowerResource:
	# A SHIELD wins over a pool, because a creep behind one is not dying and
	# that is by far the more important thing about it. Nothing in the roster
	# carries both, so the order is a rule rather than a choice being made.
	var ceiling: float = shield_maximum()
	if ceiling > 0.0:
		return TowerResource.shield(
			int(round(shield_points())), int(round(ceiling)))
	if _mana == null:
		return null
	return _mana.as_resource()


## Damage standing in front of this creep's health. Its own pool on the
## authority, and whatever the server last sent on a client - see Unit.
func shield_points() -> float:
	if !MatchSession.is_authority():
		return super()
	return 0.0 if _status == null else _status.shield_points()


func shield_maximum() -> float:
	if !MatchSession.is_authority():
		return super()
	return 0.0 if _status == null else _status.shield_max()


## Advances a clock one of this creep's passives owns and reports whether it
## came round, having already taken the interval back off it.
##
## The passive states the interval and reads the answer; the count lives here,
## because the passive is one shared resource standing in for every creep of
## its type. The remainder is CARRIED rather than reset, so a four second
## bombardment really does fire every four seconds instead of drifting by up to
## a tick each time.
func advance_passive_clock(source: UnitAbility, interval: float, delta: float) -> bool:
	if source == null || interval <= 0.0:
		return false

	var elapsed: float = float(_passive_clocks.get(source, 0.0)) + delta
	if elapsed < interval:
		_passive_clocks[source] = elapsed
		return false

	_passive_clocks[source] = elapsed - interval
	return true


## The status effects on this creep, created on the spot if it has none yet.
##
## Only ever called by something that is ABOUT to apply one, which is why it
## always answers with an object: a caller that has to check for null first
## would eventually forget to.
func status() -> StatusEffects:
	if _status == null:
		_status = StatusEffects.new(self)
	return _status


## What is on this creep right now, or null when nothing is. The read side, for
## anything asking a question rather than applying an effect.
func status_or_null() -> StatusEffects:
	return _status


## Whether this creep is currently pinned in place and shootable as though it
## walked the ground, whatever it really is. Water 1's paralyze is the only
## thing that does it, and TargetFinder is the only thing that asks.
func is_pinned() -> bool:
	return _status != null && _status.is_paralyzed()


## Re-reads the auras in range on a slow timer rather than every frame. Armour
## only matters at the instant a hit lands, and a quarter second of lag on a
## creep walking into an aura is not something a player can see.
##
## Auras do not stack: the best one in range wins. Every creep aura shares one
## radius, see GameConfig.creep_aura_radius_cells.
##
## Naive and linear like TargetFinder, and much cheaper, since it runs four
## times a second rather than every tick. Both want the same spatial hash
## before the population cap of 100 is real.
## Whether this creep gives out an aura at all. Cached off its passives at
## spawn - see _collect_passives.
func emits_aura() -> bool:
	return _emits_aura


func _refresh_aura(delta: float) -> void:
	var config: GameConfig = References.game_config
	var interval: float = AURA_REFRESH_SECONDS if config == null 		else config.creep_aura_refresh_seconds

	_aura_elapsed += delta
	if _aura_elapsed < interval:
		return

	# Zero, and then a slice of the interval that depends on this creep's id -
	# so the FIRST sweep still happens the tick it spawns and every one after
	# it is spread. Without this a wave of ninety six sweeps on one tick, five
	# ticks apart, which is a spike rather than a cost. Measured on a Wendigo
	# wave, where every creep carries an aura and so every creep sweeps.
	_aura_elapsed = 0.0
	if !_aura_phased:
		_aura_phased = true
		_aura_elapsed = _aura_phase(interval)

	if config == null:
		return

	_aura_armor = 0
	_aura_move_ratio = 1.0
	_aura_attack_ratio = 1.0
	_aura_damage_ratio = 1.0
	_aura_regen = 0.0

	# One creep in the roster hears none of them, its own included, which is
	# what Unfathomable Power means and why a Demon cannot be walked in a pack
	# to be made faster. Answered before the search rather than inside it, so
	# it costs a scan of the lane rather than a question per aura.
	#
	# An Arcane disc does the same thing to whatever walks over it, for a few
	# seconds at a time rather than for good. Same gate, because it is the same
	# question and this is the only place a creep hears an aura at all - which
	# is what lets the disc take one away without any aura knowing it exists.
	if _aura_deaf || (_status != null && _status.is_aura_denied()):
		return

	# NEARBY first, through the spatial index, and only THEN whether it emits
	# anything. Both halves are needed and each is useless without the other:
	#
	#   the index is what stops a lane of two hundred being walked, and
	#   emits_aura is what stops five virtual calls per passive being spent on
	#   a neighbour that was never going to answer with anything.
	#
	# An earlier version of this asked the area for its emitters and skipped
	# the index entirely. That is faster only while emitters are RARE, and the
	# roster has creeps - the Ancient Wendigo among them - that all carry one,
	# where it degenerates to walking the whole lane again. Measured: it cost
	# about 30 ms on the worst ticks of a Wendigo wave. Nearby first.
	for creep: Creep in TargetFinder.creeps_in_radius(
			area, global_position, config.creep_aura_radius_cells):
		if !creep.emits_aura():
			continue
		for passive in creep.passives():
			_aura_armor = maxi(_aura_armor, passive.aura_armor_bonus(creep))
			_aura_move_ratio = maxf(_aura_move_ratio,
				passive.aura_move_speed_ratio(creep))
			_aura_attack_ratio = maxf(_aura_attack_ratio,
				passive.aura_attack_speed_ratio(creep))
			_aura_damage_ratio = maxf(_aura_damage_ratio,
				passive.aura_attack_damage_ratio(creep))
			_aura_regen = maxf(_aura_regen, passive.aura_health_regen(creep))


## Where in the interval this creep's sweep sits, so two creeps that spawned
## together do not come due together.
##
## The unit id rather than a roll, for the reason AttackComponent gives for the
## same trick: it is a number the server and every client already agree on, so
## nothing here can make two machines sweep on different ticks. One phase per
## TICK of the interval, which is as fine a spread as a fixed tick can carry.
func _aura_phase(interval: float) -> float:
	var phases: int = maxi(1, int(round(interval * float(Engine.physics_ticks_per_second))))
	return interval * float(unit_id % phases) / float(phases)


## Heals the creep from its own regeneration passives.
##
## Nothing is carried between ticks: current_health is a float, so a rate below
## one point a second banks its fraction where it lands rather than being
## rounded away to nothing. What the player reads is display_health().
func _regenerate(delta: float) -> void:
	if current_health >= float(max_health()):
		return

	# Its own regeneration ADDS to the aura standing over it. The passives sum
	# because they are the creep's own; the aura was already reduced to the
	# best one in range, since auras never stack.
	var per_second: float = _aura_regen
	for passive in _passives:
		per_second += passive.health_regen(self)
	if per_second <= 0.0:
		return

	heal(per_second * delta)


## Runs the passives that are on a clock of their own rather than answering a
## question when something happens: so far the Siege Engine's Bombardment.
##
## Before the held check on purpose. A passive that is an ACTION asks whether
## the creep is stunned itself, and one that merely counts - a mana bar
## draining, a shield rebuilding - should keep counting while the creep stands
## still, exactly as its regeneration does.
func _advance_passives(delta: float) -> void:
	# The pool fills before the traits that spend it are asked, so a creep
	# whose mana tops up this tick fires on the same one rather than a tick
	# later. Nothing at all for the great majority of creeps, which have no
	# pool - see CreepMana.of().
	if _mana != null && _creep_stats != null:
		_mana.regenerate(_creep_stats.mana_regen_per_second, delta)

	for passive in _passives:
		passive.on_tick(self, delta)


## Advances everything a tower has left on this creep, and drops the whole
## object once nothing is running - so a creep that was chilled once and has
## walked out of it goes back to costing nothing per tick.
func _advance_status(delta: float) -> void:
	if _status == null:
		return
	if !_status.advance(delta):
		_status = null


## Ratios multiply, so two resistances compound rather than one hiding the
## other. Order independent by construction, which is what lets the damage
## pipeline ask for all of them as a single number.
func _damage_taken_ratio(damage_type: DamageTable.DamageType,
		is_aoe: bool) -> float:
	var ratio: float = 1.0
	for passive in _passives:
		ratio *= passive.damage_taken_ratio(self, damage_type, is_aoe)
	# An amplification a tower left on the creep multiplies alongside its own
	# resistances rather than replacing them, so a spell-resistant creep under
	# a Titan Vault is still spell-resistant - just less so.
	if _status != null:
		ratio *= _status.damage_taken_ratio(DamageTable.is_spell(damage_type))
	return ratio


## What actually reaches this creep's health out of a hit that has already been
## resolved: its own bands, then a ward, then whatever a shield can eat.
##
## THE ORDER IS THE RULE and is worth stating. A band is a resistance the creep
## always has and is read against the landed figure, so it runs first. A ward
## takes the whole hit, so nothing after it can matter. A shield is a POOL and
## runs last, because a shield that ate the part a band was going to blunt
## would be spent several times faster than it should be.
func _absorb(landed: int) -> int:
	var left: float = float(landed)
	for passive in _passives:
		left *= passive.landed_damage_ratio(self, left)

	if _status == null:
		return maxi(0, int(round(left)))
	if _status.is_warded():
		return 0
	return maxi(0, int(round(_status.spend_shield(left))))


## Blocks add up, for the same reason.
func _damage_block() -> int:
	var block: int = 0
	for passive in _passives:
		block += passive.damage_block()
	return block


# --- Movement -----------------------------------------------------------

## Deliberately does not call super(). MobileUnit walks towards an ordered
## target, and a creep is driven by the area's route instead, so the two would
## be fighting over the same position.
func _physics_process(delta: float) -> void:
	# 3.4: a client runs no simulation of its own. What it draws is what the
	# server sent, so anything that would advance the world here has to stand
	# aside. See MatchSession.is_authority().
	if !MatchSession.is_authority():
		return

	if area == null || _creep_stats == null:
		return

	# A down creep does nothing but wait: no walking, no auras, no
	# regeneration. It is out of health, so every target search already
	# skips it without being told about this state.
	if is_down():
		_advance_revive(delta)
		return

	# Before everything that moves it, so a task that starts this tick is
	# walked this tick. An ordinary creep has no queue at all and pays a null
	# check for the question - see Unit.order_queue.
	_advance_orders(delta)

	active_ability.advance(delta)
	_advance_status(delta)
	_refresh_aura(delta)
	_regenerate(delta)
	_advance_passives(delta)

	# Held in place: stunned, or a flyer paralyzed out of the sky. It still
	# burns, still regenerates and can still be shot - it simply does not
	# advance, which is the whole of what a stun is worth in a tower defence.
	if _status != null && _status.is_held():
		return

	# Arriving is the same event for all three kinds, and it is checked before
	# any of them moves, so a creep ordered onto the end zone leaks exactly as
	# one that walked there did.
	# Before the exit check, so a dive that ends on the end zone leaks on the
	# tick after it lands rather than being cut short mid-arc. Nothing else a
	# creep does runs while one is in the air.
	if _dive != null:
		if !_dive.advance(self, delta):
			_dive = null
		return

	if area.is_at_exit(global_position):
		_reach_end()
		return

	# AN ATTACKER IS ASKED FIRST, before anything about how it travels. What
	# an attacker does is go after towers and never advance on its own
	# (game_rules.md), and that is true of one that flies as much as of one
	# that walks - the Phoenix is the first creep in the game that is both, and
	# asking "does it ignore the maze" first sent it gliding straight past the
	# maze it had been sent to take apart.
	if is_attacker():
		if !ignores_maze():
			_record_trail()
		_march(delta)
		# AFTER the march and outside it, because an attacker that did not move
		# this tick is exactly the case that needs it: one standing on a tower
		# or parked on an ordered point takes no step of its own, and without
		# this the next creep to walk in would simply stand inside it.
		_hold_apart()
		return

	# A flyer and an ethereal creep both read none of the maze and go straight
	# down the lane. What separates them is only how high they are drawn and
	# what may shoot them, neither of which is a movement question.
	if ignores_maze():
		_glide(delta)
		return

	_record_trail()
	_walk_route(delta)


## An ordinary creep: follow the route it committed to, one waypoint at a time.
func _walk_route(delta: float) -> void:
	if !_has_step():
		_replan()
		if !_has_step():
			return

	var to_step: Vector3 = _step_offset()
	if to_step.length() <= _step_reach(delta):
		_advance_step()
		if !_has_step():
			return
		to_step = _step_offset()

	var direction: Vector3 = to_step.normalized()
	_step(direction, delta)
	_face_direction(direction, delta)
	_watch_for_stall(to_step.length(), delta)


## Straight down the lane, reading none of the occupancy grid: what a FLYER
## does at cruising height and what an ETHEREAL creep does on the floor.
##
## There is no route and nothing to commit to, which is the whole of what both
## of them are - a tower dropped in front of one changes nothing, because the
## grid it was dropped into is not consulted. What still separates them is that
## a flyer is out of reach of half the maze and an ethereal creep is not: it
## walks through towers rather than over them, and anything may shoot it.
##
## It still separates, but only against other creeps of its own kind: shoving a
## flyer sideways because a pack is walking underneath it would be a collision
## between things that never touch.
##
## Height is a climb rather than a snap so a creep recycled into a new lane
## rises into place instead of appearing at altitude, and it is visual only:
## every distance in the game is measured flat.
func _glide(delta: float) -> void:
	# The area's own forward rather than world +z, so an area that is ever
	# turned around does not need this rewritten.
	var direction: Vector3 = area.global_transform.basis.z.normalized()
	var speed: float = _move_speed()
	var push: Vector3 = _crowding_push(speed, delta)

	var moved: Vector3 = area.clamp_point(global_position + direction * speed * delta + push)
	global_position = Vector3(
		moved.x,
		move_toward(global_position.y, _ground_height(), CLIMB_SPEED * delta),
		moved.z
	)
	_face_direction(direction, delta)


## An attacker creep with nobody steering it: walk to the nearest tower and
## stand on it until it falls, then pick the next one.
##
## It never advances towards the end zone of its own accord, which is what
## makes stealing a life something its owner has to ORDER rather than something
## it does eventually. See game_rules.md.
##
## Steering is straight at the tower rather than through the flow field, and
## that is deliberate: the thing it is walking at IS the obstacle, so bumping
## into its face is arriving. _move_by slides it along anything else in the way.
func _march(delta: float) -> void:
	# A move order wins outright. Move means move in any RTS - the creep walks
	# and does not stop to fight, which can_attack() is the other half of.
	if is_moving():
		_walk_to_order(delta)
		return

	# Standing still because a TASK is holding it there - an attack order that
	# has closed the distance and is now fighting. The march below is what an
	# attacker with nobody steering it does, and this one has somebody: walking
	# off to the nearest tower would be undoing the order it was just given.
	if order_queue != null && !order_queue.is_empty():
		_face_attack_target(delta)
		return

	_refresh_march_target(delta)
	if _march_target == null:
		return

	var offset: Vector3 = _march_target.global_position - global_position
	offset.y = 0.0
	var distance: float = offset.length()
	if distance <= 0.0001:
		return

	var direction: Vector3 = offset / distance
	# Close enough to hit it: stand still and let the attack component do the
	# rest. It runs its own search, so nothing here has to hand the target over.
	if distance > _attack_reach():
		_step(direction, delta)
	_face_direction(direction, delta)


## Walks towards a commanded position along the route it was handed, arriving
## when it gets there.
##
## Deliberately not MobileUnit's own loop: that writes the position directly
## and would walk straight through a maze, where this follows a route ROUND it
## and takes every step through _move_by like every other ground creep.
##
## The route is followed a cell at a time exactly as the walk to the exit is,
## and the LAST leg is the ordered point itself rather than a cell centre, so a
## creep lands where the player clicked instead of on the nearest half-cell.
## Arriving and giving up to the crowd are both measured against that point
## too: a creep three cells out has not arrived however near its next waypoint.
func _walk_to_order(delta: float) -> void:
	# Only the cell being walked INTO is re-tested, which is what committing to
	# a route means - a tower dropped further along changes nothing until the
	# creep gets to it. Same rule _has_step applies to the walk to the exit.
	if _order_step_blocked():
		_replan_order()

	var remaining: Vector3 = _target_position - global_position
	remaining.y = 0.0
	var distance: float = remaining.length()

	# Somebody else got there first. Stopping rather than arriving, so the
	# creep stays where the crowd left it instead of snapping onto a point it
	# was never able to reach - and stop() ends the task either way, which is
	# what MoveAbility means by "arrived or was stopped".
	if _is_crowd_blocked(distance):
		var point: Vector3 = _target_position
		stop()
		_crowd_settled = true
		_crowd_settled_point = point
		return

	if _has_order_step() && _order_step_offset().length() <= _step_reach(delta):
		_advance_order_step()

	var to_step: Vector3 = _order_step_offset() if _has_order_step() else remaining
	var length: float = to_step.length()
	if !_has_order_step() && length <= _step_reach(delta):
		_arrive()
		return
	if length <= CROWD_MIN_AXIS:
		return

	var direction: Vector3 = to_step / length
	_step(direction, delta)
	_face_direction(direction, delta)
	_watch_for_stall(length, delta)


## Whether the ordered route still has a cell left to walk to.
func _has_order_step() -> bool:
	return _order_index >= 0 && _order_index < _order_path.size()


## Whether the cell the creep is walking INTO has had a tower put in it since
## the route was planned, which is the one thing that makes it re-plan.
func _order_step_blocked() -> bool:
	if area == null || !_has_order_step():
		return false
	return !area.is_point_free(area.internal_cell_center(_order_path[_order_index]))


func _order_step_offset() -> Vector3:
	var cell: Vector3 = area.internal_cell_center(_order_path[_order_index])
	var offset: Vector3 = cell - global_position
	offset.y = 0.0
	return offset


func _advance_order_step() -> void:
	_order_index += 1
	_reset_stall()


## Takes a fresh route to the ordered point and commits to it, the way _replan
## does for the walk to the exit. An empty one - no route, or already in the
## goal cell - leaves the creep walking straight at the point, which is what it
## did before there was any pathfinding here at all.
func _plan_order_route(goal: Vector2i) -> void:
	_order_goal = goal
	_order_path = area.route_between(global_position, _target_position)
	_order_index = 0
	_reset_stall()


## Re-takes that route from where the creep now stands, for a tower dropped
## into it or a corner it has been pressed into.
func _replan_order() -> void:
	if area == null || ignores_maze():
		return
	_plan_order_route(area.world_to_internal_cell(_target_position))


func _clear_order_route() -> void:
	_order_path = []
	_order_index = 0
	_order_goal = OFF_GRID


## Turns a creep that is standing and fighting to face what it is hitting.
##
## Only for the ordered case: an attacker marching on its own already faces the
## tower it is walking at, and one walking to a point faces where it is going.
## This is the third state - planted by a task, with nothing steering the body -
## and without it the creep chews on a tower while looking somewhere else.
func _face_attack_target(delta: float) -> void:
	if attack_component == null:
		return
	var target: Unit = attack_component.current_target()
	if target == null:
		return

	var offset: Vector3 = target.global_position - global_position
	offset.y = 0.0
	if offset.length_squared() <= 0.0001:
		return
	_face_direction(offset.normalized(), delta)


## Re-picks the tower being marched on, on the same slow beat the auras use.
##
## Kept rather than re-picked every tick so an attacker does not swap targets
## because two towers are a hair apart, and re-picked at all so it moves on the
## moment the one it was chewing falls.
func _refresh_march_target(delta: float) -> void:
	_march_elapsed += delta
	var standing: bool = _march_target != null && is_instance_valid(_march_target) \
		&& _march_target.is_alive()
	if standing && _march_elapsed < AURA_REFRESH_SECONDS:
		return

	_march_elapsed = 0.0
	_march_target = TargetFinder.nearest_building(area, global_position)


## How close an attacker has to be before it stops walking, which is simply its
## own reach. Zero for a creep with no attack at all, which would be an
## attacker whose stats forgot one - it then walks to the tower and stands
## there, rather than orbiting it forever.
func _attack_reach() -> float:
	if _creep_stats == null || _creep_stats.attack == null:
		return 0.0
	return _creep_stats.attack.attack_range


## Keeps a flyer at its cruising height when a commanded move ends, rather than
## dropping it to the floor the way MobileUnit would.
func _arrive() -> void:
	super()
	_clear_order_route()
	global_position.y = _ground_height()


## Whether the committed route still has a step the creep can take.
##
## The blocked test is what makes committing work: the route is followed as it
## was planned, and only the cell the creep is walking into right now is
## checked. So a tower dropped anywhere else along the route changes nothing
## until the creep gets there, and then it re-routes standing at its face.
func _has_step() -> bool:
	if _path_index < 0 || _path_index >= _path.size():
		return false
	return area.is_point_free(area.internal_cell_center(_path[_path_index]))


func _step_offset() -> Vector3:
	var offset: Vector3 = area.internal_cell_center(_path[_path_index]) - global_position
	offset.y = 0.0
	return offset


## How close counts as "arrived at this waypoint". Never smaller than the
## distance one tick covers, and that floor is the whole point.
##
## Without it the creep OSCILLATES around the waypoint instead of passing it.
## Walking at speed v on a tick of dt it covers s = v*dt, so it lands some
## remainder r short, overshoots to s-r, comes back to r, and bounces there for
## good - it escapes only if r or s-r happens to fall inside the threshold. So
## any creep whose s/2 exceeds the authored threshold has a band of remainders
## it can get trapped in.
##
## Measured, not guessed. At 20 Hz the Spider at speed 2.2 takes s = 0.11 and
## its trapped band is r in (0.05, 0.06); the probe caught real creeps sitting
## at 0.0540 and 0.0560 on alternate ticks, which sum to exactly 0.11. Every
## other creep runs at 2.0, where s = 0.10 makes that band empty - which is why
## the Spider alone stuttered, and why dropping it to 2.0 "fixed" it.
##
## Taking the tick's own travel as the floor closes the band at every speed and
## every tick rate, so move_speed stays a freely tunable stat and changing the
## simulation rate cannot quietly reopen this.
func _step_reach(delta: float) -> float:
	return maxf(_creep_stats.arrive_threshold, _move_speed() * delta)


func _advance_step() -> void:
	_path_index += 1
	_reset_stall()
	if !_has_step():
		_replan()


## Re-acquires the route when the creep has stopped getting closer to its next
## step for a while.
##
## Committing to a route means no longer re-planning whenever a crowd nudges
## the creep out of its cell, so this is the one remaining way out of a corner
## it has been pressed into. It plans from where the creep actually stands,
## which usually hands back the same route, simply re-aimed.
##
## WHICH route is decided by whether the creep is walking on an order, and the
## two can never both be true: a commanded walk is the only thing that reaches
## _walk_to_order, and only a creep with no order left reaches _walk_route.
## Re-planning the wrong one of the two would send a commanded attacker off
## towards the exit.
func _watch_for_stall(distance: float, delta: float) -> void:
	if distance < _stall_distance - _creep_stats.arrive_threshold:
		_stall_distance = distance
		_stall_elapsed = 0.0
		return

	_stall_elapsed += delta
	if _stall_elapsed < STALL_SECONDS:
		return

	Log.debug("Creep re-routing after making no progress", {"creep": name})
	if is_moving():
		_replan_order()
	else:
		_replan()


func _reset_stall() -> void:
	_stall_distance = INF
	_stall_elapsed = 0.0


func _step(direction: Vector3, delta: float) -> void:
	var speed: float = _move_speed()
	var travel: Vector3 = direction * speed * delta
	_move_by(travel + _crowding_push(speed, delta))


## The shove this creep takes from the crowd, already scaled into a movement
## for this tick.
##
## Zero WITHOUT LOOKING AT ANYTHING when this kind of creep does not crowd,
## which is the whole point: the pairwise scan behind it is the second most
## expensive loop in a full lane, and for the ordinary roster it now never runs
## at all. Turning it back on is a number in game_config.tres, not a code
## change - see GameConfig.creep_separation_limit.
func _crowding_push(speed: float, delta: float) -> Vector3:
	var limit: float = _separation_limit()
	if limit <= 0.0:
		return Vector3.ZERO
	return _separation().limit_length(limit) * speed * delta


## Ceiling on this creep's crowding push, as a share of its own speed.
##
## Asked per creep rather than read once, because the answer is about WHAT the
## creep is: an attacker crowds and everything else walks through its own kind.
## Both halves are config values, so the rule is data and neither half is
## written into this file. See game_rules.md.
func _separation_limit() -> float:
	var config: GameConfig = References.game_config
	if config == null:
		return 0.0
	if is_attacker():
		return config.attacker_separation_limit
	return config.creep_separation_limit


## Applies a movement one axis at a time, so a step that is blocked as a whole
## still slides along the building instead of stopping dead. A creep pressed
## against a tower by the crowd behind it keeps travelling down the wall.
func _move_by(offset: Vector3) -> void:
	# Anything that ignores the maze reads none of the occupancy grid, so it
	# takes the whole step and keeps its own height. Reached by the FLYING
	# ATTACKER, which is the one creep that marches on a tower without sliding
	# along the ones in the way - and which this would otherwise have set down
	# on the floor, where half a maze that cannot reach it could shoot it.
	var height: float = _ground_height()
	if ignores_maze():
		global_position = Vector3(global_position.x + offset.x, height,
			global_position.z + offset.z)
		return

	var moved: Vector3 = global_position

	var along_x: Vector3 = Vector3(moved.x + offset.x, height, moved.z)
	if area.is_point_free(along_x):
		moved = along_x

	var along_z: Vector3 = Vector3(moved.x, height, moved.z + offset.z)
	if area.is_point_free(along_z):
		moved = along_z

	global_position = moved


## Sum of the pushes away from every creep standing too close. Only siblings
## are considered, and creeps are parented under their own root, so this never
## walks past towers.
##
## Naive pairwise, and it is only affordable because of who reaches it: an
## ATTACKER creep, of which a lane holds a handful. Run over a full lane of
## ordinary creeps it cost more than every other creep loop put together, which
## is why _crowding_push refuses to call it at all when the limit is zero. It
## still wants the spatial hash the other two scans want if it is ever switched
## back on for the whole roster.
func _separation() -> Vector3:
	if area == null:
		return Vector3.ZERO

	var push: Vector3 = Vector3.ZERO
	var own_space: float = _crowd_radius()

	# The area's own list rather than get_parent().get_children(): it is the
	# same creeps - this creep is parented under that area's creeps root - and
	# asking the parent builds a fresh array of every one of them per call.
	for other: Creep in area.creeps():
		# A down creep is walked straight through rather than shoved around.
		if other == self || other.is_down():
			continue
		# Only creeps on the same layer crowd each other. A pack walking under
		# a flyer is not something either of them can feel.
		if other.is_flying() != is_flying() || other.is_ethereal() != is_ethereal():
			continue

		var personal_space: float = own_space + other._crowd_radius()
		var offset: Vector3 = global_position - other.global_position
		offset.y = 0.0
		var distance: float = offset.length()
		if distance >= personal_space || distance <= 0.0001:
			continue
		push += offset / distance * (personal_space - distance) / personal_space

	return push


## The room this creep keeps around itself, as a radius. Two creeps may not
## stand closer than the sum of the two.
##
## An ATTACKER measures it off its own SELECTION CIRCLE, so the space it claims
## is the ring the player is already looking at and a bigger attacker claims
## more of it without a second stat per creep. Everything else measures it off
## its body, which is what the soft push has always used.
##
## select_radius rather than selection_radius(), which answers 0 for a creep
## waiting on a revive: that is a rule about what may be CLICKED, and a body
## that shrank to nothing while it was down would let the rest of the pack
## close over the spot it is about to stand up in.
func _crowd_radius() -> float:
	if !is_attacker():
		return body_radius()
	var config: GameConfig = References.game_config
	if config == null:
		return 0.0
	return config.attacker_personal_space_ratio * select_radius


## Pushes this creep out of any ATTACKER it is standing inside, and is the hard
## half of crowding.
##
## The soft push in _separation only ever steers a creep that is TAKING A STEP,
## which is why a commanded pack still ended up as one body: they all walk onto
## the same point, and the ones that got there stop walking and stop being
## pushed. This runs whatever the tick did and is what the rule actually rests
## on - see GameConfig.attacker_personal_space_ratio.
##
## Each creep corrects HALF the overlap and only its own position, so a pair
## separates by the whole of it over the tick they both run, and no creep ever
## writes another one's position. A neighbour that cannot move itself - one
## held by a stun, one waiting on a revive - simply contributes nothing back,
## and the mover walks its own way out over a few more ticks.
##
## Goes through _move_by like every other movement, so a creep shoved against a
## tower slides along it rather than being pushed inside it.
func _hold_apart() -> void:
	if area == null || !is_attacker():
		return

	var own_space: float = _crowd_radius()
	if own_space <= 0.0:
		return

	var correction: Vector3 = Vector3.ZERO
	for other: Creep in area.creeps():
		if other == self || other.is_down() || !other.is_attacker():
			continue
		# The same layer rule the soft push uses: a flyer and the pack walking
		# underneath it never touch, so neither can be inside the other.
		if other.is_flying() != is_flying() || other.is_ethereal() != is_ethereal():
			continue

		var space: float = own_space + other._crowd_radius()
		var offset: Vector3 = global_position - other.global_position
		offset.y = 0.0
		var distance: float = offset.length()
		if distance >= space:
			continue

		correction += _away_from(other, offset, distance) * (space - distance) * 0.5

	if correction != Vector3.ZERO:
		_move_by(correction)


## Which way out of a neighbour this creep goes.
##
## Straight away from it, except when the two are standing on the very same
## point and there is no direction to be had. That happens - two creeps spawned
## together and given one order arrive on one spot - and it is settled by
## UNIT ID rather than by anything about the world, so the two pick opposite
## sides and stay picked instead of trading places every tick.
func _away_from(other: Creep, offset: Vector3, distance: float) -> Vector3:
	if distance > CROWD_MIN_AXIS:
		return offset / distance
	var side: float = 1.0 if unit_id > other.unit_id else -1.0
	return Vector3(side, 0.0, 0.0)


## Whether the point this creep was ordered to is already taken by the crowd.
##
## True only close to that point, because the rule out here is "somebody is in
## my way" and further out that is something to walk around rather than a
## reason to stop. The blocker also has to be standing STILL and standing
## nearer the point than this creep is, which is what makes a pack settle
## outwards one ring at a time: the creep on the point stops first, the one
## touching it stops next, and so on to the edge of the pack.
func _is_crowd_blocked(distance: float) -> bool:
	if area == null || !is_attacker():
		return false

	# A creep sent onto a NAMED target is not after a spot on the ground, it is
	# after one within reach of that target - and there is a whole ring of
	# them. Giving up here would leave it standing behind whoever arrived
	# first, where being shoved round the outside gets it into reach on its own.
	if attack_component != null && attack_component.ordered_target() != null:
		return false

	var config: GameConfig = References.game_config
	if config == null:
		return false
	if distance > config.attacker_crowd_arrive_cells * config.cell_size:
		return false

	var own_space: float = _crowd_radius()
	for other: Creep in area.creeps():
		if other == self || other.is_down() || !other.is_attacker() || other.is_moving():
			continue
		if other.is_flying() != is_flying() || other.is_ethereal() != is_ethereal():
			continue

		# Touching, with a little slack: _hold_apart parks a pair at exactly
		# their combined space, and a test for "closer than that" would then
		# answer false for two creeps pressed right up against each other.
		var gap: Vector3 = global_position - other.global_position
		gap.y = 0.0
		if gap.length() > (own_space + other._crowd_radius()) * CROWD_CONTACT_SLACK:
			continue

		var theirs: Vector3 = _target_position - other.global_position
		theirs.y = 0.0
		if theirs.length() < distance:
			return true

	return false


## Takes a fresh route from where the creep stands and commits to it.
##
## Only ever called when the creep is standing at something it cannot walk
## through, when it spawns, or when a building set it back. Never on a plain
## grid change, which is exactly what keeps a creep on the route it chose.
##
## A creep with nowhere left to go simply stops, which cannot normally happen:
## placement that would seal the area is refused before the tower is built.
func _replan() -> void:
	# Nothing that ignores the maze reads a route at all, so there is nothing
	# here for it to take - and asking would log a warning every time one
	# crossed a sealed maze.
	if ignores_maze():
		return

	_path = area.route_to_exit(global_position)
	_path_index = 0
	_reset_stall()

	if _path.is_empty() && !area.has_route_from(global_position):
		Log.warn("Creep has no route to the end zone", {"creep": name})


func _record_trail() -> void:
	if _trail.is_empty():
		_trail.append(global_position)
		return

	var last: Vector3 = _trail[_trail.size() - 1]
	if global_position.distance_squared_to(last) < TRAIL_SPACING * TRAIL_SPACING:
		return

	_trail.append(global_position)
	if _trail.size() > TRAIL_LIMIT:
		_trail.remove_at(0)


func _teleport_to(world_pos: Vector3) -> void:
	global_position = Vector3(world_pos.x, _ground_height(), world_pos.z)
	_replan()


## Gives the passives their turn before the creep is gone: an acolyte heals
## whatever is standing around it, a skeleton gets back up.
##
## A passive reporting that it kept the creep alive calls the death off
## entirely, so no bounty is paid - the creep did not die. Every passive still
## gets its turn either way, because a creep carrying both a heal and a revive
## should do both.
##
## Bounty goes to whoever owns the maze the creep died in, not to whoever fired
## the killing shot and not to the player who sent it, per game_rules.md. So no
## damage source has to be tracked anywhere: the area already knows.
func _die() -> void:
	if _run_death_passives():
		return
	_pay_bounty()
	super()


func _run_death_passives() -> bool:
	var survived: bool = false
	for passive in _passives:
		if passive.on_death(self):
			survived = true
	return survived


func _pay_bounty() -> void:
	if _creep_stats == null || _creep_stats.bounty <= 0 || area == null:
		return

	BountyPopup.show_for(self)

	var manager: PlayerManager = References.player_manager
	if manager == null:
		return

	var state: PlayerState = manager.state_for(area.player_id)
	if state != null:
		state.gain(_creep_stats.bounty)


## A leak. Two things happen, in this order, and neither is optional.
##
## The creep's owner STEALS a life from whoever owns this maze - the pool never
## shrinks, it moves. Then the creep is RECYCLED: it is not removed, it walks
## on into the next maze in ring order with its health untouched. In a 1v1 that
## is the same maze again, which game_rules.md states explicitly.
##
## Only a creep with nowhere left to go is despawned, which today means a run
## with a single area.
func _reach_end() -> void:
	reached_end.emit()

	var stolen: bool = _steal_life()
	# A creep that steals NOTHING is not recycled either: it has reached the
	# end of the only maze it was ever going to matter in, and walking it into
	# the next player's lane would be a free bounty nobody paid for. The
	# Treasure Goblin is the only thing in the roster this describes, and it is
	# what "cannot steal lives" comes to in a game where a leak is a transfer.
	var destination: PlayerArea = null
	if _creep_stats == null || _creep_stats.lives_stolen > 0:
		destination = _next_maze()
	# DEBUG, not info: this is the most frequent gameplay event in the game -
	# every creep that walks a lane ends here - and Log.info costs a get_stack()
	# plus a print_rich() whether or not anybody reads the result. Measured at
	# ~10 ms per call on 2026-09-04, which was HALF of all creep simulation time.
	# See performance-handover.md. The line is still there at DEBUG.
	Log.debug("Creep leaked", {
		"creep": name,
		"owner": owner_player_id,
		"maze": -1 if area == null else area.player_id,
		"stole": stolen,
		"into": -1 if destination == null else destination.player_id,
	})

	if destination == null:
		queue_free()
		return
	_recycle_into(destination)


## One life from the defender to the sender. Reports whether it happened, which
## it does not when the creep is walking its own owner's maze - a single area
## run - or when the defender is already out.
func _steal_life() -> bool:
	var manager: PlayerManager = References.player_manager
	if manager == null || area == null:
		return false

	var thief: PlayerState = manager.state_for(owner_player_id)
	var victim: PlayerState = manager.state_for(area.player_id)
	if thief == null:
		return false

	var count: int = 1 if _creep_stats == null else _creep_stats.lives_stolen
	return thief.steal_life_from(victim, count)


func _next_maze() -> PlayerArea:
	var manager: PlayerManager = References.player_manager
	if manager == null || area == null:
		return null

	var slot: int = manager.next_maze_after(area.player_id, owner_player_id)
	# "Advance to the next LIVING player, skipping the creep's owner"
	# (game_rules.md). When there is no such player there is nowhere to advance
	# to, and the creep leaves rather than looping in one lane forever. Two
	# runs land there: a single area, where the only candidate is the sender
	# themselves, and a 1v1 whose other player is already out.
	if slot == owner_player_id:
		return null

	var state: PlayerState = manager.state_for(slot)
	if state != null && state.is_eliminated():
		return null
	return manager.area_for(slot)


## Puts the creep back at the top of a maze and lets it walk again, keeping the
## health it arrived with. Everything about the route is discarded, because
## none of it describes the maze it is now standing in.
func _recycle_into(destination: PlayerArea) -> void:
	if destination != area:
		var root: Node3D = destination.creeps_root()
		if get_parent() != root:
			reparent(root)
	area = destination

	var point: Vector3 = destination.random_spawn_point(
		0.0 if _creep_stats == null else _creep_stats.body_radius,
		MatchSession.match_rng()
	)
	global_position = Vector3(point.x, _ground_height(), point.z)
	# Placed, not moved: without this the interpolator streaks it across the
	# whole map from the end zone it just left.
	reset_physics_interpolation()
	_trail = [global_position]
	_replan()
