class_name ContentWarmer
extends RefCounted

## Loads every asset the match can spawn BEFORE the match starts, so that no
## turn ever pays for a first instantiation.
##
## ## Why this exists
##
## A resource names its scene by `res://` path and `UnitStats.scene()` loads it
## the first time something spawns one - synchronously, on the game thread. That
## is a deliberate and good rule (`CLAUDE.md`): a path costs nothing until
## something spawns from it, so reading a tower's gold cost does not drag its
## model, meshes and materials into memory.
##
## **Under lockstep ONE machine paying it is enough to freeze everybody.** In
## playtest 1 the guest stalled for 0.65-0.9 s the first time each kind of content
## was spawned - the first tower finishing construction, the first sheep, the
## first shot, the first upgrade - and the host, which was on time to within 10 ms
## every single time, simply waited. Both players saw the same freeze, which is
## why it read as a network problem and was not one at all.
## See `Findings/2026-09-06-playtest-1-freezes.md`.
##
## That is what makes warming worth doing even though the loading itself is FAST.
## On the machine this was written on the entire content graph loads in about half
## a second; on the tester's it cost a hundred times more per asset, most likely a
## first read of a freshly downloaded build being scanned. **A cost that varies by
## two orders of magnitude between machines cannot be judged from the fast one** -
## and it does not have to be, because the fix is the same either way: pay it on
## the load screen, where a player expects to wait, rather than mid-fight.
##
## ## What it warms, and how it knows
##
## Everything, because measurement said everything is cheap. The whole content
## graph is under 400 scenes and loads in about half a second cold on the machine
## this was written on, against roughly 810 ms the load screen already spends on
## `Main.tscn`. The original plan split the set by REACHABILITY - the early roster
## on the load screen, upgrade tiers trickled in during play while nobody can
## afford them - and that plan was thrown away when the number came in. There is
## nothing to split.
##
## **On a machine where this is slow, warming everything is still the right answer
## and the split would have been the wrong one.** The total is the total: whatever
## the multiplier, the assets get loaded either way, and the only question is
## whether the player waits for them at a moment they expect to or in the middle
## of a fight. A split would simply have moved some of the freezes later.
##
## The list comes from **the unit stats folder**, and that turns out to be very
## nearly the whole graph: an ability, an attack and a technology are all
## `ext_resource`s OF a stats file, so loading the stats resources reaches every
## scene path in the build. Scanning the ability and technology folders as well
## was measured and found not one extra scene.
##
## The one gap is an asset named by a CONFIG rather than by a unit - the
## interface sounds - which nothing reachable from a unit mentions. That is what
## `ContentConfig.shared_config_folder` is for, and it is why this takes a list
## of folders rather than the one.
##
## It reads those paths REFLECTIVELY - any String property naming a file with a
## warmable extension - rather than by asking each class what it holds. That is
## the point: a resource that gains a new path tomorrow is warmed without this
## file being told about it, which is the same reason `Main._validate_content`
## walks the graph instead of keeping a list.
##
## **Sounds ride along for free**, and for exactly the same reason scenes do:
## audio is named by path and loaded lazily too, so without this the first shot
## of each tower type would load its `.wav` mid-match. Same walk, same moment, one
## extra entry in the extension list - no second pass and no second API.
##
## ## Why it is a pipeline and not three passes
##
## Loading happens on Godot's worker threads and reflection happens on this one,
## so they run at the same time: a stats resource is reflected the moment it
## arrives, and the assets it names are requested immediately rather than after
## the last one has been read. The main thread's reflection is then hidden behind
## the workers' loading almost entirely.
##
## `advance()` is time-boxed rather than counted per item, because the two kinds
## of work differ by an order of magnitude in cost and a fixed count would either
## stutter the bar or waste the frame.
##
## ## What holds the result
##
## A static array, for the life of the process. Godot frees a resource when the
## last reference to it goes, so a warmer that let go of what it loaded would have
## achieved nothing - the scene change to `Main.tscn` would drop the lot and the
## first sheep would load again. Nothing else has to be told about this: a later
## `load()` of a path still held returns the cached resource, so the lazy loaders
## all over the codebase simply stop costing anything.
##
## Static also means a SECOND match in the same process skips the whole thing,
## which is what `is_warm()` is for.
##
## The measured cost of holding it all is about 26 MB.

## Which paths are worth warming. A scene drags its meshes, materials and
## textures with it, which is where nearly all of the time goes; the audio is
## almost free and is here because it is lazy in the same way and would otherwise
## hitch in the same place.
const WARM_EXTENSIONS: PackedStringArray = [".tscn", ".wav", ".ogg", ".mp3"]

## How deep into nested resources the walk goes. A projectile scene sits three
## levels down - delivery, attack, unit - and nothing authored is near this.
const MAX_DEPTH: int = 6

## How many loads are asked for at once. Godot queues the rest, so this is about
## keeping each poll cheap rather than about limiting the workers.
const MAX_IN_FLIGHT: int = 8

## How long one `advance()` may spend on the main thread. Sized to leave a 60 Hz
## frame its vsync: the bar has to keep moving, or this is just a freeze with a
## progress bar drawn on it.
const FRAME_BUDGET_MS: float = 12.0

## What the stats half of the work is worth on the bar. The assets are the larger
## half in both count and time.
const STATS_SHARE: float = 0.35

## Everything loaded, held for the life of the process so nothing is ever freed
## and reloaded. See the note above.
static var _held: Array[Resource] = []
static var _warm: bool = false

var _files: PackedStringArray = PackedStringArray()
var _next_file: int = 0
var _stats_pending: PackedStringArray = PackedStringArray()
var _stats_done: int = 0

var _queue: PackedStringArray = PackedStringArray()
var _pending: PackedStringArray = PackedStringArray()
var _seen: Dictionary = {}
var _assets_done: int = 0
var _scenes_done: int = 0

var _started_msec: int = 0
var _elapsed_ms: float = 0.0
var _ratio: float = 0.0
var _finished: bool = false


## Whether a previous match already warmed this process.
static func is_warm() -> bool:
	return _warm


## How much is being held warm. For the log line, and for a test that wants to
## assert the warm actually happened.
static func held_count() -> int:
	return _held.size()


## Starts the walk over every `.tres` in each folder. The folders are
## `ContentConfig`'s; passed in rather than read off `References` so this is
## equally usable from the load screen, from a test and from a tool.
func begin(folders: PackedStringArray) -> void:
	_started_msec = Time.get_ticks_msec()
	if _warm:
		# A second match in the same process. Everything is still held, so there
		# is nothing to do and pretending otherwise would put a bar on screen
		# that filled instantly.
		_finish_early()
		return

	for folder: String in folders:
		if folder.is_empty() || !DirAccess.dir_exists_absolute(folder):
			# Reported rather than skipped quietly. A folder that has been moved
			# makes the warm silently SHORTER, and a short warm looks exactly
			# like a warm that did not help.
			Log.err("ContentWarmer was given a folder that does not resolve", folder)
			continue
		_files.append_array(_tres_files(folder))

	if _files.is_empty():
		Log.warn("ContentWarmer found nothing to warm", folders)
		_finish_early()


## One frame of work. Cheap to call after it has finished.
func advance() -> void:
	if _finished:
		return

	var until: int = Time.get_ticks_usec() + int(FRAME_BUDGET_MS * 1000.0)

	# Asked for first, so the workers have something to do while this thread
	# reflects on whatever came back.
	_request_stats()
	_request_assets()

	_retire_stats(until)
	_retire_assets()

	_update_ratio()

	if _next_file >= _files.size() && _stats_pending.is_empty() \
			&& _queue.is_empty() && _pending.is_empty():
		_finish()


func is_finished() -> bool:
	return _finished


## Where the bar should be, 0 to 1. Never goes backwards: the total is not known
## until the last stats resource has been read, so the honest raw number would
## drop every time reflection found more work.
func ratio() -> float:
	return _ratio


## What it did, for the log and for a test to assert against.
func report() -> Dictionary:
	return {
		"stats": _stats_done,
		"scenes": _scenes_done,
		"other": _assets_done - _scenes_done,
		"held": _held.size(),
		"ms": snappedf(_elapsed_ms, 0.1),
	}


# --- the two lanes ---------------------------------------------------------

func _request_stats() -> void:
	while _stats_pending.size() < MAX_IN_FLIGHT && _next_file < _files.size():
		var path: String = _files[_next_file]
		_next_file += 1
		if ResourceLoader.load_threaded_request(path) == OK:
			_stats_pending.append(path)
		else:
			Log.warn("ContentWarmer could not start a stats load", path)


## Reads back whatever finished and reflects it into asset paths. This is the
## only expensive thing on the main thread, so it is what the budget guards.
func _retire_stats(until: int) -> void:
	var still: PackedStringArray = PackedStringArray()
	for path: String in _stats_pending:
		if Time.get_ticks_usec() > until:
			still.append(path)
			continue
		var status: int = ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			still.append(path)
			continue
		_stats_done += 1
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			Log.warn("ContentWarmer could not load a stats resource", path)
			continue
		var res: Resource = ResourceLoader.load_threaded_get(path)
		if res == null:
			continue
		_held.append(res)
		for asset: String in _asset_paths_on(res):
			if _seen.has(asset):
				continue
			_seen[asset] = true
			_queue.append(asset)
	_stats_pending = still


func _request_assets() -> void:
	while _pending.size() < MAX_IN_FLIGHT && !_queue.is_empty():
		var path: String = _queue[0]
		_queue.remove_at(0)
		# The type hint lets Godot skip loaders it knows cannot apply. Only the
		# scenes get one: the audio formats each have their own class and naming
		# one of them would refuse the other two.
		var hint: String = "PackedScene" if path.ends_with(".tscn") else ""
		if ResourceLoader.load_threaded_request(path, hint) == OK:
			_pending.append(path)
		else:
			Log.warn("ContentWarmer could not start an asset load", path)


## Cheap on purpose: reading a finished resource back is a pointer, and none of
## the cost of loading it was ever on this side of the thread.
func _retire_assets() -> void:
	var still: PackedStringArray = PackedStringArray()
	for path: String in _pending:
		var status: int = ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			still.append(path)
			continue
		_assets_done += 1
		if path.ends_with(".tscn"):
			_scenes_done += 1
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			Log.warn("ContentWarmer could not load an asset", path)
			continue
		var res: Resource = ResourceLoader.load_threaded_get(path)
		if res != null:
			_held.append(res)
	_pending = still


## Nothing to do, for one of the several reasons there can be nothing to do.
func _finish_early() -> void:
	_finished = true
	_ratio = 1.0


func _finish() -> void:
	_finished = true
	_ratio = 1.0
	_warm = true
	_elapsed_ms = float(Time.get_ticks_msec() - _started_msec)
	Log.info("Content warmed", report())


# --- progress --------------------------------------------------------------

func _update_ratio() -> void:
	var stats_total: int = maxi(1, _files.size())
	var stats_part: float = float(_stats_done) / float(stats_total)

	# The denominator GROWS as reflection finds more, so this half is only
	# trustworthy once every stats resource has been read. Until then it is
	# deliberately pessimistic - scaled down by how much of the walk is still to
	# come - rather than optimistic and then jumping backwards.
	var known: int = maxi(1, _seen.size())
	var asset_part: float = float(_assets_done) / float(known)
	if _stats_done < stats_total:
		asset_part *= stats_part

	var raw: float = STATS_SHARE * stats_part + (1.0 - STATS_SHARE) * asset_part
	_ratio = maxf(_ratio, clampf(raw, 0.0, 1.0))


# --- finding things --------------------------------------------------------

func _tres_files(root: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while !entry.is_empty():
		var full: String = root.path_join(entry)
		if dir.current_is_dir():
			out.append_array(_tres_files(full))
		elif entry.ends_with(".tres"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return out


## Every warmable path this resource names, and everything it holds names.
##
## The recursion is what makes one folder enough: a projectile scene is named by
## an `AttackDelivery` hanging off an `AttackStats` hanging off the unit, and
## nothing at the top level mentions it.
##
## A `PackedScene` property is stepped OVER rather than into. A node's scenes are
## plain `PackedScene` exports and are hard dependencies of the scene holding
## them, so they are loaded already by the time anything could ask - and
## descending into one would walk the whole node tree of every prefab in the
## build to learn nothing.
func _asset_paths_on(res: Resource, depth: int = 0) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if res == null || depth > MAX_DEPTH:
		return out
	for prop: Dictionary in res.get_property_list():
		if (int(prop["usage"]) & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var value: Variant = res.get(String(prop["name"]))
		if value is String:
			var text: String = value
			if _is_warmable(text):
				out.append(text)
		elif value is Resource && !(value is PackedScene):
			out.append_array(_asset_paths_on(value, depth + 1))
		elif value is Array:
			for item: Variant in value:
				if item is Resource && !(item is PackedScene):
					out.append_array(_asset_paths_on(item, depth + 1))
	return out


## A path worth loading up front, which means one that exists and is one of the
## kinds something loads lazily during a match.
func _is_warmable(path: String) -> bool:
	for extension: String in WARM_EXTENSIONS:
		if path.ends_with(extension):
			return ResourceLoader.exists(path)
	return false
