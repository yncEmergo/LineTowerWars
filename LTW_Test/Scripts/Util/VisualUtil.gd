class_name VisualUtil
extends RefCounted

## Copying what a unit LOOKS like, without copying what it does.
##
## Two things need this and they need exactly the same thing: the live portrait
## in the unit panel, and the offline renderer that bakes ability icons. Both
## want a unit's meshes standing on their own, in a viewport of their own, with
## no script attached to any of them - a portrait must never register a unit id,
## claim a grid cell, pay a bounty or shoot at anything.
##
## It copies MESHES ONLY, one at a time, rather than duplicating the unit and
## stripping it. Duplicating carries every script along and relies on
## remembering to disable each one; taking only the MeshInstance3Ds means
## nothing else can come with them by accident.
##
## NOTHING HERE TOUCHES global_transform, and that is deliberate: the icon
## renderer works from PREFABS, which are instantiated and never put in a tree
## precisely so their _ready never runs. A node outside the tree has no global
## transform, so positions are accumulated by walking up to the source instead.


## Copies every mesh under `source` into `into`, and answers the box they fill
## in `into`'s space - which is what a camera needs to frame them.
##
## `skip` is for the parts of a unit that are not the unit: its selection ring
## and its health bar belong to the UI, and a portrait of a selected tower
## should not have a green circle round its feet.
static func copy_meshes(source: Node3D, into: Node3D, skip: Array[Node] = []) -> AABB:
	if source == null || into == null:
		return AABB()
	_copy_into(source, source, into, skip)
	return measure(into)


static func _copy_into(node: Node, source: Node3D, into: Node3D,
		skip: Array[Node]) -> void:
	var mesh: MeshInstance3D = node as MeshInstance3D
	if mesh != null && mesh.visible && mesh.mesh != null \
			&& !_is_skipped(mesh, source, skip):
		var copy: MeshInstance3D = MeshInstance3D.new()
		copy.mesh = mesh.mesh
		# The override too, or an effect or a preview ghost would come out in
		# whatever its mesh was authored with rather than what it is showing.
		copy.material_override = mesh.material_override
		copy.transform = relative_transform(mesh, source)
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		into.add_child(copy)

	for child in node.get_children():
		_copy_into(child, source, into, skip)


## Where a node sits relative to an ancestor, accumulated by walking up rather
## than asked of the tree, so this works on a prefab nothing has parented.
static func relative_transform(node: Node3D, source: Node3D) -> Transform3D:
	var result: Transform3D = Transform3D.IDENTITY
	var walk: Node3D = node
	while walk != null && walk != source:
		result = walk.transform * result
		walk = walk.get_parent() as Node3D
	return result


## Whether a node, or anything above it, is one of the parts being skipped.
## Checked up the chain so skipping a model's root skips everything under it.
static func _is_skipped(node: Node, source: Node3D, skip: Array[Node]) -> bool:
	if skip.is_empty():
		return false
	var walk: Node = node
	while walk != null:
		if skip.has(walk):
			return true
		if walk == source:
			return false
		walk = walk.get_parent()
	return false


## The box every mesh under a node fills, in that node's own space. Empty when
## it has none, which the caller has to expect - a unit whose prefab is all
## script and no mesh is legal, if odd.
static func measure(into: Node3D) -> AABB:
	var bounds: AABB = AABB()
	var started: bool = false
	for child in into.get_children():
		var mesh: MeshInstance3D = child as MeshInstance3D
		if mesh == null || mesh.mesh == null:
			continue
		var box: AABB = mesh.transform * mesh.mesh.get_aabb()
		bounds = box if !started else bounds.merge(box)
		started = true
	return bounds


## Everything a unit's portrait should leave out.
##
## Three kinds of thing, and none of them is the unit:
##   - the selection ring and the health bar, which are UI wearing a mesh
##   - the ground patch a building stands on, which is FLOOR. Left in, it
##     renders as a grey smear under the tower in an icon that has no floor
static func portrait_skips(unit: Node) -> Array[Node]:
	var skip: Array[Node] = []
	if unit == null:
		return skip

	var ring: Node = unit.get("_selection_ring") as Node
	if ring != null:
		skip.append(ring)
	_collect_skips(unit, skip)
	return skip


static func _collect_skips(node: Node, into: Array[Node]) -> void:
	for child in node.get_children():
		if child is HealthBar3D || child is BuildingFoundation:
			into.append(child)
		else:
			_collect_skips(child, into)
