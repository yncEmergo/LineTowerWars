class_name TutorialScript
extends Resource

## THE LESSONS, in the order they are taught, and the board they are taught on.
##
## One resource holding the list rather than a folder scan, and for the same
## reason AiConfig holds one: the ORDER is the content here. A scan would sort
## the tutorial by file name, and a lesson that teaches sending before it has
## taught building is not a tutorial.
##
## Stored as Resources/Tutorial/tutorial_script.tres and named by
## TutorialDirector. Re-ordering the tutorial, cutting a lesson or writing a new
## one is editing this file and nothing else.

@export_group("Opponents")
## Gold each opponent is handed when the tutorial starts, to build the maze it
## spars with.
##
## It needs some: a tutorial match starts everybody on NOTHING so a lesson can
## hand the player exactly what it is about to talk about, and an opponent with
## no gold builds no maze - which leaves the player sending creeps into an empty
## lane and learning nothing from it.
@export var opponent_gold: int = 400
## The profile the FIRST opponent plays once a lesson wakes it, as a res:// path
## to an AiProfile. Until then it spars - builds, never sends.
@export_file("*.tres") var first_rival_profile_path: String = ""
## The profile the SECOND opponent plays once a lesson wakes it. Until then it
## waits on standby outside the send ring, sparring.
@export_file("*.tres") var second_rival_profile_path: String = ""
## Lives each opponent starts on. Far fewer than a match would give, because
## beating one is a lesson and a lesson should take minutes rather than a match.
@export var rival_lives: int = 10
## Share of the PLAYER's income an opponent is given when it wakes, 0 or more.
##
## An opponent that sparred has sent nothing and so earned nothing, and would
## wake a match behind a player who has been sending the whole time. Matching
## the player is what makes the fight a fair one to learn from; below 1 is a
## head start for the player.
@export var rival_income_share: float = 1.0

@export_group("Player")
## Lives the player starts on. Plenty: losing the tutorial teaches nothing.
@export var player_lives: int = 30
## The abilities every RESTRICTED lesson allows on top of its own list - moving
## and stopping the builder, calling off an order - so a lesson only has to name
## the one thing it is about. See TutorialStep.allowed_abilities, and the
## typed-array warning on it, which holds here too.
@export var always_allowed: Array[UnitAbility] = []
## Abilities the player may not use at any point in the tutorial, restricted
## lesson or not - the builder's own blueprint screens, whose saved mazes would
## compete with the one a lesson draws on the ground. See ActionLimits.forbidden.
@export var forbidden_abilities: Array[UnitAbility] = []

@export_group("Moments")
## What stops the match the FIRST time it happens, whichever lesson is open -
## see TutorialMoment. Watched for from the first lesson to the last.
@export var moments: Array[TutorialMoment] = []

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


## The steps that make up the LESSON a step belongs to, as the first and last
## index. A lesson is one step and every step after it that continues it - see
## TutorialStep.continues_lesson - so a lesson with four tasks is four steps
## drawn under one title.
func lesson_range(index: int) -> Vector2i:
	var first: int = clampi(index, 0, maxi(0, steps.size() - 1))
	while first > 0 && steps[first] != null && steps[first].continues_lesson:
		first -= 1
	var last: int = first
	while last + 1 < steps.size() && steps[last + 1] != null && steps[last + 1].continues_lesson:
		last += 1
	return Vector2i(first, last)


## Which lesson a step is in, counting from 1, and how many lessons there are,
## for the "Lesson 3 of 8" a panel draws.
func lesson_position(index: int) -> Vector2i:
	var number: int = 0
	var total: int = 0
	for at in range(steps.size()):
		if steps[at] == null || !steps[at].continues_lesson || at == 0:
			total += 1
		if at == index:
			number = total
	return Vector2i(number, total)


## The profile an opponent plays once it is woken, or null.
func rival_profile(rival: TutorialStep.Rival) -> AiProfile:
	var path: String = ""
	match rival:
		TutorialStep.Rival.FIRST:
			path = first_rival_profile_path
		TutorialStep.Rival.SECOND:
			path = second_rival_profile_path
	if path.is_empty() || !ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path, "") as AiProfile


func validate() -> bool:
	if steps.is_empty():
		Log.err("The tutorial script holds no lessons, it would open on nothing",
			resource_path)
		return false

	var complete: bool = true
	for rival: TutorialStep.Rival in [TutorialStep.Rival.FIRST, TutorialStep.Rival.SECOND]:
		var profile: AiProfile = rival_profile(rival)
		if profile == null:
			Log.err("The tutorial names no loadable profile for an opponent", {
				"rival": TutorialStep.Rival.keys()[rival],
			})
			complete = false
		elif !profile.validate():
			complete = false
	for ability: UnitAbility in always_allowed + forbidden_abilities:
		if ability == null:
			Log.err("The tutorial always allows or forbids a null ability", resource_path)
			complete = false

	for moment: TutorialMoment in moments:
		if moment == null || !moment.validate():
			Log.err("The tutorial script holds a moment it cannot use", resource_path)
			complete = false

	for index in range(steps.size()):
		var step: TutorialStep = steps[index]
		if step == null:
			Log.err("The tutorial script holds a null lesson", {"index": index})
			complete = false
			continue
		complete = step.validate() && complete
	return complete
