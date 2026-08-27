class_name ControlGroups
extends RefCounted

## Numbered unit groups, the standard RTS shortcut.
##
## Membership is stored per group index. A unit leaving the tree - sold,
## cancelled or destroyed - drops out of every group it was in, so a group
## never hands back a freed node.

var _groups: Dictionary = {}


## Replaces a group's contents with the given units.
func assign(index: int, units: Array) -> void:
	var stored: Array = []
	for unit in units:
		if unit == null || !is_instance_valid(unit):
			continue
		stored.append(unit)
		_watch(unit)

	_groups[index] = stored


## The units in a group, as a copy so callers cannot mutate the group by
## holding on to the result.
func recall(index: int) -> Array:
	if !_groups.has(index):
		return []

	# Pruned on read as well as on exit, in case a unit went away without its
	# signal reaching us.
	var alive: Array = []
	for unit in _groups[index]:
		if is_instance_valid(unit):
			alive.append(unit)

	_groups[index] = alive
	return alive.duplicate()


## Swaps one unit for another wherever it is stored, keeping its position in
## every group it was in.
##
## An upgraded tower is a NEW node, and without this it would drop out of every
## group the moment the old one left the tree - which is exactly the wrong
## answer, because to the player nothing left. Order is preserved because a
## group's first unit is what the camera centres on.
func replace(old_unit: Node, new_unit: Node) -> void:
	if old_unit == null || new_unit == null || !is_instance_valid(new_unit):
		return

	var watched: bool = false
	for index: int in _groups:
		var stored: Array = _groups[index]
		var at: int = stored.find(old_unit)
		if at < 0:
			continue
		stored[at] = new_unit
		if !watched:
			_watch(new_unit)
			watched = true


func size_of(index: int) -> int:
	if !_groups.has(index):
		return 0
	return (_groups[index] as Array).size()


## The bound callable has to be rebuilt identically to test for it, because
## binding produces a different Callable to the bare method.
func _watch(unit: Node) -> void:
	var callback: Callable = _on_unit_exiting.bind(unit)
	if !unit.tree_exiting.is_connected(callback):
		unit.tree_exiting.connect(callback)


func _on_unit_exiting(unit: Node) -> void:
	for index in _groups:
		(_groups[index] as Array).erase(unit)
