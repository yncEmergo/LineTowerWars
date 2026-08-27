@tool
class_name VisualEffect3D
extends Node3D

## Base for anything spawned purely to be LOOKED at: a projectile in flight, an
## impact flash, a shockwave ring, a spray of particles.
##
## It exists for one shared setting - OPACITY - because every effect in the game
## wants to be dialled back or up while it is being tuned, and doing that by
## hand-editing the alpha of each material in each scene means the same edit
## four times and a different answer every time.
##
## A base class rather than a child component, unlike the animation components
## next door: opacity is not an optional capability that some effects have, it
## is a property every visual effect has. What crosses the split gets a
## component; what every one of them IS goes in the base. See CLAUDE.md.
##
## HOW IT APPLIES. Each effect DUPLICATES the materials it draws with, once, on
## the way in, and sets the alpha on its own copies. That is heavier than it
## looks like it needs to be, and the two lighter ways are both closed:
##   - GeometryInstance3D.transparency is a node property that would have done
##     this in one line, and it does NOTHING under gl_compatibility, which is
##     what this project renders with. Same family of limitation as per
##     instance shader uniforms - see tower_energy.gdshader
##   - editing the materials in place would reach every other effect on screen
##     using them, since a scene's sub-resources are shared between its
##     instances
##
## Duplicating at runtime costs nothing that matters: an effect lives under a
## second and there are never many at once.
##
## @tool, so the value previews in the editor rather than only in play - an
## effect that lasts a third of a second cannot be tuned any other way. The
## overrides are stripped before a save and put back after it, so nothing this
## does can ever be written into a scene file.
##
## Subclasses that animate their own fade call set_fade() rather than touching
## alpha, so the two multiply instead of fighting.

## How visible this effect is at full strength, before any fade it animates on
## top. 1 is exactly as its materials were authored.
@export_range(0.0, 1.0, 0.01) var opacity: float = 1.0:
	set(value):
		opacity = clampf(value, 0.0, 1.0)
		_apply_alpha()

## Every drawable under this effect, itself included, and this effect's own
## copy of the material each one draws with. Collected once, because an
## effect's own children never change after it is built.
var _surfaces: Array[GeometryInstance3D] = []
var _materials: Array[StandardMaterial3D] = []
## The alpha each material was AUTHORED with, so opacity scales what the artist
## chose rather than replacing it.
var _authored_alpha: PackedFloat32Array = PackedFloat32Array()
## The animated part, owned by whichever subclass animates one. 1 is not
## fading. Kept apart from opacity so a burst's fade and the tuning value
## multiply rather than overwriting each other.
var _fade: float = 1.0


func _ready() -> void:
	_collect_surfaces(self)
	_apply_alpha()


## How far through its own fade a subclass currently is, 1 being not at all.
func set_fade(value: float) -> void:
	_fade = clampf(value, 0.0, 1.0)
	_apply_alpha()


## Starts any particles this effect has.
##
## Called by whoever spawned it, AFTER putting it where it belongs. Particles
## emit in world space and a one-shot burst fires the instant it is allowed to,
## so a spray that begins emitting as it enters the tree throws its whole load
## at the effects root's origin and leaves it there - which is exactly what a
## blood spray was doing, in the top corner of the maze, every hit.
func play() -> void:
	for surface: GeometryInstance3D in _surfaces:
		var particles: CPUParticles3D = surface as CPUParticles3D
		if particles != null:
			particles.restart()


func _collect_surfaces(node: Node) -> void:
	var drawable: GeometryInstance3D = node as GeometryInstance3D
	if drawable != null:
		var material: StandardMaterial3D = _own_material(drawable)
		if material != null:
			drawable.material_override = material
			_surfaces.append(drawable)
			_materials.append(material)
			_authored_alpha.append(material.albedo_color.a)
	for child in node.get_children():
		_collect_surfaces(child)


## This effect's own copy of what a drawable draws with, or null when it draws
## with something this cannot dim - a ShaderMaterial, or nothing at all. Both
## are left exactly as they are rather than replaced with a guess.
func _own_material(drawable: GeometryInstance3D) -> StandardMaterial3D:
	var source: Material = drawable.material_override
	if source == null:
		var mesh: Mesh = drawable.get("mesh") as Mesh
		if mesh != null && mesh.get_surface_count() > 0:
			source = mesh.surface_get_material(0)
	if source == null:
		return null

	var copy: StandardMaterial3D = source.duplicate() as StandardMaterial3D
	if copy == null:
		return null
	# Alpha does nothing to a material that is not allowed to be transparent.
	copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return copy


func _apply_alpha() -> void:
	var showing: float = clampf(opacity * _fade, 0.0, 1.0)
	for index: int in range(_materials.size()):
		var material: StandardMaterial3D = _materials[index]
		if material == null:
			continue
		var colour: Color = material.albedo_color
		colour.a = _authored_alpha[index] * showing
		material.albedo_color = colour


## Takes the overrides off before the editor writes the scene and puts them
## back afterwards, so previewing an opacity can never leave a duplicated
## material or a material_override behind in a .tscn.
func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		for surface: GeometryInstance3D in _surfaces:
			if is_instance_valid(surface):
				surface.material_override = null
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		for index: int in range(_surfaces.size()):
			if is_instance_valid(_surfaces[index]):
				_surfaces[index].material_override = _materials[index]
