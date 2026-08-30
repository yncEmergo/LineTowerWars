class_name ProjectileDelivery
extends AttackDelivery

## The tower spawns a projectile that flies to the target and lands the damage
## when it arrives.
##
## The travel time is real: a slow orb fired at a creep about to leave the
## tower's range still has to catch up with it, and a target that dies on the
## way leaves the orb to land where it stood. That is the whole reason a
## projectile tower feels different from an instant one.

@export_group("Projectile")
## Prefab flown to the target, as a res:// path. Its root must carry the
## Projectile script.
@export_file("*.tscn") var projectile_scene_path: String = ""
## World units per second.
@export var speed: float = 18.0
## How high the flight bows upwards at its midpoint. 0 is a flat shot, which is
## what a rifle wants and a mortar does not.
@export var arc_height: float = 0.0
## Where the shot is SPAWNED, as an offset from the point it will land rather
## than from the muzzle it was fired out of.
##
## Zero is an ordinary shot leaving the tower, which is nearly everything. A
## high, sideways offset is a shot CALLED DOWN on the target instead: the
## projectile appears above and to one side of the creep and dives onto it, and
## the tower that fired is nowhere on the line. That is what a meteor is.
##
## An offset rather than a subclass of its own, because it changes where the
## flight STARTS and nothing else - it still homes, still takes real time, and
## still lands its damage on arrival. Author it with enough height to clear the
## top of the frame or the shot is seen appearing out of nothing.
@export var sky_launch_offset: Vector3 = Vector3.ZERO

## Cached projectile and whether loading it has been tried. Asked once per
## shot, so it must not go back to the loader every time a tower fires.
var _cached_projectile: PackedScene = null
var _projectile_loaded: bool = false


## The projectile prefab, loaded the first time this tower actually fires.
func projectile_scene() -> PackedScene:
	if !_projectile_loaded:
		_projectile_loaded = true
		_cached_projectile = SceneUtil.load_scene(projectile_scene_path, "projectile")
	return _cached_projectile


func deliver(hit: AttackHit, from: Vector3, target: Unit) -> void:
	# The PROJECTILES root, not the effects root. Flight time is simulation:
	# the target keeps walking while the shot is in the air and the damage lands
	# on arrival, so a headless server must fly it exactly as a client does.
	# Resolving instantly instead would make the server and the client disagree
	# about when a creep died.
	var root: Node3D = References.projectiles_root
	var scene: PackedScene = projectile_scene()
	if scene == null || root == null:
		# Better a hit that lands instantly than a tower that silently does
		# nothing, which reads as a targeting bug rather than a missing prefab.
		Log.err("ProjectileDelivery cannot spawn a projectile, hitting instantly")
		hit.resolve(target, from)
		return

	var projectile: Projectile = scene.instantiate() as Projectile
	if projectile == null:
		Log.err("Projectile scene's root is not a Projectile", projectile_scene_path)
		hit.resolve(target, from)
		return

	root.add_child(projectile)
	projectile.launch(self, hit, _launch_point(from, target), target)


## Where this shot starts. The muzzle for an ordinary attack, and a point over
## the target for one that is called down - see sky_launch_offset.
##
## Measured off where the target stands NOW rather than off the muzzle, which is
## the whole point: a meteor should fall onto the creep from the same direction
## every time, whichever tower called it and wherever that tower stands.
func _launch_point(from: Vector3, target: Unit) -> Vector3:
	if sky_launch_offset == Vector3.ZERO || target == null:
		return from
	return target.global_position + sky_launch_offset


## Called by the projectile when it arrives, so the impact visual stays a
## property of the delivery rather than of every projectile prefab.
func on_impact(hit: AttackHit, target: Unit, at: Vector3) -> void:
	hit.resolve(target, at)
	spawn_impact(at, hit.attacker_position)


## The projectile is required, unlike the impact visual the base class checks:
## a projectile delivery with no prefab cannot deliver anything.
func validate(owner_name: String) -> bool:
	var complete: bool = super(owner_name)

	if !SceneUtil.exists(projectile_scene_path):
		Log.err("Attack projectile_scene_path does not resolve", {
			"owner": owner_name,
			"path": projectile_scene_path,
		})
		complete = false

	return complete
