class_name Linq

static var _sorting_ascending: bool
static var _sorting_property_function: Callable


# This is a bootleg LINQ library
# add and document the functions you need

# checks if array1 and array2 share at least one elment
static func intersect (array1: Array, array2: Array) -> bool:
	for item1: Variant in array1:
		if (array2.has(item1)):
			return true
	return false

# REMOVED: remove has been removed! Use Array.erase(item) instead
# removes the item and returns true, if item is not part of array it returns false
#static func remove (array: Array, object_to_remove: Variant) -> bool:
#	if (!array.has(object_to_remove)):
#		return false
#	var index := array.find(object_to_remove)
#	array.remove_at(index)
#	return true

# creates a new array with the elements returned from the lamda function.
# ussage:
# var newArray = Linq.select(my_list, func (item: TypeOfTheItem): return item.some_property)
# the lamda function can also be complex and used as a where function
# var newArray = Linq.select(my_list, func (item: TypeOfTheItem):
#	if (item.some_condition):
#		return item.some_value
#	else:
#		return null)
# null values can be cleaned up with remove_null_entries_from_array(array)
static func select (array: Array, selection_function: Callable, remove_null_entries: bool = true) -> Array:
	var result := []
	for item: Variant in array:
		var new_item: Variant = selection_function.call(item)
		if new_item != null || !remove_null_entries:
			result.append(new_item)

	return result

# returns the firest element returned from the lamda function.
# ussage:
# var searched_item = Linq.first(my_list, func (item: TypeOfTheItem):
#	if (item.some_condition):
#		return item
#	else:
#		return null)
static func first (array: Array, selection_function: Callable) -> Variant:
	for item: Variant in array:
		var new_item: Variant = selection_function.call(item)
		if (new_item != null):
			return new_item
	return null

# creates new array without null entires
static func remove_null_entries_from_array (array:Array) -> Array:
	var new_array := []
	for item: Variant in array:
		if (item != null):
			new_array.append(item)
	return new_array

# returns a flat array of all items in the 2d array
static func flatten_2d_array (array: Array) -> Array:
	var new_array := []
	for nested_array: Array in array:
		new_array.append_array(nested_array)
	return new_array

# returns a flat array of all items in the arries provided by the selction function
static func combine_select (array: Array, selection_function: Callable) -> Array:
	var result := []
	for item: Variant in array:
		var new_item: Variant= selection_function.call(item)
		result.append_array(new_item)

	return result

# returns an array that only contains the unique items of the given array
# uses array.has function to check uniquenes
static func remove_duplicates (array: Array) -> Array:
	var result := []
	for item: Variant in array:
		if (!result.has(item)):
			result.append(item)
	return result

# removes all elements of item_to_remove from the given array and returns the array
static func remove_multiple (array: Array, items_to_remove: Array) -> Array:
	for item_to_remove: Variant in items_to_remove:
		array.erase(item_to_remove)
	return array

## Can be used to sort an array by a property of the array elements
## uses the sort_custom function of array but combines it with the property_return_function
## example:
##	Linq.sort_by_property(run.passengers_in_train,
##		func(p: Passenger) -> float:
##			return p.position.x * 100 + p.position.y,
##		false))
## returns a duplicated and sorted array
## Only allows to sort with the < and > operators
static func sort_by_property (array: Array, property_return_function: Callable,
	ascending: bool = true) -> Array:
	array = array.duplicate()
	_sorting_ascending = ascending
	_sorting_property_function = property_return_function
	array.sort_custom(_sort_function)

	return array

## internal function of the sort_by_property function
static func _sort_function (a: Variant, b: Variant) -> bool:
	var a_value: Variant = _sorting_property_function.call(a)
	var b_value: Variant = _sorting_property_function.call(b)
	if _sorting_ascending:
		return a_value > b_value
	return a_value < b_value


## Just a reminder that the godot internal function exists
static func reverse_array_order(array: Array[Variant]) -> Array[Variant]:
	array.reverse()
	return array
