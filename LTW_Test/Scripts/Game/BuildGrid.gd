class_name BuildGrid
extends MeshInstance3D

## Grid overlay drawn on top of a player's buildable zone.
##
## A single quad carrying a derivative-based grid shader. That keeps the lines
## at a constant on-screen thickness for any camera distance or angle, costs
## one draw call, and avoids the aliasing that generated line geometry suffers.
##
## Only player-facing cells are drawn. Internal half cells stay hidden from the
## player per game_rules.md, so switching to the internal resolution is a
## matter of multiplying cell_count by internal_cells_per_cell.
##
## Shared config comes from References. The grid material stays an @export
## because it belongs to this node rather than being shared state.

## Height above the ground quads, enough to avoid z-fighting.
const GROUND_OFFSET: float = 0.02

# Row number styling. Visual reference values, so they stay in the script.
## Gap between the left grid edge and the row numbers, in cells.
const LABEL_MARGIN_CELLS: float = 0.6
const LABEL_FONT_SIZE: int = 48
## World size of one font pixel. Times the font size, this is the text height.
const LABEL_PIXEL_SIZE: float = 0.01
const LABEL_COLOR: Color = Color(0.85, 0.88, 0.92, 0.90)
const LABEL_OUTLINE_SIZE: int = 6
const LABEL_OUTLINE_COLOR: Color = Color(0.05, 0.05, 0.08, 0.90)

@export_group("References")
## The grid's own material, so it stays an @export rather than shared state.
@export var _grid_material: ShaderMaterial

@export_group("Settings")
## Whether the grid starts visible.
@export var visible_on_start: bool = true

var _runtime_material: ShaderMaterial

## Read throughout, so it comes through a getter onto References.
var _game_config: GameConfig:
	get:
		return References.game_config


func _ready() -> void:
	if _game_config == null:
		Log.err("BuildGrid found no GameConfig on References, grid disabled")
		return
	if _grid_material == null:
		Log.err("BuildGrid has no grid material assigned, grid disabled")
		return
	# An overlay should never darken the ground underneath it.
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_build_quad()
	_build_row_labels()
	visible = visible_on_start


func _build_quad() -> void:
	var depth: float = float(_game_config.build_depth_cells) * _game_config.cell_size

	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(_game_config.area_width(), depth)
	mesh = plane

	# Duplicated so writing cell_count never mutates the shared .tres on disk.
	_runtime_material = _grid_material.duplicate()
	_runtime_material.set_shader_parameter("cell_count", Vector2(
		float(_game_config.area_width_cells),
		float(_game_config.build_depth_cells)
	))
	material_override = _runtime_material


## Row numbers down the left edge, 1 at the top through to the last row at
## the bottom. They are children of this node, so they inherit its visibility
## and toggle together with the grid.
func _build_row_labels() -> void:
	var container: Node3D = Node3D.new()
	container.name = "RowLabels"
	add_child(container)

	var cell: float = _game_config.cell_size
	var rows: int = _game_config.build_depth_cells
	var label_x: float = -(_game_config.area_width() * 0.5) - LABEL_MARGIN_CELLS * cell

	for row in range(1, rows + 1):
		container.add_child(_make_row_label(row, rows, cell, label_x))


func _make_row_label(row: int, rows: int, cell: float, label_x: float) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = "RowLabel%d" % row
	label.text = str(row)

	label.font_size = LABEL_FONT_SIZE
	label.pixel_size = LABEL_PIXEL_SIZE
	label.modulate = LABEL_COLOR
	label.outline_size = LABEL_OUTLINE_SIZE
	label.outline_modulate = LABEL_OUTLINE_COLOR
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Laid flat on the ground rather than billboarded, so the numbers read as
	# part of the board. The camera pitch is fixed, so they never turn away.
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)

	# This node sits at the centre of the zone, so local z runs from
	# -depth/2 at the top to +depth/2 at the bottom. Row 1 is topmost.
	label.position = Vector3(
		label_x,
		0.0,
		(float(row) - 0.5) * cell - float(rows) * cell * 0.5
	)
	return label


## Positions the grid over the given area's buildable zone.
func cover_build_zone(area: PlayerArea) -> void:
	if _game_config == null || area == null:
		Log.err("BuildGrid.cover_build_zone called without a config or area")
		return

	var start_z: float = _game_config.build_zone_start_z()
	var end_z: float = _game_config.build_zone_end_z()

	global_position = area.to_global(Vector3(
		_game_config.area_width() * 0.5,
		GROUND_OFFSET,
		(start_z + end_z) * 0.5
	))


## Deliberately no input handling of its own any more. Showing and hiding the
## grid is a BUILDER ABILITY now, so it gets a card square, a hotkey
## that follows that square and a tooltip - and there is one way to do it
## rather than a key binding beside a button. See ToggleGridAbility.
