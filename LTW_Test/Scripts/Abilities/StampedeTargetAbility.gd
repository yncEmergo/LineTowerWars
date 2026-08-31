class_name StampedeTargetAbility
extends UnitAbility

## Points a Beastmaster's beast at one of your own towers, and leaves it
## pointed there.
##
## unit_data.md 4.7: the whole Beastmaster line sends its beast at whatever its
## attack landed on, and this is the one way to override that. LINKING is what
## makes the line playable in a real maze - a tower shooting the creep in front
## of it sends the beast across the corner it is standing on, where linking it
## to a tower further down aims the beast along the lane instead.
##
## ONLY THE DIRECTION IS TAKEN. Distance has nothing to do with it, so there is
## no range on the link at all: a tower on the far side of the maze and a tower
## one cell away aim the beast the same way, and the beast runs its own
## distance either way. That is why this refuses nothing for being far off, and
## why it is worth linking to something you never intend the beast to reach.
##
## LINKING TO ITSELF IS THE CLEAR. There is no second button and no toggle off:
## a Beastmaster aimed at itself has no direction to take from the link, so it
## goes back to aiming at what it is shooting. That is the source's own answer
## and it costs the card nothing.
##
## UNIT targeting, so pressing it arms the order and the next left click names
## the tower - the same shape Attack has, and it gets the same cancel square on
## the emptied card for free, because that is the panel's rule for anything
## waiting on a click rather than something this has to author.
##
## Not local only. Where the beast runs is simulation - it decides what takes
## damage - so this crosses the wire like any other order and the server sets
## its own copy. The link itself lives on the TOWER, in ActiveAbilityState,
## because it is per tower and this resource is shared by every Beastmaster on
## the field.

@export_group("Stampede Target")
## Seconds before the same tower may be re-aimed. Long on purpose: which way a
## Beastmaster faces is a decision about the shape of a maze, not something to
## be flicked back and forth per wave.
@export var cooldown_seconds: float = 60.0


## Aims the tower, or clears it when it was aimed at itself.
##
## The target is checked HERE rather than by the server's command check, which
## only ever asks who is acting and what is on their card. What is being aimed
## AT is this ability's own question, and it has exactly two answers: one of
## your own towers, or nothing.
func execute(unit: Unit, target: AbilityTarget) -> void:
	var tower: Building = unit as Building
	if tower == null || target == null:
		return

	var picked: Building = target.unit as Building
	if picked == null || picked.owner_player_id != tower.owner_player_id:
		return
	if !tower.active_ability.is_ready():
		return

	# Itself means "back to normal". Stored as NO_UNIT rather than as its own
	# id, so nothing downstream has to know about the special case.
	var linked: int = MatchSession.NO_UNIT if picked == tower else picked.unit_id
	tower.active_ability.set_link(linked)
	tower.active_ability.start_cooldown(cooldown_seconds)


func can_execute(unit: Unit) -> bool:
	var tower: Building = unit as Building
	if tower == null || tower.is_under_construction():
		return false
	return tower.active_ability.is_ready()


## Lit while the tower is aimed at something, so the card answers "is this one
## linked" without being hovered - which is the only way to tell from above,
## since the link draws nothing in the world.
func is_toggled_on(unit: Unit) -> bool:
	var tower: Building = unit as Building
	return tower != null && tower.active_ability.link() != MatchSession.NO_UNIT


## The wait, drawn as a countdown across the slot. Negative when there is none,
## which is what everything that is not on a clock answers.
func lockout_seconds(unit: Unit) -> float:
	var tower: Building = unit as Building
	if tower == null || tower.active_ability.is_ready():
		return -1.0
	return tower.active_ability.cooldown()


func tooltip_data(hotkey_label: String = "",
		unit: Unit = null) -> AbilityTooltipData:
	var data: AbilityTooltipData = super(hotkey_label, unit)
	data.add_stat("Cooldown", "%ss" % StringUtil.trim_number(cooldown_seconds))

	var tower: Building = unit as Building
	if tower == null:
		return data

	var linked: Unit = tower.active_ability.linked_unit()
	if linked == null || linked.stats == null:
		data.add_special("Linked to", "Nothing. The beast runs at whatever this"
			+ " tower is shooting.")
	else:
		data.add_special("Linked to", linked.stats.display_name)
	return data
