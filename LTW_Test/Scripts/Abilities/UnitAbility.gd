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
@export var slot: int = AUTO_SLOT
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


## How ready the next charge is, 0 to 1, driving the slot's cooldown sweep.
## 1 means nothing to wait for, which is why anything without charges says so.
func charge_progress(_unit: Unit) -> float:
	return 1.0


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
func tooltip_data(hotkey_label: String = "") -> AbilityTooltipData:
	var data: AbilityTooltipData = AbilityTooltipData.new()
	data.title = display_name
	data.hotkey = hotkey_label
	data.description = description
	return data


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
