class_name ReviveLight
extends Node3D

## Shaft of light standing over the spot where a creep is waiting to get back
## up.
##
## Built from primitives in code and parented to the shared effects root, the
## same way the move order marker is. A short lived effect belongs to the
## moment rather than to the unit, so a creep freed part way through - an area
## torn down, a match ending - cannot take a half played animation with it.
##
## Apex DOWN, so it reads as light landing on the ground rather than as a solid
## cone standing on it. It brightens and widens as the revive nears, which is
## what makes the wait readable without hanging a progress bar over the maze.
##
## It runs its own clock rather than being driven frame by frame. finish() only
## fast forwards it to the flash, so a light whose creep disappeared still ends
## on its own instead of standing in the maze forever.

# Placeholder visual values, so they stay in the script.
## Radius at the top of the shaft, where it is widest.
const CONE_TOP_RADIUS: float = 0.42
## Kept just above zero rather than at it, so the tip catches a little light
## instead of aliasing into a single point.
const CONE_BOTTOM_RADIUS: float = 0.03
const CONE_HEIGHT: float = 1.30
const LIGHT_COLOR: Color = Color(1.0, 0.88, 0.35)
## Height above the ground, clear of the build grid overlay at 0.02.
const GROUND_OFFSET: float = 0.04

## The shaft grows and brightens across the wait, from these to the end values.
const START_SCALE: float = 0.35
const END_SCALE: float = 1.0
const START_ALPHA: float = 0.16
const END_ALPHA: float = 0.70

## Bright snap at the moment the creep actually stands up.
const FLASH_SECONDS: float = 0.20
const FLASH_SCALE: float = 1.5

var _material: StandardMaterial3D
var _mesh: MeshInstance3D
var _duration: float = 2.0
var _elapsed: float = 0.0
var _flashing: bool = false
var _flash_elapsed: float = 0.0


func _ready() -> void:
	# Animated on the RENDER frame, not the simulation tick. Godot's physics
	# interpolation assumes a transform only changes on a tick, so an
	# interpolated node moved in _process jitters - visibly on some machines and
	# not others. Opting out is the documented fix.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build_cone()
	_apply(START_SCALE, START_ALPHA)


## Stands the light on the ground at a world point.
## Call after the light is in the tree, since it sets a global position.
func place_at(world_position: Vector3) -> void:
	global_position = Vector3(world_position.x, GROUND_OFFSET, world_position.z)


## Starts the wait. seconds is how long the creep stays down, so the shaft is
## at its brightest exactly as the creep comes back.
func play(seconds: float) -> void:
	_duration = maxf(0.01, seconds)
	_elapsed = 0.0
	_flashing = false


## Fast forwards to the closing flash. Called when the creep actually gets up,
## which is normally the same moment the clock above would have run out anyway.
func finish() -> void:
	if !_flashing:
		_begin_flash()


func _build_cone() -> void:
	# Unique per light, because the animation drives this material's alpha.
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(LIGHT_COLOR, START_ALPHA)
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Lit from inside as well, so the shaft does not go flat where it faces away.
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.emission_enabled = true
	_material.emission = LIGHT_COLOR
	# Both this and the build grid are transparent and nearly coplanar, so sort
	# the shaft after the grid rather than leaving it to depth order.
	_material.render_priority = 1

	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = CONE_TOP_RADIUS
	cone.bottom_radius = CONE_BOTTOM_RADIUS
	cone.height = CONE_HEIGHT
	cone.radial_segments = 12
	cone.rings = 1
	cone.material = _material

	_mesh = MeshInstance3D.new()
	_mesh.name = "Cone"
	_mesh.mesh = cone
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Raised by half its height so the tip sits on the ground rather than the
	# middle of the shaft.
	_mesh.position = Vector3(0.0, CONE_HEIGHT * 0.5, 0.0)
	add_child(_mesh)


func _process(delta: float) -> void:
	if _flashing:
		_advance_flash(delta)
		return

	_elapsed += delta
	var progress: float = clampf(_elapsed / _duration, 0.0, 1.0)
	_apply(
		lerpf(START_SCALE, END_SCALE, progress),
		lerpf(START_ALPHA, END_ALPHA, progress)
	)

	if _elapsed >= _duration:
		_begin_flash()


func _begin_flash() -> void:
	_flashing = true
	_flash_elapsed = 0.0


## Widens and fades out at once, so the shaft reads as bursting rather than
## simply being switched off.
func _advance_flash(delta: float) -> void:
	_flash_elapsed += delta
	var progress: float = clampf(_flash_elapsed / FLASH_SECONDS, 0.0, 1.0)
	_apply(
		lerpf(END_SCALE, FLASH_SCALE, progress),
		lerpf(END_ALPHA, 0.0, progress)
	)

	if progress >= 1.0:
		queue_free()


func _apply(scale_factor: float, alpha: float) -> void:
	scale = Vector3(scale_factor, 1.0, scale_factor)
	if _material != null:
		_material.albedo_color = Color(LIGHT_COLOR, alpha)
