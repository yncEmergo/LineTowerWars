@abstract
class_name UnitAbility
extends Resource

## One entry on a unit's command card.
##
## Abilities are resources that carry their own behaviour, so adding a new one
## means adding a script and a .tres rather than another branch in a growing
## match statement. Shared abilities such as Move are a single .tres referenced
## by many unit types.
##
## Abilities must stay STATELESS. Godot caches resources, so one move.tres
## referenced by fifty creeps is one shared object. That is why execute() takes
## the unit as an argument instead of the ability holding one, and why any
## future cooldown belongs on the unit, never here.

## What has to happen after the player picks this ability.
enum Targeting {
	## Display only, never activates. Auras and other passives.
	PASSIVE,
	## Fires the moment it is chosen. Stop, Hold.
	IMMEDIATE,
	## Needs a ground point, confirmed with a left click. Move, Patrol.
	GROUND,
	## Needs a target unit, confirmed with a left click. Attack.
	UNIT,
	## Replaces the command card with another set of abilities. Build.
	SUBMENU,
	## Needs a ground point like GROUND, but shows a snapped footprint preview
	## while choosing. Placing a tower.
	PLACEMENT,
	## Takes EITHER, whichever the click landed on: the unit under the cursor
	## if there is one, and the ground point if there is not. Attack, which is
	## an attack-MOVE when it is aimed at the floor.
	##
	## Last in the enum because these are authored as plain ints in every
	## .tres on the roster, so a new entry may only ever be added at the end.
	UNIT_OR_GROUND,
}

## Given to slot to mean "wherever there is room", see below.
const AUTO_SLOT: int = -1

@export_group("Identity")
## The number a network command names this ability by. Must be unique across
## every ability the game contains, and must never change once it has shipped.
##
## Authored HERE rather than derived from a position in some list, which is the
## whole point: adding, removing or reordering abilities cannot shift anybody
## else's id, and a deleted ability simply leaves a hole. 0 means nobody has
## assigned one yet, which AbilityRegistry reports at boot.
##
## Ids are never reused. A new ability takes the next free number.
@export var ability_id: int = 0
@export var display_name: String = "Ability"
@export_multiline var description: String = ""
## This ability's own picture, for the ones that are not ABOUT a unit - Move,
## Stop, Sell. Anything that builds, upgrades or sends takes the unit's icon
## instead and leaves this empty; see icon_texture().
@export var icon: Texture2D

@export_group("Input")
@export var targeting: Targeting = Targeting.IMMEDIATE
## Which square of the command card this claims, counting from 0 at the top
## left and running left to right, then down.
##
## The slot is the whole of the hotkey question. The card is a grid and the key
## is read off the POSITION, WC3 grid style, so an ability names where it sits
## and never which key it answers to. That also keeps the key stable when the
## grid is relaid out or a row of letters is swapped for another layout.
##
## AUTO_SLOT drops it into the first free square instead, which is what an
## entry with no key worth pressing wants - a passive is only ever read.
## Two abilities on the same card claiming the same slot is an authoring
## mistake: the panel reports it and moves the loser somewhere free.
##
## An ability that has taken a key of its OWN still names a square here, since
## it still has to be drawn somewhere - but the letter on that square is no
## longer what presses it. See hotkey_action and slot_override below.
@export var slot: int = AUTO_SLOT
## A key of this ability's OWN, off the grid, instead of the letter its square
## would give it.
##
## The rare exception to everything the slot comment above says, and it stays
## rare on purpose: it is for the handful of commands that mean the same thing
## on every card a player ever opens, which are reached for by NAME rather than
## by position. Everything else is a square and nothing but a square - there
## are hundreds of abilities and twelve squares, which is why the grid exists.
##
## Null leaves the ability on the grid. The action itself is shared, so several
## abilities may name one and answer to one key - see HotkeyAction.
@export var hotkey_action: HotkeyAction
## Square this ability takes AHEAD of anything else that wants it, or AUTO_SLOT
## to claim its slot the ordinary way.
##
## The companion to hotkey_action, and only useful with one. An ability whose
## key no longer comes from its position can be put anywhere on the card
## without its key moving - but the square it wants is usually a square the
## grid has already promised to somebody, so wanting it is not enough. This is
## how it TAKES one: whatever claimed the same square is moved to the next free
## one, wrapping round the card, and a card with nowhere left to move it to is
## reported as the authoring mistake it is.
##
## The pushed ability KEEPS ITS KEY, because a key belongs to the square an
## ability CLAIMED rather than to the square it sits on - see
## UnitPanel._letter_for. Nothing else on the card moves either: only the one
## ability that wanted this square is displaced, and only if it wanted it.
## Spending a square this way costs the card a square, never a key.
@export var slot_override: int = AUTO_SLOT
## Whether holding the slot's key fires the ability over and over, ramping up
## to a capped rate. Off by default and deliberately opt-in: repeating Sell or
## Cancel by leaning on a key would be a disaster, while repeating a send is
## exactly what a player wants when dumping a full reserve.
@export var repeat_on_hold: bool = false


## Runs the ability. Stateless: everything it needs comes in as arguments.
@abstract func execute(unit: Unit, target: AbilityTarget) -> void


## Whether this unit can use the ability right now. Drives the greyed out
## state of its slot, and later covers gold cost and tech requirements.
func can_execute(unit: Unit) -> bool:
	return unit != null


## Whether this ability is an ORDER - something the unit goes off and does,
## which therefore takes time, can be CHAINED behind another with shift, and
## wipes the chain when it is given without one.
##
## False by default and opt-in, deliberately. Nearly every entry on a card is
## not an order at all: a toggle, a sale, a reading of a range, a send. Those
## run the instant they are pressed, so there is nothing to queue and nothing
## about them that should throw a plan away - pressing Prioritize must not cost
## a tower the four creeps it was told to shoot.
##
## The three that answer yes are the three a player actually chains: Move,
## Attack and Build. See game_rules.md under Controls.
func is_queueable() -> bool:
	return false


## Whether a unit may be given this order as a QUEUED one, when its turn
## eventually comes round.
##
## The same question as can_execute for everything but a BUILD, and the
## difference there is the whole reason this exists: a tower is paid for when
## the builder reaches it rather than when the button was pressed, so a chain
## of five towers on one tower's worth of gold is a legal thing to ask for.
## can_execute still answers the gold question, because that is what greys the
## button and what refuses a plain order.
func can_queue(unit: Unit) -> bool:
	return can_execute(unit)


## Whether the task this order started has finished, so the chain may move on.
##
## Asked every tick of the head of a queue, and TRUE by default: an ability
## that is not an order does its whole job inside execute(), so by the time
## anything asks, it is over. Only the three orders answer anything else, and
## each one owns its own definition of done - a walk arrives, a build STARTS
## (the builder is free the moment it does, it never constructs), and an attack
## ends when its target dies.
##
## The target comes in rebuilt rather than remembered, so a queued attack whose
## creep somebody else killed sees a null and answers yes.
func is_task_complete(_unit: Unit, _target: AbilityTarget) -> bool:
	return true


## Keeps a running task pointed the right way, once per tick, for as long as it
## is the head of the chain.
##
## Nothing by default, which is right for a walk: move_to was given a point and
## the point does not move. It is Attack that needs it - a unit closing on a
## creep has to keep re-aiming at where that creep is NOW, and an attack-move
## has to notice the moment something wanders into reach.
func advance_task(_unit: Unit, _target: AbilityTarget, _delta: float) -> void:
	pass


## The square this ability wants, however it asked for one. Asked by the panel
## rather than reading either export, so there is one answer to the question.
func card_slot() -> int:
	if slot_override == AUTO_SLOT:
		return slot
	return slot_override


## Whether that square is a claim the rest of the card has to give way to.
func claims_slot_first() -> bool:
	return slot_override != AUTO_SLOT


## The key this ability answers to instead of a grid letter, drawn on its slot
## and in its tooltip. Empty when the grid decides, which is nearly always.
##
## Empty is also what an ability with an action bound to NOTHING answers -
## shipped unbound, or cleared by the player - and that is the same answer on
## purpose: with no key of its own it is back on the grid like everything else,
## and one empty string is what every caller has to handle either way.
func custom_hotkey_label() -> String:
	if hotkey_action == null:
		return ""
	return hotkey_action.label()


## Abilities that a SUBMENU ability puts on the card. Empty for everything else.
func submenu_abilities() -> Array[UnitAbility]:
	var empty: Array[UnitAbility] = []
	return empty


## Stats resources this ability names, so a walk of the content graph can
## follow it and find the abilities on the far side.
##
## A build ability names its tower, a send names its creep, and both of those
## carry command cards of their own. Empty for an ability that names nothing.
## Used by AbilityRegistry; deliberately explicit rather than duck typed, so a
## new ability that reaches something has to say so.
func reached_stats() -> Array[UnitStats]:
	var empty: Array[UnitStats] = []
	return empty


## Number drawn in the corner of the slot, or -1 for nothing. Sends draw their
## remaining stock here, and a future charged ability draws its charges.
##
## Takes the unit because the count is per unit, never per ability: two players
## share this very resource and must not share a count.
func charge_count(_unit: Unit) -> int:
	return -1


## The picture a slot showing this ability should draw.
##
## A method rather than the export straight, because the answer is not always
## the ability's own: one that produces a UNIT shows that unit, which lives on
## the unit's stats and is authored once there. Everything else answers with
## what it was given.
func icon_texture() -> Texture2D:
	return icon


## Whether this ability is a TOGGLE that is currently switched on, which the
## slot draws as a lit square. False for everything that is not a toggle, which
## is nearly everything.
##
## Takes the unit for the same reason charge_count() does: the setting is per
## unit and this resource is shared, so two towers of one type must be able to
## be set differently.
func is_toggled_on(_unit: Unit) -> bool:
	return false


## Which of this ability's own OPTIONS the unit is currently set to, or -1 for
## an ability that offers none - which is nearly all of them.
##
## The companion to is_toggled_on() for an ability that cycles through several
## answers rather than two. Takes the unit for the same reason everything else
## in this family does: the setting is per unit and this resource is shared, so
## two towers set differently must read differently.
##
## An index rather than the thing chosen, because the index is what crosses the
## wire - a client is TOLD which option its tower is on, exactly as it is told
## which way the Prioritize toggle is set. See Building.ability_choice.
func choice_index(_unit: Unit) -> int:
	return -1


## How ready the next charge is, 0 to 1, driving the slot's cooldown sweep.
## 1 means nothing to wait for, which is why anything without charges says so.
func charge_progress(_unit: Unit) -> float:
	return 1.0


## Seconds this unit still has to wait before the ability can be used AT ALL,
## drawn as a countdown across the middle of its slot. Negative for anything
## that is not waiting on a clock, which is nearly everything.
##
## Deliberately not charge_progress(): that is a sweep over a reserve that is
## refilling and will refill again, this is the one-off wait before an ability
## exists for this player. A send counts down its creep's start delay.
##
## Takes the unit for the same reason charge_count() does - the wait is per
## unit and this resource is shared.
func lockout_seconds(_unit: Unit) -> float:
	return -1.0


## Everything the hover tooltip shows, as data rather than as a laid out
## string, so the layout and the colours stay in one place instead of being
## rebuilt by every ability that has a number to add.
##
## Subclasses call super() and then fill in what they know: a send adds the
## price, the income and the creep's own stats, a tower build adds its cost.
##
## The hotkey letter comes IN rather than being read off this resource, since
## the card position is what decides it and only the slot drawing this ability
## knows where it landed.
##
## The UNIT comes in for the reason charge_count() takes one: this resource is
## every tower of its type at once, so anything a tooltip says about the tower
## it is sitting on - a setting that tower is on, a bonus it has grown - can
## only be read off the unit. Null for a tooltip with nobody behind it, and
## nearly every ability ignores it.
func tooltip_data(hotkey_label: String = "",
		unit: Unit = null) -> AbilityTooltipData:
	var data: AbilityTooltipData = AbilityTooltipData.new()
	data.title = display_name
	data.hotkey = hotkey_label
	data.description = description_text(null if unit == null else unit.stats)
	return data


## The authored description with every {placeholder} in it replaced by the
## number it names.
##
## THE NUMBER IS NEVER TYPED INTO THE TEXT. A description that says "steals 2
## lives" is a second copy of a figure that really lives on a stats file, and
## the day somebody changes the file the card goes on saying 2 - silently, with
## nothing to catch it. So the .tres writes "{lives}" and this fills it in from
## whatever the unit is actually carrying.
##
## The generated lines every passive already builds - CreepPassive.effect_text
## and TowerPassive.effect_text - are the same rule reached the other way: they
## have so many numbers that a sentence assembled from them is easier to read
## than a sentence full of braces. This is for the handful of descriptions that
## are mostly prose with one figure in them.
##
## A placeholder with nothing behind it is left standing rather than blanked,
## so an unwired one is visible in play instead of reading as a finished
## sentence with a hole in it.
func description_text(context: UnitStats = null) -> String:
	var values: Dictionary = description_values(context)
	if values.is_empty() || !description.contains("{"):
		return description

	var text: String = description
	for key: String in values:
		text = text.replace("{%s}" % key, str(values[key]))
	return text


## What this ability's placeholders stand for, as name -> value.
##
## Takes the stats of the unit the description is being shown FOR, because
## every value worth placeholdering belongs to that unit rather than to this
## resource - which is shared, and is the whole reason the number cannot simply
## be stored here. Empty for the great majority of abilities, which have no
## placeholder in their text at all.
func description_values(_context: UnitStats = null) -> Dictionary:
	return {}


## Plain text fallback, used when the rich tooltip cannot be built. Godot also
## needs this non-empty for a slot to show any tooltip at all.
func tooltip_text(hotkey_label: String = "") -> String:
	var title: String = display_name
	if !hotkey_label.is_empty():
		title = "%s  (%s)" % [display_name, hotkey_label]
	if description.is_empty():
		return title
	return "%s\n%s" % [title, description]


## Reports every scene path this ability reaches that does not resolve. The
## base ability reaches none; the ones that spawn something override this.
##
## seen is threaded through so a stats resource on two cards is checked, and
## reported, exactly once.
func validate(_seen: Dictionary) -> bool:
	return true


## Whether this ability changes only what THIS machine sees, and so must never
## become a network command.
##
## The line is the one multiplayer.md already draws: an order is intent the
## server decides on, while the build ghost, the selection, the order markers
## and the range overlay are feedback that never leaves the machine. Toggling
## the grid overlay is the same kind of thing - the server has no grid, and
## another player has no business being told about yours.
##
## False by default, deliberately: an ability that forgets to answer this ends
## up validated by the server, which is the safe way round.
func is_local_only() -> bool:
	return false


## Whether arming this ability should show the reach of every selected unit.
## True only for Attack, which is the one order where range decides whether
## the order can be given at all.
func shows_attack_range() -> bool:
	return false


## The radius of ground this ability covers around its own unit, in cells, or 0
## for one that covers none - which is nearly all of them.
##
## What Show Ranges draws in its second colour, and the reason it is a question
## asked of every ability rather than a list kept somewhere: the number stays on
## the resource that USES it, so an aura that is retuned cannot end up drawn at
## the radius it used to have.
##
## HAND PICKED, deliberately. Answering is opting in, and only the abilities
## whose radius a player has to place a tower against answer at all - an aura,
## a heal, a spread. An attack's splash does NOT: it lands where the shot
## lands, so a ring around the tower would be describing the wrong thing.
##
## Only a radius centred on the UNIT belongs here. An ability that reaches a
## ring around its TARGET has no circle to draw until it has one.
##
## Takes the unit for the reason charge_count() does - this resource is every
## tower of its type at once, and a tier that has no aura at all is the same
## resource as one that has.
func display_radius(_unit: Unit) -> float:
	return 0.0
