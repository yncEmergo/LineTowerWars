class_name FadeAnimation2D
extends Node

var target: Node
var tween: Tween

func _ready() -> void:
	try_get_target()

func try_get_target() -> void:
	target = get_parent()
	if !(target is Node2D || target is Control):
		push_error("FadeAnimation2D requires Node2D or Control parent.")
		queue_free()
		return

func fade(start_value: float, end_value: float, duration: float, set_start_value: bool = false) -> void:
	if !target:
		try_get_target()

	if !target:
		return

	if !target.visible:
		target.show()

	if tween && tween.is_running():
		tween.kill()

	# No need for a tween here, also no need to wait 1 frame.
	if duration == 0:
		target.modulate.a = end_value
		return

	if target.modulate.a == end_value && !set_start_value:
		return

	var color: Color = target.modulate
	color.a = start_value
	target.modulate = color

	tween = create_tween()
	tween.tween_property(target, "modulate:a", end_value, duration)
	await tween.finished

# Does set start value
func fade_in_from_zero(duration: float) -> void:
	await fade(0, 1, duration, true)

# Does set start value
func fade_out_from_one(duration: float) -> void:
	await fade(1, 0, duration, true)

# Does not set start value
func fade_in(duration: float) -> void:
	if !target:
		try_get_target()

	if !target:
		return

	var current: float = target.modulate.a

	if current >= 1.0:
		return

	#D uration scaled by remaining distance
	var scaled_duration := duration * (1.0 - current)
	await fade(current, 1.0, scaled_duration)

# Does not set start value
func fade_out(duration: float) -> void:
	if !target:
		try_get_target()

	if !target:
		return

	var current: float = target.modulate.a

	if current <= 0.0:
		return

	# Duration scaled by remaining distance
	var scaled_duration: float = duration * current
	await fade(current, 0.0, scaled_duration)
