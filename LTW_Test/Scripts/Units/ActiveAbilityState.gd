class_name ActiveAbilityState
extends RefCounted

## What a tower's ACTIVE ability - the one a player presses - is currently
## doing: how long it still has to wait, and what it has been aimed at.
##
## Deliberately NOT Building.ability_state, which is the scratch space the
## tower's PASSIVES keep their own per-tower counters in. The difference is who
## reads it: a passive's counter is the server's business alone, and both of
## these are drawn on a card - the cooldown sweep on the slot, and the lit
## square that says the tower is aimed at something. So both cross the wire and
## both need the authority-or-replicated question answered in one place, which
## is what this object is.
##
## An OBJECT the tower owns rather than four more fields and six more methods
## on Building, which is already past gdlint's ceiling for both. Same shape
## CreepMana has, and the shape CLAUDE.md names as the intended fix for the
## rest of Building.
##
## ONE clock and ONE link per tower rather than one of each per ability, on the
## same grounds Building.replicated_ability_choice is one number: no tower in
## the roster carries two abilities that wait, and the day one does it needs a
## record of its own anyway.
##
## The link is a UNIT ID rather than a reference, exactly as a Command names
## its target by one: the tower it points at can be sold while the link stands,
## and an id resolves to null on its own rather than leaving a dangling node
## behind. It is also already the form the wire wants.

## Seconds left before the ability may be used again, on the AUTHORITY.
var cooldown_left: float = 0.0
## The unit this tower's ability is aimed at, on the AUTHORITY, or NO_UNIT.
var link_id: int = MatchSession.NO_UNIT

## The same two as the SERVER last reported them, and meaningful on a CLIENT
## only. A client runs no simulation, so nothing of its own ever advances the
## clock or answers the order that set the link - see Building's
## replicated_ability_choice, which is here for the same reason.
var replicated_cooldown: float = 0.0
var replicated_link: int = MatchSession.NO_UNIT


## Seconds still to wait, from whichever copy this machine is entitled to read.
## The one place that question is answered, so nothing drawing a cooldown has
## to know whether it is running the world or watching one.
func cooldown() -> float:
	if MatchSession.is_authority():
		return cooldown_left
	return replicated_cooldown


func is_ready() -> bool:
	return cooldown() <= 0.0


## Puts the ability back on the clock. Authority only, like every other change
## to the world: a client that started its own would grey a button the server
## still considers free.
func start_cooldown(seconds: float) -> void:
	if !MatchSession.is_authority():
		return
	cooldown_left = maxf(0.0, seconds)


## Counts one tick off the clock. Called by the tower that owns this, which
## already stands aside on a client.
func advance(delta: float) -> void:
	if cooldown_left <= 0.0:
		return
	cooldown_left = maxf(0.0, cooldown_left - delta)


## The unit this is aimed at, by id, from whichever copy this machine may read.
func link() -> int:
	if MatchSession.is_authority():
		return link_id
	return replicated_link


## The unit itself, or null - which is also the answer when the tower it named
## has since been sold, since a dead id resolves to nothing.
func linked_unit() -> Unit:
	var id: int = link()
	if id == MatchSession.NO_UNIT:
		return null
	var session: MatchSession = References.match_session
	if session == null:
		return null
	return session.unit_for(id)


## Aims the ability, or clears it with NO_UNIT. Authority only, for the reason
## start_cooldown is.
func set_link(id: int) -> void:
	if !MatchSession.is_authority():
		return
	link_id = id


## Handed down by the server, which is the only way either changes on a client.
func set_replicated(seconds: float, id: int) -> void:
	replicated_cooldown = maxf(0.0, seconds)
	replicated_link = id


## Takes over what the tier below carried. Called by the upgrade that replaced
## it, alongside the mana and the passives' own counters: an upgrade is the
## same tower with a bigger beast, so neither its wait nor what it was aimed at
## should be handed back for free.
func inherit(other: ActiveAbilityState) -> void:
	if other == null:
		return
	cooldown_left = other.cooldown_left
	link_id = other.link_id
