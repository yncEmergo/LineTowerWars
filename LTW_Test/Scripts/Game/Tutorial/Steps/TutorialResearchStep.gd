class_name TutorialResearchStep
extends TutorialStep

## Finished once the player has researched something - any technologies up to a
## number, or exactly the ones the lesson names.
##
## NAMED is the telegraphed form: only those technologies can be researched
## while the lesson is up, every other square in the Research Center is dimmed,
## and the border walks the player from the button that opens it to the next
## square to press. It is how the tutorial makes sure the player ends up with
## the Ultimate the rest of it is written around.

@export_group("Objective")
## The technologies to research, by tech_id - the only ones that can be. Empty
## for any technologies at all, counted up to `technologies`.
@export var tech_ids: Array[int] = []
## How many technologies have to be owned, when tech_ids is empty.
@export var technologies: int = 1


func is_complete(director: TutorialDirector) -> bool:
	var counted: Vector2i = progress(director)
	return counted.y > 0 && counted.x >= counted.y


func progress(director: TutorialDirector) -> Vector2i:
	if director == null:
		return Vector2i.ZERO
	if tech_ids.is_empty():
		return Vector2i(director.technologies_owned(), maxi(1, technologies))
	var owned: int = 0
	for id in tech_ids:
		if director.owns_tech(id):
			owned += 1
	return Vector2i(owned, tech_ids.size())


## The next named technology still to research, or 0 - which square the border
## goes to.
func next_tech(director: TutorialDirector) -> int:
	for id in tech_ids:
		if director != null && !director.owns_tech(id):
			return id
	return 0


func research_whitelist() -> Array[int]:
	return tech_ids
