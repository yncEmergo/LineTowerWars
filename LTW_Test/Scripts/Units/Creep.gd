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
## Not controllable: a creep can be clicked and inspected but takes no orders,
## per game_rules.md. Attacker creeps will flip that through their stats.

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

## How often the auras standing around a creep are re-read, in seconds.
const AURA_REFRESH_SECONDS: float = 0.25

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
## Armour granted by the auras currently in range, refreshed on a slow timer.
var _aura_armor: int = 0
## Starts at the interval so the very first physics frame reads the auras
## rather than leaving a freshly spawned creep unbuffed for a quarter second.
var _aura_elapsed: float = AURA_REFRESH_SECONDS
## Fraction of a health point regeneration has built up but not handed over yet.
var _regen_carry: float = 0.0
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


## Places a freshly sent creep. sender_id is the player who paid for it, which
## is not the owner of the maze it walks once sending across areas exists.
func spawn(sender_id: int, target_area: PlayerArea, world_pos: Vector3) -> void:
	setup(sender_id, target_area)
	global_position = Vector3(world_pos.x, 0.0, world_pos.z)
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


## Only towers that can hit air may target a flyer. Nothing flies yet.
func is_flying() -> bool:
	return _creep_stats != null && _creep_stats.is_flying


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
	if _path.is_empty() || _path_index >= _path.size():
		return NO_ROUTE_STEPS
	return _path.size() - _path_index


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

	for entry in _creep_stats.abilities:
		var passive: CreepPassive = entry as CreepPassive
		if passive != null:
			_passives.append(passive)


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
## Armour this creep grants to every creep inside the shared aura radius,
## itself included. 0 for a creep with no aura, which is nearly all of them.
func aura_armor_bonus() -> int:
	var best: int = 0
	for passive in _passives:
		best = maxi(best, passive.aura_armor_bonus())
	return best


## Its own armour plus whatever the auras standing around it are worth.
func armor_value() -> int:
	return super() + _aura_armor


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

	var best: int = 0
	for creep: Creep in TargetFinder.creeps_in_radius(
			area, global_position, config.creep_aura_radius_cells):
		best = maxi(best, creep.aura_armor_bonus())
	_aura_armor = best


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

	var per_second: float = 0.0
	for passive in _passives:
		per_second += passive.health_regen()
	if per_second <= 0.0:
		return

	_regen_carry += per_second * delta
	var whole: int = int(_regen_carry)
	if whole > 0:
		_regen_carry -= float(whole)
		heal(whole)


## Ratios multiply, so two resistances compound rather than one hiding the
## other. Order independent by construction, which is what lets the damage
## pipeline ask for all of them as a single number.
func _damage_taken_ratio(is_aoe: bool) -> float:
	var ratio: float = 1.0
	for passive in _passives:
		ratio *= passive.damage_taken_ratio(is_aoe)
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

	_refresh_aura(delta)
	_regenerate(delta)

	if area.is_at_exit(global_position):
		_reach_end()
		return

	_record_trail()

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
	return maxf(_creep_stats.arrive_threshold, _creep_stats.move_speed * delta)


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
	var speed: float = _creep_stats.move_speed
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
	global_position = Vector3(world_pos.x, 0.0, world_pos.z)
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
	return thief.steal_life_from(victim)


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
	global_position = Vector3(point.x, 0.0, point.z)
	# Placed, not moved: without this the interpolator streaks it across the
	# whole map from the end zone it just left.
	reset_physics_interpolation()
	_trail = [global_position]
	_replan()
