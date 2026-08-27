class_name PlayerTech
extends RefCounted

## What one player has researched, and what they can still take back.
##
## Lives on PlayerState next to their gold, because it is exactly that kind of
## thing: per player, owned for the rest of the match, and handed down from the
## server rather than worked out locally.
##
## It holds no RULES. Whether a technology may be bought, what it costs and
## whether the undo window is still open are TechManager's, in the same way
## PlayerState holds the gold while the abilities decide what may be spent.
## This only remembers.
##
## No signal of its own, deliberately: the Research Center polls its squares
## the way a command slot polls its ability, because availability moves with
## gold as much as with what is owned and a signal per source would mean every
## new caller having to remember to wire itself up.
##
## The undo HISTORY is authority side and a client never has one: it is told
## how many ticks its Undo button has left and nothing more, because it has
## nothing to undo with. Same split as everywhere else - the server owns what
## happened, the client is told what to draw.

## tech_id -> true for everything owned. A set rather than an array, because
## the question asked of it a thousand times is "do I have this one".
var _owned: Dictionary = {}
## Presses still inside their undo window, oldest first. Authority only.
var _history: Array[TechPurchase] = []
## Ticks left on the newest press, or 0 when there is nothing to undo. Written
## by the authority every tick and sent down, so a client's button greys itself
## at the moment the server would start refusing.
var _undo_ticks_left: int = 0


func has(tech_id: int) -> bool:
	return _owned.has(tech_id)


## How many technologies this player has bought, which is what decides the
## price of the next one (unit_data.md 2.2).
func owned_count() -> int:
	return _owned.size()


## Everything owned, ascending. Ascending because it is what goes over the wire
## and what two machines compare.
func owned_ids() -> PackedInt32Array:
	var ids: Array = _owned.keys()
	ids.sort()
	return PackedInt32Array(ids)


func undo_ticks_left() -> int:
	return _undo_ticks_left


func can_undo() -> bool:
	return _undo_ticks_left > 0


# --- authority ------------------------------------------------------------

func grant(tech_id: int) -> void:
	_owned[tech_id] = true


func revoke(tech_id: int) -> void:
	_owned.erase(tech_id)


## Remembers a press so it can be taken back. Newest last.
func push_purchase(record: TechPurchase) -> void:
	if record == null:
		return
	_history.append(record)


## The newest press still inside its window, taken off the history, or null
## when there is nothing left to take back.
func pop_purchase(tick: int) -> TechPurchase:
	if _history.is_empty():
		return null

	var newest: TechPurchase = _history.back()
	if !newest.is_live(tick):
		return null
	_history.pop_back()
	return newest


## Closes every window at once. What starting a build or an upgrade does: the
## gold is committed from that moment, so the tech choice behind it is too.
func forget_history() -> void:
	_history.clear()
	_undo_ticks_left = 0


## Drops presses whose window has closed and republishes what is left, so the
## number a client is sent is never a tick stale. Runs every tick on the
## authority.
func expire_history(tick: int) -> void:
	while !_history.is_empty() && !_history[0].is_live(tick):
		_history.pop_front()

	if _history.is_empty():
		_undo_ticks_left = 0
	else:
		_undo_ticks_left = _history.back().ticks_left(tick)


# --- client ---------------------------------------------------------------

## What the server says is owned and how long the Undo button has left. Set
## rather than earned, exactly like PlayerState.set_replicated: these values
## have already been through the rules once and must not go through them a
## second time here.
func set_replicated(ids: PackedInt32Array, undo_ticks: int) -> void:
	_undo_ticks_left = undo_ticks
	if !_differs_from(ids):
		return

	_owned.clear()
	for id in ids:
		_owned[id] = true


## Whether the set that arrived is a different set from the one already held.
## Sizes first, because the snapshot repeats the same list twenty times a
## second and rebuilding the dictionary each time would be the only work this
## class ever does.
func _differs_from(ids: PackedInt32Array) -> bool:
	if ids.size() != _owned.size():
		return true
	for id in ids:
		if !_owned.has(id):
			return true
	return false
