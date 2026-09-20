class_name TutorialPointer
extends Control

## The golden border that says WHICH BUTTON.
##
## A tutorial that describes a button in words is a tutorial somebody has to
## hunt through a HUD for. This marks it: a glowing gold border drawn exactly
## over the one control the lesson wants pressed, pulsing so it is found at a
## glance. A border ON the button rather than an arrow beside it, because an
## arrow beside a button in a tight row sits over its neighbour.
##
## **It marks the BUTTON, never the bar the button sits in.** The first version
## pointed at whole panels - the middle of the send bar, the middle of the unit
## panel - which landed between two buttons or over a portrait, and read as
## pointing at the wrong thing every time. So what it resolves to, every frame
## and in this order, is:
##
##   1. the button that SELECTS the unit the lesson is guiding the player to,
##      while that unit is not selected - the builder's square, the tier 1
##      sender's square. See TutorialGuide.
##   2. the command card square showing one of the lesson's guide_abilities -
##      the Build menu, then the tower inside it. Nothing while an order is
##      being aimed: the player is doing the thing, and a border on the square
##      they already pressed only competes with the build ghost.
##   3. the control the lesson names by highlight_key.
##
## Every frame rather than on a lesson change, because every one of those
## changes under the player: they click off the builder, open a submenu, arm a
## tower.
##
## **The lesson names the button and never where it is.** A key - "send_tier_1",
## "research_button" - maps to a Control HERE, in the HUD scene, next to the
## things it names, so relaying the HUD out moves the border with it. Two
## parallel arrays rather than a Dictionary export, because a Dictionary of
## NodePaths cannot be authored in the inspector. They are kept in step by
## _validate().
##
## The DIM around the target is opt-in per lesson (dims_around_highlight). On by
## default it greyed out the whole screen, lane included, while the lesson was
## asking the player to act in it.

## How far the border sits OUTSIDE the control, in pixels, so it frames the
## button rather than covering its edge.
const OUTSET: float = 3.0
## The pulse: how fast, and how low the border's alpha dips.
const PULSE_SPEED: float = 4.0
const PULSE_MIN_ALPHA: float = 0.45
## How far below the border its caption sits, and how far it keeps from the
## screen's edge.
const CAPTION_GAP: float = 8.0
const CAPTION_MARGIN: float = 8.0

@export_group("References")
## The border itself, moved and sized onto whatever the lesson names.
@export var _highlight: Control
## The dim that covers everything BUT the highlighted control. Four rectangles
## rather than a shader, because that is all a rectangular hole needs and it
## costs no material, no compile and nothing for ShaderWarmup to know about.
@export var _dim_top: ColorRect
@export var _dim_bottom: ColorRect
@export var _dim_left: ColorRect
@export var _dim_right: ColorRect
## A short name for what the border frames - "Your current gold" - drawn just
## under it, on an explanation page that has one. See TutorialPage.caption.
@export var _caption: Control
@export var _caption_label: Label

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
	# The whole screen, always. The border is placed in SCREEN space - see
	# _process - so this node's own rect must not move it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The HUD scene authors this hidden; what is drawn is decided per child.
	show()
	_validate()
	_set_dim_visible(false)
	if _highlight != null:
		_highlight.hide()

	var director: TutorialDirector = _director
	if director != null:
		director.lesson_changed.connect(_check_keys)


## Two lists that have to agree, so a mismatch is a message at boot rather than
## a border that marks nothing in the middle of a lesson.
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
		# A page about nothing on the HUD still dims everything but itself.
		var director: TutorialDirector = _director
		if director != null && director.current_page() != null:
			_place_dim(Rect2(size * 0.5, Vector2.ZERO))
		else:
			_set_dim_visible(false)
		if _highlight != null:
			_highlight.hide()
		if _caption != null:
			_caption.hide()
		return

	_phase += delta * PULSE_SPEED
	var rect: Rect2 = _screen_rect_of(target)
	_place_highlight(rect)
	var step: TutorialStep = _director.current_step()
	# An explanation always dims: what it is about and the page saying so are
	# the only two things on screen.
	if step != null && (step.dims_around_highlight || step is TutorialExplainStep):
		_place_dim(rect)
	else:
		_set_dim_visible(false)
	var page: TutorialPage = _director.current_page()
	_place_caption(rect, "" if page == null else page.caption)


## What the border marks this frame, in the order the class note gives.
func _resolve() -> Control:
	var director: TutorialDirector = _director
	if director == null || !director.is_running() || director.is_between_lessons():
		return null
	if director.current_moment() != null:
		return null
	var step: TutorialStep = director.current_step()
	if step == null:
		return null
	if step is TutorialExplainStep:
		var page: TutorialPage = director.current_page()
		return null if page == null else _control_for(page.highlight_key)

	if TutorialGuide.needs_selecting(step):
		return _control_for(TutorialGuide.button_key(step.guide_unit))

	# A named technology: the button that opens the Research Center until it is
	# open, then the square to press. Before the command card, because a task
	# that names both is researched first and built afterwards.
	var tech: int = step.next_tech(director)
	if tech != 0:
		var center: ResearchCenter = References.research_center
		if center == null || !center.is_open():
			return _control_for(&"research_button")
		return center.slot_for_tech(tech)

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
			# The scoreboard rebuilds its rows whenever a number moves, so the
			# one cell worth framing in it is asked for rather than named.
			var stats: PlayerStatsPanel = _controls[index] as PlayerStatsPanel
			if stats != null:
				return stats.tutorial_part(key)
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


## Frames the control with the border, pulsing.
func _place_highlight(rect: Rect2) -> void:
	if _highlight == null:
		return
	_highlight.show()
	var framed: Rect2 = rect.grow(OUTSET)
	_highlight.position = framed.position
	_highlight.size = framed.size
	var pulse: float = 0.5 + 0.5 * sin(_phase)
	_highlight.modulate.a = lerpf(PULSE_MIN_ALPHA, 1.0, pulse)


## The caption under the border, kept on screen, or hidden with no text.
func _place_caption(rect: Rect2, text: String) -> void:
	if _caption == null || _caption_label == null:
		return
	if text.is_empty():
		_caption.hide()
		return
	_caption_label.text = text
	_caption.show()
	_caption.reset_size()
	var wanted: Vector2 = Vector2(rect.get_center().x - _caption.size.x * 0.5,
		rect.end.y + OUTSET + CAPTION_GAP)
	wanted.x = clampf(wanted.x, CAPTION_MARGIN, size.x - _caption.size.x - CAPTION_MARGIN)
	_caption.position = wanted


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
