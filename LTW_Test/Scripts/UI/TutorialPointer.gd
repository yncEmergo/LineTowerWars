class_name TutorialPointer
extends Control

## The arrow that says WHICH BUTTON.
##
## A tutorial that describes a button in words is a tutorial somebody has to
## hunt through a HUD for. This points at it: an arrow beside the one control
## the lesson wants pressed, bobbing so it is found at a glance.
##
## **It points at the BUTTON, never at the bar the button sits in.** The first
## version pointed at whole panels - the middle of the send bar, the middle of
## the unit panel - which put the arrow between two buttons or over a portrait,
## and read as pointing at the wrong thing every time. So what it resolves to,
## every frame and in this order, is:
##
##   1. the button that SELECTS the unit the lesson is guiding the player to,
##      while that unit is not selected - the builder's square, the tier 1
##      sender's square. See TutorialGuide.
##   2. the command card square showing one of the lesson's guide_abilities -
##      the Build menu, then the tower inside it. Nothing while an order is
##      being aimed: the player is doing the thing, and an arrow on the square
##      they already pressed only competes with the build ghost.
##   3. the control the lesson names by highlight_key.
##
## Every frame rather than on a lesson change, because every one of those
## changes under the player: they click off the builder, open a submenu, arm a
## tower.
##
## **The lesson names the button and never where it is.** A key - "send_tier_1",
## "research_button" - maps to a Control HERE, in the HUD scene, next to the
## things it names, so relaying the HUD out moves the arrow with it. Two
## parallel arrays rather than a Dictionary export, because a Dictionary of
## NodePaths cannot be authored in the inspector. They are kept in step by
## _validate().
##
## The DIM around the target is opt-in per lesson (dims_around_highlight). On by
## default it greyed out the whole screen, lane included, while the lesson was
## asking the player to act in it.

## How far the arrow floats up and down, in pixels, and how fast.
const BOB_PIXELS: float = 6.0
const BOB_SPEED: float = 3.0
## Gap between the arrow and the control it is pointing at.
const ARROW_GAP: float = 4.0

@export_group("References")
## The arrow itself, moved to whatever the lesson names.
@export var _arrow: Control
## The dim that covers everything BUT the highlighted control. Four rectangles
## rather than a shader, because that is all a rectangular hole needs and it
## costs no material, no compile and nothing for ShaderWarmup to know about.
@export var _dim_top: ColorRect
@export var _dim_bottom: ColorRect
@export var _dim_left: ColorRect
@export var _dim_right: ColorRect

@export_group("Targets")
## The names a lesson may point at, in the same order as the controls below.
@export var _keys: PackedStringArray = PackedStringArray()
## What each of those names points at.
@export var _controls: Array[Control] = []

var _phase: float = 0.0

var _director: TutorialDirector:
	get:
		return References.tutorial_director


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# The whole screen, always. The arrow is placed in SCREEN space - see
	# _process - so this node's own rect must not move it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The HUD scene authors this hidden; what is drawn is decided per child.
	show()
	_validate()
	_set_dim_visible(false)
	if _arrow != null:
		_arrow.hide()

	var director: TutorialDirector = _director
	if director != null:
		director.lesson_changed.connect(_check_keys)


## Two lists that have to agree, so a mismatch is a message at boot rather than
## an arrow that points at nothing in the middle of a lesson.
func _validate() -> void:
	if _keys.size() == _controls.size():
		return
	Log.err("TutorialPointer has a different number of names and controls", {
		"names": _keys.size(),
		"controls": _controls.size(),
	})


## Reports, once per lesson rather than once per frame, a lesson naming a key
## this HUD does not have - which is a lesson that will point at nothing.
func _check_keys() -> void:
	var director: TutorialDirector = _director
	if director == null || !director.is_running():
		return
	var step: TutorialStep = director.current_step()
	if step != null && step.highlight_key != &"" && _control_for(step.highlight_key) == null:
		Log.warn("A tutorial lesson points at something this HUD has no name for",
			step.highlight_key)


func _process(delta: float) -> void:
	var target: Control = _resolve()
	if target == null || !is_instance_valid(target) || !target.is_visible_in_tree():
		_set_dim_visible(false)
		if _arrow != null:
			_arrow.hide()
		return

	_phase += delta * BOB_SPEED
	var rect: Rect2 = _screen_rect_of(target)
	_place_arrow(rect)
	var step: TutorialStep = _director.current_step()
	if step != null && step.dims_around_highlight:
		_place_dim(rect)
	else:
		_set_dim_visible(false)


## What the arrow points at this frame, in the order the class note gives.
func _resolve() -> Control:
	var director: TutorialDirector = _director
	if director == null || !director.is_running() || director.is_between_lessons():
		return null
	var step: TutorialStep = director.current_step()
	if step == null:
		return null

	if TutorialGuide.needs_selecting(step):
		return _control_for(TutorialGuide.button_key(step.guide_unit))

	if !step.guide_abilities.is_empty():
		var controller: CommandController = References.command_controller
		if controller != null && controller.is_armed():
			return null
		var panel: UnitPanel = References.unit_panel
		var slot: Control = null if panel == null else panel.command_slot_for(step.guide_abilities)
		if slot != null:
			return slot

	return _control_for(step.highlight_key)


## The control one name points at, or null.
func _control_for(key: StringName) -> Control:
	if key == &"":
		return null
	for index in range(mini(_keys.size(), _controls.size())):
		if StringName(_keys[index]) == key:
			return _controls[index]
	return null


## A control's rect in THIS node's coordinates.
##
## Through the canvas transforms rather than get_global_rect(), so a target that
## sits under a scaled container, or in another CanvasLayer, still lands where it
## is drawn: global_rect is in the target's own canvas, and this node may not
## share it.
func _screen_rect_of(target: Control) -> Rect2:
	var to_screen: Transform2D = target.get_global_transform_with_canvas()
	var to_here: Transform2D = get_global_transform_with_canvas().affine_inverse() * to_screen
	return to_here * Rect2(Vector2.ZERO, target.size)


## Puts the arrow over the control, or under it when the control is too near
## the top of the screen for an arrow to fit above.
func _place_arrow(rect: Rect2) -> void:
	if _arrow == null:
		return
	_arrow.show()

	var bob: float = sin(_phase) * BOB_PIXELS
	var arrow_size: Vector2 = _arrow.size
	var above: bool = rect.position.y > arrow_size.y + ARROW_GAP * 2.0
	# The arrow is drawn pointing DOWN, so it is flipped when it sits under the
	# thing it is pointing at. Flipped about its own middle, which is where the
	# pivot is put before anything is moved.
	_arrow.pivot_offset = arrow_size * 0.5
	_arrow.scale = Vector2(1.0, 1.0 if above else -1.0)
	var y: float = rect.end.y + ARROW_GAP - bob
	if above:
		y = rect.position.y - arrow_size.y - ARROW_GAP + bob
	_arrow.position = Vector2(rect.get_center().x - arrow_size.x * 0.5, y)


## Cuts a hole in the dim around the control, as four rectangles.
func _place_dim(rect: Rect2) -> void:
	if _dim_top == null || _dim_bottom == null || _dim_left == null || _dim_right == null:
		return
	_set_dim_visible(true)

	var screen: Vector2 = size
	_dim_top.position = Vector2.ZERO
	_dim_top.size = Vector2(screen.x, maxf(0.0, rect.position.y))
	_dim_bottom.position = Vector2(0.0, rect.end.y)
	_dim_bottom.size = Vector2(screen.x, maxf(0.0, screen.y - rect.end.y))
	_dim_left.position = Vector2(0.0, rect.position.y)
	_dim_left.size = Vector2(maxf(0.0, rect.position.x), rect.size.y)
	_dim_right.position = Vector2(rect.end.x, rect.position.y)
	_dim_right.size = Vector2(maxf(0.0, screen.x - rect.end.x), rect.size.y)


func _set_dim_visible(shown: bool) -> void:
	for panel: ColorRect in [_dim_top, _dim_bottom, _dim_left, _dim_right]:
		if panel != null:
			panel.visible = shown
