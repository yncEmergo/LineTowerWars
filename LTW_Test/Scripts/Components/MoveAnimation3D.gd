class_name MoveAnimation3D
extends Node

# This can be used if the animator is only used for one specific animation
@export_group("Single Animiation Settings")
@export var single_animation_start_pos: Vector3
@export var single_animation_target_pos: Vector3
@export var single_animation_duration: float
@export var single_animation_ease_type: Tween.EaseType = Tween.EaseType.EASE_OUT
@export var single_animation_transition_type: Tween.TransitionType = Tween.TransitionType.TRANS_CUBIC

@export_group("Interpolate Settings")
@export var do_interpolate_at_start: bool = false
@export var delay_for_interpolate_autostart: float = 0.0
@export var interpolate_target_position: Vector3
@export var interpolate_duration: float = 1.0
@export var interpolate_ease_type: Tween.EaseType = Tween.EASE_IN_OUT
@export var interpolate_trans_type: Tween.TransitionType = Tween.TransitionType.TRANS_QUAD

@export var add_debugging: bool = false

var interpolate_start_position: Vector3

var tween: Tween

var has_interpolated: bool = false
var wiggle_rest_position: Vector3
var is_wiggling: bool = false
var _target: Node3D
var target: Node3D:
	get:
		if !_target:
			set_target()
		return _target

func set_target() -> void:
	if _target != null:
		return
	var parent: Node = get_parent()

	if !(parent is Node3D):
		push_error("MoveAnimation3D requires Node3D parent.")
		queue_free()
		return

	_target = parent as Node3D

func _ready() -> void:
	set_target()

	if do_interpolate_at_start:
		if delay_for_interpolate_autostart > 0:
			await get_tree().create_timer(delay_for_interpolate_autostart).timeout
		start_interpolate()


func move_to(
		target_position: Vector3,
		duration: float,
		ease_type: Tween.EaseType = Tween.EASE_IN_OUT,
		trans_type: Tween.TransitionType = Tween.TransitionType.TRANS_QUAD
) -> void:
	if tween && tween.is_running():
		tween.kill()

	if add_debugging:
		Log.info("Start moving: " + target.name)

	# No need for a tween here, also no need to wait 1 frame.
	if duration == 0:
		target.position = target_position
		return

	if target.position == target_position:
		return

	tween = create_tween()

	tween.set_trans(trans_type)
	tween.set_ease(ease_type)

	tween.tween_property(target, "position", target_position, duration)

	await tween.finished

	if add_debugging:
		Log.info("finished")


func start_interpolate() -> void:
	if tween && tween.is_running():
		tween.kill()

	if add_debugging:
		Log.info("Start interpolate: " + target.name)

	interpolate_start_position = target.position

	tween = create_tween()
	tween.set_trans(interpolate_trans_type)
	tween.set_ease(interpolate_ease_type)

	tween.set_loops()

	tween.tween_property(target, "position", interpolate_target_position, interpolate_duration)
	tween.tween_property(target, "position", interpolate_start_position, interpolate_duration)

	has_interpolated = true


func start_interpolate_manual(from: Vector3, to: Vector3, duration: float) -> void:
	if add_debugging:
		Log.info("Start interpolate manual: " + target.name)

	# Stop any existing tween
	if tween && tween.is_running():
		tween.kill()

	var current: Vector3 = target.position
	var dist_from_to: float = from.distance_to(to)
	var dist_current_to_from: float = current.distance_to(from)

	if is_zero_approx(dist_from_to):
		target.position = from
		interpolate_target_position = to
		interpolate_duration = duration
		has_interpolated = true
		return

	var ratio: float = clamp(dist_current_to_from / dist_from_to, 0.0, 1.0)
	var duration_to_from: float = duration * ratio

	interpolate_target_position = to
	interpolate_duration = duration

	if is_zero_approx(duration_to_from) || dist_current_to_from < 0.001:
		target.position = from
		start_interpolate()
		return

	tween = create_tween()
	tween.set_trans(interpolate_trans_type)
	tween.set_ease(interpolate_ease_type)

	tween.tween_property(target, "position", from, duration_to_from)

	await tween.finished
	start_interpolate()


func stop_interpolate() -> void:
	if tween && tween.is_running():
		tween.kill()

	if add_debugging:
		Log.info("Stop interpolate: " + target.name)

	if has_interpolated:
		target.position = interpolate_start_position


func side_wiggle(max_x_offset: float, duration_per_movement: float, total_duration: float) -> void:
	if tween && tween.is_running():
		tween.kill()

	if add_debugging:
		Log.info("Start side wiggle: " + target.name)

	# Guard against invalid input
	if max_x_offset <= 0.0 || duration_per_movement <= 0.0 || total_duration <= 0.0:
		if add_debugging:
			Log.info("Side wiggle aborted (invalid params): " + target.name)
		return

	# IMPORTANT: Don't take the current position as center if we were already wiggling.
	# That avoids drift when side_wiggle is called while a wiggle is in progress.
	if !is_wiggling:
		wiggle_rest_position = target.position

	is_wiggling = true

	tween = create_tween()
	tween.set_trans(Tween.TransitionType.TRANS_QUAD)
	tween.set_ease(Tween.EaseType.EASE_IN_OUT)

	var elapsed: float = 0.0
	var dir: float = 1.0

	while elapsed < total_duration:
		var step: float = min(duration_per_movement, total_duration - elapsed)

		dir *= -1.0
		var target_pos: Vector3 = wiggle_rest_position + Vector3(max_x_offset * dir, 0.0, 0.0)

		tween.tween_property(target, "position", target_pos, step)
		elapsed += step

	var return_step: float = min(duration_per_movement, total_duration)
	tween.tween_property(target, "position", wiggle_rest_position, return_step)

	await tween.finished

	# Ensure exact restore and clear state
	target.position = wiggle_rest_position
	is_wiggling = false


#region Single Animation
func single_animation(override_duration: float = -1) -> void:
	var duration: float = single_animation_duration if override_duration == -1 else override_duration
	#target.position = single_animation_start_pos
	await move_to(single_animation_target_pos, duration, single_animation_ease_type, single_animation_transition_type)


func reverse_single_animation(override_duration: float = -1) -> void:
	var duration: float = single_animation_duration if override_duration == -1 else override_duration
	var type: Tween.EaseType = Tween.EASE_IN

	match single_animation_ease_type:
		Tween.EASE_IN:
			type = Tween.EASE_OUT
		Tween.EASE_OUT:
			type = Tween.EASE_IN
		Tween.EASE_IN_OUT:
			type = Tween.EASE_OUT_IN
		Tween.EASE_OUT_IN:
			type = Tween.EASE_IN_OUT

	#target.position = single_animation_target_pos
	await move_to(single_animation_start_pos, duration, type, single_animation_transition_type)


func reset_single_animation() -> void:
	target.position = single_animation_start_pos


func set_single_animation_end_pos() -> void:
	target.position = single_animation_target_pos
#endregion
