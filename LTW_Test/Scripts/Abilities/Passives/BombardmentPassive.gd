class_name BombardmentPassive
extends CreepPassive

## Lobs a rocket at a random tower nearby on a clock of its own.
##
## The Siege Engine's second trait, and the only ranged attack any creep in the
## roster has. unit_data.md 6.3: "Bombardment fires a rocket at a random tower
## within 400 radius every 4 sec."
##
## A SECOND attack, running alongside the creep's own. The Siege Engine is an
## attacker, so its AttackComponent is already busy chewing on whatever it
## walked up to; this fires whether or not that is happening and at something
## else entirely. Which is why the rocket is an AttackStats of its own here
## rather than anything the component knows about.
##
## RANDOM rather than nearest, which is the whole character of it: a Siege
## Engine cannot be walled off from the tower it is hurting, and a maze loses
## value from the back as readily as from the front. Rolled on the match RNG,
## so every machine picks the same tower - see MatchSession.match_rng().
##
## The CLOCK lives on the creep. This resource is every Siege Engine on the
## field at once and may remember nothing, so it asks the creep to advance a
## countdown it owns. See Creep.advance_passive_clock().

@export_group("Settings")
## Seconds between rockets.
@export var interval_seconds: float = 4.0
## How far a rocket reaches, in player cells. The source states it as a 400
## radius, which snaps to 3 at the quarter every reach in the game is stated
## in - see unit_data.md 3.
@export var radius_cells: float = 3.0

@export_group("Rocket")
## What one rocket is: its damage, its type, and how it gets there. An
## AttackStats rather than a damage number, so a rocket is authored the same
## way every other attack in the game is and can grow splash or a projectile
## without this script changing. Its own attack_range and attacks_per_second
## are ignored - the two above are what this passive runs on.
@export var rocket: AttackStats


func on_tick(creep: Creep, delta: float) -> void:
	if rocket == null || !creep.is_alive():
		return

	# A creep held still cannot act. Checked here rather than by the caller
	# because a passive that merely COUNTS should keep counting through a stun,
	# and this one is an action.
	var status: StatusEffects = creep.status_or_null()
	if status != null && status.is_held():
		return

	if !creep.advance_passive_clock(self, interval_seconds, delta):
		return

	var target: Building = _pick_target(creep)
	if target == null:
		return
	_fire(creep, target)


## One tower in reach, chosen at random, or null when none is.
##
## Rolled on the match RNG rather than on a local one, for the reason every
## other roll in the simulation is: two machines running the same match have to
## bombard the same tower, or their worlds part company on the first rocket.
func _pick_target(creep: Creep) -> Building:
	var reachable: Array[Building] = TargetFinder.buildings_in_radius(
		creep.area, creep.global_position, radius_cells)
	if reachable.is_empty():
		return null
	return reachable[MatchSession.match_rng().randi_range(0, reachable.size() - 1)]


## Builds the hit and hands it to the rocket's own delivery.
##
## The hit is assembled here rather than through AttackComponent because no
## component owns this attack: the creep's component is aimed at something
## else, and a second component per Siege Engine would be a whole node carrying
## a target and a cooldown neither of which this uses. `source` and `passives`
## stay empty on purpose - both are a TOWER's, and nothing feeds a creep's
## attack back to it.
func _fire(creep: Creep, target: Building) -> void:
	var hit: AttackHit = AttackHit.new()
	hit.damage = rocket.roll_damage(MatchSession.match_rng())
	hit.damage_type = rocket.damage_type
	hit.is_aoe = rocket.is_aoe_damage
	hit.effects = rocket.effects
	hit.area = creep.area
	hit.attacker_player_id = creep.owner_player_id
	hit.attacker_position = creep.global_position

	if rocket.delivery == null:
		Log.err("Bombardment's rocket has no delivery assigned", display_name)
		hit.resolve(target, target.global_position)
		return
	rocket.delivery.deliver(hit, creep.global_position, target)


## Reports a rocket that could never be fired, at boot rather than four seconds
## into the first Siege Engine's walk.
func validate(seen: Dictionary) -> bool:
	var complete: bool = super(seen)
	if rocket == null:
		Log.err("Bombardment has no rocket assigned", display_name)
		return false
	return rocket.validate(display_name) && complete


func effect_text() -> String:
	return ("Fires a rocket at a random tower within %s every %s"
		+ " seconds.") % [
		StringUtil.trim_number(radius_cells),
		StringUtil.trim_number(interval_seconds),
	]
