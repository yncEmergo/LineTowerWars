class_name DiveAbility
extends UnitAbility

## Sends the Phoenix out along a line and back, burning whatever it passes over.
##
## The only ACTIVE ability any creep in the game has. unit_data.md 6.6:
## "Phoenix dives forward and back in an arc up to 700 distance in the targeted
## direction, dealing 150 Spell Damage per sec for 4 sec. 16 sec cooldown. The
## dive can be stopped with the stop ability; if stopped, the Phoenix
## regenerates its armour to full."
##
## GROUND targeting, so pressing it arms the order and the next left click
## names the direction - the same shape Move has, and it gets the same cancel
## square on the emptied card for free.
##
## ONLY THE DIRECTION IS TAKEN, exactly as the Beastmaster's link does: the
## reach is the ability's own number and clicking further away does not send
## the Phoenix further. Which is the honest reading of "up to 700 distance in
## the targeted direction", and it is also what stops a player aiming a dive by
## measuring rather than by looking.
##
## NOT LOCAL ONLY. Where the Phoenix goes decides what takes damage, so this
## crosses the wire like every other order and the server runs it - see
## Commands.submit and multiplayer.md. The dive itself lives on the CREEP, in
## CreepDive, because this resource is every Phoenix on the field at once.
##
## STOPPING IT IS REAL COUNTERPLAY and belongs to the OWNER rather than to the
## defender: a dive aimed into a maze that turned out to be worse than it
## looked can be called off, and the Phoenix gets its armour back for the
## trouble. See Creep.cancel_dive(), which StopAbility reaches through the
## ordinary halt every unit already answers.

@export_group("Dive")
## How far out the arc reaches at its turn, in player cells. The source states
## 700, which snaps to 5.5 at the quarter every reach in the game is
## stated in - unit_data.md 3.
@export var reach_cells: float = 5.5
## Seconds the whole dive takes, out and back.
@export var duration_seconds: float = 4.0
## Seconds before it may be dived again.
@export var cooldown_seconds: float = 16.0

@export_group("Damage")
## Spell damage dealt per second to every tower under the Phoenix.
@export var damage_per_second: float = 150.0
## How far that reaches from the Phoenix, in player cells.
##
## `?` A CHOICE. The source states the damage and the duration and says nothing
## at all about how wide the trail is, so this is authored rather than read. It
## is deliberately narrow: a dive is a line drawn through a maze, and a wide
## one would be an area attack that happened to travel.
@export var damage_radius_cells: float = 1.5


func execute(unit: Unit, target: AbilityTarget) -> void:
	var creep: Creep = unit as Creep
	if creep == null || target == null || !target.has_position:
		return
	if !creep.active_ability.is_ready() || creep.is_diving():
		return

	if !creep.begin_dive(target.position, reach_cells, duration_seconds,
			damage_per_second, damage_radius_cells):
		return
	creep.active_ability.start_cooldown(cooldown_seconds)


func can_execute(unit: Unit) -> bool:
	var creep: Creep = unit as Creep
	if creep == null || !creep.is_alive() || creep.is_diving():
		return false
	return creep.active_ability.is_ready()


## The wait, drawn as a countdown across the slot. Negative when there is none,
## which is what everything not on a clock answers.
func lockout_seconds(unit: Unit) -> float:
	var creep: Creep = unit as Creep
	if creep == null || creep.active_ability.is_ready():
		return -1.0
	return creep.active_ability.cooldown()


## Lit while the Phoenix is actually in the air, so a player who has lost track
## of it in a maze can read off the card that the dive is still running.
func is_toggled_on(unit: Unit) -> bool:
	var creep: Creep = unit as Creep
	return creep != null && creep.is_diving()


## The reach, drawn as a circle while the order is armed, so a player aiming
## one can see how far it actually goes rather than guessing from the click.
func display_radius(_unit: Unit) -> float:
	return reach_cells


func tooltip_data(hotkey_label: String = "",
		unit: Unit = null) -> AbilityTooltipData:
	var data: AbilityTooltipData = super(hotkey_label, unit)
	data.description = ("Dives out along the aimed direction and back, dealing"
		+ " %s spell damage a second to towers it passes over. Stopping the dive"
		+ " restores its armor in full.") % StringUtil.trim_number(damage_per_second)
	data.add_stat("Reach", "%s" % StringUtil.trim_number(reach_cells))
	data.add_stat("Duration", "%ss" % StringUtil.trim_number(duration_seconds))
	data.add_stat("Cooldown", "%ss" % StringUtil.trim_number(cooldown_seconds))
	return data
