@abstract
class_name TutorialStep
extends Resource

## ONE LESSON of the tutorial: what it says, what it hands over, what has to
## happen before the next one, and what it points at while the player does it.
##
## A polymorphic Resource rather than a row in a table, and it is the same shape
## every other piece of behaviour in this project has: an attack's delivery is a
## resource, a tower's passive is a resource, and a lesson is a resource. What
## makes a step a BUILD lesson rather than a SEND one is which subclass it is,
## so nothing anywhere has to switch on a kind.
##
## **A step is STATELESS and SHARED, like every other ability-shaped resource
## here.** It is asked whether it is finished and answers from the world; it
## holds no timer, no count and no "have I run yet". Anything per-run lives on
## TutorialDirector, which is the one object that knows a tutorial is being
## played at all.
##
## Three things a step owns, and they are deliberately separate:
##
##   WHAT IT SAYS      the panel: a title, a paragraph, and the one line that
##                     says what to do now.
##   WHAT IT GIVES     gold, a blueprint to follow, a rule switched on. The
##                     tutorial is not a normal match and does not pretend to
##                     be: a lesson hands over exactly what it is about to talk
##                     about and nothing else.
##   WHEN IT IS DONE   asked of the world every tick, never reported by the
##                     thing that did it. That is what keeps the steps
##                     independent of the systems they teach - nothing in the
##                     builder, the sender or the tech screen knows a tutorial
##                     exists.

@export_group("What it says")
@export var title: String = ""
@export_multiline var body: String = ""
## The one line under the paragraph that says what to do NOW, in the imperative.
## Empty on a step that only explains, where the Continue button is the answer.
@export var objective: String = ""

@export_group("Pacing")
## Whether the world is HELD STILL while this step is on screen.
##
## True for anything that is read rather than done: the popup stops the match so
## a player reading a paragraph is not being leaked on while they read. False
## for a step whose objective IS to do something, where a frozen world would
## make it impossible.
##
## Held through MatchSession.hold, which is the same mechanism a technology
## draft uses, so the HUD stops with everything else and only the panel answers.
@export var pauses_world: bool = true
## How long before the panel offers a way past this step, in seconds, or 0 for
## one that is offered immediately.
##
## **This is the anti-softlock rule and it is not optional.** A step waits on
## the world reaching a state, and a world can always be put in a state it
## cannot reach - a maze built somewhere the blueprint did not ask for, gold
## spent on the wrong thing, a creep that walked past. A tutorial that can be
## stuck is worse than one that can be skipped.
@export var skip_after_seconds: float = 45.0


@export_group("What it gives")
## Gold handed to the player when this step opens, on top of what they have.
##
## The tutorial does NOT start as a normal match: there is no income until the
## economy is taught, and a lesson hands over exactly enough to do the thing it
## is about. That is why this is per step rather than a starting total.
@export var grant_gold: int = 0
## Income handed over permanently when this step opens, for the economy lesson -
## the first moment the tutorial starts behaving like a real match.
@export var grant_income: int = 0
## A saved maze to draw over the player's zone while this step is up, as a
## res:// path to a TowerLayout, or empty for none.
##
## How the tutorial says WHERE to build without taking the mouse off the player:
## a blueprint is one blue square per cell still to build on and it disappears
## as each is filled, which is exactly "these ones, in any order".
##
## A PATH rather than one of the player's nine SLOTS, and the difference
## matters: a slot is theirs, and somebody who has saved their own maze into
## slot one would be shown that maze by a lesson meaning to show them the shape
## it is teaching. See BlueprintOverlay.show_layout.
@export_file("*.tres") var blueprint_path: String = ""
## Whether this step opens the whole send card, waiving every creep's start
## delay for the player.
##
## The same switch the developer cheat throws, and reached for the same reason:
## a tutorial teaching how sending works cannot spend four minutes waiting for
## the second creep in the game to unlock.
@export var unlocks_creeps: bool = false

@export_group("What it points at")
## A named control on the HUD to draw an arrow at while this step is up, or
## empty for none. The names are authored on TutorialHighlights, in the HUD
## scene, so a step names WHAT it is pointing at and never where that is.
@export var highlight_key: StringName = &""
## What to dim the WORLD around while this step is up, so one thing on the
## ground is the only lit thing on screen. See TutorialSpotlight.
##
## An enum rather than a position, because a lesson cannot know where anything
## is: a creep is wherever it has walked to and a tower is wherever the player
## put it. What a lesson knows is WHICH THING it is talking about, and the
## spotlight resolves that against the world every frame.
enum Spotlight {
	## Nothing dimmed, which is nearly every lesson.
	NONE,
	## The player's own lane.
	MY_LANE,
	## The lane they send into, which is the one thing a player being taught the
	## send ring has never had a reason to look at.
	TARGET_LANE,
	## The last tower the player built, wherever they put it.
	MY_NEWEST_TOWER,
	## Whichever creep in the player's lane has walked furthest, which is the one
	## worth watching and the one about to leak.
	LEADING_CREEP,
}

@export var spotlight: Spotlight = Spotlight.NONE


## Whether the world is now in the state this step was waiting for.
##
## Asked EVERY TICK of the current step and of nothing else, so it may read the
## world freely - but it must not change it, and it must be cheap enough to run
## twenty times a second.
##
## The director is passed in rather than the world, because what a step wants to
## know is nearly always about the LOCAL player and about what has happened
## since the step opened, and the director is what holds both.
@abstract func is_complete(director: TutorialDirector) -> bool


## What a step DOES when it opens, beyond the grants above. Nothing for most of
## them; a step that has to put something in the world overrides it.
func on_enter(_director: TutorialDirector) -> void:
	pass


## Reports anything authored wrong on this one step. Called at boot with the
## rest of the content.
func validate() -> bool:
	var complete: bool = true
	if title.is_empty():
		Log.err("Tutorial step has no title", resource_path)
		complete = false
	# The editor does not rewrite a path string when a .tres moves, so a renamed
	# blueprint would leave a lesson quietly pointing at nothing - which reads as
	# a lesson that forgot to say where.
	if !blueprint_path.is_empty() && !ResourceLoader.exists(blueprint_path):
		Log.err("Tutorial step names a blueprint that does not resolve", {
			"step": title,
			"path": blueprint_path,
		})
		complete = false
	return complete


## The plan this lesson puts on the ground, or null for one that puts none.
##
## Loaded on first ask rather than held, for the reason the path is a path: a
## tutorial script listing a dozen lessons should not pull a dozen mazes into
## memory to be validated.
##
## No type hint on the load and the existence check is ResourceLoader's, which
## is the export trap CLAUDE.md records - both are right in the editor and wrong
## in the thing players download.
func blueprint() -> TowerLayout:
	if blueprint_path.is_empty() || !ResourceLoader.exists(blueprint_path):
		return null
	return ResourceLoader.load(blueprint_path, "") as TowerLayout
