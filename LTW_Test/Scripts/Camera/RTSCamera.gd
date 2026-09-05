class_name RTSCamera
extends Camera3D

## Top-down RTS camera.
##
## Per game_rules.md the camera never follows a unit. It is driven only by the
## player via edge panning, plus a center_on() call used by the
## center-on-target function.
##
## The camera is described by a ground focus point, a fixed pitch and a
## distance. Panning moves the focus point, the wheel moves the distance, and
## the transform is derived from both.
##
## Its config comes from References, which is where every shared config lives.

# Arrow keys pan the camera. WASD is deliberately left free, it is reserved
# for builder hotkeys. Routed through input actions rather than raw keycodes
# so they stay rebindable and can take a gamepad stick later.
const ACTION_PAN_LEFT: StringName = &"camera_pan_left"
const ACTION_PAN_RIGHT: StringName = &"camera_pan_right"
const ACTION_PAN_UP: StringName = &"camera_pan_up"
const ACTION_PAN_DOWN: StringName = &"camera_pan_down"

## Read throughout, so it comes through a getter onto References.
var _config: CameraConfig:
	get:
		return References.camera_config

var _focus: Vector3 = Vector3.ZERO
## xz rectangle the focus point is clamped to.
var _focus_bounds: Rect2 = Rect2()
var _has_bounds: bool = false

## How far back the camera currently sits, and where it is heading. Two
## values rather than one so a wheel notch eases in instead of snapping, which
## is the difference between reading as a zoom and reading as a teleport.
##
## Never below min_distance() and never past the config's own distance: the
## authored value IS zoomed all the way out, so a match opens there.
var _distance: float = 0.0
var _target_distance: float = 0.0

var _grabbing: bool = false
## World point that was under the cursor when the middle drag started. The pan
## keeps putting this point back under the cursor, which makes the drag
## independent of resolution, pitch and any future zoom.
var _grab_world_point: Vector3 = Vector3.ZERO


func _ready() -> void:
	if _config == null:
		Log.err("RTSCamera found no CameraConfig on References, panning is disabled")
		return
	fov = _config.field_of_view
	_distance = _config.distance
	_target_distance = _distance
	_apply_transform()


## Limits panning to a world-space xz rectangle, usually the whole map
## plus a margin.
func set_focus_bounds(bounds: Rect2) -> void:
	_focus_bounds = bounds
	_has_bounds = true
	_set_focus(_focus)


## Snaps the camera to a world position. This is the center-on-target hook
## for the builder or any other unit or building.
func center_on(world_position: Vector3) -> void:
	_set_focus(world_position)


## How far back the camera is right now. Read by anything that has to scale
## with the zoom rather than assume a fixed view.
func distance() -> float:
	return _distance


## The closest the wheel may bring the camera in, worked out from how much of a
## lane the config wants visible at that point.
##
## Derived rather than authored so the knob can stay in CELLS, which is the
## unit a player and a designer both think in - and so a change to the field of
## view or the window's aspect cannot silently make the closest zoom show a
## different amount of ground than it was tuned to.
##
## The horizontal extent is what is solved for: the camera only pitches around
## X, so the ground and the view plane stay parallel across the screen's width
## and the width is a straight frustum calculation. The DEPTH the player sees is
## foreshortened by the pitch, which is exactly why width is the honest measure.
func min_distance() -> float:
	if _config == null:
		return 1.0

	var cell: float = 1.0
	var game: GameConfig = References.game_config
	if game != null:
		cell = game.cell_size

	var wanted: float = maxf(0.5, _config.min_visible_width_cells) * cell
	var half_angle: float = tan(deg_to_rad(clampf(fov, 1.0, 179.0) * 0.5))
	var closest: float = wanted / (2.0 * half_angle * _viewport_aspect())
	# A config that asks for a closest zoom further out than its own distance is
	# an authoring mistake rather than a range, so the distance wins and the
	# wheel simply has nowhere to go.
	return minf(closest, _config.distance)


func _viewport_aspect() -> float:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return 1.0
	var size: Vector2 = viewport.get_visible_rect().size
	if size.x <= 0.0 || size.y <= 0.0:
		return 1.0
	return size.x / size.y


## Where a screen point lands on the ground plane at y = 0, or null when the
## ray runs parallel to or away from the ground.
## Public because ability targeting needs the same projection.
func ground_point_at(screen_pos: Vector2) -> Variant:
	var from: Vector3 = project_ray_origin(screen_pos)
	var direction: Vector3 = project_ray_normal(screen_pos)
	return Plane(Vector3.UP, 0.0).intersects_ray(from, direction)


# --- Middle mouse drag --------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _config == null:
		return

	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		# Checked before the middle drag, and independently of it, so turning
		# the drag off in the config does not take the wheel with it.
		if _handle_zoom(button):
			get_viewport().set_input_as_handled()
			return
		if !_config.allow_middle_drag_pan:
			return
		if button.button_index != MOUSE_BUTTON_MIDDLE:
			return
		if button.pressed:
			_begin_grab(button.position)
		else:
			_grabbing = false
		get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion && _grabbing:
		_update_grab((event as InputEventMouseMotion).position)


## Answers whether this button event was a zoom, so the caller knows to stop.
##
## Only the press half is acted on: a wheel notch arrives as a press and a
## release, and treating both would double every step.
func _handle_zoom(button: InputEventMouseButton) -> bool:
	if !_config.allow_zoom || !button.pressed:
		return false

	var step: float = clampf(_config.zoom_step, 0.5, 0.99)
	if button.button_index == MOUSE_BUTTON_WHEEL_UP:
		_set_target_distance(_target_distance * step)
		return true
	if button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_set_target_distance(_target_distance / step)
		return true
	return false


func _set_target_distance(value: float) -> void:
	_target_distance = clampf(value, min_distance(), _config.distance)


func _begin_grab(screen_pos: Vector2) -> void:
	var point: Variant = ground_point_at(screen_pos)
	if point == null:
		return
	_grab_world_point = point
	_grabbing = true


## Moving the camera by D shifts every ground intersection by D, so putting the
## grabbed point back under the cursor is a single subtraction rather than any
## pixels-to-world conversion.
func _update_grab(screen_pos: Vector2) -> void:
	var point: Variant = ground_point_at(screen_pos)
	if point == null:
		return

	var delta: Vector3 = _grab_world_point - (point as Vector3)
	if !_config.middle_drag_grabs_world:
		delta = -delta
	_set_focus(_focus + delta)


func _process(delta: float) -> void:
	if _config == null:
		return
	var pan: Vector2 = _read_pan_input()
	if pan != Vector2.ZERO:
		_set_focus(_focus + Vector3(pan.x, 0.0, pan.y) * _config.pan_speed * delta)
	_advance_zoom(delta)


## Eases the camera towards the zoom the wheel asked for.
##
## The cursor anchoring is re-done every frame rather than once per notch,
## because the distance is still moving in between: anchoring only at the
## moment of the click would let the point under the cursor drift for the rest
## of the ease, which is the exact thing the anchoring exists to prevent.
func _advance_zoom(delta: float) -> void:
	if is_equal_approx(_distance, _target_distance):
		return

	var anchor: Variant = null
	if _config.zoom_to_cursor:
		anchor = ground_point_at(_cursor_position())

	if _config.zoom_smoothing <= 0.0:
		_distance = _target_distance
	else:
		_distance = lerpf(_distance, _target_distance,
			clampf(_config.zoom_smoothing * delta, 0.0, 1.0))
		# Snap the last sliver, or the lerp approaches forever and this runs
		# every frame for the rest of the match.
		if absf(_distance - _target_distance) < 0.001:
			_distance = _target_distance
	_apply_transform()

	if anchor == null:
		return
	# Moving the camera by D shifts every ground intersection by D, so putting
	# the anchored point back under the cursor is one subtraction - the same
	# trick the middle drag uses.
	var landed: Variant = ground_point_at(_cursor_position())
	if landed != null:
		_set_focus(_focus + (anchor as Vector3) - (landed as Vector3))


func _cursor_position() -> Vector2:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return Vector2.ZERO
	return viewport.get_mouse_position()


func _read_pan_input() -> Vector2:
	var pan: Vector2 = _read_edge_pan()

	if _config.allow_key_panning:
		# get_vector applies the action deadzone and handles analog input, so
		# binding a stick to these actions gives controller panning for free.
		pan += Input.get_vector(
			ACTION_PAN_LEFT,
			ACTION_PAN_RIGHT,
			ACTION_PAN_UP,
			ACTION_PAN_DOWN
		)

	# Edge and key panning can stack, so cap the combined speed.
	return pan.limit_length(1.0)


func _read_edge_pan() -> Vector2:
	# A player setting rather than authored data, so it is asked every tick and
	# the options screen has nothing to tell this camera when it changes.
	if !UserSettings.edge_panning:
		return Vector2.ZERO

	# A middle drag routinely takes the cursor to a screen edge, and edge
	# panning fighting the drag feels broken.
	if _grabbing:
		return Vector2.ZERO

	var viewport: Viewport = get_viewport()
	if viewport == null:
		return Vector2.ZERO

	# Only pan for a focused window. Without this the camera creeps whenever
	# the cursor happens to rest near an edge while the player is working in
	# another window.
	if !get_window().has_focus():
		return Vector2.ZERO

	var screen: Vector2 = viewport.get_visible_rect().size
	var mouse: Vector2 = viewport.get_mouse_position()

	# Ignore edge panning while the cursor is outside the window, otherwise
	# the camera drifts whenever the player alt-tabs away.
	if mouse.x < 0.0 || mouse.y < 0.0 || mouse.x > screen.x || mouse.y > screen.y:
		return Vector2.ZERO

	var margin: float = float(_config.edge_margin_px)
	var pan: Vector2 = Vector2.ZERO

	if mouse.x <= margin:
		pan.x -= 1.0
	elif mouse.x >= screen.x - margin:
		pan.x += 1.0

	if mouse.y <= margin:
		pan.y -= 1.0
	elif mouse.y >= screen.y - margin:
		pan.y += 1.0

	return pan


func _set_focus(value: Vector3) -> void:
	_focus = Vector3(value.x, 0.0, value.z)
	if _has_bounds:
		_focus.x = clampf(_focus.x, _focus_bounds.position.x, _focus_bounds.end.x)
		_focus.z = clampf(_focus.z, _focus_bounds.position.y, _focus_bounds.end.y)
	_apply_transform()


func _apply_transform() -> void:
	if _config == null:
		return
	rotation_degrees = Vector3(_config.pitch_degrees, 0.0, 0.0)
	# Pull the camera back along its own view direction from the focus point.
	var forward: Vector3 = -transform.basis.z
	global_position = _focus - forward * _distance
