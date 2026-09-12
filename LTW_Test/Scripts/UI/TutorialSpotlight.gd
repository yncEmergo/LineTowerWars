class_name TutorialSpotlight
extends Control

## Dims the world around the one thing a lesson is talking about.
##
## A tutorial can say "watch that creep" and a player has a lane full of them.
## This answers it the way a finger does: everything goes dark except a circle
## around the thing, and the circle FOLLOWS it - the creep the lesson is about
## is walking while the lesson is being read.
##
## **The projection is done here and the dimming is done in the shader**, and
## the split is the point. Which creep is the leading one, where a tower is, and
## how big a lane looks from this camera are all questions about the WORLD, and
## the code that answers them is not a shader. What the shader gets is a point
## and a radius on the screen.
##
## It is PRESENTATION from end to end: nothing is tinted, nothing is re-rendered
## and nothing in the world is touched. A lesson that dims a lane changes not one
## thing about what is in it.

## How much of the screen the lit circle covers for each kind of subject, as a
## share of screen height. A LANE is most of the screen; one creep is a dot.
const LANE_RADIUS: float = 0.34
const BUILDING_RADIUS: float = 0.09
const CREEP_RADIUS: float = 0.07
## How quickly the circle chases what it is lighting, per second. A creep walks,
## and a circle snapped to it every frame reads as a jitter rather than as a
## follow.
const FOLLOW_SPEED: float = 12.0

@export_group("References")
## The full-screen rectangle the shader draws on.
@export var _dim: ColorRect

var _subject: TutorialStep.Spotlight = TutorialStep.Spotlight.NONE
var _radius: float = LANE_RADIUS
## Where the circle is now, in screen fractions, chased toward where it should
## be. Kept separate so the follow is smooth across a frame the subject moved a
## long way in - a creep leaking and the next one spawning at the top.
var _at: Vector2 = Vector2(0.5, 0.5)
var _has_position: bool = false

var _director: TutorialDirector:
	get:
		return References.tutorial_director


func _ready() -> void:
	# The world is held still for most lessons and the circle still has to be
	# drawn - and on a lesson that is NOT held, the thing it is lighting moves.
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()

	var director: TutorialDirector = _director
	if director == null:
		return
	director.lesson_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	_subject = TutorialStep.Spotlight.NONE
	var director: TutorialDirector = _director
	if director != null && director.is_running():
		var step: TutorialStep = director.current_step()
		if step != null:
			_subject = step.spotlight

	_radius = _radius_for(_subject)
	# Re-aimed rather than eased on the first frame of a lesson, so the circle
	# opens where it belongs instead of sliding across the screen from wherever
	# the last lesson left it.
	_has_position = false
	visible = _subject != TutorialStep.Spotlight.NONE


func _radius_for(subject: TutorialStep.Spotlight) -> float:
	match subject:
		TutorialStep.Spotlight.MY_NEWEST_TOWER:
			return BUILDING_RADIUS
		TutorialStep.Spotlight.LEADING_CREEP:
			return CREEP_RADIUS
		_:
			return LANE_RADIUS


## Re-projected every frame, because everything it can be pointed at moves: a
## creep walks, and the camera pans under all of them.
func _process(delta: float) -> void:
	if _subject == TutorialStep.Spotlight.NONE || _dim == null:
		return

	var world: Vector3 = _subject_point()
	if world == Vector3.INF:
		# Nothing to light: the creep died, the tower was sold, the lane is
		# empty. The dim comes off rather than sitting over a circle of nothing.
		_dim.hide()
		return
	_dim.show()

	var wanted: Vector2 = _to_screen(world)
	if !_has_position:
		_at = wanted
		_has_position = true
	else:
		_at = _at.lerp(wanted, clampf(delta * FOLLOW_SPEED, 0.0, 1.0))
	_push_uniforms()


## The shader's own inputs. Set rather than bound, because two of the three
## change every frame and the third changes when the window is resized.
func _push_uniforms() -> void:
	var material: ShaderMaterial = _dim.material as ShaderMaterial
	if material == null:
		Log.err("TutorialSpotlight has no shader material, nothing can be dimmed")
		_dim.hide()
		return

	var screen: Vector2 = get_viewport_rect().size
	material.set_shader_parameter("focus", _at)
	material.set_shader_parameter("radius", _radius)
	material.set_shader_parameter("aspect", screen.x / maxf(1.0, screen.y))


## Where on screen a world point is, in 0..1, for the shader.
##
## Camera projection maths, which is also the only kind of "where is this on
## screen" this project has - there is no physics and no ray to ask. See
## CLAUDE.md and SelectionController.unit_at, which picks a unit the same way.
func _to_screen(world: Vector3) -> Vector2:
	var camera: RTSCamera = References.rts_camera
	var screen: Vector2 = get_viewport_rect().size
	if camera == null || screen.x <= 0.0 || screen.y <= 0.0:
		return Vector2(0.5, 0.5)
	var point: Vector2 = camera.unproject_position(world)
	return Vector2(point.x / screen.x, point.y / screen.y)


## The world point this lesson is lighting, or INF when there is nothing to
## light.
##
## Vector3.INF as the empty answer rather than a second bool, because every
## caller of this asks the same question about the result and there is no world
## point that could be mistaken for it.
func _subject_point() -> Vector3:
	var manager: PlayerManager = References.player_manager
	if manager == null:
		return Vector3.INF

	var mine: int = manager.local_player_id()
	match _subject:
		TutorialStep.Spotlight.MY_LANE:
			return _lane_center(manager.area_for(mine))
		TutorialStep.Spotlight.TARGET_LANE:
			return _lane_center(manager.area_for(manager.sends_into(mine)))
		TutorialStep.Spotlight.MY_NEWEST_TOWER:
			return _newest_tower(manager.area_for(mine))
		TutorialStep.Spotlight.LEADING_CREEP:
			return _leading_creep(manager.area_for(mine))
		_:
			return Vector3.INF


func _lane_center(area: PlayerArea) -> Vector3:
	return Vector3.INF if area == null else area.build_zone_center()


## The last tower the player put up, which is the last Building child of their
## area - children are appended in the order they are added, so tree order IS
## build order.
func _newest_tower(area: PlayerArea) -> Vector3:
	if area == null:
		return Vector3.INF
	var children: Array = area.get_children()
	for index in range(children.size() - 1, -1, -1):
		var building: Building = children[index] as Building
		if building != null && building.cell.x >= 0:
			return building.global_position
	return Vector3.INF


## Whichever creep in the lane has walked furthest down it, which is the one
## worth watching and the one about to leak.
##
## By local Z rather than by how much route is left, because the lane runs top
## to bottom and a flyer has no route at all - and because this is a circle on a
## screen rather than a targeting decision.
func _leading_creep(area: PlayerArea) -> Vector3:
	if area == null:
		return Vector3.INF

	var best: Creep = null
	var deepest: float = -INF
	for creep: Creep in area.creeps():
		if creep == null || !is_instance_valid(creep) || !creep.is_alive():
			continue
		var depth: float = area.to_local(creep.global_position).z
		if depth > deepest:
			deepest = depth
			best = creep
	return Vector3.INF if best == null else best.global_position
