class_name TutorialWorldArrows
extends Node3D

## The arrows that hover over things IN THE WORLD during a lesson: over the
## builder while the lesson wants it selected, and over every blueprint cell
## still to build on.
##
## The counterpart of TutorialPointer, which points at the HUD. A HUD arrow
## cannot point into the world - the thing it would point at moves under the
## camera - so the world gets arrows of its own, standing in it and bobbing.
##
## Built by TutorialDirector when a tutorial begins, and nowhere else. Re-read
## every frame rather than on a lesson change, because what it points at moves
## and disappears on its own: the builder walks, and a cell stops wanting an
## arrow the moment a tower starts on it.
##
## PRESENTATION, local from end to end. The arrows are reused rather than freed
## and made again, so a cell filling in costs a hide rather than a free.

## The arrow's scene. Loaded on first use. A constant rather than an export
## because this node is built in code, and the scene is a visual asset rather
## than a setting.
const ARROW_SCENE_PATH: String = "res://Scenes/Effects/tutorial_hover_arrow.tscn"
## How far above a unit's origin the arrow's tip hovers, in world units - clear
## over its head rather than into it.
const ABOVE_UNIT: float = 2.4
## How far above an empty cell the tip hovers.
const ABOVE_CELL: float = 0.35
## How far above a standing tower's origin the tip hovers - over its top.
const ABOVE_TOWER: float = 1.2

var _scene: PackedScene = null
var _pool: Array[Node3D] = []


func _process(_delta: float) -> void:
	var points: Array[Vector3] = _points()
	while _pool.size() < points.size():
		var arrow: Node3D = _make_arrow()
		if arrow == null:
			break
		_pool.append(arrow)

	var facing: Basis = _facing()
	for index in range(_pool.size()):
		var arrow: Node3D = _pool[index]
		var shown: bool = index < points.size()
		arrow.visible = shown
		if shown:
			arrow.global_transform = Transform3D(facing, points[index])


## An arrow instance for the shader warm-up to draw before the match, so its
## material is not compiled on the frame the first lesson opens. Null when the
## scene does not load. See ShaderWarmup._draw_acted.
static func warmup_proxy() -> Node3D:
	if !ResourceLoader.exists(ARROW_SCENE_PATH):
		return null
	var scene: PackedScene = ResourceLoader.load(ARROW_SCENE_PATH, "PackedScene") as PackedScene
	return null if scene == null else scene.instantiate() as Node3D


## Where the tips go this frame.
func _points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	var director: TutorialDirector = References.tutorial_director
	if director == null || !director.is_running() || director.is_between_lessons():
		return points
	var step: TutorialStep = director.current_step()
	if step == null:
		return points

	if step.guide_unit == TutorialStep.Select.BUILDER && TutorialGuide.needs_selecting(step):
		var builder: Unit = TutorialGuide.unit_for(TutorialStep.Select.BUILDER)
		if builder != null:
			points.append(builder.global_position + Vector3.UP * ABOVE_UNIT)

	if step.arrows_on_blueprint:
		points.append_array(_open_cells(step.blueprint()))
	points.append_array(_towers_of(step.arrow_tower()))
	return points


## The world point over every tower of the player's of exactly this type.
func _towers_of(stats: BuildingStats) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var manager: PlayerManager = References.player_manager
	if stats == null || manager == null:
		return points
	var area: PlayerArea = manager.area_for(manager.local_player_id())
	if area == null:
		return points
	for child in area.get_children():
		var building: Building = child as Building
		if building != null && building.stats == stats:
			points.append(building.global_position + Vector3.UP * ABOVE_TOWER)
	return points


## The world point over every cell of a plan that nothing stands on yet.
func _open_cells(plan: TowerLayout) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var manager: PlayerManager = References.player_manager
	if plan == null || manager == null:
		return points
	var area: PlayerArea = manager.area_for(manager.local_player_id())
	if area == null:
		return points

	var taken: Dictionary = {}
	for child in area.get_children():
		var building: Building = child as Building
		if building != null:
			taken[building.cell] = true
	var footprint: Vector2i = area.cells_to_internal(Vector2i.ONE)
	for cell: Vector2i in plan.cells:
		if !taken.has(cell):
			points.append(area.footprint_world_center(cell, footprint) + Vector3.UP * ABOVE_CELL)
	return points


## The arrow stands upright in the world and points straight down, as the
## authored mesh does - a 3D object in the scene rather than a billboard. A
## camera-facing version was tried and read worse than this.
func _facing() -> Basis:
	return Basis.IDENTITY


func _make_arrow() -> Node3D:
	if _scene == null:
		if !ResourceLoader.exists(ARROW_SCENE_PATH):
			Log.err("The tutorial arrow scene is missing", ARROW_SCENE_PATH)
			return null
		_scene = ResourceLoader.load(ARROW_SCENE_PATH, "PackedScene") as PackedScene
	if _scene == null:
		return null
	var arrow: Node3D = _scene.instantiate() as Node3D
	add_child(arrow)
	return arrow
