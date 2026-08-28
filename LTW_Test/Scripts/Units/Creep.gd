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

## Ceiling on the crowding push, as a share of the creep's own speed. Kept
## below 1 so the push can never cancel forward movement: an uncapped sum over
## a dense clump was shoving creeps a cell per frame into the walls.
const SEPARATION_LIMIT: float = 0.6

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

## Route the creep committed to, as internal cells in walking order.
var _path: Array[Vector2i] = []
## Which cell of that route the creep is currently walking towards.
var _path_index: int = 0
## Route already covered, newest last, for being set back along it.
var _trail: Array[Vector3] = []

## Closest the creep has been to its current step, and how long it has been no
## closer than that.
var _stall_distance: float = INF
var _stall_elapsed: float = 0.0

## Passives read off this creep's stats once, since they are asked on every hit.
var _passives: Array[CreepPassive] = []
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
var _aura_regen: float = 0.0
## Whether any of this creep's passives says towers should ignore it. Read once
## rather than per target scan, since a creep cannot gain a passive mid-walk.
var _skittering: bool = false
## The tower an unordered attacker creep is marching on, and the countdown to
## re-picking it. Null for every creep that is not an attacker.
var _march_target: Building = null
var _march_elapsed: float = 0.0
## Starts at the interval so the very first physics frame reads the auras
## rather than leaving a freshly spawned creep unbuffed for a quarter second.
var _aura_elapsed: float = AURA_REFRESH_SECONDS
## Fraction of a health point regeneration has built up but not handed over yet.
var _regen_carry: float = 0.0
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

var _creep_stats: CreepStats:
	get:
		return stats as CreepStats


func _ready() -> void:
	super()
	if stats != null && _creep_stats == null:
		Log.err("Creep needs CreepStats but got plain UnitStats", name)
	_collect_passives()
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


## An attacker creep takes orders and goes after towers; nothing else does
## either. Both follow from the same stats flag, so they can never disagree.
func is_attacker() -> bool:
	return _creep_stats != null && _creep_stats.is_attacker


## Height this creep's origin sits at: cruising height for a flyer, the ground
## for everything else. Asked wherever a position is written rather than
## assumed zero, which is what keeps a flyer off the floor after a leak.
func _ground_height() -> float:
	return _creep_stats.fly_height if is_flying() else 0.0


## Its own speed, with whatever aura is standing over it and whatever a tower
## has chilled it with folded in.
##
## The two multiply rather than one winning: an aura is the pack helping itself
## and a chill is a tower fighting it, and a creep that is both buffed and
## slowed should end up somewhere between the two.
func _move_speed() -> float:
	var ratio: float = 1.0 if _status == null else _status.move_ratio()
	return _creep_stats.move_speed * _aura_move_ratio * ratio


## Attack speed is an aura's business too, and only an attacker creep has an
## attack for it to act on. See Combat/AttackComponent.gd.
func attack_speed_ratio() -> float:
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
	# A flyer has no route to read, so it answers with the rows it has left to
	# cross - which is the same question in the same units.
	if is_flying():
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


# --- Passives -----------------------------------------------------------

## Reads the creep's passives off its stats once. Cached because they are asked
## on every hit and every frame, not because the list is expensive to build.
func _collect_passives() -> void:
	_passives.clear()
	if _creep_stats == null:
		return

	_skittering = false
	for entry in _creep_stats.abilities:
		var passive: CreepPassive = entry as CreepPassive
		if passive != null:
			_passives.append(passive)
			_skittering = _skittering || passive.is_skittering()


## Whether a once-only passive has already fired on THIS creep.
##
## The record lives here rather than on the passive because the passive is one
## shared resource standing in for every creep of its type: a flag stored on it
## would be spent for all of them the moment any single one used it.
func has_spent(passive: CreepPassive) -> bool:
	return _spent.has(passive)


func spend(passive: CreepPassive) -> void:
	_spent[passive] = true


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

	var restored: int = roundi(float(max_health()) * _revive_ratio)
	_set_health(maxi(1, restored))
	Log.info("Creep revived", {"creep": name, "health": current_health})
## The passives this creep offers to everything standing around it, itself
## included. Handed out whole rather than one question at a time, so a creep
## reading the auras in range asks each of them everything at once.
##
## Every passive is offered, not only the ones that grant something: a passive
## with no aura answers each question with its neutral default, and filtering
## here would mean knowing which of them count.
func aura_passives() -> Array[CreepPassive]:
	return _passives


## Its own armour, whatever the auras standing around it are worth, and
## whatever an elemental tower has eaten out of it.
func armor_value() -> int:
	var eaten: int = 0 if _status == null else _status.armor_delta()
	return super() + _aura_armor + eaten


## Its own armour type, unless something has altered it. Ultimate Alchemist is
## the only thing that does, and only for a few seconds at a time.
func armor_type_value() -> UnitStats.ArmorType:
	if _status != null:
		var altered: int = _status.armor_type_override()
		if altered >= 0:
			return altered as UnitStats.ArmorType
	return super()


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
## Naive and linear like _separation() and TargetFinder, and strictly cheaper
## than either, since it runs four times a second rather than every frame. All
## three want the same spatial hash before the population cap of 100 is real.
func _refresh_aura(delta: float) -> void:
	_aura_elapsed += delta
	if _aura_elapsed < AURA_REFRESH_SECONDS:
		return
	_aura_elapsed = 0.0

	var config: GameConfig = References.game_config
	if config == null:
		return

	_aura_armor = 0
	_aura_move_ratio = 1.0
	_aura_attack_ratio = 1.0
	_aura_regen = 0.0

	for creep: Creep in TargetFinder.creeps_in_radius(
			area, global_position, config.creep_aura_radius_cells):
		for passive in creep.aura_passives():
			_aura_armor = maxi(_aura_armor, passive.aura_armor_bonus())
			_aura_move_ratio = maxf(_aura_move_ratio, passive.aura_move_speed_ratio())
			_aura_attack_ratio = maxf(_aura_attack_ratio, passive.aura_attack_speed_ratio())
			_aura_regen = maxf(_aura_regen, passive.aura_health_regen())


## Heals the creep from its own regeneration passives.
##
## Fractions are carried between frames rather than rounded away, so a rate
## below one point a second still heals instead of doing nothing at all. The
## carry is dropped at full health, so a creep cannot bank regeneration while
## untouched and dump it the instant it is finally hit.
func _regenerate(delta: float) -> void:
	if current_health >= max_health():
		_regen_carry = 0.0
		return

	# Its own regeneration ADDS to the aura standing over it. The passives sum
	# because they are the creep's own; the aura was already reduced to the
	# best one in range, since auras never stack.
	var per_second: float = _aura_regen
	for passive in _passives:
		per_second += passive.health_regen()
	if per_second <= 0.0:
		return

	_regen_carry += per_second * delta
	var whole: int = int(_regen_carry)
	if whole > 0:
		_regen_carry -= float(whole)
		heal(whole)


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
func _damage_taken_ratio(is_aoe: bool, is_spell: bool) -> float:
	var ratio: float = 1.0
	for passive in _passives:
		ratio *= passive.damage_taken_ratio(is_aoe, is_spell)
	# An amplification a tower left on the creep multiplies alongside its own
	# resistances rather than replacing them, so a spell-resistant creep under
	# a Titan Vault is still spell-resistant - just less so.
	if _status != null:
		ratio *= _status.damage_taken_ratio(is_spell)
	return ratio


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

	_advance_status(delta)
	_refresh_aura(delta)
	_regenerate(delta)

	# Held in place: stunned, or a flyer paralyzed out of the sky. It still
	# burns, still regenerates and can still be shot - it simply does not
	# advance, which is the whole of what a stun is worth in a tower defence.
	if _status != null && _status.is_held():
		return

	# Arriving is the same event for all three kinds, and it is checked before
	# any of them moves, so a creep ordered onto the end zone leaks exactly as
	# one that walked there did.
	if area.is_at_exit(global_position):
		_reach_end()
		return

	if is_flying():
		_fly(delta)
		return

	_record_trail()
	if is_attacker():
		_march(delta)
		return
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


## A flyer: straight down the lane at cruising height, reading none of the
## occupancy grid.
##
## There is no route and nothing to commit to, which is the whole of what
## flying is - a tower dropped in front of one changes nothing, because the
## grid it was dropped into is not consulted. It still separates, but only
## against other flyers: shoving a flyer sideways because a pack is walking
## underneath it would be a collision between things that never touch.
##
## Height is a climb rather than a snap so a creep recycled into a new lane
## rises into place instead of appearing at altitude, and it is visual only:
## every distance in the game is measured flat.
func _fly(delta: float) -> void:
	# The area's own forward rather than world +z, so an area that is ever
	# turned around does not need this rewritten.
	var direction: Vector3 = area.global_transform.basis.z.normalized()
	var speed: float = _move_speed()
	var push: Vector3 = _separation().limit_length(SEPARATION_LIMIT) * speed * delta

	var moved: Vector3 = area.clamp_point(global_position + direction * speed * delta + push)
	global_position = Vector3(
		moved.x,
		move_toward(global_position.y, _creep_stats.fly_height, CLIMB_SPEED * delta),
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


## Walks towards a commanded position, arriving when it gets there.
##
## Deliberately not MobileUnit's own loop: that writes the position directly
## and would walk straight through a maze, where this goes through _move_by and
## slides along the towers like every other ground creep.
func _walk_to_order(delta: float) -> void:
	var offset: Vector3 = _target_position - global_position
	offset.y = 0.0

	var distance: float = offset.length()
	if distance <= _step_reach(delta):
		_arrive()
		return

	var direction: Vector3 = offset / distance
	_step(direction, delta)
	_face_direction(direction, delta)


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
func _watch_for_stall(distance: float, delta: float) -> void:
	if distance < _stall_distance - _creep_stats.arrive_threshold:
		_stall_distance = distance
		_stall_elapsed = 0.0
		return

	_stall_elapsed += delta
	if _stall_elapsed < STALL_SECONDS:
		return

	Log.info("Creep re-routing after making no progress", {"creep": name})
	_replan()


func _reset_stall() -> void:
	_stall_distance = INF
	_stall_elapsed = 0.0


func _step(direction: Vector3, delta: float) -> void:
	var speed: float = _move_speed()
	var travel: Vector3 = direction * speed * delta
	var push: Vector3 = _separation().limit_length(SEPARATION_LIMIT) * speed * delta
	_move_by(travel + push)


## Applies a movement one axis at a time, so a step that is blocked as a whole
## still slides along the building instead of stopping dead. A creep pressed
## against a tower by the crowd behind it keeps travelling down the wall.
func _move_by(offset: Vector3) -> void:
	var moved: Vector3 = global_position

	var along_x: Vector3 = Vector3(moved.x + offset.x, 0.0, moved.z)
	if area.is_point_free(along_x):
		moved = along_x

	var along_z: Vector3 = Vector3(moved.x, 0.0, moved.z + offset.z)
	if area.is_point_free(along_z):
		moved = along_z

	global_position = moved


## Sum of the pushes away from every creep standing too close. Only siblings
## are considered, and creeps are parented under their own root, so this never
## walks past towers.
##
## Naive pairwise, which is fine for the numbers the prototype spawns. It needs
## a spatial hash before the population cap of 100 is real.
func _separation() -> Vector3:
	var parent: Node = get_parent()
	if parent == null:
		return Vector3.ZERO

	var push: Vector3 = Vector3.ZERO
	var personal_space: float = body_radius() * 2.0

	for sibling in parent.get_children():
		var other: Creep = sibling as Creep
		# A down creep is walked straight through rather than shoved around.
		if other == null || other == self || other.is_down():
			continue
		# Only creeps on the same layer crowd each other. A pack walking under
		# a flyer is not something either of them can feel.
		if other.is_flying() != is_flying():
			continue

		var offset: Vector3 = global_position - other.global_position
		offset.y = 0.0
		var distance: float = offset.length()
		if distance >= personal_space || distance <= 0.0001:
			continue
		push += offset / distance * (personal_space - distance) / personal_space

	return push


## Takes a fresh route from where the creep stands and commits to it.
##
## Only ever called when the creep is standing at something it cannot walk
## through, when it spawns, or when a building set it back. Never on a plain
## grid change, which is exactly what keeps a creep on the route it chose.
##
## A creep with nowhere left to go simply stops, which cannot normally happen:
## placement that would seal the area is refused before the tower is built.
func _replan() -> void:
	# A flyer reads no route at all, so there is nothing here for it to take -
	# and asking would log a warning every time it flew over a sealed maze.
	if is_flying():
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
	var destination: PlayerArea = _next_maze()
	Log.info("Creep leaked", {
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
