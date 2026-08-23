class_name HealthBar3D
extends Node3D

## Worldspace health bar: green for remaining health, red for missing.
##
## Deliberately plain - no easing, no fade.
##
## A single quad with a split-colour shader rather than a green quad layered
## over a red one. Two overlapping quads sort by camera distance, so which one
## drew on top changed with where the unit stood, and billboarded materials
## also discard node scale, which broke resizing the fill by scaling it. One
## quad plus a uniform sidesteps both.

const SHADER_PATH: String = "res://Resources/Shaders/health_bar.gdshader"

const BAR_WIDTH: float = 0.72
const BAR_HEIGHT: float = 0.11
const COLOR_MISSING: Color = Color(0.65, 0.13, 0.13, 1.0)
const COLOR_FILL: Color = Color(0.24, 0.80, 0.28, 1.0)

var _material: ShaderMaterial


func _ready() -> void:
	var shader: Shader = load(SHADER_PATH) as Shader
	if shader == null:
		Log.err("HealthBar3D could not load its shader", SHADER_PATH)
		return

	# One material per bar, because each carries its own ratio.
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("fill_color", COLOR_FILL)
	_material.set_shader_parameter("missing_color", COLOR_MISSING)
	_material.set_shader_parameter("ratio", 1.0)

	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	quad.material = _material

	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = "Bar"
	instance.mesh = quad
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


## Sets the filled proportion, 0 to 1.
func set_ratio(ratio: float) -> void:
	if _material == null:
		return
	_material.set_shader_parameter("ratio", clampf(ratio, 0.0, 1.0))
