class_name FadePulse2D
extends Node

@export_group("Settings")
@export var autostart: bool = true
@export_range(0.0, 1.0, 0.01) var alpha_min: float = 0.4
@export_range(0.0, 1.0, 0.01) var alpha_max: float = 1.0
@export var duration: float = 1.5

var target: Node
var tween: Tween
var start_alpha: float = 1.0

var start_value

func _ready() -> void:
	target = get_parent()
	if !(target is Node2D) && !(target is Control):
		push_error("FadeComponent: Parent must be a Node2D or Control")
		return

	if autostart:
		start_pulse()


func start_pulse() -> void:
	tween = create_tween()
	start_alpha = target.modulate.a

	tween.tween_property(target, "modulate:a", alpha_max, duration)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)

	await tween.finished
	tween.kill()
	tween = create_tween()

	tween.set_loops()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(target, "modulate:a", alpha_max, duration)
	tween.tween_property(target, "modulate:a", alpha_min, duration)

func stop_pulse() -> void:
	tween.kill()

	tween = create_tween()

	tween.tween_property(target, "modulate:a", start_alpha, duration)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
