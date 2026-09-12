class_name TutorialScript
extends Resource

## THE LESSONS, in the order they are taught.
##
## One resource holding the list rather than a folder scan, and for the same
## reason AiConfig holds one: the ORDER is the content here. A scan would sort
## the tutorial by file name, and a lesson that teaches sending before it has
## taught building is not a tutorial.
##
## Stored as Resources/Tutorial/tutorial_script.tres and named by
## TutorialDirector. Re-ordering the tutorial, cutting a lesson or writing a new
## one is editing this file and nothing else.

@export_group("Opponent")
## Gold the sparring partner is handed when the tutorial starts.
##
## It needs some: a tutorial match starts everybody on NOTHING so a lesson can
## hand the player exactly what it is about to talk about, and an opponent with
## no gold builds no maze - which leaves the player sending creeps into an empty
## lane and learning nothing from it.
##
## One lump rather than income, because the partner is a demonstration rather
## than a match: enough for the short maze its profile plans and no more.
@export var opponent_gold: int = 400

@export_group("Lessons")
## In teaching order. **A TYPED ARRAY IN A .TRES IS ALL OR NOTHING**: one entry
## that fails to load empties the whole list silently, and the editor writes
## that emptiness back on the next save. validate() is what refuses it loudly at
## boot rather than leaving a tutorial that opens on nothing.
@export var steps: Array[TutorialStep] = []


func count() -> int:
	return steps.size()


## The lesson at a position, or null once the tutorial is over - which is what
## the director reads as "finished" rather than keeping a separate flag.
func step_at(index: int) -> TutorialStep:
	if index < 0 || index >= steps.size():
		return null
	return steps[index]


func validate() -> bool:
	if steps.is_empty():
		Log.err("The tutorial script holds no lessons, it would open on nothing",
			resource_path)
		return false

	var complete: bool = true
	for index in range(steps.size()):
		var step: TutorialStep = steps[index]
		if step == null:
			Log.err("The tutorial script holds a null lesson", {"index": index})
			complete = false
			continue
		complete = step.validate() && complete
	return complete
