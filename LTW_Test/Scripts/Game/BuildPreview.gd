class_name BuildPreview
extends Node3D

## Ghost shown while a build order is being aimed.
##
## Uses the building's own model scene rather than a stand-in box, so what you
## see while aiming is exactly what gets placed. The model handles looking like
## a ghost; this only positions it and reports whether the spot is legal.

var _model: UnitModel


## Builds the ghost from a unit's model scene. Safe to call again to swap it.
func setup(model_scene: PackedScene) -> void:
	if is_instance_valid(_model):
		_model.queue_free()
	_model = null

	if model_scene == null:
		Log.err("BuildPreview got no model scene, nothing to show")
		return

	var instance: UnitModel = model_scene.instantiate() as UnitModel
	if instance == null:
		Log.err("Build preview model scene root is not a UnitModel")
		return

	_model = instance
	_model.name = "PreviewModel"
	add_child(_model)
	# After add_child, so the model has collected its meshes in _ready.
	_model.set_mode(UnitModel.Mode.PREVIEW)


func show_at(world_center: Vector3, valid: bool) -> void:
	global_position = Vector3(world_center.x, 0.0, world_center.z)
	if is_instance_valid(_model):
		_model.set_preview_valid(valid)
	visible = true
