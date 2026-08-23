class_name ScaleAnimation2D
extends Node

signal finished

# This can be used if the animator is only used for one specific animation
@export_group("Single Animiation Settings")
@export var single_animation_start_scale: Vector2
@export var single_animation_target_scale: Vector2
@export var single_animation_duration: float
@export var single_animation_ease_type: Tween.EaseType = Tween.EaseType.EASE_OUT
@export var single_animation_transition_type: Tween.TransitionType = Tween.TransitionType.TRANS_CUBIC

var target: Node
var tween: Tween

func _ready() -> void:
	set_target()

func set_target() -> void:
	if target: 
		return

	target = get_parent()
	if !(target is Node2D || target is Control):
		push_error("MoveAnimation2D requires Node2D or Control parent.")
		queue_free()
		return

func scale_to(target_scale: Vector2,
		duration: float,
		ease_type: Tween.EaseType = Tween.EASE_IN_OUT,
		trans_type: Tween.TransitionType = Tween.TransitionType.TRANS_QUAD,
		use_signal: bool = true,
)-> void:
	if tween && tween.is_running():
		tween.kill()

	if !target:
		target = get_parent()

	# No need for a tween here, also no need to wait 1 frame.
	if duration == 0:
		target.scale = target_scale
		return

	if target.scale == target_scale:
		return

	tween = create_tween()

	tween.set_trans(trans_type)
	tween.set_ease(ease_type)

	tween.tween_property(target, "scale", target_scale, duration)

	await tween.finished
	if use_signal:
		finished.emit()

func do_pop(start_scale: Vector2, peak_scale: Vector2, end_scale: Vector2, duration_up: float, duration_down: float) -> void:
	if tween && tween.is_running():
		tween.kill()

	target.scale = start_scale
	await scale_to(peak_scale, duration_up, Tween.EaseType.EASE_OUT, Tween.TransitionType.TRANS_SINE, false)
	await scale_to(end_scale, duration_down, Tween.EASE_IN, Tween.TransitionType.TRANS_SINE, false)
	finished.emit()

#region Single Animation
func single_animation(override_duration: float = -1) -> void:
	var duration: float = single_animation_duration if override_duration == -1 else override_duration

	target.scale = single_animation_start_scale
	await scale_to(single_animation_target_scale, duration, single_animation_ease_type, single_animation_transition_type)

func reverse_single_animation(override_duration: float = -1) -> void:
	var duration: float = single_animation_duration if override_duration == -1 else override_duration

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

	target.scale = single_animation_target_scale
	await scale_to(single_animation_start_scale, duration, type, single_animation_transition_type)

func reset_single_animation() -> void:
	target.scale = single_animation_start_scale

func set_single_animation() -> void:
	target.scale = single_animation_target_scale
#endregion
