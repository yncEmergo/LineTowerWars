class_name TutorialTickBox
extends Control

## The box at the end of a tutorial task, which gets a green tick when the task
## is done.
##
## DRAWN rather than a glyph from the font, so it cannot come out as a missing
## character on a font that has no tick in it, and it scales with the rest of the
## HUD like any other Control.

## Placeholder look, in the HUD's own palette: the gold of the lesson board's
## border for the box, and the green of the objective text for the tick.
const BOX_COLOR: Color = Color(0.42, 0.38, 0.24, 1.0)
const TICK_COLOR: Color = Color(0.4, 0.9, 0.45, 1.0)
const BOX_WIDTH: float = 2.0
const TICK_WIDTH: float = 3.0

## Whether the task is done.
var checked: bool = false:
	set(value):
		if checked == value:
			return
		checked = value
		queue_redraw()


func _draw() -> void:
	var box: Rect2 = Rect2(Vector2.ONE * BOX_WIDTH * 0.5, size - Vector2.ONE * BOX_WIDTH)
	draw_rect(box, BOX_COLOR, false, BOX_WIDTH)
	if !checked:
		return
	# A tick in the box's own proportions: down to the lower third, up to the
	# top right corner.
	var points: PackedVector2Array = PackedVector2Array([
		Vector2(size.x * 0.2, size.y * 0.52),
		Vector2(size.x * 0.42, size.y * 0.74),
		Vector2(size.x * 0.82, size.y * 0.26),
	])
	draw_polyline(points, TICK_COLOR, TICK_WIDTH, true)
