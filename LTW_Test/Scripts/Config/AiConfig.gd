class_name AiConfig
extends Resource

## Every AI difficulty this build contains, in the order a setup screen lists
## them: easiest first.
##
## Stored as Resources/Config/ai_config.tres and reached through
## References.ai_config. A list in one resource rather than a folder scan,
## unlike the abilities and the unit types, and the difference is what the
## number MEANS: an ability id is authored so it can never move, where a
## difficulty is an ORDER a player reads down a dropdown. A scan would sort them
## by file name.
##
## **An AI is named on a MatchPlayer by its INDEX here** (MatchPlayer
## ai_difficulty), so inserting one in the middle renames every seat above it.
## That is fine for a setting chosen on a screen and thrown away with the match,
## and it is exactly why the index must never be written into a save or onto the
## wire as an identity. It is not an authored id and must not be treated as one.

## What ai_difficulty holds for a slot a person plays.
const HUMAN: int = MatchPlayer.HUMAN

@export_group("Difficulties")
## Easiest first. **A TYPED ARRAY IN A .TRES IS ALL OR NOTHING**: one entry that
## fails to load empties the whole list silently, and the editor then writes
## that emptiness back on the next save. validate() is what refuses it loudly at
## boot rather than leaving a single player screen with no difficulties in it.
@export var profiles: Array[AiProfile] = []


## How many difficulties there are, for the dropdown that lists them.
func count() -> int:
	return profiles.size()


## The profile an index names, or null for one this build does not contain.
##
## Callers must expect null: an index is a position in a list rather than an
## authored id, so a setup carrying one from a build with more difficulties in
## it is a real thing that can arrive.
func profile_for(index: int) -> AiProfile:
	if index < 0 || index >= profiles.size():
		return null
	return profiles[index]


## The default a setup screen opens on: the middle of what can be chosen,
## rounded down, so a fresh single player game is neither the gentlest thing in
## the build nor the one nobody can beat.
func default_index() -> int:
	var choices: PackedInt32Array = selectable_indices()
	if choices.is_empty():
		return HUMAN
	@warning_ignore("integer_division")
	return choices[choices.size() / 2]


## Every difficulty's name, in order, for anything that lists all of them.
func names() -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for profile in profiles:
		found.append("?" if profile == null else profile.display_name)
	return found


## The indices a player may actually CHOOSE, in order.
##
## Not every profile is an opponent: the tutorial's sparring partner lives in
## this list so a match can name it by index like any other, and has no business
## in a dropdown. So a setup screen draws these and maps a position in its own
## menu back to the index here - which is why this returns indices rather than
## names, and why the two must never be assumed to be the same number.
func selectable_indices() -> PackedInt32Array:
	var found: PackedInt32Array = PackedInt32Array()
	for index in range(profiles.size()):
		var profile: AiProfile = profiles[index]
		if profile != null && profile.selectable:
			found.append(index)
	return found


## The names of a given set of indices, in the order they were asked for.
func names_of(indices: PackedInt32Array) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for index: int in indices:
		var profile: AiProfile = profile_for(index)
		found.append("?" if profile == null else profile.display_name)
	return found


## Reports everything authored wrong across the whole list, at boot.
func validate() -> bool:
	if profiles.is_empty():
		Log.err("AiConfig holds no difficulties, no AI can be added to a match",
			resource_path)
		return false

	var complete: bool = true
	for index in range(profiles.size()):
		var profile: AiProfile = profiles[index]
		if profile == null:
			Log.err("AiConfig holds a null difficulty", {"index": index})
			complete = false
			continue
		complete = profile.validate() && complete
	return complete
