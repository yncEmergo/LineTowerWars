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
##
## Whether it is drawn at all is the player's choice, held on UserSettings.
## Every bar answers that question for itself out of the ratio it already has,
## so a unit taking its first hit reveals its own bar with no manager watching.
## Changing the setting mid-match is the one case a bar cannot notice on its
## own, which is what the group is for.

## Every live bar, so the options screen can refresh all of them at once when
## the setting changes. Nothing else uses it, and nothing else should: a bar
## going from full to damaged already updates itself.
const GROUP: String = "health_bars"

const SHADER_PATH: String = "res://Resources/Shaders/health_bar.gdshader"

const BAR_WIDTH: float = 0.72
const BAR_HEIGHT: float = 0.11
const COLOR_MISSING: Color = Color(0.65, 0.13, 0.13, 1.0)
const COLOR_FILL: Color = Color(0.24, 0.80, 0.28, 1.0)

var _material: ShaderMaterial
## Last ratio set, kept because the WHEN_DAMAGED rule is a question about it and
## the shader parameter cannot be read back cheaply.
var _ratio: float = 1.0


func _ready() -> void:
	add_to_group(GROUP)

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

	refresh_visibility()


## Sets the filled proportion, 0 to 1.
func set_ratio(ratio: float) -> void:
	_ratio = clampf(ratio, 0.0, 1.0)
	if _material != null:
		_material.set_shader_parameter("ratio", _ratio)
	refresh_visibility()


## Re-reads the player's choice. Called on every ratio change, and on the whole
## group by the options screen when that choice is changed mid-match.
func refresh_visibility() -> void:
	match UserSettings.health_bar_display:
		UserSettings.HealthBarDisplay.ALWAYS:
			visible = true
		UserSettings.HealthBarDisplay.WHEN_DAMAGED:
			visible = _ratio < 1.0
		UserSettings.HealthBarDisplay.NEVER:
			visible = false
		_:
			Log.err("HealthBar3D has a display mode it does not know",
				UserSettings.health_bar_display)
			visible = true
