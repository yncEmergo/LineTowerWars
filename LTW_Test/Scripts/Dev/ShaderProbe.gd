extends Node

## THROWAWAY. Proves `ShaderWarmup` compiles, before the match, what the match
## would otherwise compile in the middle of play.
##
## **Godot's own shader cache is the instrument.** The GL renderer writes every
## variant it compiles to `user://shader_cache/SceneShaderGLES3` as one file, so
## a file appearing IS a compile happening - on this machine, whatever its driver
## caches on top. Run on an EMPTY cache, or every count below measures nothing.
##
##     godot --path . res://Scenes/Main.tscn --windowed -- --shaderprobe cold|warm
##
## `cold` skips the warm-up, `warm` lets it run. Both then do what play does -
## stand every model up for real, turn it into a ghost, play every effect, show
## every unit in the portrait - and count the files each one writes. What `warm`
## still writes is what the warm-up missed.
##
## Does NOTHING without --shaderprobe. Scaffolding: delete with the rest of
## `Scripts/Dev` when the work is done.

const ROLE_ARGUMENT: String = "--shaderprobe"
const CACHE_DIR: String = "user://shader_cache/SceneShaderGLES3"
const MODEL_DIRS: PackedStringArray = [
	"res://Scenes/Units/Models/Towers", "res://Scenes/Units/Models/Creeps",
]
const EFFECT_DIR: String = "res://Scenes/Effects"
## Frames each thing stays up, and frames to settle after the match opens.
const HOLD_FRAMES: int = 3
const SETTLE_FRAMES: int = 30
const DISTANCE: float = 8.0

var _mode: String = ""
var _phase: String = "wait"
var _settle: int = 0
var _queue: Array = []
var _item: Array = []
var _node: Node = null
var _frames: int = 0
var _files_before_item: int = 0
var _worst_ms: float = 0.0
var _last_usec: int = 0
var _files_at_start: int = 0
var _files_at_draw: int = 0
var _by_kind: Dictionary = {}
var _heavy: Array = []
var _portrait_sources: Array[Node3D] = []


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(args.size()):
		if args[index] == ROLE_ARGUMENT && index + 1 < args.size():
			_mode = args[index + 1]
	if _mode.is_empty():
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _mode == "cold":
		# The warm-up's own guard: a process that has warmed never warms again.
		ShaderWarmup._warmed = true
	_files_at_start = _count_files()
	print("SHADERPROBE start mode=%s files=%d" % [_mode, _files_at_start])


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	if _last_usec > 0:
		_worst_ms = maxf(_worst_ms, float(now - _last_usec) / 1000.0)
	_last_usec = now

	if _phase == "wait":
		if References.match_session == null || !ShaderWarmup.is_done():
			return
		_settle += 1
		if _settle < SETTLE_FRAMES:
			return
		_files_at_draw = _count_files()
		_build_queue()
		_phase = "draw"
		print("SHADERPROBE drawing %d items, files so far %d (+%d since start)" % [
			_queue.size(), _files_at_draw, _files_at_draw - _files_at_start])
		return

	if _phase != "draw":
		return

	if _node == null && _item.is_empty():
		if _queue.is_empty():
			_report()
			return
		_item = _queue.pop_front()
		_files_before_item = _count_files()
		_worst_ms = 0.0
		_frames = 0
		_start_item()
		return

	_frames += 1
	if _frames == HOLD_FRAMES && String(_item[0]) == "model":
		# The same model again as a ghost, which is how every tower is placed.
		var model: UnitModel = _node as UnitModel
		if model != null:
			model.set_mode(UnitModel.Mode.PREVIEW)
		return
	var hold: int = HOLD_FRAMES * (2 if String(_item[0]) == "model" else 1)
	if _frames < hold:
		return
	_end_item()


func _build_queue() -> void:
	for folder: String in MODEL_DIRS:
		for path: String in _scenes_in(folder):
			_queue.append(["model", path])
	for path: String in _scenes_in(EFFECT_DIR):
		_queue.append(["effect", path])
	_queue.append(["portrait", "every unit"])


func _start_item() -> void:
	var kind: String = _item[0]
	if kind == "portrait":
		var panel: UnitPanel = References.unit_panel
		var portrait: UnitPortrait = null if panel == null else panel.portrait()
		if portrait == null:
			_item = []
			return
		for folder: String in MODEL_DIRS:
			for path: String in _scenes_in(folder):
				var scene: PackedScene = load(path) as PackedScene
				var instance: Node3D = null if scene == null else scene.instantiate() as Node3D
				if instance != null:
					_portrait_sources.append(instance)
		portrait.warm(_portrait_sources)
		_node = portrait
		return

	var packed: PackedScene = load(String(_item[1])) as PackedScene
	var instance: Node3D = null if packed == null else packed.instantiate() as Node3D
	var root: Node3D = References.effects_root
	var camera: Camera3D = get_viewport().get_camera_3d()
	if instance == null || root == null || camera == null:
		_item = []
		return
	root.add_child(instance)
	instance.global_position = camera.global_position \
		+ (-camera.global_transform.basis.z) * DISTANCE
	_node = instance


func _end_item() -> void:
	var kind: String = _item[0]
	if kind == "portrait":
		(_node as UnitPortrait).end_warm()
		for source: Node3D in _portrait_sources:
			source.free()
	elif is_instance_valid(_node):
		_node.queue_free()
	var written: int = _count_files() - _files_before_item
	var entry: Dictionary = _by_kind.get(kind, {"items": 0, "files": 0, "worst_ms": 0.0})
	entry["items"] = int(entry["items"]) + 1
	entry["files"] = int(entry["files"]) + written
	entry["worst_ms"] = maxf(float(entry["worst_ms"]), _worst_ms)
	_by_kind[kind] = entry
	if written > 0:
		_heavy.append("%s %s: %d files, worst frame %.0f ms" % [
			kind, String(_item[1]).get_file(), written, _worst_ms])
	_node = null
	_item = []


func _report() -> void:
	_phase = "done"
	var total: int = _count_files()
	print("SHADERPROBE RESULT mode=%s" % _mode)
	print("  files at start %d, when drawing began %d, at the end %d" % [
		_files_at_start, _files_at_draw, total])
	print("  written while drawing (what play would compile mid-match): %d" % [
		total - _files_at_draw])
	for kind: Variant in _by_kind:
		print("  %-8s %s" % [kind, str(_by_kind[kind])])
	for line: String in _heavy:
		print("    " + line)
	get_tree().quit()


func _scenes_in(folder: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return out
	for file: String in dir.get_files():
		var name_only: String = file.trim_suffix(".remap")
		if name_only.ends_with(".tscn"):
			out.append(folder.path_join(name_only))
	out.sort()
	return out


func _count_files() -> int:
	var total: int = 0
	var dir: DirAccess = DirAccess.open(CACHE_DIR)
	if dir == null:
		return 0
	for sub: String in dir.get_directories():
		var inner: DirAccess = DirAccess.open(CACHE_DIR.path_join(sub))
		if inner != null:
			total += inner.get_files().size()
	return total
