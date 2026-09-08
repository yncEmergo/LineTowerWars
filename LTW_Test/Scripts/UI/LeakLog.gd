class_name LeakLog
extends VBoxContainer

## The running account of what is happening BETWEEN players, stacked above the
## command card. Newest at the bottom, older ones pushed up, gone after a few
## seconds.
##
## Two things reach it today. A LEAK - who is taking lives off whom - and a
## DEPARTURE, a player who is gone and whose lane the match is carrying on
## without (D13, D14). They share this stack rather than getting one each
## because they are the same kind of thing to a reader: a sentence about
## somebody else that is worth a glance and then worth forgetting.
##
## **Only the local player's own leaks.** A life is stolen rather than lost
## (game_rules.md), so every leak has two ends, and the two that matter are the
## ones you are at. A twelve player free for all generates a leak somewhere
## almost every second and a log that showed all of them would say nothing.
##
## A DEPARTURE is not filtered that way, and deliberately: there is one of them
## per player per match, it changes what the rest of the match is, and "who is
## still in this" is worth knowing about a player you never share a creep with.
##
## The server tells every client about every leak - see
## ReplicationService.report_leak - and the filter is here rather than there
## for exactly one reason: a spectator's HUD is the same HUD, and the day one
## exists it wants the whole ledger without the server having to learn about
## it.
##
## GROWS UPWARD. The container is anchored to its own bottom edge, so adding a
## line at the end of the box lifts everything already in it by a row rather
## than pushing the newest one down the screen. The command card underneath
## never moves.
##
## Nothing here simulates. It is told what happened and draws it, and a client
## that missed the message simply never shows that line - see the note on
## report_leak being reliable.

@export_group("Settings")
## The line prefab. A node's own prefab stays a plain PackedScene export.
@export var _message_scene: PackedScene

var _config: PresentationConfig:
	get:
		return References.presentation_config


func _ready() -> void:
	# Kept running while the world is held still: the draft pauses the match,
	# and a message caught by that would otherwise hang there at full strength
	# until somebody picked a technology.
	process_mode = Node.PROCESS_MODE_ALWAYS
	Replication.leak_reported.connect(_on_leak_reported)
	# MatchStart rather than a channel of its own: under lockstep a drop rides
	# a turn as a PLAYER_LEFT order and every peer emits this signal locally
	# when it applies one, so both machines write this line on the same turn
	# without anything new crossing the wire.
	#
	# Under the REPLICATION path it only ever fires on the server, so this line
	# is a lockstep-only thing. That is not a hole to plug here: it is the same
	# asymmetry MatchStartService._announce_drop describes, and the fix for it
	# is that path's, not this one's.
	MatchStart.player_dropped.connect(_on_player_dropped)


## Ages every line and drops the ones that have finished fading.
##
## On the RENDER frame rather than the tick, deliberately: this is presentation
## and nothing about it may reach the simulation, so it fades at whatever rate
## the machine draws at rather than at 20 Hz.
func _process(delta: float) -> void:
	for child in get_children():
		var message: LeakMessage = child as LeakMessage
		if message != null && message.advance(delta):
			_drop(message)


## One leak, as the authority saw it. Silently ignores everything the local
## player is not part of, which is most of them in a big match.
func _on_leak_reported(thief: int, victim: int, lives: int) -> void:
	var session: MatchSession = References.match_session
	if session == null:
		return

	var is_gain: bool = session.is_local_player(thief)
	if !is_gain && !session.is_local_player(victim):
		return
	var kind: LeakMessage.Kind = LeakMessage.Kind.GAIN if is_gain else LeakMessage.Kind.LOSS
	_write(victim if is_gain else thief, kind, lives)


## A player is gone for good and the match is carrying on without them.
##
## The LOCAL player's own slot is skipped. It can arrive here - a machine that
## stopped sending turn words is dropped by the relay while still receiving
## them, so it applies the order announcing its own departure - and "You have
## left the match." is not news to the person reading it. What that player
## needs instead is the reason and a way out, which is StallPanel's job.
func _on_player_dropped(slot: int) -> void:
	var session: MatchSession = References.match_session
	if session == null || session.is_local_player(slot):
		return
	_write(slot, LeakMessage.Kind.DEPARTED, 0)


## Adds the line, or adds to the one already at the bottom.
##
## Only the BOTTOM line is ever merged into. Merging into an older one would
## reorder the log - a line would suddenly grow above two newer ones - and the
## order is the only thing saying which of these just happened.
##
## Whether a kind merges at all is LeakMessage's answer rather than a test
## here, because it is a fact about what the sentence MEANS: see
## LeakMessage.counts_lives.
func _write(other_slot: int, kind: LeakMessage.Kind, lives: int) -> void:
	if _message_scene == null:
		return

	var key: StringName = LeakMessage.message_key(other_slot, kind)
	var newest: LeakMessage = _newest()
	if newest != null && newest.key == key:
		# A kind that counts adds to the number; one that does not simply
		# starts its clock again, so the same notice arriving twice is one
		# line held a little longer rather than the same sentence stacked.
		if LeakMessage.counts_lives(kind):
			newest.add_lives(lives)
		else:
			newest.refresh()
		return

	var message: LeakMessage = _message_scene.instantiate() as LeakMessage
	if message == null:
		Log.err("LeakLog message prefab root does not have a LeakMessage script")
		return
	add_child(message)
	message.show_notice(other_slot, kind, lives)
	_trim()


func _newest() -> LeakMessage:
	var count: int = get_child_count()
	if count == 0:
		return null
	return get_child(count - 1) as LeakMessage


## Throws away whatever no longer fits, oldest first.
##
## Immediately and without a fade, which is the point: the stack has a ceiling
## so that a bad wave cannot walk the log up the screen, and a line being
## squeezed out by newer ones has already been overtaken by them.
func _trim() -> void:
	var config: PresentationConfig = _config
	var ceiling: float = 190.0 if config == null else config.leak_max_height
	while get_child_count() > 1 && _stack_height() > ceiling:
		var oldest: LeakMessage = get_child(0) as LeakMessage
		if oldest == null:
			return
		_drop(oldest)


## How tall the box wants to be, measured off the children rather than read off
## the container: a line added this frame has not been laid out yet, and the
## container's own size still describes the stack without it.
func _stack_height() -> float:
	var total: float = 0.0
	var lines: int = 0
	for child in get_children():
		var message: LeakMessage = child as LeakMessage
		if message == null:
			continue
		total += message.get_combined_minimum_size().y
		lines += 1
	return total + float(maxi(0, lines - 1)) * float(get_theme_constant(&"separation"))


## Out of the tree at once rather than only queued, so the very next line
## measures a stack this one is no longer in - queue_free is deferred and would
## leave it counted for the rest of the frame.
func _drop(message: LeakMessage) -> void:
	remove_child(message)
	message.queue_free()
