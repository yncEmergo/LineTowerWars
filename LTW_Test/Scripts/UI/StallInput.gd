class_name StallInput
extends Node

## Keeps the ORDER UI awake while a lockstep stall holds the world still.
##
## **This is the most player-visible half of the sealed-stream cutover, and it
## is easy to miss entirely.** `MatchSession.hold` pauses the TREE, and Godot
## suppresses `_unhandled_input`, `_gui_input` and every button press on a
## paused node. So a stalled peer cannot click anything.
##
## That was harmless while everybody stalled together - there was nothing to
## click for, because nobody's world was moving - and it **defeats the whole
## design the moment a peer stalls alone**: that player would be frozen AND
## mute, watching a match they can no longer act on, while everyone else plays
## on. Under the sealed stream a peer stalling alone is the NORMAL case, so this
## is not an edge.
##
## Accepting an order mid-stall is newly safe precisely because no client names
## a turn any more. `Lockstep.schedule` sends the order bare, at press time, and
## the relay decides which turn it lands in - so an order given during a hold is
## an order given a few milliseconds earlier than the player would otherwise have
## managed, and nothing about the schedule depends on this machine's clock.
##
## **Only for a lockstep stall, and only when the sealed stream is on.** The two
## guards are separate and both matter:
##
## - the DRAFT also holds the world, and un-muting the command card during a
##   draft would let a player build while the draft is up. That is a rule change
##   and this is not the place for one, so the release happens only when
##   `lockstep` is the single holder
## - under the OLD gate a stall means every machine is waiting, so there is
##   nothing to be gained and the paired measurement across the flag stays honest
##
## Done from a node rather than in `match_hud.tscn` for exactly that reason: a
## `process_mode` written into the scene would apply to the draft and to both
## sides of the flag, which is three behaviours where one was wanted.

@export_group("References")
## The HUD's own order-taking nodes: the command card, the send bar, the action
## bar, the research centre and anything else a player gives an order through.
## Siblings in this scene, so a plain @export rather than References.
@export var _order_ui: Array[Node] = []

## Whether the order UI is currently released from the pause.
var _released: bool = false
## What each node's process_mode was before it was released, so restoring it
## cannot silently clobber a node that wanted something other than INHERIT.
var _restore: Dictionary = {}


func _ready() -> void:
	# Immune to the pause it exists to work around. Without this it would stop
	# with everything else and could never notice the stall had begun.
	process_mode = Node.PROCESS_MODE_ALWAYS


## On the render frame rather than the tick, because the tick is the thing that
## has stopped. A stall holds the physics loop of everything that is not
## PROCESS_MODE_ALWAYS, and the point of this is to react to a world that is not
## moving.
func _process(_delta: float) -> void:
	var wanted: bool = _should_release()
	if wanted == _released:
		return
	_released = wanted

	for node: Node in _nodes():
		if node == null:
			continue
		var id: int = node.get_instance_id()
		if wanted:
			_restore[id] = node.process_mode
			node.process_mode = Node.PROCESS_MODE_ALWAYS
		else:
			node.process_mode = _restore.get(id, Node.PROCESS_MODE_INHERIT)


## Whether a lockstep stall, and nothing else, is holding the world.
func _should_release() -> bool:
	var config: NetworkConfig = References.network_config
	if config == null || !config.sealed_stream:
		return false
	if !Lockstep.is_stalled():
		return false

	var session: MatchSession = References.match_session
	if session == null:
		return false
	# **The single holder, not merely one of them.** A draft holding the world
	# as well means the answer is no: the draft's mute is a rule and this must
	# not lift it.
	var holders: Array = session.holders()
	return holders.size() == 1 && holders[0] == &"lockstep"


## Everything that has to stay awake. The HUD's own nodes come from the scene;
## the two controllers live in `Main.tscn` and so cannot be reached by a
## NodePath from here, which is exactly what References is for.
func _nodes() -> Array[Node]:
	var out: Array[Node] = []
	out.append_array(_order_ui)
	out.append(References.command_controller)
	out.append(References.selection_controller)
	return out
