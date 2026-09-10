class_name ShaderWarmup
extends Node3D

## Draws everything a match can show, once, before the match starts - so no
## shader is ever compiled in the middle of one.
##
## ## Why this exists
##
## **The Compatibility renderer compiles a shader the first time something USING
## it is drawn, on the game thread, and nothing can ask it to do so earlier.**
## Godot's ubershaders and pipeline precompilation belong to the Vulkan and
## Direct3D renderers; for this one the engine's own documentation says to use
## "the legacy approach of preloading materials, shaders, and particles by
## displaying them for at least one frame in the view frustum when the level is
## loading". This is that.
##
## Playtest 7 measured what skipping it costs: a freeze of one to two seconds on
## a player's own machine the first time a kind of tower appeared on their screen
## - their first tower, their first Archer, their first Lesser Crusher, their
## first Runic Monolith - each followed by the catch-up servo fast-forwarding
## through the backlog it left. Upgrading seven towers at once took one. A kind
## the player had already drawn cost nothing, the same upgrade seen in somebody
## else's lane cost nothing, and the one player on an AMD card never froze once,
## which is what put it on the driver rather than on the simulation. See
## Findings/2026-09-10-playtest-7.md.
##
## `ContentWarmer` does not cover this and was never meant to: it LOADS resources
## so no turn pays for a disk read. A material in memory is not a compiled one.
##
## ## What it draws
##
## - every scene `ContentWarmer` holds: every tower, creep, projectile and effect a
##   match can spawn, and each effect's see-through copy, which `VisualEffect3D`
##   makes on the way in and which is a shader of its own
## - every drawable already standing in the match, hidden or not - the build grid
##   is the one that matters, drawn the moment somebody places a first tower
## - what only exists once somebody acts: the build ghost, the order markers, the
##   bars, the range overlay, the blueprint plan and the bounty number, each built
##   by its own class exactly as it is in play
## - every selectable unit again inside the unit panel's portrait, which is a world
##   of its own with lights of its own and so compiles its own variants - on the
##   frame a player selects a kind for the first time
##
## Everything drawn from a scene is a PROXY: a bare node holding the same mesh and
## the same materials with no script on it, so nothing drawn here can register a
## unit, claim a cell or run a tick. The rule `VisualUtil` states for the portrait.
##
## ## What it costs, and who waits
##
## On a machine that has compiled all of it before - Godot keeps what it compiles
## on disk, in `user://shader_cache` - a fraction of a second. On one that has not,
## whatever the compiles cost, paid here once instead of across the opening
## minutes of the match. **Nobody else waits for it.** Under lockstep this machine
## only tells the relay it is ready once it is warm, and the relay already waits
## for the slowest loader before it starts the clock, so this spends the wait
## everybody is already sitting in; a machine slow enough to outlast the relay's
## patience starts behind and catches up, on its own. See
## `LockstepService._physics_process`.
##
## The world is held still for the duration, by name, so no tick passes while it
## runs - on a peer, where a tick without its turn would be a desync, and offline,
## where it would be a tick the player never saw. See `MatchSession.hold`.

## The name this holds the world under. See MatchSession.hold.
const HOLD_REASON: StringName = &"shader_warmup"

## How many scenes are drawn per step. Whatever is new in a step compiles on the
## frame it is drawn, so smaller steps keep each frame short - one frame compiling
## everything at once can run long enough for Windows to call the window
## unresponsive - and larger ones finish in fewer frames.
const SCENES_PER_STEP: int = 24

## How many frames each step stays up. One is the least a draw can happen in; the
## second is margin for anything that settles a frame late.
const FRAMES_PER_STEP: int = 2

## How long this may run before it lets the match start anyway, in seconds. A
## machine that cannot finish in time pays the rest mid-match, as every machine
## did before this existed - better than a match that never starts.
const TIMEOUT_SECONDS: float = 15.0

## How far in front of the camera everything is drawn. Well inside the sun's
## shadow distance, so the shadow pass compiles its variants too.
const DISTANCE: float = 8.0

## What the warm-up screen says, and what share of the bar the loading takes when
## the match was opened without the load screen having loaded anything.
const STATUS_TEXT: String = "Preparing the battlefield..."
const LOAD_SHARE: float = 0.3

## Whether this machine may start playing. True wherever nothing is warming,
## which is every process that never warms at all - a relay, a headless probe.
static var _done: bool = true
## Whether a warm-up has run to the end in this process. A compiled shader stays
## compiled for the life of the process, so the second match skips all of it.
static var _warmed: bool = false

var _steps: Array[Callable] = []
var _step: int = 0
var _frames_left: int = 0
var _loader: ContentWarmer = null
var _root: Node3D = null
var _backdrop: ColorRect = null
var _status: Label = null
var _bar: ProgressBar = null
var _portrait: UnitPortrait = null
var _portrait_warming: bool = false
## One mesh of every KIND of mesh met on the way, so the ghost material can be
## drawn on each shape a tower is built from.
var _shapes: Dictionary = {}
var _started_msec: int = 0
var _drawn: int = 0
var _finished: bool = false


## Starts warming for the match `parent` has just built, or does nothing when
## there is nothing to warm: a headless process has no renderer, and a process
## that has warmed once already has every shader it will need.
static func start(parent: Node) -> void:
	if parent == null || _warmed || DisplayServer.get_name() == "headless":
		return
	var warmup: ShaderWarmup = ShaderWarmup.new()
	warmup.name = "ShaderWarmup"
	parent.add_child(warmup)


## Whether this machine may start playing. See `_done`.
static func is_done() -> bool:
	return _done


func _ready() -> void:
	# It runs while the world it holds is paused, which is the whole point.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_done = false
	_started_msec = Time.get_ticks_msec()
	_hold(true)
	_build_screen()

	_root = Node3D.new()
	_root.name = "Proxies"
	add_child(_root)
	_portrait = _find_portrait()

	if ContentWarmer.is_warm():
		_plan()
		return
	# A match opened WITHOUT the load screen - single player, straight from the
	# menu - has loaded none of its content yet, and the warmer is what finds every
	# scene. So it runs here first, pumped a frame at a time exactly as the load
	# screen pumps it.
	var content: ContentConfig = References.content_config
	if content == null:
		_plan()
		return
	_loader = ContentWarmer.new()
	_loader.begin(PackedStringArray([
		content.unit_stats_folder, content.shared_config_folder,
	]))


func _process(_delta: float) -> void:
	if _finished:
		return

	if _loader != null:
		_loader.advance()
		if !_loader.is_finished() && !_timed_out():
			_show_progress(_loader.ratio() * LOAD_SHARE)
			return
		_loader = null
		_plan()

	if _frames_left > 0:
		_frames_left -= 1
		return

	_clear_proxies()
	if _step >= _steps.size() || _timed_out():
		_finish()
		return

	_place_in_view()
	var run: Callable = _steps[_step]
	_step += 1
	run.call()
	_frames_left = FRAMES_PER_STEP
	_show_progress(LOAD_SHARE + (1.0 - LOAD_SHARE) * float(_step) / float(_steps.size()))


## A warm-up freed before it finished - the player left, the match was torn down -
## must never leave the match gated or the world held.
func _exit_tree() -> void:
	if _finished:
		return
	_finished = true
	if _portrait_warming && is_instance_valid(_portrait):
		_portrait.end_warm()
	_release()


# --- the plan --------------------------------------------------------------

## Every step, in order. Scenes first and in slices, then the three that each
## fit in one frame.
func _plan() -> void:
	var scenes: Array[PackedScene] = ContentWarmer.held_scenes()
	var index: int = 0
	while index < scenes.size():
		var slice: Array[PackedScene] = scenes.slice(index, index + SCENES_PER_STEP)
		_steps.append(_draw_scenes.bind(slice))
		index += SCENES_PER_STEP
	_steps.append(_draw_standing)
	_steps.append(_draw_acted)
	if _portrait == null:
		return
	# Sliced like the scenes: every unit in one frame is a frame long enough to
	# notice, all of it spent instantiating rather than compiling.
	var units: Array[UnitStats] = _portrait_units()
	var at: int = 0
	while at < units.size():
		var batch: Array[UnitStats] = units.slice(at, at + SCENES_PER_STEP)
		_steps.append(_draw_portrait.bind(batch))
		at += SCENES_PER_STEP


## Proxies of everything in these scenes. Instantiated and never put in a tree,
## so no script in them ever runs its _ready - the same rule the icon renderer
## and the portrait keep.
func _draw_scenes(scenes: Array[PackedScene]) -> void:
	for scene: PackedScene in scenes:
		var instance: Node = scene.instantiate()
		if instance == null:
			continue
		_copy_drawables(instance, false)
		instance.free()


## Proxies of everything already standing in the match, shown or hidden. The
## build grid is the one worth the step: it is hidden until the first placement,
## which is the busiest moment of the whole opening.
func _draw_standing() -> void:
	var main: Node = get_parent()
	if main != null:
		_copy_standing(main)


func _copy_standing(node: Node) -> void:
	for child: Node in node.get_children():
		# Not this warm-up's own proxies, and not another world: a SubViewport's
		# contents are drawn under that viewport's lights, never these.
		if child == self || child is SubViewport:
			continue
		var geometry: GeometryInstance3D = child as GeometryInstance3D
		if geometry != null:
			_add_proxy(geometry, null)
		_copy_standing(child)


## What only exists once somebody acts, each built by its own class exactly as it
## is in play, since a copy of the flags here would be the one that drifts.
func _draw_acted() -> void:
	# The ghost a tower is placed as, on every shape a tower is made of.
	var ghost: StandardMaterial3D = UnitModel.make_preview_material()
	ghost.albedo_color = UnitModel.PREVIEW_VALID_COLOR
	for shape: Variant in _shapes.values():
		var preview: MeshInstance3D = MeshInstance3D.new()
		preview.mesh = shape as Mesh
		preview.material_override = ghost
		preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root.add_child(preview)
		_drawn += 1

	_root.add_child(MoveOrderMarker.new())
	_root.add_child(OrderWaypointMarker.new())
	_root.add_child(ReviveLight.new())
	_root.add_child(Bar3D.new())

	var target: AttackTargetMarker = AttackTargetMarker.new()
	_root.add_child(target)
	target.setup(1.0)

	var bounty: BountyPopup = BountyPopup.new()
	bounty.text = "+0"
	_root.add_child(bounty)

	var ranges: AttackRangeOverlay = AttackRangeOverlay.new()
	_root.add_child(ranges)
	ranges.visible = true

	var plan: BlueprintOverlay = References.blueprint_overlay
	if plan != null:
		_root.add_child(plan.warmup_proxy())
	_drawn += 8


## Every selectable unit in `units` drawn in the portrait's own world. The
## portrait copies meshes exactly as it does for a selection, and `end_warm` puts
## back whatever was selected.
##
## **Measured redundant on the build it was written against, and kept anyway.**
## Drawn after the match world had compiled everything, the portrait compiled
## nothing of its own - its two unshadowed suns need no variant the match's one
## shadowed sun does not. That is a fact about today's lighting rather than a rule:
## give the portrait a shadow or a fog and it would start compiling on the frame a
## player first selects each kind of unit, with nothing to say so. Re-measure with
## `Scripts/Dev/ShaderProbe.gd` after changing either world's lights.
func _draw_portrait(units: Array[UnitStats]) -> void:
	var sources: Array[Node3D] = []
	for stats: UnitStats in units:
		var building: BuildingStats = stats as BuildingStats
		var scene: PackedScene = building.model_scene() if building != null \
			else stats.scene()
		if scene == null:
			continue
		var instance: Node3D = scene.instantiate() as Node3D
		if instance != null:
			sources.append(instance)
	_portrait.warm(sources)
	_portrait_warming = true
	_drawn += sources.size()
	# The portrait holds copies, so the instances can go at once.
	for source: Node3D in sources:
		source.free()


## Every unit a player can select that has something to draw: a tower by its
## model, anything else by its prefab. A stats file naming no scene at all - a
## send building, which stands in its area rather than being spawned - is left
## out rather than asked, since asking one for its scene is an error.
func _portrait_units() -> Array[UnitStats]:
	var units: Array[UnitStats] = []
	for stats: UnitStats in ContentWarmer.held_unit_stats():
		var building: BuildingStats = stats as BuildingStats
		var path: String = building.model_scene_path if building != null \
			else stats.scene_path
		if !path.is_empty():
			units.append(stats)
	return units


# --- proxies ---------------------------------------------------------------

## A proxy of every drawable under `source`, and of the see-through copy a fading
## effect draws each one with. `dimmed` says an effect above has claimed them.
func _copy_drawables(source: Node, dimmed: bool) -> void:
	var dims: bool = dimmed || source is VisualEffect3D
	var geometry: GeometryInstance3D = source as GeometryInstance3D
	if geometry != null:
		_add_proxy(geometry, null)
		if dims:
			var faded: StandardMaterial3D = VisualEffect3D.dimmable_copy(geometry)
			if faded != null:
				_add_proxy(geometry, faded)
	for child: Node in source.get_children():
		_copy_drawables(child, dims)


## One proxy of one drawable, drawing with `override` instead when given one.
func _add_proxy(source: GeometryInstance3D, override: Material) -> void:
	var proxy: GeometryInstance3D = _proxy_of(source)
	if proxy == null:
		return
	if override != null:
		proxy.material_override = override
	_root.add_child(proxy)
	# Particles are started only once they are IN the tree: asked to emit before,
	# they reach for a global transform they do not have yet, and say so.
	var cpu: CPUParticles3D = proxy as CPUParticles3D
	if cpu != null:
		cpu.emitting = true
	var gpu: GPUParticles3D = proxy as GPUParticles3D
	if gpu != null:
		gpu.emitting = true
	_drawn += 1


func _proxy_of(source: GeometryInstance3D) -> GeometryInstance3D:
	var mesh_source: MeshInstance3D = source as MeshInstance3D
	if mesh_source != null:
		if mesh_source.mesh == null:
			return null
		var shape: String = mesh_source.mesh.get_class()
		if !_shapes.has(shape):
			_shapes[shape] = mesh_source.mesh
		var copy: MeshInstance3D = MeshInstance3D.new()
		copy.mesh = mesh_source.mesh
		for surface: int in range(mesh_source.get_surface_override_material_count()):
			copy.set_surface_override_material(
				surface, mesh_source.get_surface_override_material(surface))
		copy.material_override = mesh_source.material_override
		copy.material_overlay = mesh_source.material_overlay
		copy.cast_shadow = mesh_source.cast_shadow
		return copy

	var many_source: MultiMeshInstance3D = source as MultiMeshInstance3D
	if many_source != null:
		if many_source.multimesh == null || many_source.multimesh.mesh == null:
			return null
		# A plan's MultiMesh may hold no instances yet, and a MultiMesh with none
		# draws nothing at all - so the proxy gets its own, with one.
		var multi: MultiMesh = MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = many_source.multimesh.mesh
		multi.instance_count = 1
		multi.set_instance_transform(0, Transform3D.IDENTITY)
		var many: MultiMeshInstance3D = MultiMeshInstance3D.new()
		many.multimesh = multi
		many.material_override = many_source.material_override
		many.material_overlay = many_source.material_overlay
		many.cast_shadow = many_source.cast_shadow
		return many

	# Anything else that draws - a label, a sprite, a particle system - copied
	# whole but bare: `duplicate(0)` leaves the script, the signals and the groups
	# behind. Its children are proxied on their own, so the copy keeps none.
	var other: GeometryInstance3D = source.duplicate(0) as GeometryInstance3D
	if other == null:
		return null
	for child: Node in other.get_children():
		other.remove_child(child)
		child.free()
	other.visible = true
	return other


func _clear_proxies() -> void:
	if _root != null:
		for child: Node in _root.get_children():
			child.queue_free()
	if _portrait_warming:
		_portrait_warming = false
		if is_instance_valid(_portrait):
			_portrait.end_warm()


## Everything drawn at one point straight ahead of the camera, where nothing can
## be culled. The screen in front of it means the player sees none of it.
func _place_in_view() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null || _root == null:
		return
	var ahead: Vector3 = -camera.global_transform.basis.z
	_root.global_position = camera.global_position + ahead * DISTANCE


# --- the end ---------------------------------------------------------------

func _finish() -> void:
	_finished = true
	_clear_proxies()
	var complete: bool = _step >= _steps.size()
	# A warm-up cut short tries again next match: whatever it did not reach has
	# still not been compiled.
	_warmed = complete
	var report: Dictionary = {
		"drawn": _drawn,
		"steps": _step,
		"of": _steps.size(),
		"ms": Time.get_ticks_msec() - _started_msec,
	}
	if complete:
		Log.info("Shaders warmed", report)
	else:
		Log.warn("Shader warm-up ran out of time, starting anyway", report)
	report["complete"] = complete
	SessionLog.note("match.shaders_warmed", report)
	_release()
	queue_free()


func _release() -> void:
	_hold(false)
	_done = true


func _hold(held: bool) -> void:
	var session: MatchSession = References.match_session
	if session != null && is_instance_valid(session):
		session.hold(HOLD_REASON, held)


func _timed_out() -> bool:
	return float(Time.get_ticks_msec() - _started_msec) / 1000.0 > TIMEOUT_SECONDS


func _find_portrait() -> UnitPortrait:
	var panel: UnitPanel = References.unit_panel
	return null if panel == null else panel.portrait()


# --- the screen ------------------------------------------------------------

## A plain black screen over everything while it runs, so the player sees neither
## the proxies nor the world standing still. Transient and never interactive,
## which is why it is built here rather than being a scene of its own.
func _build_screen() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 100
	add_child(layer)

	_backdrop = ColorRect.new()
	_backdrop.color = Color.BLACK
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_backdrop)

	var column: VBoxContainer = VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.custom_minimum_size = Vector2(360.0, 0.0)
	column.position -= column.custom_minimum_size * 0.5
	_backdrop.add_child(column)

	_status = Label.new()
	_status.text = STATUS_TEXT
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_status)

	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(360.0, 8.0)
	column.add_child(_bar)


func _show_progress(ratio: float) -> void:
	if _bar != null:
		_bar.value = clampf(ratio, 0.0, 1.0) * 100.0
