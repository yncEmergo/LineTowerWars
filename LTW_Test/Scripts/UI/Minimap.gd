class_name Minimap
extends Control

## The whole map in one square: every lane, everything standing in one, and
## where the camera is looking. Left click jumps the camera there.
##
## PRESENTATION ONLY. It reads the world and draws it and decides nothing, so
## it needs no authority check - a dedicated server never loads the HUD and
## never runs this at all. See multiplayer.md.
##
## It frames GameConfig.map_bounds rather than the areas that happen to exist,
## which is what keeps the picture identical in a 1v1 and in a full house: the
## empty slots are simply black. The camera pans over that same rectangle, so
## every point on this square is somewhere the camera can actually go.
##
## Everything on it is a square. A building is one size whatever it is, a
## mobile unit a fraction of that. So a maze's SHAPE is deliberately not
## readable here, only roughly where its towers stand - which is all the
## Warcraft III minimap this copies ever showed either.
##
## Colour says ownership and nothing else, and WHICH of the three schemes is
## PresentationConfig.OwnerColors' answer, not this file's. What holds either
## way: a creep is its SENDER's colour, so an opponent's creeps walking through
## your own maze read as theirs rather than as yours.

## The map fitted into this control, in pixels per world unit, and where the
## map's own origin lands. Both are recomputed from the current size on every
## draw and every click, so a resized window needs no invalidation step.
var _pixels_per_unit: float = 1.0
var _map_origin_px: Vector2 = Vector2.ZERO
## Whether the left button is still down, so dragging keeps steering the
## camera rather than only the click that started it.
var _dragging: bool = false

var _config: GameConfig:
	get:
		return References.game_config

var _presentation: PresentationConfig:
	get:
		return References.presentation_config


func _ready() -> void:
	# The minimap has to swallow its own clicks, or the same press also lands
	# on the world underneath as a selection or an order.
	mouse_filter = Control.MOUSE_FILTER_STOP


## Units move every tick and the camera every frame, so there is nothing worth
## tracking that would let this redraw less often than always.
func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _config == null || _presentation == null:
		return
	if !_refresh_projection():
		return

	draw_rect(Rect2(Vector2.ZERO, size), _presentation.minimap_background_color, true)
	_draw_lanes()
	_draw_units()
	_draw_camera_view()


# --- Projection ---------------------------------------------------------
#
# The map is fitted into the square whole and centred, never stretched, so a
# lane keeps the proportions it has in the world. The letterbox bars this
# leaves are black, which is also what the map's own empty ground is, so the
# fit is invisible.

## False when there is no map to fit, which is the one case the maths below
## would divide by zero on.
func _refresh_projection() -> bool:
	var map: Rect2 = _config.map_bounds()
	if map.size.x <= 0.0 || map.size.y <= 0.0 || size.x <= 0.0 || size.y <= 0.0:
		return false

	_pixels_per_unit = minf(size.x / map.size.x, size.y / map.size.y)
	var drawn: Vector2 = map.size * _pixels_per_unit
	_map_origin_px = (size - drawn) * 0.5 - map.position * _pixels_per_unit
	return true


## World xz to a point on this control. y is ignored: the map is flat and a
## tower's height would only smear it off its own footprint.
func _to_minimap(world_pos: Vector3) -> Vector2:
	return Vector2(world_pos.x, world_pos.z) * _pixels_per_unit + _map_origin_px


func _to_world(point: Vector2) -> Vector3:
	var ground: Vector2 = (point - _map_origin_px) / _pixels_per_unit
	return Vector3(ground.x, 0.0, ground.y)


# --- The map ------------------------------------------------------------

func _draw_lanes() -> void:
	var manager: PlayerManager = References.player_manager
	if manager == null:
		return
	for area: PlayerArea in manager.areas():
		if area != null:
			_draw_lane(area)


## One lane: the spawn cap, the buildable body and the end strip.
##
## The send strip above them is deliberately left out. It is not ground anyone
## plays on - it exists so the send building has somewhere to stand, and that
## building is a building here only so it can be put in a control group. Drawing
## its strip would add a stripe to every lane that means nothing.
func _draw_lane(area: PlayerArea) -> void:
	var origin: Vector3 = area.global_position
	_draw_zone(origin, 0.0, _config.build_zone_start_z(), _presentation.minimap_spawn_color)
	_draw_zone(
		origin,
		_config.build_zone_start_z(),
		_config.build_zone_end_z(),
		_presentation.minimap_build_color
	)
	_draw_zone(
		origin,
		_config.build_zone_end_z(),
		_config.area_depth(),
		_presentation.minimap_end_color
	)


## One full-width band of a lane, between two z values in the area's own local
## coordinates - which are the cell coordinates game_rules.md uses.
func _draw_zone(origin: Vector3, start_z: float, end_z: float, color: Color) -> void:
	var top_left: Vector2 = _to_minimap(origin + Vector3(0.0, 0.0, start_z))
	var bottom_right: Vector2 = _to_minimap(
		origin + Vector3(_config.area_width(), 0.0, end_z)
	)
	draw_rect(Rect2(top_left, bottom_right - top_left), color, true)


# --- What is standing on it ---------------------------------------------

func _draw_units() -> void:
	var session: MatchSession = References.match_session
	if session == null:
		return

	var building_px: float = _presentation.minimap_building_px
	var unit_px: float = building_px * _presentation.minimap_unit_scale

	for unit: Unit in session.live_units():
		# A unit that stands nowhere has no dot to draw. The senders are the
		# whole of that: they are reached through the buttons over the unit
		# panel, and a marker for one would float in the black above a lane.
		if !unit.is_in_world():
			continue

		var side: float = building_px if unit.is_structure() else unit_px
		var color: Color = _presentation.minimap_color_for(
			unit.owner_player_id, unit.is_owned_by_local_player()
		)

		var center: Vector2 = _to_minimap(unit.global_position)
		draw_rect(Rect2(center - Vector2(side, side) * 0.5, Vector2(side, side)), color, true)


## Outline of the ground the camera can see.
##
## The camera looks down at a fixed pitch, so what it really covers is a
## trapezoid - the far edge of the view spans more ground than the near one.
## This draws a rectangle anyway, and takes its WIDTH from the near edge, the
## bottom of the screen. A frame that changes shape as it moves is harder to
## read at this size than one that is always the same box, and the near edge is
## the honest half of the two: everything inside the rectangle really is on
## screen, it is the far corners that are cropped rather than invented.
func _draw_camera_view() -> void:
	var view: Variant = _camera_ground_rect()
	if view == null:
		return

	var ground: Rect2 = view as Rect2
	var top_left: Vector2 = _to_minimap(Vector3(ground.position.x, 0.0, ground.position.y))
	var bottom_right: Vector2 = _to_minimap(Vector3(ground.end.x, 0.0, ground.end.y))

	draw_rect(
		_fit_inside(Rect2(top_left, bottom_right - top_left)),
		_presentation.minimap_camera_color,
		false,
		_presentation.minimap_camera_width
	)


## The ground the camera covers, as an xz rectangle, or null when a screen
## corner does not meet the ground at all.
##
## Three corners are enough: the near edge gives the width and the camera's own
## x, and either far corner gives how far up the view reaches.
func _camera_ground_rect() -> Variant:
	var camera: RTSCamera = References.rts_camera
	var viewport: Viewport = get_viewport()
	if camera == null || viewport == null:
		return null

	var screen: Vector2 = viewport.get_visible_rect().size
	var near_left: Variant = camera.ground_point_at(Vector2(0.0, screen.y))
	var near_right: Variant = camera.ground_point_at(screen)
	var far_left: Variant = camera.ground_point_at(Vector2.ZERO)
	if near_left == null || near_right == null || far_left == null:
		return null

	var left: float = (near_left as Vector3).x
	var right: float = (near_right as Vector3).x
	var top: float = (far_left as Vector3).z
	var bottom: float = (near_left as Vector3).z
	return Rect2(left, top, right - left, bottom - top)


## Slides a rectangle back inside this control, so the camera frame is always
## whole rather than half off the edge.
##
## It has to move at all because the camera may pan a margin past the map
## itself, and because half a stroke sits outside the rectangle it draws.
func _fit_inside(rect: Rect2) -> Rect2:
	var stroke: float = _presentation.minimap_camera_width * 0.5
	var limit: Rect2 = Rect2(Vector2(stroke, stroke), size - Vector2(stroke, stroke) * 2.0)

	var fitted: Rect2 = rect
	fitted.size.x = minf(fitted.size.x, limit.size.x)
	fitted.size.y = minf(fitted.size.y, limit.size.y)
	fitted.position.x = clampf(fitted.position.x, limit.position.x, limit.end.x - fitted.size.x)
	fitted.position.y = clampf(fitted.position.y, limit.position.y, limit.end.y - fitted.size.y)
	return fitted


# --- Click to look ------------------------------------------------------

## Left click puts the camera where it was clicked, and holding keeps steering
## it. Presentation, so it goes straight to the camera rather than through
## Commands: where a player is looking is not a rule the server enforces.
func _gui_input(event: InputEvent) -> void:
	var camera: RTSCamera = References.rts_camera
	if camera == null || _config == null || !_refresh_projection():
		return

	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		_dragging = button.pressed
		if button.pressed:
			camera.center_on(_to_world(button.position))
		accept_event()

	elif event is InputEventMouseMotion && _dragging:
		camera.center_on(_to_world((event as InputEventMouseMotion).position))
		accept_event()
