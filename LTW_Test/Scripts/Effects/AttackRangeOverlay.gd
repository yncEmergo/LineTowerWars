class_name AttackRangeOverlay
extends MeshInstance3D

## The reach of every selected unit, drawn flat on the ground as ONE shape.
##
## A circle per tower, each its own transparent mesh, looked right until two
## overlapped: the fills blended over one another and the shared ground came
## out darker than either. One quad running Resources/Shaders/attack_range
## draws the UNION instead, so every pixel is painted at most once and ten
## towers piled together read exactly like one.
##
## Built in code and parented to the shared effects root, like the move order
## marker: it belongs to the order being aimed rather than to any one tower, it
## appears and disappears with that order, and a tower sold mid-aim cannot take
## it with it.
##
## The quad is sized to the circles it has to hold rather than to the map, so
## the fragment shader only ever runs over ground that might be covered.

## Must match MAX_CIRCLES in the shader. Selecting more than this many towers
## simply leaves the extra ranges undrawn, which is reported rather than being
## allowed to look like a tower with no reach.
const MAX_CIRCLES: int = 32

const SHADER_PATH: String = "res://Resources/Shaders/attack_range.gdshader"
## Height above the ground. Clear of the build grid overlay at 0.02, and below
## the move order marker at 0.05 so a move click still reads on top of it.
const GROUND_OFFSET: float = 0.03
## Slack around the outermost circle, so the ring is never clipped by the very
## edge of the quad it is drawn on.
const QUAD_MARGIN: float = 0.5

var _material: ShaderMaterial


func _ready() -> void:
	var shader: Shader = load(SHADER_PATH) as Shader
	if shader == null:
		Log.err("Attack range shader did not load, ranges will not draw", SHADER_PATH)
		return

	_material = ShaderMaterial.new()
	_material.shader = shader

	var quad: PlaneMesh = PlaneMesh.new()
	quad.material = _material
	mesh = quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


## Draws the reach of every unit handed over that actually has one, and hides
## itself when none of them do.
##
## Recomputed wholesale rather than tracked per unit: a selection is small, this
## runs when an order is armed rather than every frame, and rebuilding is what
## keeps a sold or dead tower from leaving its range behind.
func show_ranges(units: Array) -> void:
	if _material == null:
		return

	var centres: PackedVector3Array = PackedVector3Array()
	var bounds: Rect2 = Rect2()
	var found: bool = false

	for unit in units:
		var radius: float = _range_of(unit)
		if radius <= 0.0:
			continue
		if centres.size() >= MAX_CIRCLES:
			Log.info("More units selected than the range overlay can draw", {
				"limit": MAX_CIRCLES,
			})
			break

		var origin: Vector3 = unit.global_position
		centres.append(Vector3(origin.x, origin.z, radius))

		var reach: Rect2 = Rect2(
			origin.x - radius, origin.z - radius, radius * 2.0, radius * 2.0
		)
		bounds = reach if !found else bounds.merge(reach)
		found = true

	if !found:
		hide_ranges()
		return

	_material.set_shader_parameter("circles", centres)
	_material.set_shader_parameter("circle_count", centres.size())
	_fit_quad(bounds.grow(QUAD_MARGIN))
	visible = true


func hide_ranges() -> void:
	visible = false
	if _material != null:
		_material.set_shader_parameter("circle_count", 0)


## Reach of one unit, read off its stats rather than its attack component: the
## number is on the prefab either way, and a unit that cannot attack simply has
## no attack to ask.
func _range_of(unit: Variant) -> float:
	var typed: Unit = unit as Unit
	if typed == null || !is_instance_valid(typed):
		return 0.0
	if typed.stats == null || typed.stats.attack == null:
		return 0.0
	return typed.stats.attack.attack_range


## The quad only has to cover the circles, so it is sized to their bounding box
## on the ground plane. PlaneMesh already lies flat in xz, so nothing is rotated.
func _fit_quad(area: Rect2) -> void:
	var quad: PlaneMesh = mesh as PlaneMesh
	if quad == null:
		return

	quad.size = area.size
	global_position = Vector3(
		area.position.x + area.size.x * 0.5,
		GROUND_OFFSET,
		area.position.y + area.size.y * 0.5
	)
