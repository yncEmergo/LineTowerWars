class_name BuildingFoundation
extends MeshInstance3D

## The stone patch a building paints onto the ground under its footprint.
##
## The look itself is entirely the shader on its mesh, in
## Resources/Shaders/building_foundation.gdshader. What this class owns is the
## one thing that changes about it: whether it is a placed building's ground
## or a ghost's, which UnitModel tells it as the model's mode changes.
##
## A type rather than a node name, so renaming the node in a model scene can
## never quietly turn that rule off.

## Shader uniform the tint is written to. See the Preview group in
## building_foundation.gdshader.
const TINT_PARAM: StringName = &"preview_tint"

## The stone material duplicated for this node alone, built on first preview.
var _preview_material: ShaderMaterial

## Read on every mode change, so it comes through a getter onto References.
## Null on a dedicated server, which draws nothing and never previews.
var _config: PresentationConfig:
	get:
		return References.presentation_config


## Ground of a building that is actually there, whether still going up or
## finished. Plain stone, straight off the shared material.
func show_as_built() -> void:
	visible = true
	material_override = null


## Ground under a ghost. Whether it shows at all is a presentation setting,
## since it is a matter of taste whether the footprint helps or clutters.
## The colour is the ghost's own, so an illegal spot turns this red along with
## the rest of the model rather than staying reassuringly green.
func show_as_preview(color: Color) -> void:
	if _config == null:
		visible = false
		return

	visible = _config.preview_shows_foundation
	if !visible:
		return

	_build_preview_material()
	if _preview_material == null:
		return

	_preview_material.set_shader_parameter(TINT_PARAM, Color(
		color.r, color.g, color.b, _config.preview_foundation_tint
	))
	material_override = _preview_material


## Duplicated rather than tinted in place: one .tres is the material behind
## every foundation in the match, so writing a parameter on it would turn the
## whole board green. Built on first use, since the mesh is only guaranteed to
## be there once something asks to see it.
func _build_preview_material() -> void:
	if _preview_material != null:
		return
	if mesh == null:
		Log.err("BuildingFoundation has no mesh, its preview cannot be tinted")
		return

	var base: ShaderMaterial = mesh.surface_get_material(0) as ShaderMaterial
	if base == null:
		Log.err("BuildingFoundation mesh carries no ShaderMaterial to tint")
		return

	_preview_material = base.duplicate()
