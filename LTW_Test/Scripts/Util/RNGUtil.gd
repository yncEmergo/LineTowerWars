## Provides static methods for seeded random number generators
class_name RNGUtil

## Returns a random int within the range (min and max inclusive)
static func random_int(rng: RandomNumberGenerator, minimum: int, maximum: int) -> int:
	var result: int = rng.randi_range(minimum, maximum)
	return result

static func shuffle_with_rng(rng: RandomNumberGenerator, array: Array) -> Array:
	for i: int in range(array.size() - 1, 0, -1):
		var random_index: int = rng.randi_range(0, i)

		var temp: Variant = array[i]
		array[i] = array[random_index]
		array[random_index] = temp
	return array

## Returns a random element of the given array
static func pick_random(rng: RandomNumberGenerator, array: Array) -> Variant:
	if array.size() == 0:
		return null
	
	var result: Variant = array[rng.randi_range(0, array.size() - 1)]
	return result

## Returns true if a random chance exceeds the given threshold
## Chance should be a between 0 and 1
static func evaluate_probability(rng: RandomNumberGenerator, chance: float) -> bool:
	var value := rng.randf_range(0, 1)
	
	var result: bool = value < chance
	#print (str(value) + " < " + str(chance) + " = " + str(result))
	return result

## Evaluates a dictionary with variants as keys and their weightings as values and returns the chosen variant.
## The values must be floats.
static func evaluate_weighted(rng: RandomNumberGenerator, dic: Dictionary) -> Variant:
	var valid_entries: Array[Dictionary] = []
	var total_weighting: float = 0.0

	for variant: Variant in dic.keys():
		var weighting_value: Variant = dic[variant]

		if !(weighting_value is float):
			Log.warn("Value in dictionary is not a float. Ignoring this entry.")
			continue

		var weighting: float = weighting_value as float

		if weighting <= 0.0:
			continue

		valid_entries.append({
			"variant": variant,
			"weighting": weighting,
		})

		total_weighting += weighting

	if total_weighting <= 0.0:
		Log.err("Weighted random evaluation failed. No valid weightings found.")
		return null

	var random_pick: float = rng.randf_range(0.0, total_weighting)

	var current_weighting: float = 0.0
	for entry: Dictionary in valid_entries:
		current_weighting += entry["weighting"] as float

		if random_pick < current_weighting:
			return entry["variant"]

	Log.err("Weighted random evaluation failed. This should not happen.")
	return null
	
## Selects a set number of random diverse elements from the provided array, ensuring no duplicates
## If the number of requested elements exceeds the available unique elements, it falls back to non-unique selections
## Returns an array containing the selected diverse elements
static func pick_random_diverse_elements(rng: RandomNumberGenerator, array: Array[Variant], variant_count: int) -> Array[Variant]:
	var variants_to_return: Array[Variant]
	if array.size() == 0:
		return variants_to_return
	
	var diverse_variants: Array[Variant]
	for variant: Variant in array:
		if !diverse_variants.has(variant):
			diverse_variants.append(variant)

	while variants_to_return.size() < variant_count:
		var new_variant_to_add: Variant 
		if diverse_variants.size() > 0:
			new_variant_to_add = pick_random(rng, diverse_variants)
			diverse_variants.erase(new_variant_to_add)
		else:
			new_variant_to_add = pick_random(rng, array)
		variants_to_return.append(new_variant_to_add)
		
	return variants_to_return
