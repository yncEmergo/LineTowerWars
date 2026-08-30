class_name BurningGroundEffect
extends AttackEffect

## Sets the ground alight where the attack landed. Whatever stands in it keeps
## taking damage until the fire goes out.
##
## The lingering half of a shot that arrives with weight behind it - a meteor
## leaves a crater that is still burning after the rock has stopped moving. It
## stacks with splash rather than replacing it: the splash is what the impact
## did, this is what the ground does afterwards.
##
## Its damage is a SHARE OF THE ATTACK'S OWN, so one authored row covers every
## tier of a path and the fire can never drift out of step with the shot that
## lit it. The share is read off `hit.damage`, which by the time an effect runs
## is what the attack really dealt including whatever its tower's passives
## added - the same number splash is measured against, and for the same reason.
##
## Shared and stateless like every other effect. The fire itself is a
## GroundHazard node, which is where all the per-patch state lives.

# THE DEFAULTS BELOW ARE ALL "NO FIRE" on purpose, and three of them are 0
# rather than a sensible number. The .tres is the authority for what a
# particular attack sets alight, and the editor STRIPS any property that
# happens to equal its script default when it saves a file - so a default
# matching real authored data would quietly move that data into this script.
# See CLAUDE.md. An unfilled row simply does not burn, which apply() answers
# for without a special case.
@export_group("Burning Ground")
## Radius of the patch, in player cells. Usually the attack's own splash, so
## the ground that keeps burning is the ground the player watched explode.
@export var radius: float = 0.0
## How long the ground burns.
@export var duration_seconds: float = 0.0
## Seconds between ticks. The first one lands a full interval AFTER the fire
## catches, because the attack that lit it has already hit everything there.
@export var tick_seconds: float = 0.5
## Damage dealt per second, as a share of what the attack dealt. An eighth of a
## shot per second over three seconds is a bit over a third of it, spread out
## and reaching anything that walks in afterwards.
@export var damage_share_per_second: float = 0.0
## What the fire deals. Spell Damage by default, which is what nearly every
## tower ABILITY in the game deals and what makes this ignore armour - see
## unit_data.md 1.1.
@export var damage_type: DamageTable.DamageType = DamageTable.DamageType.SPELL

@export_group("Visuals")
## The patch itself, as a res:// path. Its root must carry the GroundHazard
## script, and it must be authored at RADIUS 1 - this scales it to the real one.
@export_file("*.tscn") var hazard_scene_path: String = ""

## Cached hazard and whether loading it has been tried. Asked once per hit, so
## it must not go back to the loader every time something burns.
var _cached_hazard: PackedScene = null
var _hazard_loaded: bool = false


func apply(hit: AttackHit, _target: Unit, impact_point: Vector3) -> void:
	if hit == null || hit.area == null || radius <= 0.0 || duration_seconds <= 0.0:
		return

	var per_tick: int = int(round(
		float(hit.damage) * damage_share_per_second * tick_seconds))
	if per_tick <= 0:
		return

	# The PROJECTILES root, not the effects root: the fire deals damage over
	# real time, so a headless server has to run it exactly as a client does.
	# See GroundHazard on why that is safe on both.
	var root: Node3D = References.projectiles_root
	var scene: PackedScene = hazard_scene()
	if scene == null || root == null:
		return

	var hazard: GroundHazard = scene.instantiate() as GroundHazard
	if hazard == null:
		Log.err("Burning ground scene's root is not a GroundHazard", hazard_scene_path)
		return

	root.add_child(hazard)
	hazard.global_position = impact_point
	hazard.light(hit.area, radius, per_tick, tick_seconds, duration_seconds,
		damage_type)


## The patch prefab, loaded the first time something actually catches fire.
func hazard_scene() -> PackedScene:
	if !_hazard_loaded:
		_hazard_loaded = true
		_cached_hazard = SceneUtil.load_scene(hazard_scene_path, "burning ground")
	return _cached_hazard


func effect_name() -> String:
	return "Burning Ground"


func description_text() -> String:
	return ("Leaves the ground burning for %s seconds, dealing %s%% of the"
		+ " damage dealt per second to everything within %s cells.") % [
		StringUtil.trim_number(duration_seconds),
		StringUtil.trim_number(damage_share_per_second * 100.0),
		StringUtil.trim_number(radius),
	]


## The hazard is required, unlike an impact visual: a burning ground with no
## patch to spawn is a fire nobody can see standing on.
func validate(owner_name: String) -> bool:
	if SceneUtil.exists(hazard_scene_path):
		return true

	Log.err("Burning ground hazard_scene_path does not resolve", {
		"owner": owner_name,
		"path": hazard_scene_path,
	})
	return false
