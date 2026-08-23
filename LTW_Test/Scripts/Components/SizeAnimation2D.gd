class_name SizeAnimation2D
extends Node

signal finished

# This can be used if the animator is only used for one specific animation
@export_group("Single Animation Settings")
@export var single_animation_start_size: Vector2
@export var single_animation_target_size: Vector2
@export var single_animation_duration: float
@export var single_animation_ease_type: Tween.EaseType = Tween.EaseType.EASE_OUT
@export var single_animation_transition_type: Tween.TransitionType = Tween.TransitionType.TRANS_CUBIC

var target: Control
var tween: Tween

func _ready() -> void:
	target = get_parent() as Control
	if !target:
		push_error("SizeAnimationControl requires a Control parent.")
		queue_free()
		return


func size_to(target_size: Vector2,
		duration: float,
		ease_type: Tween.EaseType = Tween.EASE_IN_OUT,
		trans_type: Tween.TransitionType = Tween.TransitionType.TRANS_QUAD,
		use_signal: bool = true,
) -> void:
	if tween && tween.is_running():
		tween.kill()

	if !target:
		target = get_parent() as Control

	# No need for a tween here
	if duration == 0:
		target.size = target_size
		return

	tween = create_tween()

	tween.set_trans(trans_type)
	tween.set_ease(ease_type)

	tween.tween_property(target, "size", target_size, duration)

	await tween.finished
	if use_signal:
		finished.emit()


func do_pop(start_size: Vector2, peak_size: Vector2, end_size: Vector2, duration_up: float, duration_down: float) -> void:
	if tween && tween.is_running():
		tween.kill()

	target.size = start_size
	await size_to(peak_size, duration_up, Tween.EaseType.EASE_OUT, Tween.TransitionType.TRANS_SINE, false)
	await size_to(end_size, duration_down, Tween.EASE_IN, Tween.TransitionType.TRANS_SINE, false)
	finished.emit()


#region Single Animation
func single_animation() -> void:
	target.size = single_animation_start_size
	await size_to(single_animation_target_size, single_animation_duration, single_animation_ease_type, single_animation_transition_type)

func reverse_single_animation() -> void:
	var type: Tween.EaseType = Tween.EASE_IN
	match single_animation_ease_type:
		Tween.EASE_IN:
			type = Tween.EASE_OUT
		Tween.EASE_IN_OUT:
			type = Tween.EASE_IN
		Tween.EASE_IN_OUT:
			type = Tween.EASE_OUT_IN
		Tween.EASE_OUT_IN:
			type = Tween.EASE_IN_OUT

	target.size = single_animation_target_size
	await size_to(single_animation_start_size, single_animation_duration, type, single_animation_transition_type)

func reset_single_animation() -> void:
	target.size = single_animation_start_size
#endregion
