class_name TechPurchase
extends RefCounted

## One press of a Research Center button, kept only for as long as it can still
## be undone.
##
## A press rather than a technology, because one press does not always buy one
## thing: rolling a random Ultimate buys the four technologies that Ultimate
## needs, and undoing it has to give back all four and the whole price. So the
## record is the unit of undo, and it holds a list.
##
## The gold is stored rather than recomputed, and that is the point of the
## record: the price of a technology depends on how many were already owned
## when it was bought (unit_data.md 2.2), so a refund worked out afterwards
## would be a different number from the one that was charged.
##
## Authority side only. A client never holds one - it is told how long the undo
## window has left and nothing else, because it has nothing to undo WITH.

## Everything this press bought, in the order it was bought.
var tech_ids: PackedInt32Array = PackedInt32Array()
## What it cost altogether. 0 for a press that spent one of the free
## technologies, which is still undoable - the free one comes back.
var gold_paid: int = 0
## The simulation tick the undo window closes on. A tick rather than a
## timestamp, so the deadline means the same on every machine and survives a
## frame rate that does not.
var deadline_tick: int = 0


static func create(ids: PackedInt32Array, paid: int, deadline: int) -> TechPurchase:
	var record: TechPurchase = TechPurchase.new()
	record.tech_ids = ids
	record.gold_paid = paid
	record.deadline_tick = deadline
	return record


## Whether the window is still open on the given tick.
func is_live(tick: int) -> bool:
	return tick < deadline_tick


## Ticks left before it closes, floored at 0. What a client is sent, so its
## Undo button can grey itself without holding the record.
func ticks_left(tick: int) -> int:
	return maxi(0, deadline_tick - tick)
