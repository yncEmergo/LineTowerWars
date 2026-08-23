## Provided by ChatGPT TM

class_name FloatingNoiseAnimator
extends Node

@export var target: Node            # Node2D or Control

# ---- POSITION FLOAT SETTINGS ----
@export var pos_enabled: bool = true
@export var pos_amount: Vector2 = Vector2(5, 3)   # max XY offset in px
@export var pos_speed: float = 1.0                # noise speed
@export var pos_seed: int = 12345                 # seed for noise

# ---- SCALE FLOAT SETTINGS ----
@export var scale_enabled: bool = false
@export var scale_amount: Vector2 = Vector2(0.05, 0.05)  # max scale offsets
@export var scale_speed: float = 1.0
@export var scale_seed: int = 54321

# Internal noise generators
var _pos_noise := FastNoiseLite.new()
var _scale_noise := FastNoiseLite.new()

var _base_pos: Vector2
var _base_scale: Vector2
var _time: float = 0.0


func _ready() -> void:
	if !target:
		push_warning("FloatingNoiseAnimator: No target assigned.")
		return

	_base_pos = target.position if target is Node2D else target.position
	_base_scale = target.scale

	# Setup noise generators
	_pos_noise.seed = pos_seed
	_pos_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX

	_scale_noise.seed = scale_seed
	_scale_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX


func _process(delta: float) -> void:
	if !target:
		return

	_time += delta

	if pos_enabled:
		_apply_position_float()

	if scale_enabled:
		_apply_scale_float()

# Pos float
func _apply_position_float() -> void:
	var nx = _pos_noise.get_noise_2d(_time * pos_speed, 0.0)
	var ny = _pos_noise.get_noise_2d(0.0, _time * pos_speed)

	var offset = Vector2(
		nx * pos_amount.x,
		ny * pos_amount.y
	)

	if target is Node2D:
		target.position = _base_pos + offset
	elif target is Control:
		target.position = _base_pos + offset

# Scale float
func _apply_scale_float() -> void:
	var nx = _scale_noise.get_noise_2d(_time * scale_speed, 0.0)
	var ny = _scale_noise.get_noise_2d(0.0, _time * scale_speed)

	var offset = Vector2(
		nx * scale_amount.x,
		ny * scale_amount.y
	)

	target.scale = _base_scale + offset


# Manual calling

func get_position_float_offset(time: float) -> Vector2:
	return Vector2(
		_pos_noise.get_noise_2d(time * pos_speed, 0.0) * pos_amount.x,
		_pos_noise.get_noise_2d(0.0, time * pos_speed) * pos_amount.y
	)


func get_scale_float_offset(time: float) -> Vector2:
	return Vector2(
		_scale_noise.get_noise_2d(time * scale_speed, 0.0) * scale_amount.x,
		_scale_noise.get_noise_2d(0.0, time * scale_speed) * scale_amount.y
	)
