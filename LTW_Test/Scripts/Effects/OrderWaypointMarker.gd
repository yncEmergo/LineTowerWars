class_name OrderWaypointMarker
extends Node3D

## Small standing marker on a point a unit still has to walk to.
##
## The QUIET relative of MoveOrderMarker. That one is a flourish that answers
## a click and then goes; this one is a note on the ground that stays for as
## long as the task does, and there can be six of them at once. So it holds
## still, sits low and says nothing until the unit arrives and it is taken
## away - a second set of converging arrows per waypoint would turn a chain of
## orders into a light show.
##
## PRESENTATION, and local from end to end. Nothing here is an order, the
## server has none of these, and the other player has no business seeing your
## plan. See OrderOverlay.

## What the unit is going to that point FOR, which is the whole of what the
## colour says.
enum Kind {
	## Walking there and nothing else.
	MOVE,
	## Walking there looking for a fight - an attack-move. Red, so a lane full
	## of waypoints can be read at a glance for which of them mean trouble.
	ATTACK,
}

# Placeholder visual values, so they stay in the script.
const MOVE_COLOR: Color = Color(0.30, 0.95, 0.35, 0.75)
## The same red the attack order's own ring uses, so "this is an attack" is one
## colour across the whole interface rather than two that nearly match.
const ATTACK_COLOR: Color = Color(0.95, 0.22, 0.20, 0.78)
## Radius of the flat disc on the floor.
const RING_RADIUS: float = 0.20
const RING_THICKNESS: float = 0.045
## Height of the pin standing in the middle of it.
const PIN_HEIGHT: float = 0.26
const PIN_RADIUS: float = 0.035
## Height above the ground, clear of the build grid overlay at 0.02 and of the
## move order marker at 0.05 - a chained order drops both on the same spot.
const GROUND_OFFSET: float = 0.06

var _material: StandardMaterial3D


func _ready() -> void:
	# Animated by nothing, but it is parented to a static effects root and
	# never moves, so it wants no interpolation of its own either.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build()


## Places the marker on the ground at a world point, in the colour of whatever
## is going to happen there.
## Call after the marker is in the tree, since it sets a global position and
## the material it recolours is built in _ready.
func place_at(world_position: Vector3, kind: Kind = Kind.MOVE) -> void:
	global_position = Vector3(world_position.x, GROUND_OFFSET, world_position.z)
	if _material != null:
		_material.albedo_color = MOVE_COLOR if kind == Kind.MOVE else ATTACK_COLOR


func _build() -> void:
	_material = StandardMaterial3D.new()
	_material.albedo_color = MOVE_COLOR
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Both this and the build grid are transparent and nearly coplanar, so
	# sort the marker after the grid rather than leaving it to depth order.
	_material.render_priority = 1

	var ring: TorusMesh = TorusMesh.new()
	ring.inner_radius = RING_RADIUS - RING_THICKNESS
	ring.outer_radius = RING_RADIUS
	ring.rings = 16
	ring.material = _material
	_add_mesh("Ring", ring, Vector3.ZERO)

	# The pin is what makes one of these readable from the game's camera angle:
	# a flat ring alone reads as a scorch mark on the floor at this distance.
	var pin: CylinderMesh = CylinderMesh.new()
	pin.top_radius = 0.0
	pin.bottom_radius = PIN_RADIUS
	pin.height = PIN_HEIGHT
	pin.radial_segments = 8
	pin.rings = 1
	pin.material = _material
	_add_mesh("Pin", pin, Vector3(0.0, PIN_HEIGHT * 0.5, 0.0))


func _add_mesh(mesh_name: String, mesh: Mesh, offset: Vector3) -> void:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	instance.position = offset
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
