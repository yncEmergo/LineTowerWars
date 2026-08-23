@abstract
class_name AttackDelivery
extends Resource

## How an attack's damage gets from the tower to the target.
##
## Exactly one per attack, and picking the subclass is what answers "is this a
## projectile". A flag would need a matching flag for every future way of
## landing a hit, and a branch somewhere reading all of them.
##
## Like abilities, a delivery is a shared resource carrying its own behaviour,
## so it must stay STATELESS. Everything one shot needs travels in the
## AttackHit, which is created per attack.

@export_group("Visuals")
## Spawned where the hit lands, as a res:// path. Optional on purpose: a tower
## can be a spinning blade that simply hurts whatever stands next to it, so an
## empty path means no visual rather than a missing one.
@export_file("*.tscn") var impact_scene_path: String = ""

## Cached impact and whether loading it has been tried, see impact_scene().
var _cached_impact: PackedScene = null
var _impact_loaded: bool = false


## Sends the hit on its way. from is the muzzle the attack leaves, which for an
## instant attack is only where a visual would start.
@abstract func deliver(hit: AttackHit, from: Vector3, target: Unit) -> void


## The impact visual, or null when this delivery has none. An empty path is an
## answer rather than a fault, so it never reaches the loader.
func impact_scene() -> PackedScene:
	if impact_scene_path.is_empty():
		return null
	if !_impact_loaded:
		_impact_loaded = true
		_cached_impact = SceneUtil.load_scene(impact_scene_path, "impact")
	return _cached_impact


## Drops the impact visual at a world point, if this delivery has one. Parented
## to the shared effects root rather than to the tower, so selling the tower
## mid animation cannot take the effect with it.
func spawn_impact(at: Vector3) -> void:
	var scene: PackedScene = impact_scene()
	if scene == null:
		return

	var root: Node3D = References.effects_root
	if root == null:
		return

	var effect: Node3D = scene.instantiate() as Node3D
	if effect == null:
		Log.err("Impact scene's root is not a Node3D", impact_scene_path)
		return

	root.add_child(effect)
	effect.global_position = at


## Reports a filled-in path that does not resolve. Called at boot through the
## attack that owns this delivery.
func validate(owner_name: String) -> bool:
	if impact_scene_path.is_empty() || SceneUtil.exists(impact_scene_path):
		return true

	Log.err("Attack impact_scene_path does not resolve", {
		"owner": owner_name,
		"path": impact_scene_path,
	})
	return false
