@tool
class_name AttackComponent
extends Node

## Makes its unit attack by itself: acquire a target, keep aiming at it, and
## fire whenever the cooldown allows.
##
## A component rather than a subclass, because attacking crosses the split
## between what a unit IS: towers attack, the builder will, attacker creeps
## will, and none of those share a base class below Unit. Everything that is
## per unit lives here - the cooldown and the current target - while the shared
## numbers stay on the unit's AttackStats.
##
## Towers need no attack order and no command card entry. A tower with this
## component simply shoots, which is why nothing here talks to abilities.
##
## @tool for ONE reason, and it is an editor convenience with no gameplay in
## it: a tower's projectile and impact scenes are named by PATH, two levels
## down inside the sub-resources of its stats file, so the inspector draws them
## as text fields in a collapsed section nobody can find. This node surfaces
## them as read-only slots you can click straight through to. See the res://
## path rule in CLAUDE.md for why they are paths in the first place.
##
## Everything else here stands aside in the editor.

## Raised when an attack COMMITS: the target is chosen, the cooldown has
## started, and the windup is now running. This is what an attack animation
## plays on, and the animation has exactly `windup_seconds` to finish.
signal attack_started(target: Unit, windup: float)
## Raised the moment the damage is released - the hammer lands, the shot
## leaves. With no windup it follows attack_started in the same frame.
signal attacked(target: Unit)

## Height above the unit's origin that shots leave from when no muzzle node was
## wired. A placeholder visual value, like the rest of the primitive art.
const MUZZLE_FALLBACK_HEIGHT: float = 0.7

## How far a multishot reaches for its further targets when no config is
## wired, in player cells. A placeholder like MUZZLE_FALLBACK_HEIGHT above it;
## GameConfig.multishot_reach_cells is the real answer.
const MULTISHOT_FALLBACK_REACH: float = 3.0

@export_group("References")
## The unit this attacks for. Its own parent in every prefab so far, wired
## explicitly rather than walked to, like every other reference in the project.
@export var _unit: Unit
## Where shots leave from. Optional: an instant attack with no visual does not
## need one, and the unit's own centre stands in.
@export var _muzzle: Node3D
## Part of the model that turns to face the target, usually the barrel.
## Optional, since a grinder or a stomper has nothing to aim.
@export var _turret_head: Node3D

@export_group("Settings")
## How fast the turret swings around to a new target, in radians per second.
## Purely visual: a tower fires whether or not it has finished turning, so this
## can never cost damage.
@export var turn_towards_target: bool = true
@export var turret_turn_speed: float = 10.0

## Seconds left before the next attack may fire.
var _cooldown: float = 0.0
## What this is shooting. A Unit rather than a Creep, because an attacker creep
## uses this same component to chew on a tower - see AttackStats.TargetClass.
var _target: Unit
## The attack this tower has COMMITTED to, and how long is left of its windup.
##
## Kept apart from _target on purpose: once an attack starts, the tower has
## picked what it is hitting and must not be retargeted mid-swing, or an
## animation would play at one creep and land on another. The point is
## remembered too, so a creep that dies during the windup still gets swung at -
## the same rule a projectile already follows when its target dies mid flight.
var _windup_left: float = 0.0
var _windup_target: Unit = null
var _windup_point: Vector3 = Vector3.ZERO
## Whether the Prioritize toggle is set to go for air first, see
## PrioritizeAbility.
##
## Per TOWER, which is why it lives here rather than on the shared ability
## resource, and simulation rather than presentation, which is why the server
## owns it and a client is told - see ReplicationService.
var _prioritize_air: bool = false
## The unit this was ORDERED onto, held until that unit dies or stops being a
## legal target - which is a different lifetime from _target above.
##
## _target is what this is shooting THIS tick and is dropped the moment the
## creep steps out of reach. An order outlives that: a player who names a creep
## has named it until it is dead, so a tower keeps shooting whatever it can
## reach meanwhile and switches back the moment the ordered one is reachable
## again, and a unit that can walk goes after it. It is also what an attack
## task in an order chain waits on - see AttackAbility.
var _ordered_target: Unit = null
## Ticks left before this unit may search for a target again.
##
## Only ever set by a search that came back EMPTY, so a unit that is fighting
## never waits: it is holding a target, or it is on cooldown, and neither of
## those reaches the search at all. See GameConfig.idle_target_scan_ticks.
var _scan_wait: int = 0
## Whether this unit's first empty search has already spread its phase. Its
## waits are the plain interval from then on.
var _scan_phased: bool = false

var _attack: AttackStats:
	get:
		if _unit == null || _unit.stats == null:
			return null
		return _unit.stats.attack


## Registered on the unit rather than wired from it, so no prefab has to carry
## the same link twice. The component already names its unit through an
## @export; this is that one reference read back the other way, which is what
## lets an ability reach the attack of whatever unit it was handed.


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if _unit == null:
		Log.err("AttackComponent has no unit assigned in its prefab", get_parent().name)
		return
	if _attack == null:
		Log.err("AttackComponent's unit has no AttackStats", _unit.name)

	_unit.attack_component = self


## Whether this component currently has something to shoot. Read by the UI,
## and by any animation that idles differently when there is nothing to hit.
func has_target() -> bool:
	if _windup_target != null && is_instance_valid(_windup_target):
		return true
	return _target != null && is_instance_valid(_target)


## What this is shooting right now, or null. The committed swing first, since
## once an attack starts that is what the unit is really pointed at.
func current_target() -> Unit:
	if _windup_target != null && is_instance_valid(_windup_target):
		return _windup_target
	if _target != null && is_instance_valid(_target):
		return _target
	return null


## Whether a unit is close enough for this attack to land on it.
##
## Public because closing the distance is the ORDER's job rather than this
## one's: a unit walking onto a target has to know when to stop, and the reach
## it stops at is the same one every other range test here uses.
func is_in_reach(target: Unit) -> bool:
	var attack: AttackStats = _attack
	if attack == null || target == null || !is_instance_valid(target):
		return false
	return TargetFinder.is_in_range(_origin(), target, attack.attack_range)


## Whether an attack is committed and its damage has not landed yet.
func is_winding_up() -> bool:
	return _windup_left > 0.0


## Whether this tower is set to go for air targets first.
func prioritizes_air() -> bool:
	return _prioritize_air


## Flips the Prioritize toggle and drops whatever the tower was shooting, so
## the change takes effect on the next scan rather than after the current
## target happens to die. Pressing it and watching nothing happen for six
## seconds would read as a broken button.
func set_prioritize_air(value: bool) -> void:
	if _prioritize_air == value:
		return
	_prioritize_air = value
	_target = null
	# And look again NOW rather than on this tower's own beat. The whole point
	# of the toggle is that pressing it does something you can see.
	_scan_wait = 0


## Orders this unit onto one specific target, the way an attack order works in
## any RTS. Answers whether the order was taken.
##
## The order is HELD until that unit dies or stops being something this could
## ever be aimed at. While it is in reach it is what gets shot; while it is not,
## this unit goes on picking its own targets exactly as it always did, so a
## tower told to shoot something across the map never stands idle - which is
## what makes the order safe to give to a whole selection at once.
##
## Holding it rather than refusing an out-of-range one outright is what lets an
## attack be CHAINED: "shoot that one after this one" is a task with a lifetime,
## and a unit that can walk closes the distance itself. See AttackAbility.
##
## A SKITTERING creep can be ordered onto perfectly well. Its rule is a
## priority inside the automatic search, and this never goes through it.
func order_attack(target: Unit) -> bool:
	var attack: AttackStats = _attack
	if attack == null || _unit == null || !_unit.can_attack():
		return false
	if !_is_valid_target(target, attack):
		return false

	_ordered_target = target
	# Look again NOW rather than on this unit's own beat, so a creep already
	# standing in reach is shot on the tick the order arrived.
	_scan_wait = 0
	return true


## Forgets the standing order, leaving the unit to pick its own targets again.
## What a new order without shift, and a Stop, both do.
func clear_order() -> void:
	_ordered_target = null


## The unit a standing order names, or null once it has died, been sold or
## stopped being a legal target. Read by the attack task waiting on it.
func ordered_target() -> Unit:
	if _ordered_target == null || !is_instance_valid(_ordered_target):
		return null
	if !_ordered_target.is_alive():
		return null
	var attack: AttackStats = _attack
	if attack == null || !_is_valid_target(_ordered_target, attack):
		return null
	return _ordered_target


## Whether this unit could be aimed at that one at all, ignoring range.
##
## Public so a click can ask BEFORE it becomes an order. It is what decides
## whether a left click on something is an attack order or an ordinary
## selection: with towers selected a creep is an order and a tower is not, and
## with attacker creeps selected it is the other way round.
func can_target(target: Unit) -> bool:
	var attack: AttackStats = _attack
	return attack != null && _is_valid_target(target, attack)


## Whether this attack may go after that unit at all, ignoring range.
##
## Three questions. The AREA first, because every search here is over one
## area's own units and an order across a lane boundary is not a thing that can
## be carried out. Then the class - a tower shoots creeps, an attacker creep
## chews on towers - and then the ground-versus-air one, which only means
## anything about a creep.
func _is_valid_target(target: Unit, attack: AttackStats) -> bool:
	if target == null || !is_instance_valid(target) || _unit == null:
		return false
	if target.area != _unit.area:
		return false
	if attack.hits_buildings():
		return target is Building
	return TargetFinder.can_be_hit_by(target as Creep, attack)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var attack: AttackStats = _attack
	if attack == null || _unit == null || !_unit.can_attack():
		# A tower that started upgrading mid-swing drops it rather than landing
		# a hit it is no longer standing to deliver.
		_cancel_windup()
		return

	_cooldown = maxf(0.0, _cooldown - delta)
	_scan_wait = maxi(0, _scan_wait - 1)

	# A committed attack owns the tower until it lands. It still aims, so the
	# swing tracks, but nothing may retarget it and nothing may start a second.
	if _windup_left > 0.0:
		_advance_windup(delta, attack)
		return

	_drop_lost_target(attack)
	# After the drop, deliberately: a standing order is the answer to what to
	# shoot, so it must not be thrown away by the same pass that clears a
	# target which wandered off.
	_apply_order(attack)

	# Scanning only when the tower could actually shoot keeps the cost down: a
	# tower on cooldown has nothing to do with a new target anyway, and it goes
	# on aiming at the last one meanwhile.
	#
	# That alone was not enough, because it only ever protects a tower that is
	# FIRING. One with nothing in range never fires, so its cooldown never
	# starts and never runs down - both halves stayed true on every tick for
	# the whole match, and most of a full maze is in exactly that state. The
	# wait is the other half: after a search comes back empty, it does not
	# search again for a few ticks. See GameConfig.idle_target_scan_ticks.
	if _target == null && _cooldown <= 0.0 && _scan_wait <= 0:
		_target = _acquire(attack)
		if _target == null:
			_scan_wait = _next_scan_wait()

	if _target == null:
		return

	_aim(delta)
	if _cooldown <= 0.0:
		_begin_attack(attack)


## Ticks to wait before searching again, after a search that found nothing.
##
## The FIRST wait of a unit's life is spread by its own id and every one after
## it is the plain interval. Without that spread a maze whose towers all went
## up together comes due on the same tick forever after, which turns a cost
## that was flat into a spike every few ticks - the same total work, arriving
## in a way that is worse for frame pacing than what it replaced.
##
## The id is the spread rather than a roll, because it is a number the server
## and every client already agree on, so nothing here can make two machines
## search on different ticks.
func _next_scan_wait() -> int:
	var config: GameConfig = References.game_config
	var ticks: int = 1 if config == null else config.idle_target_scan_ticks
	if ticks <= 1:
		return 0

	if !_scan_phased:
		_scan_phased = true
		var id: int = 0 if _unit == null else _unit.unit_id
		return 1 + (id % ticks)
	return ticks


## The target this unit picks for itself, which is a different search per
## target class. Nothing else in here has to know which kind it got back.
func _acquire(attack: AttackStats) -> Unit:
	if attack.hits_buildings():
		return TargetFinder.best_building_target(_unit.area, _origin(), attack)
	return TargetFinder.best_target(_unit.area, _origin(), attack, _prioritize_air)


## Forgets a target that died, left range, or stopped being a legal target.
func _drop_lost_target(attack: AttackStats) -> void:
	if _target == null:
		return
	# Either way this unit just lost something it could see, which is the one
	# moment its picture of the lane is known to be stale. Whatever was left of
	# its idle wait is thrown away rather than delaying the replacement.
	if !TargetFinder.is_in_range(_origin(), _target, attack.attack_range):
		_target = null
		_scan_wait = 0
		return
	if !_is_valid_target(_target, attack):
		_target = null
		_scan_wait = 0


## Points this unit at what it was ORDERED onto, whenever that is reachable.
##
## Forgets an order whose target is gone, so nothing has to come back and tidy
## up after a creep that died to somebody else's tower. Out of reach and still
## alive is neither of those: the order stands, and this unit shoots whatever
## it can meanwhile - a tower because it cannot do anything else, a unit that
## can walk because its task is already walking it closer.
func _apply_order(attack: AttackStats) -> void:
	if _ordered_target == null:
		return
	if ordered_target() == null:
		_ordered_target = null
		return
	if TargetFinder.is_in_range(_origin(), _ordered_target, attack.attack_range):
		_target = _ordered_target


## Commits to an attack. The cooldown starts HERE rather than when the damage
## lands, which is what keeps the windup inside the attack period instead of on
## top of it - see AttackStats.windup_seconds.
func _begin_attack(attack: AttackStats) -> void:
	# Asked of the UNIT rather than read off the stats, so an aura standing
	# over an attacker creep really does make it swing faster. Every tower
	# answers 1.0 and pays nothing for the question.
	_cooldown = attack.cooldown_seconds() / maxf(0.01, _unit.attack_speed_ratio())
	_windup_target = _target
	_windup_point = _target.global_position
	_windup_left = attack.windup_seconds_clamped()

	# The tower's own abilities hear about the attack the moment it COMMITS,
	# not when it lands: mana gained by attacking, a ramp that resets on a new
	# target and an idle bonus being cashed in are all per attack rather than
	# per creep struck. See TowerPassive.on_attack.
	var tower: Building = _unit as Building
	if tower != null:
		for passive in tower.tower_passives():
			passive.on_attack(tower, _target)

	attack_started.emit(_target, _windup_left)
	if _windup_left <= 0.0:
		_release(attack)


## Keeps the aim and the remembered impact point up to date while the swing
## plays out, so a windup tracks a walking creep instead of committing to where
## it stood a moment ago.
func _advance_windup(delta: float, attack: AttackStats) -> void:
	if is_instance_valid(_windup_target) && _windup_target.is_alive():
		_windup_point = _windup_target.global_position
		_target = _windup_target
		_aim(delta)

	_windup_left -= delta
	if _windup_left <= 0.0:
		_release(attack)


## Drops a swing that can no longer land. Nothing is refunded: the cooldown was
## already spent, exactly as it would have been if the attack had landed.
func _cancel_windup() -> void:
	_windup_left = 0.0
	_windup_target = null


## Releases the damage of a committed attack.
##
## A creep that died during the windup leaves the swing to land where it stood,
## so a splash still catches the crowd around it - the same rule a projectile
## already follows when its target dies mid flight.
func _release(attack: AttackStats) -> void:
	var target: Unit = _windup_target
	var point: Vector3 = _windup_point
	_windup_left = 0.0
	_windup_target = null

	var gone: bool = target == null || !is_instance_valid(target) || !target.is_alive()
	_fire(attack, null if gone else target, point)
	if gone:
		_target = null
		_scan_wait = 0


func _fire(attack: AttackStats, target: Unit, point: Vector3) -> void:
	# ONE roll for the whole attack, shared by the primary target and by every
	# creep a multishot picks up alongside it - the same rule splash already
	# follows, and for the same reason: a player watching one shot land should
	# not see three different numbers come off it.
	var rolled: int = attack.roll_damage(MatchSession.match_rng())
	_send(attack, _new_hit(attack, rolled, true), target, point)

	for extra: Unit in _extra_targets(attack, target):
		_send(attack, _new_hit(attack, rolled, false), extra, extra.global_position)

	attacked.emit(target)


## One AttackHit, filled in from the attack and from the tower firing it.
func _new_hit(attack: AttackStats, rolled: int, primary: bool) -> AttackHit:
	var hit: AttackHit = AttackHit.new()
	hit.damage = rolled
	hit.damage_type = attack.damage_type
	hit.is_aoe = attack.is_aoe_damage
	# A creep picked up by a multishot takes no splash of its own: the splash
	# belongs to the shot, and running it once per extra target would multiply
	# a splash tower's output by however many creeps were standing about.
	hit.effects = attack.effects if primary else ([] as Array[AttackEffect])
	hit.area = _unit.area
	hit.attacker_player_id = _unit.owner_player_id
	hit.attacker_position = _origin()
	hit.is_primary = primary

	var tower: Building = _unit as Building
	if tower != null:
		hit.source = tower
		hit.passives = tower.tower_passives()
	return hit


## Hands one hit to the delivery, or lands it where the target stood if there
## is nothing left to hand it to.
func _send(attack: AttackStats, hit: AttackHit, target: Unit, point: Vector3) -> void:
	if target == null:
		hit.resolve(null, point)
		if attack.delivery != null:
			attack.delivery.spawn_impact(point, muzzle_position())
		return

	if attack.delivery == null:
		# An attack with no delivery is a half authored resource. Landing it
		# instantly makes that visible in play rather than as silence.
		Log.err("AttackStats has no delivery assigned", _unit.name)
		hit.resolve(target, target.global_position)
		return

	attack.delivery.deliver(hit, muzzle_position(), target)


## The further creeps this attack strikes alongside its primary target.
##
## MULTISHOT, and it is a different thing from splash: it picks several single
## targets standing near the one that was aimed at, so it is not area damage
## and a creep that resists area damage gets no help from it. See
## game_rules.md.
##
## The count comes off the attack's own stats PLUS whatever the tower's
## passives add, because nearly every elemental tower that multishots does it
## through an ability rather than through its base attack.
func _extra_targets(attack: AttackStats, target: Unit) -> Array[Unit]:
	var found: Array[Unit] = []
	if target == null || _unit == null || _unit.area == null:
		return found

	var wanted: int = attack.multishot_targets + _passive_extra_targets()
	if wanted <= 0:
		return found

	var reach: float = _multishot_reach()
	for creep: Creep in TargetFinder.creeps_in_radius(
			_unit.area, target.global_position, reach):
		if found.size() >= wanted:
			break
		if creep == target || !TargetFinder.can_be_hit_by(creep, attack):
			continue
		found.append(creep)
	return found


func _passive_extra_targets() -> int:
	var tower: Building = _unit as Building
	if tower == null:
		return 0
	var extra: int = 0
	for passive in tower.tower_passives():
		extra += passive.extra_targets(tower)
	return extra


## How far from the primary target a further creep may stand.
##
## ONE distance shared by the whole game unless a passive names its own, which
## is game_rules.md's rule: a player learns the reach of a multishot once
## rather than per tower.
func _multishot_reach() -> float:
	var tower: Building = _unit as Building
	if tower != null:
		for passive in tower.tower_passives():
			var named: float = passive.extra_target_range(tower)
			if named > 0.0:
				return named

	var config: GameConfig = References.game_config
	if config == null:
		return MULTISHOT_FALLBACK_REACH
	return config.multishot_reach_cells


## Point range is measured from, which is the unit itself rather than the
## muzzle: a barrel swinging around must not change how far a tower reaches.
func _origin() -> Vector3:
	return _unit.global_position


## Where shots leave this unit, in world space. Public because an ability that
## draws something from the tower to a creep needs the same point the attack
## itself left from - an arc strung from the tower's feet reads as coming out
## of the ground. See FocusedLightningPassive.
func muzzle_position() -> Vector3:
	if _muzzle != null:
		return _muzzle.global_position
	return _unit.global_position + Vector3(0.0, MUZZLE_FALLBACK_HEIGHT, 0.0)


## Swings the turret around towards the target, flat on the xz plane. Models
## face -Z by Godot's convention, which is what the angle is built from.
func _aim(delta: float) -> void:
	if _turret_head == null || !turn_towards_target:
		return

	var offset: Vector3 = _target.global_position - _turret_head.global_position
	if absf(offset.x) < 0.0001 && absf(offset.z) < 0.0001:
		return

	var wanted: float = atan2(-offset.x, -offset.z)
	_turret_head.global_rotation.y = rotate_toward(
		_turret_head.global_rotation.y, wanted, turret_turn_speed * delta
	)


# --- editor only ------------------------------------------------------------
#
# Shown rather than stored: these are DERIVED from the unit's stats, so they
# carry PROPERTY_USAGE_EDITOR without PROPERTY_USAGE_STORAGE and can never be
# saved into a prefab or drift from the resource they are read out of. They are
# read only for the same reason - the stats file is the one place to change
# them.

func _get_property_list() -> Array[Dictionary]:
	var shown: Array[Dictionary] = []
	if !Engine.is_editor_hint():
		return shown

	shown.append({
		"name": "Attack Visuals",
		"type": TYPE_NIL,
		"usage": PROPERTY_USAGE_GROUP,
	})
	for entry: String in ["projectile_scene", "impact_scene"]:
		shown.append({
			"name": entry,
			"type": TYPE_OBJECT,
			"hint": PROPERTY_HINT_RESOURCE_TYPE,
			"hint_string": "PackedScene",
			"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY,
		})
	return shown


func _get(property: StringName) -> Variant:
	if !Engine.is_editor_hint():
		return null
	if property == &"projectile_scene":
		return _editor_scene(_editor_delivery_path("projectile_scene_path"))
	if property == &"impact_scene":
		return _editor_scene(_editor_delivery_path("impact_scene_path"))
	return null


## The path one of the delivery's scene fields holds, or empty when this tower
## has no attack, no delivery, or a delivery without that field - an instant
## attack has no projectile, which is an answer rather than a fault.
func _editor_delivery_path(field: String) -> String:
	var attack: AttackStats = _attack
	if attack == null || attack.delivery == null:
		return ""
	var path: Variant = attack.delivery.get(field)
	return "" if path == null else String(path)


func _editor_scene(path: String) -> PackedScene:
	if path.is_empty() || !ResourceLoader.exists(path):
		return null
	return load(path) as PackedScene
