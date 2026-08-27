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
##
## The effect is TURNED TO FACE where the hit came from, so a scene can be
## authored knowing which way is "back towards the tower" - a spray of blood
## off the near side of a creep needs that, and a plain flash simply ignores it.
## Godot's forward is -Z, so an effect's -Z ends up pointing at the attacker.
##
## Orientation rather than an offset, deliberately: how far towards the tower a
## given effect should sit depends on the effect, so it belongs in the scene
## next to the thing being offset rather than as a number here.
func spawn_impact(at: Vector3, from: Vector3 = Vector3.ZERO) -> void:
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

	# Flat, because the game is played on the xz plane and an effect tipped up
	# at a muzzle would read as leaning over.
	var back: Vector3 = from - at
	back.y = 0.0
	if back.length_squared() > 0.0001:
		effect.look_at(at + back.normalized(), Vector3.UP)

	# LAST, and it has to be last. Particles emit in world space and a one-shot
	# burst fires the moment it is allowed to, so an effect that started
	# emitting on the way into the tree would leave its whole spray at the
	# effects root's origin instead of on the creep. See VisualEffect3D.play().
	var visual: VisualEffect3D = effect as VisualEffect3D
	if visual != null:
		visual.play()


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
