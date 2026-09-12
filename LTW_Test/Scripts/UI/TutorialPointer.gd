class_name TutorialPointer
extends Control

## The arrow that says WHICH BUTTON, and the dim that says which part of the
## screen matters.
##
## A tutorial that describes a button in words is a tutorial somebody has to
## hunt through a HUD for. This points at it: an arrow beside the control the
## current lesson names, bobbing so it is found at a glance, with the rest of
## the screen dimmed behind a hole cut around it.
##
## **The lesson names the button and never where it is.** A step carries a KEY -
## "send bar", "research center" - and the map from a key to a Control is
## authored HERE, in the HUD scene, next to the things it names. So relaying the
## HUD out moves the arrow with it, and a lesson written six months ago goes on
## pointing at the right thing.
##
## Two parallel arrays rather than a Dictionary export, because a Dictionary of
## NodePaths cannot be authored in the inspector and a Control cannot be a
## Dictionary key in a .tscn. They are kept in step by validate(), which is the
## same trade PlayerStatRow's duplicated column widths make.

## How far the arrow floats up and down, in pixels, and how fast.
const BOB_PIXELS: float = 6.0
const BOB_SPEED: float = 3.0
## Gap between the arrow and the control it is pointing at.
const ARROW_GAP: float = 8.0

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

var _target: Control = null
var _phase: float = 0.0

var _director: TutorialDirector:
	get:
		return References.tutorial_director


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	_validate()

	var director: TutorialDirector = _director
	if director == null:
		return
	director.lesson_changed.connect(_refresh)
	_refresh()


## Two lists that have to agree, so a mismatch is a message at boot rather than
## an arrow that points at nothing in the middle of a lesson.
func _validate() -> void:
	if _keys.size() == _controls.size():
		return
	Log.err("TutorialPointer has a different number of names and controls", {
		"names": _keys.size(),
		"controls": _controls.size(),
	})


func _refresh() -> void:
	_target = null
	var director: TutorialDirector = _director
	if director != null && director.is_running():
		var step: TutorialStep = director.current_step()
		if step != null:
			_target = _control_for(step.highlight_key)
	visible = _target != null


## The control one name points at, or null for a lesson that names nothing - and
## for one that names something this HUD does not have, which is worth a line
## because it is a lesson that will teach nothing.
func _control_for(key: StringName) -> Control:
	if key == &"":
		return null
	for index in range(mini(_keys.size(), _controls.size())):
		if StringName(_keys[index]) == key:
			return _controls[index]
	Log.warn("A tutorial lesson points at something this HUD has no name for", key)
	return null


## Follows the target every frame rather than being placed once.
##
## A HUD control MOVES: the command card is rebuilt when the selection changes,
## the send bar resizes with the tiers, and a panel laid out this frame has a
## different rect next frame. An arrow placed once would be beside where the
## button used to be, which is worse than no arrow at all.
func _process(delta: float) -> void:
	if _target == null || !is_instance_valid(_target):
		hide()
		return
	if !_target.is_visible_in_tree():
		# The thing being pointed at is not on screen - a card that changed, a
		# screen that closed. Nothing is drawn rather than an arrow hanging in
		# space, and it comes back the moment the control does.
		_set_dim_visible(false)
		if _arrow != null:
			_arrow.hide()
		return

	_phase += delta * BOB_SPEED
	var rect: Rect2 = _target.get_global_rect()
	_place_arrow(rect)
	_place_dim(rect)


## Puts the arrow on whichever side of the control has room for it.
##
## ABOVE by default and BELOW when the control is near the top of the screen,
## which is the only case that matters: the status bar and the player table live
## up there, and an arrow above them would be off the screen.
func _place_arrow(rect: Rect2) -> void:
	if _arrow == null:
		return
	_arrow.show()

	var bob: float = sin(_phase) * BOB_PIXELS
	var size: Vector2 = _arrow.size
	var above: bool = rect.position.y > size.y + ARROW_GAP * 2.0
	var y: float = rect.position.y - size.y - ARROW_GAP - bob if above \
		else rect.end.y + ARROW_GAP + bob
	_arrow.global_position = Vector2(
		rect.position.x + rect.size.x * 0.5 - size.x * 0.5, y
	)
	# The arrow is drawn pointing DOWN, so it is flipped when it sits under the
	# thing it is pointing at.
	_arrow.scale = Vector2(1.0, 1.0 if above else -1.0)
	_arrow.pivot_offset = size * 0.5


## Cuts a hole in the dim around the control, as four rectangles.
func _place_dim(rect: Rect2) -> void:
	if _dim_top == null || _dim_bottom == null || _dim_left == null || _dim_right == null:
		return
	_set_dim_visible(true)

	var screen: Vector2 = get_viewport_rect().size
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
