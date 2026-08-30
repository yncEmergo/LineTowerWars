class_name Bar3D
extends Node3D

## One worldspace bar: a filled proportion, drawn flat over the world.
##
## Deliberately plain - no easing, no fade.
##
## A single quad with a split-colour shader rather than a filled quad layered
## over an empty one. Two overlapping quads sort by camera distance, so which
## one drew on top changed with where the unit stood, and billboarded materials
## also discard node scale, which broke resizing the fill by scaling it. One
## quad plus a uniform sidesteps both.
##
## The colours are plain vars rather than @exports because every bar in the
## game is built in code by the unit that owns it, never placed in a scene.
## Set them before the bar enters the tree; _ready is what hands them over.

const SHADER_PATH: String = "res://Resources/Shaders/health_bar.gdshader"

const BAR_WIDTH: float = 0.72
const BAR_HEIGHT: float = 0.11

## Colour of the filled part, and of what is left to fill. Placeholder values
## a subclass or a creator overrides, which is why they are constants here and
## vars below.
const DEFAULT_FILL: Color = Color(0.24, 0.80, 0.28, 1.0)
const DEFAULT_EMPTY: Color = Color(0.65, 0.13, 0.13, 1.0)

var fill_color: Color = DEFAULT_FILL
var empty_color: Color = DEFAULT_EMPTY
## How thick this bar is drawn. A var rather than the constant it defaults to,
## because a bar stacked under the health bar should not be as loud as the one
## it hangs off - a second full-height rectangle over every tower reads as two
## health bars. Set it before the bar enters the tree, like the colours.
var bar_height: float = BAR_HEIGHT

var _material: ShaderMaterial
## Last ratio set. Kept because a subclass's visibility rule is a question
## about it and the shader parameter cannot be read back cheaply.
var _ratio: float = 1.0


func _ready() -> void:
	var shader: Shader = load(SHADER_PATH) as Shader
	if shader == null:
		Log.err("Bar3D could not load its shader", SHADER_PATH)
		return

	# One material per bar, because each carries its own ratio.
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("fill_color", fill_color)
	_material.set_shader_parameter("missing_color", empty_color)
	_material.set_shader_parameter("ratio", _ratio)

	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(BAR_WIDTH, bar_height)
	quad.material = _material

	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = "Bar"
	instance.mesh = quad
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

	_on_ratio_changed()


## Repaints the bar. Safe before the bar is in the tree - the vars are what
## _ready hands to the material - and after, which is what a bar whose tower
## changed KIND of second resource needs. See ResourceBar3D.
func set_colors(fill: Color, empty: Color) -> void:
	fill_color = fill
	empty_color = empty
	if _material == null:
		return
	_material.set_shader_parameter("fill_color", fill_color)
	_material.set_shader_parameter("missing_color", empty_color)


## Sets the filled proportion, 0 to 1.
func set_ratio(ratio: float) -> void:
	_ratio = clampf(ratio, 0.0, 1.0)
	if _material != null:
		_material.set_shader_parameter("ratio", _ratio)
	_on_ratio_changed()


## Hook for a subclass that decides whether to be seen from the ratio it was
## just given. Does nothing here: a plain bar is shown by whoever made it and
## hidden when the thing it describes is over.
func _on_ratio_changed() -> void:
	pass
