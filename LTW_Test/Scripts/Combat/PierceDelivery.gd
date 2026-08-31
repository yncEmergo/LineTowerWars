class_name PierceDelivery
extends AttackDelivery

## The tower fires a shot that does NOT home. It leaves along the line to
## wherever the target stood, damages every creep it passes through on the way,
## and gives up after a fixed distance whether or not it hit anything.
##
## The one attack in the game that can MISS, and the one whose reach is not the
## tower's: `travel_cells` is how far the shot itself flies, which is longer
## than the range the tower acquires targets at. A creep that walks into the
## line after the shot left is hit; the creep it was aimed at can walk out of it
## and take nothing. Both of those are the point.
##
## A different SUBCLASS rather than a flag on ProjectileDelivery, because "does
## it home" is not a setting on one behaviour - a homing shot cannot miss and
## resolves exactly once, and neither is true here. See CLAUDE.md on why one
## exclusive choice is a polymorphic resource.
##
## NO PHYSICS, like everything else: the shot is a point walking along a line
## and a creep is struck when the distance from its centre to the SEGMENT
## covered this tick is small enough. Testing the segment rather than the
## endpoint is not optional - a fast shot covers more than a creep's width in
## one tick and would otherwise step straight over it.
##
## Like splash, it does not ask whether the attack may target ground or air. A
## spike flying down a lane goes through what is standing in it.

@export_group("Projectile")
## Prefab flown down the line, as a res:// path. Its root must carry the
## PiercingProjectile script.
@export_file("*.tscn") var projectile_scene_path: String = ""
## World units per second.
@export var speed: float = 24.0
## How far the shot flies before it gives up, in player cells. Deliberately
## authored against the TOWER's width rather than its range: what a player
## reads off a piercing shot is how far down the lane it reaches, and that
## should not move every time the tower's targeting range is retuned.
@export var travel_cells: float = 8.0
## How close the shot's centre passes to a creep's centre to strike it, in
## cells, on top of that creep's own body radius. Half a cell each side is what
## HitPattern's instant line uses and this is the moving version of it.
@export var hit_radius: float = 0.35
## Damage type dealt to every creep AFTER the first, or -1 for the attack's own.
##
## The first creep struck is an ordinary hit and goes through the whole
## pipeline; the ones behind it are what the shot did on its way past. An
## attack whose ability says it pierces armour authors Spell Damage here, which
## is what already ignores both the matrix and the points.
@export var trailing_damage_type: int = -1

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
	var root: Node3D = References.projectiles_root
	var scene: PackedScene = projectile_scene()
	if scene == null || root == null || target == null:
		# Better a hit that lands instantly than a tower that silently does
		# nothing, which reads as a targeting bug rather than a missing prefab.
		Log.err("PierceDelivery cannot spawn a projectile, hitting instantly")
		hit.resolve(target, from)
		return

	# Aimed FLAT at where the target stands now, and then committed to. Flat
	# because the game is played on the xz plane and a shot tipped up at a
	# muzzle would climb away from the lane it was fired down.
	var direction: Vector3 = target.global_position - from
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		hit.resolve(target, from)
		return

	var projectile: PiercingProjectile = scene.instantiate() as PiercingProjectile
	if projectile == null:
		Log.err("Pierce projectile's root is not a PiercingProjectile",
			projectile_scene_path)
		hit.resolve(target, from)
		return

	root.add_child(projectile)
	projectile.launch(self, hit, from, direction.normalized())


## What a creep behind the first one takes, given the attack's own type.
func trailing_type(own: DamageTable.DamageType) -> DamageTable.DamageType:
	if trailing_damage_type < 0:
		return own
	return trailing_damage_type as DamageTable.DamageType


## The projectile is required, exactly as it is for a homing delivery: without
## one there is nothing to fly down the line.
func validate(owner_name: String) -> bool:
	var complete: bool = super(owner_name)

	if !SceneUtil.exists(projectile_scene_path):
		Log.err("Attack projectile_scene_path does not resolve", {
			"owner": owner_name,
			"path": projectile_scene_path,
		})
		complete = false

	return complete
