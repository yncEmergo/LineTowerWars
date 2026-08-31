class_name StatusBar
extends GridContainer

## The row of debuff icons under the stat lines in the unit panel.
##
## Two rows of squares, reserved whether or not anything fills them, so the
## stat lines above never move as a creep picks debuffs up and loses them
## again. Deliberately far more squares than the game can put on one unit: the
## alternative to a fixed reserve is a panel that changes height, which is the
## one thing the layout cannot do.
##
## Shown for a SINGLE selected unit only, and never while that unit is busy
## with a countdown - the panel says one thing at a time, and a tower being sold
## is what it is saying then. UnitPanel owns both of those rules; this only
## fills the squares.
##
## Squares are claimed once and refilled, exactly as the command card's are, so
## nothing churns as effects come and go.

## How often the row is re-read, in seconds.
##
## Not every frame: `entries()` builds a record per effect, and a countdown
## written in whole seconds cannot show more than this anyway. Slow enough to
## cost nothing, fast enough that a stun landing is on screen before a player
## could notice it was not.
const REFRESH_SECONDS: float = 0.1

@export_group("References")
@export var _icon_scene: PackedScene

@export_group("Settings")
## How many rows of squares to reserve. The width comes from `columns`, which is
## the GridContainer's own.
@export var reserved_rows: int = 2

var _icons: Array[StatusIcon] = []
## The unit whose debuffs are drawn, or null when nothing is selected.
var _unit: Unit = null
var _since_refresh: float = 0.0
## How many effects the last overflow reported, so the same one is not written
## out again on every refresh. 0 when the row is not overflowing.
var _overflowed: int = 0


func _ready() -> void:
	clear()


## Claims the squares the first time the row is asked to draw anything.
##
## Built lazily rather than in _ready, because Godot refuses to give a node a
## child while that node is still setting its own up - the same reason a unit's
## components build what they need on first use.
func _ensure_icons() -> void:
	if !_icons.is_empty():
		return
	if _icon_scene == null:
		Log.err("StatusBar has no status icon scene assigned, it will stay empty")
		return

	for index in range(maxi(1, columns) * maxi(1, reserved_rows)):
		var icon: StatusIcon = _icon_scene.instantiate() as StatusIcon
		if icon == null:
			Log.err("Status icon scene does not have a StatusIcon script")
			return
		icon.name = "StatusIcon%d" % index
		add_child(icon)
		_icons.append(icon)


## Points the row at a unit and fills it at once, so a debuff already running is
## on screen the moment it is selected rather than a tenth of a second later.
func show_unit(unit: Unit) -> void:
	_ensure_icons()
	_unit = unit
	_since_refresh = 0.0
	_request_watch()
	_refresh()


func clear() -> void:
	_unit = null
	_request_watch()
	for icon in _icons:
		icon.clear()


## Polled rather than driven by a signal, for the reason the armour line above
## it is: a debuff is applied and worn off by a dozen different passives and by
## the server's own snapshot, and a signal per source would mean every new one
## having to remember this panel.
func _process(delta: float) -> void:
	# In the TREE rather than this node's own flag, so a row left switched on
	# under a hidden panel stops asking a creep what is on it.
	if !is_visible_in_tree() || _icons.is_empty():
		return

	_since_refresh += delta
	if _since_refresh < REFRESH_SECONDS:
		return
	_since_refresh = 0.0
	_refresh()


func _refresh() -> void:
	_ensure_icons()
	var entries: Array[StatusEntry] = _entries()
	for index in range(_icons.size()):
		if index < entries.size():
			_icons[index].show_entry(entries[index])
		else:
			_icons[index].clear()

	# Once per overflow rather than ten times a second while one is on screen.
	# This row refreshes on a timer, so an unguarded line here is a stream
	# rather than a report - and towers reach it far more easily than creeps
	# ever did, since a tower standing between two technology discs carries a
	# row per number both of them lend it.
	if entries.size() > _icons.size():
		if _overflowed != entries.size():
			_overflowed = entries.size()
			Log.info("More debuffs on a unit than the panel has squares", {
				"effects": entries.size(),
				"squares": _icons.size(),
			})
	else:
		_overflowed = 0


## What is on the shown unit right now, from whichever source this machine has.
##
## The question itself lives on StatusEntry, because the armour line above this
## row asks it too and the two must never answer differently: a row saying
## three points have been eaten over a line saying they have not is worse than
## either being wrong alone.
##
## TOWERS FILL THIS TOO, which they did not used to: what a creep has cursed
## one with, and everything a technology disc standing beside it is lending it.
## Nothing here had to change for that - the question is asked of the unit and
## a tower now answers it - which is the whole point of it living on
## StatusEntry rather than here.
func _entries() -> Array[StatusEntry]:
	return StatusEntry.for_unit(_unit)


## Tells the server which unit's debuffs this client needs, and to stop sending
## when nothing is selected. Does nothing at all on the authority.
func _request_watch() -> void:
	var id: int = MatchSession.NO_UNIT
	if _unit != null && is_instance_valid(_unit):
		id = _unit.unit_id
	Replication.request_watch(id)
