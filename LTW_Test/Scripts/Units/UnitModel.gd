class_name UnitModel
extends Node3D

## Visuals for one unit type, and nothing else.
##
## The same model scene is used by the real prefab and by the build preview,
## so a tower and its ghost can never show different shapes. Which of the two
## it is showing is the mode.
##
## Behaviour stays out of here: this script only knows how to look like the
## unit, which is where animations and hit flashes will go later.

enum Mode {
	## Normal appearance, as placed in the world.
	BUILT,
	## Translucent ghost used while choosing where to build.
	PREVIEW,
}

const PREVIEW_VALID_COLOR: Color = Color(0.30, 0.90, 0.40, 0.45)
const PREVIEW_INVALID_COLOR: Color = Color(0.90, 0.28, 0.28, 0.45)

var _mode: Mode = Mode.BUILT
var _preview_valid: bool = true
var _meshes: Array[MeshInstance3D] = []
var _preview_material: StandardMaterial3D


func _ready() -> void:
	_collect_meshes(self)
	_apply_mode()


## Every MeshInstance3D under the model, so a model can be as deep as it likes
## without this needing to know its layout.
func _collect_meshes(node: Node) -> void:
	for child in node.get_children():
		var mesh: MeshInstance3D = child as MeshInstance3D
		if mesh != null:
			_meshes.append(mesh)
		_collect_meshes(child)


func set_mode(mode: Mode) -> void:
	if _mode == mode:
		return
	_mode = mode
	_apply_mode()


## Colours the ghost by whether the spot is legal. Ignored outside preview mode.
func set_preview_valid(valid: bool) -> void:
	if _preview_valid == valid:
		return
	_preview_valid = valid
	if _mode == Mode.PREVIEW:
		_apply_preview_color()


func _apply_mode() -> void:
	if _mode == Mode.PREVIEW:
		_build_preview_material()
		_apply_preview_color()

	for mesh in _meshes:
		if _mode == Mode.PREVIEW:
			mesh.material_override = _preview_material
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			mesh.material_override = null
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _build_preview_material() -> void:
	if _preview_material != null:
		return
	_preview_material = StandardMaterial3D.new()
	_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Above the ground and the build grid, both of which are transparent too.
	_preview_material.render_priority = 2


func _apply_preview_color() -> void:
	if _preview_material == null:
		return
	if _preview_valid:
		_preview_material.albedo_color = PREVIEW_VALID_COLOR
	else:
		_preview_material.albedo_color = PREVIEW_INVALID_COLOR
