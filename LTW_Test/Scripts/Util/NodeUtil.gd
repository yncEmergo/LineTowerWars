class_name NodeUtil

static func get_all_children(node: Node) -> Array[Node]:
	var children: Array[Node]
	
	for child in node.get_children():
		children.append(child)
		children.append_array(get_all_children(child))

	return children
