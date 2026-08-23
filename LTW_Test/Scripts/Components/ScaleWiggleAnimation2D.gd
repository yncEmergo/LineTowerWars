class_name ScaleWiggleAnimation2D
extends ScaleAnimation2D

#region Single Animation
func single_animation(override_duration: float = -1) -> void:
	var duration: float = single_animation_duration if override_duration == -1 else override_duration

	target.scale = single_animation_start_scale
	await scale_to(single_animation_target_scale, duration, single_animation_ease_type, single_animation_transition_type)
	await reverse_single_animation(override_duration)
