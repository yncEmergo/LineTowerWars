class_name AttackRangeOverlay
extends MeshInstance3D

## Every range a selection carries, drawn flat on the ground as ONE shape.
##
## A circle per tower, each its own transparent mesh, looked right until two
## overlapped: the fills blended over one another and the shared ground came
## out darker than either. One quad running Resources/Shaders/attack_range
## draws the UNION instead, so every pixel is painted at most once and ten
## towers piled together read exactly like one.
##
## TWO GROUPS, in two colours: how far a tower SHOOTS, and how far its ability
## REACHES. Aiming an attack asks the first question only; Show Ranges asks
## both. The union rule holds inside each group, so an aura shared by three
## towers is still one shape.
##
## Where the groups OVERLAP the smaller circle owns the ground, which the shader
## settles per pixel rather than this script settling it per unit - two towers
## can each be the smaller one over different halves of the same patch.
##
## Built in code and parented to the shared effects root, like the move order
## marker: it belongs to the order being aimed rather than to any one tower, it
## appears and disappears with that order, and a tower sold mid-aim cannot take
## it with it.
##
## The quad is sized to the circles it has to hold rather than to the map, so
## the fragment shader only ever runs over ground that might be covered.

## Must match MAX_CIRCLES in the shader. Counted PER GROUP, so a selection may
## draw this many attack ranges and this many ability ranges. Selecting more
## than this many towers simply leaves the extra ranges undrawn, which is
## reported rather than being allowed to look like a tower with no reach.
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


## The reach of every unit handed over that has one, and nothing else. What
## aiming an attack shows, where the only question is whether the order can be
## given at all.
##
## Recomputed wholesale rather than tracked per unit: a selection is small, this
## runs when an order is armed rather than every frame, and rebuilding is what
## keeps a sold or dead tower from leaving its range behind.
func show_attack_ranges(units: Array) -> void:
	_draw(_attack_circles(units), PackedVector3Array())


## Attack reach AND every ability range those units carry, the second group in
## its own colour. What Show Ranges puts on the ground.
func show_all_ranges(units: Array) -> void:
	_draw(_attack_circles(units), _ability_circles(units))


func hide_ranges() -> void:
	visible = false
	if _material == null:
		return
	_material.set_shader_parameter("attack_count", 0)
	_material.set_shader_parameter("ability_count", 0)


## Hands both groups to the shader and sizes the quad to hold them, or hides
## when neither group has anything in it.
func _draw(attack: PackedVector3Array, ability: PackedVector3Array) -> void:
	if _material == null:
		return
	if attack.is_empty() && ability.is_empty():
		hide_ranges()
		return

	_material.set_shader_parameter("attack_circles", attack)
	_material.set_shader_parameter("attack_count", attack.size())
	_material.set_shader_parameter("ability_circles", ability)
	_material.set_shader_parameter("ability_count", ability.size())
	_fit_quad(_bounds(attack, ability).grow(QUAD_MARGIN))
	visible = true


## One circle per unit that can attack, as the shader wants them: xy is the
## centre on the ground plane and z is the radius.
func _attack_circles(units: Array) -> PackedVector3Array:
	var circles: PackedVector3Array = PackedVector3Array()
	for unit in units:
		var typed: Unit = _valid_unit(unit)
		if typed == null || typed.stats == null || typed.stats.attack == null:
			continue
		# Asked of the UNIT, so a tower a Primal disc is reaching draws the
		# circle it really covers rather than the one its stats file records.
		_append_circle(circles, typed,
			typed.stats.attack.attack_range + typed.attack_range_bonus())
	return _capped(circles, "attack")


## One circle per ability that answers with a radius, which is the handful that
## reach a ring of ground around their tower - an aura, a heal, a spread. Asked
## of the ability rather than listed here, so the number stays on the resource
## that uses it and cannot drift.
func _ability_circles(units: Array) -> PackedVector3Array:
	var circles: PackedVector3Array = PackedVector3Array()
	for unit in units:
		var typed: Unit = _valid_unit(unit)
		if typed == null || typed.stats == null:
			continue
		for ability: UnitAbility in typed.stats.abilities:
			if ability == null:
				continue
			_append_circle(circles, typed, ability.display_radius(typed))
	return _capped(circles, "ability")


func _valid_unit(unit: Variant) -> Unit:
	var typed: Unit = unit as Unit
	return null if typed == null || !is_instance_valid(typed) else typed


## Adds one circle unless there is no radius to draw.
func _append_circle(circles: PackedVector3Array, unit: Unit, radius: float) -> void:
	if radius <= 0.0:
		return
	var origin: Vector3 = unit.global_position
	circles.append(Vector3(origin.x, origin.z, radius))


## Cuts a group down to what the shader can hold, and says so when it had to.
## Trimmed after the fact rather than refused during: the cap is generous
## enough that it is never reached in play, and a loop that has to watch for it
## costs every caller a check for the sake of a case nobody hits.
func _capped(circles: PackedVector3Array, group: String) -> PackedVector3Array:
	if circles.size() <= MAX_CIRCLES:
		return circles
	Log.info("More ranges to draw than the overlay can hold", {
		"limit": MAX_CIRCLES,
		"group": group,
		"wanted": circles.size(),
	})
	return circles.slice(0, MAX_CIRCLES)


## The ground the two groups cover together, which is all the quad has to be.
func _bounds(attack: PackedVector3Array, ability: PackedVector3Array) -> Rect2:
	var area: Rect2 = Rect2()
	var found: bool = false
	for group: PackedVector3Array in [attack, ability]:
		for circle: Vector3 in group:
			var reach: Rect2 = Rect2(
				circle.x - circle.z, circle.y - circle.z, circle.z * 2.0, circle.z * 2.0
			)
			area = reach if !found else area.merge(reach)
			found = true
	return area


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
