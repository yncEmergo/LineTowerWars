@abstract
class_name TutorialStep
extends Resource

## ONE LESSON of the tutorial: what it says, what it hands over, what the player
## may do while it is up, and what has to happen before the next one.
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
## Four things a step owns, and they are deliberately separate:
##
##   WHAT IT SAYS      the panel: a title, a SHORT paragraph, and the one line
##                     that says what to do now. Short is the rule - a lesson is
##                     read by somebody who wants to be playing.
##   WHAT IT GIVES     gold, a reserve of sends, a blueprint to follow, an
##                     opponent woken up. A lesson hands over exactly what its
##                     task needs and nothing else.
##   WHAT IT ALLOWS    whether the match clock runs, and which buttons and cells
##                     the player may use. The early lessons allow only the one
##                     thing they ask for, so the gold they handed over cannot be
##                     spent anywhere else.
##   WHEN IT IS DONE   asked of the world every tick, never reported by the
##                     thing that did it. That is what keeps the steps
##                     independent of the systems they teach - nothing in the
##                     builder, the sender or the tech screen knows a tutorial
##                     exists.

## One line of a lesson's task list: what to do, and whether it is done. The
## panel draws one row per task, with a tickbox that fills when it is done.
class Task:
	extends RefCounted
	var text: String = ""
	var done: bool = false
	## A task of this lesson still to come: drawn, so the player sees the plan,
	## but faded.
	var pending: bool = false

	func _init(what: String, finished: bool, later: bool = false) -> void:
		text = what
		done = finished
		pending = later


## Which opponent a lesson is about. By ROLE rather than by slot, so a lesson
## never has to know which lane the tutorial put anybody in - TutorialSetup
## decides that and TutorialSetup.slot_for answers it.
enum Rival {
	NONE,
	## The first opponent: a duel with it is where the basics are played out.
	FIRST,
	## The second: on standby, maze and all, until the first is beaten. Its half
	## of the tutorial is where technology is taught.
	SECOND,
}

## A unit of the player's that a lesson GUIDES them to select, before pointing
## at a button on its card. See guide_unit.
enum Select {
	NONE,
	## The player's builder.
	BUILDER,
	## The player's tier 1 sender, which is where the first creeps are bought.
	FIRST_SENDER,
}

@export_group("What it says")
## Whether this step is the next TASK of the lesson before it rather than a
## lesson of its own. The panel then keeps that lesson's title, adds this as one
## more row under it with its own tickbox, and does not pop - the lesson is the
## same one, a step further on. Its body, if it has one, replaces the lesson's
## text while it is the current task; its title is not shown.
@export var continues_lesson: bool = false
@export var title: String = ""
@export_multiline var body: String = ""
## The one line under the paragraph that says what to do NOW, in the imperative.
## Empty on a step that only explains, where the Continue button is the answer.
@export var objective: String = ""
## What the count after the objective counts - "Towers built", "Waves killed" -
## for a lesson that can count its task. Drawn as "Towers built: 1 / 4". Empty
## draws the bare numbers.
@export var progress_label: String = ""

@export_group("Pacing")
## Seconds between the lesson before this one being DONE and this one opening.
##
## A beat to see the thing just done land - the last tower going up, the last
## creep dying - before the next instruction arrives. The panel says the last
## lesson is done while it waits, and everything that lesson held stays held.
@export var delay_seconds: float = 2.0
## Whether the WORLD is held still while this step is on screen - nothing moves
## at all, and only the lesson panel answers a click.
##
## **Off for nearly everything, and that is deliberate.** A world held for
## reading is a world the player cannot touch, which is the opposite of what a
## lesson is for. Reach for it only where something really would go wrong
## while the player reads - and prefer holds_clock, which stops what the match
## does TO the player while leaving them free to act.
@export var pauses_world: bool = false
## Whether the match CLOCK stands still while this step is open: no income
## payout, no creep unlock, no reserve refilling. Units still walk, towers
## still go up and creeps still die.
##
## What makes a task untimed. The early lessons hold it, so a player asked to
## build a row takes as long as they like over it and nothing the clock times
## moves on without them - the clock only runs again once a lesson that lets it
## go opens. See MatchSession.hold_clock.
@export var holds_clock: bool = false

## Where a lesson holds the camera while it is open. See pinned_camera.
enum CameraPin {
	## Wherever the player puts it, which is nearly every lesson.
	NONE,
	## The top of the lane the player sends into: the spawn and the maze under
	## it, where the creeps they are about to send appear.
	TARGET_LANE_TOP,
}

@export_group("What it gives")
## Gold handed to the player when this step opens, on top of what they have.
##
## The tutorial does NOT start as a normal match: there is no gold and no
## income until a lesson hands them over, and a lesson hands over exactly what
## its task costs. That is why this is per step rather than a starting total.
@export var grant_gold: int = 0
## Income handed over permanently when this step opens - the base income a real
## match starts with, arriving at the moment the lesson about income opens.
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
## Waves this lesson sends into the PLAYER's own lane, each on its own delay
## after the lesson opens. Empty for a lesson that sends nothing.
##
## **The tutorial has to be able to attack the player before any opponent
## does.** The first opponent sends nothing until the basics are taught, so the
## lessons about a maze working set up their own waves.
##
## Spawned as the OPPONENT's creeps and as whole packs, so the leak, the bounty
## and the life steal all resolve exactly as they would from a real send.
@export var waves: Array[TutorialWave] = []
## A creep whose reserve is SET, not topped up, to stock_count when this step
## opens, as a res:// path to its CreepStats. Empty leaves every reserve alone.
##
## What makes a sending lesson exact: four sends available and the gold for
## four, with the clock held so nothing refills behind them.
@export_file("*.tres") var stock_creep_path: String = ""
@export var stock_count: int = 0
## The player's income is SET to this when the step opens, whatever it was,
## or left alone below zero. Once: sending raises it from there as usual.
@export var set_income: int = -1
## Seconds the creep roster is moved AHEAD when this step opens: creeps unlock as
## if that much more of the match had been played. Income is untouched. See
## MatchSession.unlock_elapsed_seconds.
@export var unlocks_ahead_seconds: float = 0.0
## A send tier the unlock clock is stopped short of from this step on: it runs
## until the last creep BELOW this tier is open, and stands there. 0 lets it run
## again, and below zero leaves whatever an earlier step set.
##
## What keeps a lesson's roster to what it has taught, while the rest of the
## match - income, the reserves refilling - goes on as normal.
@export var holds_back_tier: int = -1
## An opponent this step brings into the match properly: out of standby if it
## was waiting there, and playing its real profile from now on instead of
## sparring. See TutorialScript for which profile each one plays.
@export var wakes_rival: Rival = Rival.NONE
## Whether the Research Center opens with this step, and stays open for the rest
## of the tutorial. Until one step says so it is shut, so technology arrives
## when the lesson about it does rather than whenever a player finds the button.
@export var unlocks_research: bool = false

@export_group("What it allows")
## Whether the player is held to allowed_abilities while this step is up.
##
## Off, the player may press anything the rules allow - which is every lesson
## once the basics are done. On, only the abilities listed here and on the
## script's always_allowed list work at all, and everything else on the card is
## drawn dim. See ActionLimits.
@export var restricts_actions: bool = false
## The only abilities that work while restricts_actions is on, besides the
## script's always_allowed. A build lesson lists the one tower it asks for; a
## send lesson lists the one creep.
##
## **A TYPED ARRAY IN A .TRES IS ALL OR NOTHING** - one entry that fails to load
## empties the list silently, and a restricted lesson with an empty list allows
## nothing and cannot be finished. validate() refuses exactly that.
@export var allowed_abilities: Array[UnitAbility] = []
## Whether a restricted lesson's blueprint is also the only place a tower may
## go. On, a tower can be started on the blueprint's cells and nowhere else, and
## the build ghost turns red off it.
@export var build_on_blueprint_only: bool = false
## The dearest tower upgrade the player may start while this step is up, in
## gold, or below zero for any. Holds whether or not the step restricts, so a
## lesson that sets the player free can still keep the top of the tree back.
@export var max_upgrade_gold: int = -1

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
## Whether the screen is dimmed around the highlighted HUD control. Off by
## default: a dim over the whole screen hides the lane the player is being
## asked to act in, and the arrow alone says where to look.
@export var dims_around_highlight: bool = false
## A unit to walk the player to first. While it is not selected, the arrow
## points at the HUD button that selects it - and, for the builder, a second
## arrow hovers over the unit itself. Once it is selected, the arrow moves on to
## guide_abilities.
@export var guide_unit: Select = Select.NONE
## Command card buttons to point at, in the order they are pressed - the Build
## menu, then the tower inside it. The arrow points at whichever of them is on
## the card right now, and at nothing while an order is being aimed. Takes
## precedence over highlight_key once guide_unit is satisfied.
@export var guide_abilities: Array[UnitAbility] = []
## Whether an arrow hovers over every cell of the lesson's blueprint still to
## build on, disappearing as each is filled.
@export var arrows_on_blueprint: bool = false
## A tower type, as a res:// path to its BuildingStats: an arrow hovers over
## every tower of the player's of exactly that type - the Lesser Archers a
## lesson wants upgraded. Empty for none.
@export_file("*.tres") var arrows_on_towers_path: String = ""
## Where the camera is held while this step is open, released the moment it is
## done. For a task the player cannot do right while looking elsewhere - the
## first send, whose creeps appear in somebody else's lane.
@export var pinned_camera: CameraPin = CameraPin.NONE


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


## How far along the task is, as a short line the panel draws with the
## objective - "Towers built: 1 / 4" - or empty for a task with nothing to count.
##
## The cheapest telegraph there is: a player who can see the number move knows
## the thing they did counted.
func progress_text(director: TutorialDirector) -> String:
	var counted: Vector2i = progress(director)
	if counted.y <= 0:
		return ""
	var numbers: String = "%d / %d" % [mini(counted.x, counted.y), counted.y]
	return numbers if progress_label.is_empty() else "%s: %s" % [progress_label, numbers]


## The count behind progress_text: how many done (x) of how many (y), or a y of
## 0 for a task with nothing to count. A step that can count overrides it.
func progress(_director: TutorialDirector) -> Vector2i:
	return Vector2i.ZERO


## The lesson's tasks, each a row with its own tickbox. One by default - the
## objective with its count - done once the lesson is. A lesson with several
## things to do overrides it and ticks them off one at a time.
func tasks(director: TutorialDirector) -> Array[Task]:
	var list: Array[Task] = []
	if objective.is_empty():
		return list
	var progress_line: String = "" if director == null else progress_text(director)
	var text: String = objective if progress_line.is_empty() \
		else "%s\n%s" % [objective, progress_line]
	list.append(Task.new(text, director != null && director.is_between_lessons()))
	return list


## How many cells of this lesson's blueprint have one of the player's towers on
## them. Matched on the footprint's top-left cell, which is how a TowerLayout
## names a cell and how Building.cell stores one.
func blueprint_built() -> int:
	var plan: TowerLayout = blueprint()
	var area: PlayerArea = _local_area()
	if plan == null || area == null:
		return 0
	var wanted: Dictionary = {}
	for cell: Vector2i in plan.cells:
		wanted[cell] = true
	var count: int = 0
	for child in area.get_children():
		var building: Building = child as Building
		if building != null && wanted.has(building.cell):
			count += 1
	return count


## What a step DOES when it opens, beyond the grants above. Nothing for most of
## them; a step that has to put something in the world overrides it.
func on_enter(_director: TutorialDirector) -> void:
	pass


## Reports anything authored wrong on this one step. Called at boot with the
## rest of the content.
func validate() -> bool:
	var complete: bool = true
	# A task continuing a lesson shows that lesson's title, never its own.
	if title.is_empty() && !continues_lesson:
		Log.err("Tutorial step has no title", resource_path)
		complete = false
	# The editor does not rewrite a path string when a .tres moves, so a renamed
	# blueprint would leave a lesson quietly pointing at nothing - which reads as
	# a lesson that forgot to say where.
	for path: String in [blueprint_path, stock_creep_path, arrows_on_towers_path]:
		if !path.is_empty() && !ResourceLoader.exists(path):
			Log.err("Tutorial step names a resource that does not resolve", {
				"step": title,
				"path": path,
			})
			complete = false
	# An EMPTY allowed list on a restricted lesson is legitimate - nothing but
	# the script's always_allowed, which is what the lesson about selecting the
	# builder wants - so only a null entry is refused here. The typed-array trap
	# that empties a list silently is caught by the probe instead: a lesson that
	# names a button and then allows nothing never finishes.
	for ability: UnitAbility in allowed_abilities + guide_abilities:
		if ability == null:
			Log.err("Tutorial step allows or points at a null ability", title)
			complete = false
	for wave: TutorialWave in waves:
		if wave == null || !wave.validate(title):
			complete = false
	if build_on_blueprint_only && blueprint_path.is_empty():
		Log.err("Tutorial step keeps building to a blueprint it does not have", title)
		complete = false
	return complete


## The creep whose reserve this lesson sets, or null.
func stock_creep() -> CreepStats:
	return _load_creep(stock_creep_path)


## The tower type arrows hover over, or null.
func arrow_tower() -> BuildingStats:
	if arrows_on_towers_path.is_empty() || !ResourceLoader.exists(arrows_on_towers_path):
		return null
	return ResourceLoader.load(arrows_on_towers_path, "") as BuildingStats


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


func _load_creep(path: String) -> CreepStats:
	if path.is_empty() || !ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path, "") as CreepStats


## The player's own lane, for a step reading the ground rather than a counter.
func _local_area() -> PlayerArea:
	var manager: PlayerManager = References.player_manager
	return null if manager == null else manager.area_for(manager.local_player_id())
