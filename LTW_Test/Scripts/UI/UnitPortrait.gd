class_name UnitPortrait
extends SubViewportContainer

## The live 3D picture of the selected unit, in the corner of the unit panel.
##
## A real camera looking at a real copy of the unit, not a baked image. That is
## worth the viewport for one reason above the others: it CANNOT go stale. A
## tower that upgrades, a creep that is a different colour to the one beside
## it, anything that ever gains a variant - the portrait already shows it,
## because it is showing the thing itself.
##
## PRESENTATION ONLY, and it copies MESHES rather than the unit (see
## VisualUtil): a portrait must never register a unit id, claim a grid cell or
## take a shot at anything. Nothing in here decides anything, and a dedicated
## server never builds one.
##
## Its viewport has a world of its own, so the portrait's lights are only ever
## the portrait's and the match's lighting cannot change what a player is
## looking at. The background is transparent, so what shows behind the unit is
## the panel rather than a box.
##
## The unit is COPIED once per selection rather than followed frame by frame:
## following would mean re-copying every frame, and the portrait is a picture
## of what the unit IS, not of what it happens to be doing.

@export_group("References")
## Where the copied meshes go. Turned by the turntable, so the unit spins
## rather than the camera orbiting - the lighting then stays put and the shape
## is what changes.
@export var _stage: Node3D
@export var _camera: Camera3D

@export_group("Framing")
## Degrees around the unit at rest, and how far above it the camera sits.
@export var yaw_degrees: float = 35.0
@export var pitch_degrees: float = 22.0
## How much of the frame the unit fills.
@export_range(0.4, 1.0, 0.01) var fill: float = 0.82

@export_group("Turntable")
## Turns per second. 0 holds the unit still at its resting angle, which is what
## to set if the movement ever reads as noise next to a busy command card.
@export var turns_per_second: float = 0.08

var _showing: Unit = null
var _turned: float = 0.0


func _ready() -> void:
	if _stage == null || _camera == null:
		Log.err("UnitPortrait is missing its stage or its camera", name)
		return
	clear()


## Points the portrait at a unit, or at nothing when given null.
##
## Cheap enough to call on every selection change: a unit is a handful of
## meshes and the copies are plain MeshInstance3Ds with no scripts on them.
func show_unit(unit: Unit) -> void:
	if unit == _showing && is_instance_valid(unit):
		return
	_showing = unit

	if _stage == null:
		return
	for child in _stage.get_children():
		child.free()

	if unit == null || !is_instance_valid(unit):
		visible = false
		return

	var source: Node3D = unit.visual_root()
	var bounds: AABB = VisualUtil.copy_meshes(
		source, _stage, VisualUtil.portrait_skips(unit))
	if bounds.size == Vector3.ZERO:
		# A unit with nothing to draw. Better an empty corner than a camera
		# pointed at the origin showing whatever happens to be there.
		visible = false
		return

	visible = true
	_turned = 0.0
	_stage.rotation.y = 0.0
	_frame(bounds)


func clear() -> void:
	show_unit(null)


## Puts the camera far enough back, at a fixed angle, for the unit's longest
## axis to fill `fill` of the frame.
##
## Framed on the unit's own box, so a Lesser Archer and an Ultimate Watch Tower
## both fill the portrait rather than the cheap one being a speck. The tier is
## told by its trim metal, which survives being scaled; it is not told by how
## much of the corner it takes up.
##
## The stage is moved so the unit's middle sits on the origin, which is what
## lets the turntable spin it in place instead of swinging it around a corner.
func _frame(bounds: AABB) -> void:
	var centre: Vector3 = bounds.position + bounds.size * 0.5
	for child in _stage.get_children():
		var mesh: Node3D = child as Node3D
		if mesh != null:
			mesh.position -= centre

	var radius: float = maxf(0.05, bounds.size.length() * 0.5)
	var yaw: float = deg_to_rad(yaw_degrees)
	var pitch: float = deg_to_rad(pitch_degrees)
	var direction: Vector3 = Vector3(
		cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))

	# Orthographic, so the unit reads as its own shape rather than as a shape
	# seen from somewhere, and so nothing distorts as the turntable turns.
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = radius * 2.0 / fill
	_camera.near = 0.01
	_camera.far = radius * 8.0 + 4.0
	_camera.position = direction * (radius * 3.0 + 1.0)
	_camera.look_at(Vector3.ZERO, Vector3.UP)


func _process(delta: float) -> void:
	if _stage == null || is_zero_approx(turns_per_second) || !visible:
		return
	_turned += turns_per_second * TAU * delta
	_stage.rotation.y = _turned
