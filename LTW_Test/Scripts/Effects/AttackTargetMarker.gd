class_name AttackTargetMarker
extends Node3D

## Red ring that blinks around the creep an attack order was just given on.
##
## The confirmation for an attack is the TARGET, not the ground, so this
## replaces the move order marker there. A marker dropped on the floor would
## say where the player clicked; this says which creep the towers were pointed
## at, which is the thing that was actually chosen.
##
## Parented to the creep rather than to the effects root, deliberately and
## unlike every other effect in the game. It has to follow a target that is
## walking away, and a target that dies has nothing left to point at - letting
## it go with the creep is both of those answers at once.
##
## Blinks rather than fades: a steady ring would read as a second selection, and
## a fade would be mistaken for the ring already under a selected unit.

# Placeholder visual values, so they stay in the script.
const MARKER_COLOR: Color = Color(0.95, 0.22, 0.20)
const RING_THICKNESS: float = 0.05
## Height above the ground, just over the selection ring at 0.03 so the two
## never fight when a creep happens to be selected as well.
const GROUND_OFFSET: float = 0.045
## Fast enough to read as an alarm rather than as a pulse.
const BLINK_INTERVAL: float = 0.09
const LIFETIME: float = 1.5

var _ring: MeshInstance3D
var _elapsed: float = 0.0
var _since_blink: float = 0.0


## Sizes the ring to sit just outside a unit's own selection ring.
## Call after the marker is in the tree.
func setup(radius: float) -> void:
	# Animated on the RENDER frame, not the simulation tick. Godot's physics
	# interpolation assumes a transform only changes on a tick, so an
	# interpolated node moved in _process jitters - visibly on some machines and
	# not others. Opting out is the documented fix.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	var outer: float = maxf(0.1, radius)

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = MARKER_COLOR
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = maxf(0.01, outer - RING_THICKNESS)
	torus.outer_radius = outer
	torus.rings = 24
	torus.material = material

	_ring = MeshInstance3D.new()
	_ring.name = "Ring"
	_ring.mesh = torus
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	position = Vector3(0.0, GROUND_OFFSET, 0.0)


func _process(delta: float) -> void:
	if _ring == null:
		return

	_elapsed += delta
	if _elapsed >= LIFETIME:
		queue_free()
		return

	_since_blink += delta
	if _since_blink >= BLINK_INTERVAL:
		_since_blink = 0.0
		_ring.visible = !_ring.visible
