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
## Each mesh's authored shadow setting, so leaving preview mode restores what
## the scene asked for instead of switching everything on. The foundation quad
## is the reason: a flat decal lying on the ground has no business casting.
var _mesh_shadows: Array[int] = []
## Kept apart from _meshes because a foundation is the one part of a model
## that is NOT the building: it never takes the flat ghost material, and it
## has a say of its own in whether it shows at all.
var _foundations: Array[BuildingFoundation] = []
var _preview_material: StandardMaterial3D


func _ready() -> void:
	_collect_meshes(self)
	_apply_mode()


## Every MeshInstance3D under the model, so a model can be as deep as it likes
## without this needing to know its layout. Ground patches are sorted out here
## rather than tested for again in every loop below.
func _collect_meshes(node: Node) -> void:
	for child in node.get_children():
		var foundation: BuildingFoundation = child as BuildingFoundation
		if foundation != null:
			_foundations.append(foundation)
		else:
			var mesh: MeshInstance3D = child as MeshInstance3D
			if mesh != null:
				_meshes.append(mesh)
				_mesh_shadows.append(mesh.cast_shadow)
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

	for index: int in _meshes.size():
		var mesh: MeshInstance3D = _meshes[index]
		if _mode == Mode.PREVIEW:
			mesh.material_override = _preview_material
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			mesh.material_override = null
			mesh.cast_shadow = (
				_mesh_shadows[index] as GeometryInstance3D.ShadowCastingSetting
			)

	# A ground patch keeps its own stone shader in both modes. Flattening it
	# into the ghost material would lose the thing worth showing - which cells
	# the building is about to pave - and leave a plain coloured square.
	if _mode == Mode.PREVIEW:
		_apply_preview_color()
	else:
		for foundation: BuildingFoundation in _foundations:
			foundation.show_as_built()


func _build_preview_material() -> void:
	if _preview_material != null:
		return
	_preview_material = StandardMaterial3D.new()
	_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Above the ground and the build grid, both of which are transparent too.
	_preview_material.render_priority = 2


func _apply_preview_color() -> void:
	var color: Color = PREVIEW_VALID_COLOR
	if !_preview_valid:
		color = PREVIEW_INVALID_COLOR

	if _preview_material != null:
		_preview_material.albedo_color = color
	for foundation: BuildingFoundation in _foundations:
		foundation.show_as_preview(color)
