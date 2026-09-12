class_name BlueprintOverlay
extends Node3D

## Draws a saved plan on the ground: one blue square on every cell the plan
## puts a tower on and nothing stands on yet.
##
## **Local only, and it changes nothing.** It reads a file this machine wrote,
## it draws over the local player's own zone, and no other player and no server
## is ever told which plan is up - the same line the build grid toggle, the
## selection and the range overlay sit on. See multiplayer.md.
##
## ONE PLAN AT A TIME, and it stays up until the player switches it off. It is
## a thing to build against over the next minute rather than a thing to glance
## at, so it deliberately does not go away on its own the way Show Ranges does,
## and it is not tied to the builder still being selected.
##
## A square DISAPPEARS the moment anything is built on its cell, so what is
## still blue is exactly what is still to place.
##
## **EVERY SQUARE IS BUILT ONCE, WHEN THE PLAN IS SHOWN, AND AFTER THAT ONLY
## HIDDEN AND UNHIDDEN.** That is the whole performance story of this file, and
## it is worth stating plainly because the obvious version is wrong: rebuilding
## the drawn set on each change means reallocating the MultiMesh and working
## out every transform again, and a real plan is a hundred and fifty towers -
## so laying one tower stuttered the frame it landed on. Nothing about a square
## moves while a plan is up, so nothing about it should be worked out twice.
##
## Hiding one is a zero SCALE rather than a removal, because a MultiMesh has no
## per-instance visibility and the alternative - shrinking the buffer - is the
## reallocation this exists to avoid. So `instance_count` is the size of the
## PLAN and not the number of squares on screen, which is the one surprise in
## here worth knowing before reading it.
##
## One MultiMesh rather than a node per square, for the same reason it is one
## allocation: a plan is a hundred-odd quads that never move independently and
## never need a script, and one mesh with many instances is a single draw call
## where a hundred nodes are a hundred of them plus a hundred nodes of tree for
## the engine to walk every frame.

## Height above the ground the squares sit at. Above BuildGrid's own offset, so
## a plan drawn while the grid is up reads on top of it rather than fighting it
## for the same depth - the grid is the ruler, the plan is the answer.
const GROUND_OFFSET: float = 0.03

## Slack around the plan's own extent for the drawn bounds below. A cell either
## way, which is more than the half cell a square reaches past its own centre.
const BOUNDS_MARGIN: float = 1.0

## Fallback colour for a build with no PresentationConfig wired, so the overlay
## still draws something rather than a hundred invisible squares.
const FALLBACK_COLOR: Color = Color(0.28, 0.55, 1.0, 0.42)
## Fallback beat, same reason.
const FALLBACK_REFRESH_SECONDS: float = 0.25

## Footprint used for an entry naming a building type this build does not
## contain, in PLAYER cells. Every building is one cell today, so this is also
## what every entry gets when the registry is not up yet.
const FALLBACK_FOOTPRINT: Vector2i = Vector2i.ONE

## Which slot is on screen, or 0 for none. Slots count from 1, see
## BlueprintLibrary.
var _slot: int = 0
## The plan being drawn. Held rather than looked up fresh each beat so a slot
## SAVED OVER while it is on screen is noticed by identity - the library drops
## its cache on a write, so the next read hands back a different object.
var _plan: TowerLayout = null
var _mesh: MultiMeshInstance3D = null
var _since_refresh: float = 0.0

## Where each entry's square sits and how big it is, one per plan entry, worked
## out once when the plan is shown. The instance index IS the entry index, so
## hiding one is a single write at a known place.
var _squares: Array[Transform3D] = []
## The internal footprint of each entry, cached beside its transform so a beat
## never has to ask the unit registry anything.
var _footprints: Array[Vector2i] = []
## Whether each entry is currently hidden because something is built on it. A
## byte per entry rather than a set, so a beat compares rather than allocates.
var _covered: PackedByteArray = PackedByteArray()

var _presentation: PresentationConfig:
	get:
		return References.presentation_config


func _ready() -> void:
	visible = false
	set_process(false)


## Puts a slot's plan on the ground, replacing whatever was up.
##
## Silent about an empty slot beyond a log line: the card already refuses to
## offer a square with nothing behind it, so reaching here with one is a
## mistake in the card rather than something to tell the player about.
func show_slot(slot: int) -> void:
	var plan: TowerLayout = BlueprintLibrary.layout(slot)
	if plan == null:
		Log.warn("There is no blueprint in that slot to show", {"slot": slot})
		return

	_show(slot, plan)
	Log.info("Blueprint shown", {"slot": slot, "towers": plan.entry_count()})


## The same drawing, for a plan that is not in one of the player's slots.
##
## The TUTORIAL is the caller, and it needs this rather than a slot for a reason
## worth stating: a slot is the PLAYER's, and a player who has saved their own
## maze into slot one would be shown that maze by a lesson meaning to show them
## the one it is teaching. A lesson names its own file instead.
##
## Slot 0 while it is up, so the builder's own card draws none of its squares as
## lit - which is right: nothing the player chose is on screen.
func show_layout(plan: TowerLayout) -> void:
	if plan == null || plan.entry_count() <= 0:
		return
	_show(0, plan)
	Log.info("Blueprint shown from a file", {"towers": plan.entry_count()})


## Puts a plan on the ground, whichever road it arrived by.
func _show(slot: int, plan: TowerLayout) -> void:
	_slot = slot
	_plan = plan
	_squares.clear()
	visible = true
	set_process(true)
	# Laid out and hidden in the same call, so the plan is on the ground -
	# already minus whatever is standing - in the frame the button was pressed.
	_refresh()


## Takes the plan away. Safe to call with nothing up.
func hide_blueprint() -> void:
	# **The PLAN rather than the slot decides whether anything is up**, because a
	# plan shown from a file has no slot - see show_layout. Testing the slot left
	# the tutorial unable to take its own blueprint off the ground.
	if _plan == null:
		return
	Log.info("Blueprint hidden", {"slot": _slot})
	_slot = 0
	_plan = null
	_squares.clear()
	_footprints.clear()
	_covered = PackedByteArray()
	visible = false
	set_process(false)
	if _mesh != null && is_instance_valid(_mesh):
		_mesh.multimesh.instance_count = 0


## Switches a slot on, or off again when it is the one already up.
##
## The whole toggle in one place, so the card square and any later way of
## reaching this cannot answer the press differently.
func toggle_slot(slot: int) -> void:
	if _slot == slot:
		hide_blueprint()
		return
	show_slot(slot)


func is_showing() -> bool:
	return _plan != null


## Which slot is up, or 0 for none. What a card square reads to light itself.
func shown_slot() -> int:
	return _slot


func _process(delta: float) -> void:
	_since_refresh += delta
	if _since_refresh < _refresh_interval():
		return
	_since_refresh = 0.0
	_refresh()


## Brings the squares into line with what is standing.
##
## On a beat rather than every frame because nothing here can change faster
## than a tower goes up, and on a beat rather than on a signal because there is
## no signal: a tower is placed, sold, cancelled and destroyed by four
## different paths, and a plan that missed one of them would keep drawing under
## a tower that is already there.
##
## The WHOLE cost of a beat where nothing changed is the walk over the area's
## buildings plus one byte compared per entry. A beat where a tower landed adds
## exactly one instance write - see the note at the top of the file.
func _refresh() -> void:
	var area: PlayerArea = _local_area()
	if _plan == null || area == null:
		return

	# A SLOT saved over while it is on screen is a different plan behind the same
	# number, so its squares have to be laid out again from scratch.
	#
	# **Only a slot**, and the guard is load-bearing: a plan shown from a FILE has
	# no slot (see show_layout), so asking the library for slot 0 hands back null
	# and the plan was wiped on the first beat after it appeared - the tutorial's
	# blueprint drew for a quarter of a second and vanished, silently, because
	# hide_blueprint then found nothing left to report.
	if _slot != 0:
		var current: TowerLayout = BlueprintLibrary.layout(_slot)
		if current != _plan:
			_plan = current
			_squares.clear()
			if _plan == null:
				hide_blueprint()
				return

	if _squares.is_empty():
		_lay_out(area)

	var taken: Dictionary = _occupied_cells(area)
	var mesh: MultiMeshInstance3D = _ensure_mesh()
	for entry in range(_squares.size()):
		var hidden: int = (
			1 if _covers_any(taken, _plan.cells[entry], _footprints[entry]) else 0
		)
		if hidden == _covered[entry]:
			continue
		_covered[entry] = hidden
		mesh.multimesh.set_instance_transform(
			entry, _hidden(_squares[entry]) if hidden == 1 else _squares[entry]
		)


## Works every square of the plan out and writes them all, once.
##
## The only place `instance_count` is ever set to anything but zero, which is
## what makes the rest of this file cheap: allocating a MultiMesh reallocates
## its buffer and clears every transform in it, so doing that per change was
## paying for the whole plan to say that one tower had gone up.
func _lay_out(area: PlayerArea) -> void:
	var count: int = _plan.entry_count()
	_footprints.resize(count)
	_squares.resize(count)
	# Zeroed by resize, which is exactly "nothing hidden yet" - so the pass in
	# _refresh writes every square that IS covered, and no others.
	_covered = PackedByteArray()
	_covered.resize(count)

	var mesh: MultiMeshInstance3D = _ensure_mesh()
	mesh.multimesh.instance_count = count
	for entry in range(count):
		_footprints[entry] = _footprint_of(_plan.unit_type_ids[entry], area)
		_squares[entry] = _square_transform(_plan, entry, area)
		mesh.multimesh.set_instance_transform(entry, _squares[entry])

	# Stated rather than derived, so Godot never walks the instances to work
	# out how big the thing is - which it would otherwise redo every time one
	# of them was hidden. Nothing moves once laid out, so it cannot go stale.
	mesh.multimesh.custom_aabb = _drawn_bounds()


## One entry's square, taken out of sight without taking it out of the buffer.
##
## A zero scale collapses the quad to a point and draws nothing. The material
## is unshaded, so the degenerate basis reaches no lighting maths - and the
## origin is kept, so the bounds above stay true whichever squares are hidden.
static func _hidden(square: Transform3D) -> Transform3D:
	return Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), square.origin)


## A box around every square the plan holds, in the mesh's own space.
func _drawn_bounds() -> AABB:
	if _squares.is_empty():
		return AABB()

	var bounds: AABB = AABB(_squares[0].origin, Vector3.ZERO)
	for square: Transform3D in _squares:
		bounds = bounds.expand(square.origin)
	return bounds.grow(BOUNDS_MARGIN)


## Every internal cell any building in the area sits on, as a set.
##
## Occupancy is read off the area's BUILDING CHILDREN rather than off its
## movement grid, and the difference matters: a technology disc does not block
## movement at all, so a grid reading would go on drawing a blue square under
## one forever. It is the same walk TowerLayout.capture does, and for the same
## reason - what is placed is what is a child of the area.
func _occupied_cells(area: PlayerArea) -> Dictionary:
	var taken: Dictionary = {}
	for child: Node in area.get_children():
		var building: Building = child as Building
		if building == null || building.cell.x < 0 || building.cell.y < 0:
			continue
		# The building's own answer rather than one worked out from its stats,
		# so a plan can never disagree with the grid about how much room a
		# tower takes.
		var footprint: Vector2i = building.footprint()
		for dz in range(footprint.y):
			for dx in range(footprint.x):
				taken[building.cell + Vector2i(dx, dz)] = true
	return taken


static func _covers_any(taken: Dictionary, cell: Vector2i, footprint: Vector2i) -> bool:
	for dz in range(footprint.y):
		for dx in range(footprint.x):
			if taken.has(cell + Vector2i(dx, dz)):
				return true
	return false


## The internal footprint of a plan entry, by the type it names.
##
## Read off the registry rather than assumed, so a plan stays honest the day
## something bigger than one cell is buildable. A type this build does not
## contain falls back to one cell instead of being dropped: the plan still
## knows a tower belongs there, and drawing the wrong SIZE of square is a far
## better answer than silently drawing none.
func _footprint_of(type_id: int, area: PlayerArea) -> Vector2i:
	var session: MatchSession = References.match_session
	var stats: BuildingStats = null
	if session != null:
		stats = session.unit_types().stats_for(type_id) as BuildingStats
	if stats == null:
		return area.cells_to_internal(FALLBACK_FOOTPRINT)
	return area.cells_to_internal(stats.footprint_cells)


## Where one entry's square goes and how big it is, in the mesh's own space.
##
## Split out of the layout pass because it is the whole of what this node
## COMPUTES - everything else here is bookkeeping - and because it is the only
## part of it anything can ever check. **A MultiMesh cannot be read back under
## `--headless`:** the dummy renderer accepts every instance transform and
## stores none, so `get_instance_transform` hands back identity however
## carefully the transform was worked out. Anything wanting to prove a square
## lands on the cell it names has to ask for the transform, never for the
## instance.
func _square_transform(plan: TowerLayout, entry: int, area: PlayerArea) -> Transform3D:
	var footprint: Vector2i = _footprint_of(plan.unit_type_ids[entry], area)
	var center: Vector3 = area.footprint_world_center(plan.cells[entry], footprint)
	center.y += GROUND_OFFSET

	var size: float = area.internal_cell_size()
	var basis: Basis = Basis.IDENTITY.scaled(Vector3(
		float(footprint.x) * size, 1.0, float(footprint.y) * size
	))
	return Transform3D(basis, _ensure_mesh().to_local(center))


## Builds the mesh and its material on first use, rather than in _ready: a
## player who never opens a plan never pays for either.
func _ensure_mesh() -> MultiMeshInstance3D:
	if _mesh != null && is_instance_valid(_mesh):
		return _mesh

	var plane: PlaneMesh = PlaneMesh.new()
	# A unit square, sized per instance. See _square_transform.
	plane.size = Vector2.ONE
	plane.material = _make_material()

	var multi: MultiMesh = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = plane

	_mesh = MultiMeshInstance3D.new()
	_mesh.name = "Squares"
	_mesh.multimesh = multi
	# An overlay must never darken the ground it is drawn on.
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	return _mesh


## A stand-in for the plan, built from the very mesh and material a plan draws
## with and attached to nothing, for `ShaderWarmup`. The real one holds no
## instances until a plan is shown, and a MultiMesh with none draws nothing - so
## this has one of its own.
func warmup_proxy() -> MultiMeshInstance3D:
	var multi: MultiMesh = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = _ensure_mesh().multimesh.mesh
	multi.instance_count = 1
	multi.set_instance_transform(0, Transform3D.IDENTITY)
	var proxy: MultiMeshInstance3D = MultiMeshInstance3D.new()
	proxy.multimesh = multi
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return proxy


## Flat, unshaded and transparent: a plan is a mark ON the ground rather than a
## thing standing on it, so it takes no light and casts nothing.
##
## depth_draw_disabled because a hundred coplanar transparent quads that write
## depth flicker against each other wherever two of them touch.
func _make_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = _color()
	return material


## The local player's own zone, which is the only one a plan is ever drawn
## over: it is a building aid for the person holding the mouse, and an
## opponent's lane is not theirs to build in.
func _local_area() -> PlayerArea:
	var manager: PlayerManager = References.player_manager
	if manager == null:
		return null
	return manager.area_for(manager.local_player_id())


func _color() -> Color:
	var config: PresentationConfig = _presentation
	if config == null:
		return FALLBACK_COLOR
	return config.blueprint_color


func _refresh_interval() -> float:
	var config: PresentationConfig = _presentation
	if config == null:
		return FALLBACK_REFRESH_SECONDS
	return maxf(0.0, config.blueprint_refresh_seconds)
