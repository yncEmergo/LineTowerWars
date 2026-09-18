class_name TutorialWaves
extends RefCounted

## The waves of the lesson that is open: which have gone out, which creeps each
## one put in the lane, and how many of them are dealt with.
##
## A WAVE here is every TutorialWave entry sharing one delay - two entries with
## the same delay are one mixed wave, which is how a lesson authors Sheep and
## Skeletons arriving together. What the player is told is "waves killed", so
## that is the unit this counts in.
##
## A wave is KILLED once it has gone out and none of its creeps is still alive
## in the player's lane. A creep that leaked is gone from the lane too, and
## counts - the lesson is about the wave being over, and a leak is shown by the
## leak log and the lost life. Held by TutorialDirector, reset per lesson.

## Wave number -> the delay it goes out on, ascending.
var _delays: Array[float] = []
## Wave number -> the creeps it spawned so far.
var _members: Array[Array] = []
## Entry index in the lesson's list -> true once it has gone out.
var _sent: Dictionary = {}
var _entries: Array[TutorialWave] = []


## Starts over for a lesson's list of waves.
func reset(entries: Array[TutorialWave]) -> void:
	_entries = entries
	_sent.clear()
	_delays.clear()
	_members.clear()
	for entry: TutorialWave in entries:
		if entry != null && !(entry.delay_seconds in _delays):
			_delays.append(entry.delay_seconds)
	_delays.sort()
	for index in range(_delays.size()):
		_members.append([])


## Sends every entry whose delay has run out, through `spawn`, which takes a
## TutorialWave and answers the creeps it put in the lane.
func send_due(elapsed: float, spawn: Callable) -> void:
	for index in range(_entries.size()):
		var entry: TutorialWave = _entries[index]
		if entry == null || _sent.has(index) || elapsed < entry.delay_seconds:
			continue
		_sent[index] = true
		var creeps: Array = spawn.call(entry)
		_members[_delays.find(entry.delay_seconds)].append_array(creeps)


## How many waves the lesson has.
func total() -> int:
	return _delays.size()


## Whether every entry has gone out.
func all_sent() -> bool:
	return _sent.size() >= _entries.size()


## How many waves have gone out and are dealt with.
func killed(area: PlayerArea) -> int:
	if area == null:
		return 0
	var alive: Dictionary = {}
	for creep: Creep in area.creeps():
		if creep != null && is_instance_valid(creep) && creep.is_alive():
			alive[creep] = true

	var count: int = 0
	for wave in range(_delays.size()):
		if !_wave_sent(wave):
			continue
		var over: bool = true
		for member: Variant in _members[wave]:
			if is_instance_valid(member) && alive.has(member):
				over = false
				break
		if over:
			count += 1
	return count


func _wave_sent(wave: int) -> bool:
	for index in range(_entries.size()):
		var entry: TutorialWave = _entries[index]
		if entry != null && entry.delay_seconds == _delays[wave] && !_sent.has(index):
			return false
	return true
