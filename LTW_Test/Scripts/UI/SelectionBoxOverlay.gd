class_name SelectionBoxOverlay
extends Control

## Draws the drag-selection rectangle. Purely visual - the actual selection
## test lives in SelectionController.

# Visual reference values, so they stay in the script.
const FILL_COLOR: Color = Color(0.30, 0.95, 0.35, 0.12)
const BORDER_COLOR: Color = Color(0.40, 1.00, 0.45, 0.85)
const BORDER_WIDTH: float = 1.5

var _rect: Rect2 = Rect2()
var _active: bool = false


func _ready() -> void:
	# The overlay must never swallow gameplay clicks.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func show_box(rect: Rect2) -> void:
	_rect = rect
	_active = true
	queue_redraw()


func hide_box() -> void:
	if !_active:
		return
	_active = false
	queue_redraw()


func _draw() -> void:
	if !_active:
		return
	draw_rect(_rect, FILL_COLOR, true)
	draw_rect(_rect, BORDER_COLOR, false, BORDER_WIDTH)
