class_name RadialCooldown
extends Control

## Dark wedge sweeping off a command slot as its next charge comes back.
##
## The convention every RTS and MMO uses: the overlay covers the icon and
## clockwise-unwinds to nothing as the wait finishes, so how much is left is
## readable at a glance without a number.
##
## It also stands for a wait that has not STARTED - an ability that cannot be
## used at all draws it whole - which is why nothing dims a command slot any
## more. One mark rather than two saying the same thing over each other.
##
## Drawn rather than textured, because a wedge is a polygon fan and a texture
## would need either a shader or an art asset for something this simple.

## Where the sweep begins. Straight up, like a clock.
const START_ANGLE: float = -PI * 0.5
## Degrees per polygon segment. 48 segments to a full circle is smooth at the
## size a command slot is ever drawn.
const SEGMENTS_PER_TURN: int = 48

@export_group("Settings")
## Dark enough to be read as "cannot be pressed" on its own. It carries that
## alone now: a slot no longer greys its icon, so this is the whole of the
## mark rather than half of it. See CommandSlot._sweep_progress().
@export var overlay_color: Color = Color(0.0, 0.0, 0.0, 0.78)

var _progress: float = 1.0


func _ready() -> void:
	# Purely a readout, so it must never take the click meant for the slot
	# underneath it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The fan reaches the CORNERS of the square (see _draw), which on a circle
	# means it also reaches past its edges. Clipped rather than drawn smaller,
	# because a wedge that stopped at the inscribed circle would leave four lit
	# triangles in the corners of every covered slot.
	clip_contents = true
	visible = false


## Sets how ready the charge is, 0 to 1. At 1 the overlay disappears entirely.
func set_progress(value: float) -> void:
	var clamped: float = clampf(value, 0.0, 1.0)
	if is_equal_approx(clamped, _progress):
		return

	_progress = clamped
	visible = _progress < 1.0
	queue_redraw()


func _draw() -> void:
	if _progress >= 1.0:
		return

	var center: Vector2 = size * 0.5
	# Out to the corners, so a square slot is covered edge to edge rather than
	# leaving four lit triangles behind.
	var radius: float = center.length()

	var start: float = START_ANGLE + _progress * TAU
	var sweep: float = (1.0 - _progress) * TAU
	var steps: int = maxi(2, int(ceil(float(SEGMENTS_PER_TURN) * (1.0 - _progress))))

	var points: PackedVector2Array = PackedVector2Array()
	points.append(center)
	for index in range(steps + 1):
		var angle: float = start + sweep * float(index) / float(steps)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)

	draw_colored_polygon(points, overlay_color)
