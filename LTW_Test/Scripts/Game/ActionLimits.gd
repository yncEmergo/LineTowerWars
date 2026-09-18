class_name ActionLimits
extends RefCounted

## What ONE PLAYER is allowed to do right now, when that is less than the rules
## allow: which buttons, which cells, and whether the Research Center.
##
## Held on the player's own state as `PlayerState.limits`, and null there for
## every player in every match except the tutorial's student - null is "no
## limits", which is why nothing about an ordinary match changes and nothing in
## it has to know this exists.
##
## **It exists so a lesson can say "only this, only here" and mean it.** The
## tutorial hands a player exactly the gold a task needs, and that promise is
## only worth anything if the gold cannot be spent on something else: a player
## asked to build a row who upgrades a tower instead has no row and no gold,
## and a lesson that can be broken that way is one somebody will break.
##
## Asked in the places a player's intent turns into an order, and nowhere
## deeper:
##
##   the COMMAND CARD    a square that is not allowed is drawn dim - see
##                       CommandSlot - which is most of how a player is told
##   the CONTROLLER      a click or a key is not turned into an order at all
##   the ORDER ROAD      CommandService refuses it, which is the one that holds
##                       whatever the other two missed
##   the AREA            PlayerArea.can_place refuses a cell outside the set, so
##                       the ghost turns red there exactly as it does over a
##                       tower
##   the RESEARCH CENTER does not open, and a research order is refused
##
## A WHITELIST rather than a list of what is forbidden, because a lesson knows
## the few things it wants and cannot know every button the roster will ever
## grow. Anything that changes nothing in the world - a submenu, a passive, a
## presentation-only toggle - is always allowed: dimming the Build button would
## hide the tower the lesson is asking for.
##
## Offline only, like everything that sets the board for the tutorial. It is
## not replicated and not checksummed; a networked match never has one.

## Whether the ability list below is the whole of what may be pressed. False
## leaves every ability alone, for a limit that only locks the research.
var restricts_abilities: bool = false
## The abilities that may be used while restricts_abilities is on, besides the
## ones that change nothing - see is_free().
var abilities: Array[UnitAbility] = []
## Internal cells a tower's footprint may START on, as keys. Empty is anywhere.
##
## The top-left cell of a footprint, which is how a TowerLayout names one and
## how Building.cell stores it, so a blueprint's cells go straight in.
var build_cells: Dictionary = {}
## Whether the Research Center may be used.
var research: bool = true


## Whether this player may press this ability at all.
func allows(ability: UnitAbility) -> bool:
	if ability == null:
		return false
	if !restricts_abilities || is_free(ability):
		return true
	return ability in abilities


## Whether a tower may be started with its top-left cell here.
func allows_cell(cell: Vector2i) -> bool:
	return build_cells.is_empty() || build_cells.has(cell)


## Whether an ability changes nothing in the world, so no limit is ever needed
## on it: a submenu only swaps the card, a passive is only read, and a
## presentation toggle draws something on this machine alone.
static func is_free(ability: UnitAbility) -> bool:
	return ability.targeting == UnitAbility.Targeting.PASSIVE \
		|| ability.targeting == UnitAbility.Targeting.SUBMENU \
		|| ability.is_local_only()


## The limits on one player, or null for a player who has none - which is
## every player in an ordinary match.
static func of(player_id: int) -> ActionLimits:
	var manager: PlayerManager = References.player_manager
	if manager == null:
		return null
	var state: PlayerState = manager.state_for(player_id)
	return null if state == null else state.limits


## Whether a unit's owner may give it this order. The one question the card,
## the controller and the order road all ask.
static func permits(ability: UnitAbility, unit: Unit) -> bool:
	if ability == null || unit == null:
		return true
	var limits: ActionLimits = of(unit.owner_player_id)
	return limits == null || limits.allows(ability)


## Whether a player may use the Research Center.
static func permits_research(player_id: int) -> bool:
	var limits: ActionLimits = of(player_id)
	return limits == null || limits.research
