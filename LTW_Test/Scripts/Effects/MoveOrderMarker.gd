class_name MoveOrderMarker
extends Node3D

## Short lived ground marker showing where a move order was issued.
##
## Four arrows point inward at the target, slide in until their tips meet in
## the centre, hold briefly and fade out. Built from primitives in code like
## the other placeholder visuals, and frees itself when the animation ends.

# Placeholder visual values, so they stay in the script.
const ARROW_COUNT: int = 4
## Arrow footprint: width across, length along the pointing direction, thickness.
const ARROW_SIZE: Vector3 = Vector3(0.30, 0.34, 0.05)
## How far out from the target the arrows start before sliding inwards.
const ARROW_START_DISTANCE: float = 0.62
const MARKER_COLOR: Color = Color(0.30, 0.95, 0.35, 0.95)
## Height above the ground, clear of the build grid overlay at 0.02.
const GROUND_OFFSET: float = 0.05

const CONVERGE_TIME: float = 0.40
const FADE_TIME: float = 0.15

var _material: StandardMaterial3D
var _arrows: Array[MeshInstance3D] = []


func _ready() -> void:
	_build_arrows()
	_play()


## Places the marker on the ground at a world point.
## Call after the marker is in the tree, since it sets a global position.
func place_at(world_position: Vector3) -> void:
	global_position = Vector3(world_position.x, GROUND_OFFSET, world_position.z)


func _build_arrows() -> void:
	# Unique per marker, because the fade animates this material's alpha.
	_material = StandardMaterial3D.new()
	_material.albedo_color = MARKER_COLOR
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Both this and the build grid are transparent and nearly coplanar, so
	# sort the marker after the grid rather than leaving it to depth order.
	_material.render_priority = 1

	var mesh: PrismMesh = PrismMesh.new()
	mesh.size = ARROW_SIZE
	mesh.material = _material

	for index in range(ARROW_COUNT):
		var pivot: Node3D = Node3D.new()
		pivot.name = "ArrowPivot%d" % index
		pivot.rotation.y = float(index) * TAU / float(ARROW_COUNT)
		add_child(pivot)

		var arrow: MeshInstance3D = MeshInstance3D.new()
		arrow.name = "Arrow"
		arrow.mesh = mesh
		arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# A prism's triangle stands in xy with the tip up, so tipping it flat
		# leaves the tip pointing along -z, back towards the marker centre.
		arrow.rotation.x = -PI * 0.5
		arrow.position = Vector3(0.0, 0.0, ARROW_START_DISTANCE)
		pivot.add_child(arrow)
		_arrows.append(arrow)


## Distance from the centre at which the arrow tips meet. A prism is centred on
## its own origin, so half the arrow length puts the tip exactly at zero.
func _tip_touching_distance() -> float:
	return ARROW_SIZE.y * 0.5


func _play() -> void:
	var end_distance: float = _tip_touching_distance()

	var tween: Tween = create_tween()
	tween.set_parallel(true)

	# Each arrow slides along its own pivot's forward axis, so all four end
	# with their tips meeting in the middle.
	for arrow in _arrows:
		tween.tween_property(arrow, "position:z", end_distance, CONVERGE_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# Delayed past the slide so the arrows hold together briefly before fading.
	tween.tween_property(_material, "albedo_color:a", 0.0, FADE_TIME) \
		.set_delay(CONVERGE_TIME)
	# chain() waits for every tweener above before the marker removes itself.
	tween.chain().tween_callback(queue_free)
