extends Node

## Bakes one PNG per unit type out of that unit's own placeholder model.
##
## Scaffolding, and the tool 2DArt/Icons/README.md names. It has to RUN rather
## than be a headless script, because baking an image means rendering one and
## a headless Godot has no renderer at all:
##
##   godot --path . res://Scenes/Dev/icon_renderer.tscn -- creeps
##   godot --path . res://Scenes/Dev/icon_renderer.tscn -- <key> [<key> ...]
##
## With no arguments it bakes every creep, which is the only roster whose
## models have moved. The towers' icons are current and re-baking them would be
## two hundred files of churn for no change anybody asked for.
##
## MESHES ONLY, through VisualUtil, which is what keeps a portrait from
## registering a unit id, claiming a grid cell or taking a shot at something.
## It is also what leaves a flyer's shadow disc out - see GroundShadow3D.
##
## FRAMED ON THE UNIT'S OWN BOUNDING BOX, so a Sheep and a Rot Golem come out
## the same size on a card. That is deliberate and it costs the size ladder:
## an icon says WHICH creep, and the world says how big it is.

const CREEPS: Array[String] = [
	"sheep", "timber_wolf", "skeleton_warrior", "acolyte", "forest_spider",
	"swordsman", "fel_orc_grunt", "vile_temptress", "shade", "mud_golem",
	"priest", "corrupted_treant", "rot_golem",
]

const OUT: String = "res://2DArt/Icons"

## Where the camera stands, as an angle up from the ground and one round from
## the front. A three quarter view: enough top to read a silhouette from, and
## enough front to read a face on.
const ELEVATION: float = 0.50
const YAW: float = 0.55
## How much room is left around the unit inside the frame.
const MARGIN: float = 1.18

@export_group("References")
@export var _viewport: SubViewport
@export var _camera: Camera3D
@export var _stage: Node3D


func _ready() -> void:
	if _viewport == null || _camera == null || _stage == null:
		push_error("IconRenderer is missing its viewport, camera or stage")
		get_tree().quit(1)
		return

	var keys: PackedStringArray = OS.get_cmdline_user_args()
	if keys.is_empty() || (keys.size() == 1 && keys[0] == "creeps"):
		keys = PackedStringArray(CREEPS)

	_camera.fov = 30.0
	_camera.near = 0.01
	for key: String in keys:
		await _bake(key)
	print("baked %d icons" % keys.size())
	get_tree().quit()


func _bake(key: String) -> void:
	var path: String = "res://Scenes/Units/Creeps/%s.tscn" % key
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		push_error("IconRenderer could not load %s" % path)
		return

	for child in _stage.get_children():
		child.free()

	# NEVER put the prefab in a tree: its _ready would run, and a portrait must
	# not register a unit id or claim anything.
	var unit: Node3D = scene.instantiate() as Node3D
	var box: AABB = VisualUtil.copy_meshes(
		unit, _stage, VisualUtil.portrait_skips(unit))
	unit.free()
	if box.size.length() <= 0.0:
		push_error("IconRenderer found no meshes on %s" % key)
		return

	_frame(box)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	var file: String = "%s/%s.png" % [OUT, key]
	image.save_png(ProjectSettings.globalize_path(file))
	print("wrote %s" % file)


## Puts the camera where the whole unit fits, whatever size it is.
func _frame(box: AABB) -> void:
	var centre: Vector3 = box.get_center()
	var radius: float = box.size.length() * 0.5
	var half_fov: float = deg_to_rad(_camera.fov) * 0.5
	var distance: float = radius / maxf(0.05, sin(half_fov)) * MARGIN
	var direction: Vector3 = Vector3(
		sin(YAW) * cos(ELEVATION), sin(ELEVATION), cos(YAW) * cos(ELEVATION))
	_camera.global_position = centre + direction * distance
	_camera.look_at(centre, Vector3.UP)
