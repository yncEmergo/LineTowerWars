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
## How far above a unit's origin the arrow's tip hovers, in world units - over
## its head rather than through it.
const ABOVE_UNIT: float = 1.3
## How far above an empty cell the tip hovers.
const ABOVE_CELL: float = 0.35
## How much bigger than the authored mesh the arrow is drawn. The mesh is sized
## for a close camera; this game's sits high over a whole lane.
const ARROW_SCALE: float = 1.8

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


## The arrow is a flat slab facing +Z with its tip down local -Y, so it is
## turned to face the camera COMPLETELY - a billboard - and then points straight
## down the screen at the thing under it. Turning it about the vertical alone was
## the first version, and under a camera looking almost straight down that left
## a flat arrow seen nearly edge-on: a red smudge on the builder.
func _facing() -> Basis:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return Basis.IDENTITY.scaled(Vector3.ONE * ARROW_SCALE)
	return camera.global_basis.orthonormalized().scaled(Vector3.ONE * ARROW_SCALE)


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
