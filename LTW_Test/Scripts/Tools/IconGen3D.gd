extends Node

## Bakes one PNG per unit type out of that unit's own placeholder model.
##
## The tool 2DArt/Icons/README.md names. It has to RUN rather than go headless,
## because baking an image means rendering one and a headless Godot has no
## renderer at all:
##
##   godot --path . res://Scenes/Tools/icon_gen_3d.tscn -- creeps
##   godot --path . res://Scenes/Tools/icon_gen_3d.tscn -- discs
##   godot --path . res://Scenes/Tools/icon_gen_3d.tscn -- <key> [<key> ...]
##   godot --path . res://Scenes/Tools/icon_gen_3d.tscn -- new
##
## KEPT TOOLING, not scaffolding, which is why it does not live in Scripts/Dev.
## That folder is for probes that get deleted when the work they were written
## for lands; this is run again every time a roster gains a unit, and tiers 3
## and 4 of the creep roster are still to come. It cannot live in Tools/ either,
## where the rest of the build tooling is, because a `.gdignore` keeps Godot's
## filesystem out of that folder entirely and this has to be a scene Godot can
## open. See CLAUDE.md under Project structure.
##
## WHAT IT BAKES IS SCANNED, never listed. It walks the stats folder rather
## than carrying a roster of its own, so a creep added tomorrow is baked
## without anybody remembering to add it here - the trap a hand-kept list falls
## into the first time it is not updated.
##
## `new` bakes only the units whose PNG is missing, which is what to pass after
## adding a roster: re-baking a roster whose models have not moved is a few
## hundred files of churn nobody asked for.
##
## MESHES ONLY, through VisualUtil, which is what keeps this from registering a
## unit id, claiming a grid cell or taking a shot at something. It is also what
## leaves a flyer's shadow disc out - see GroundShadow3D.
##
## FRAMED ON THE UNIT'S OWN BOUNDING BOX, so a Sheep and an Infernal come out
## the same size on a card. That is deliberate and it costs the size ladder: an
## icon says WHICH creep, and the world says how big it is.

## Which folder each roster keyword scans, and where its prefabs live. The two
## are separate because a stats file names its prefab by path and this only
## needs the KEY, which both folders agree on.
##
## Each entry is [stats folder, prefab folder, camera elevation in radians].
##
## THE BASIC TOWERS ARE IN and the ELEMENTAL ones are not, and neither of those
## is stated here as a list - see _bakeable_name, which is what decides.
##
## The trap this used to be guarded against by leaving towers out entirely: the
## icons in 2DArt/Icons are named after a unit's DISPLAY NAME, while every
## folder here is keyed by PREFAB, and for the elemental roster those two
## disagree - `apprentice.png` against a key of `arcane_apprentice`. Baking the
## Towers folder by key wrote a second, parallel set of two hundred files under
## names nothing references, which is exactly what it did once.
##
## The DISCS sidestepped it by being named so that a key and a display name slug
## are the same string - `fire_disc` is "Fire Disc" - and the Basic towers turn
## out to have always been the same: `lesser_watch_tower` is "Lesser Watch
## Tower". So the fix is to make that agreement the RULE rather than a property
## three rosters happen to have. A unit whose two names disagree is skipped and
## SAID SO, which is the same protection the old omission bought, applied by the
## thing it is actually about instead of by a folder being left out.
##
## Their ELEVATION is their own, and it is the reason this is a three-column
## table. A disc is a flat quad painted on the ground: seen from the creeps'
## three quarter view it is a squashed ellipse with its glyph foreshortened
## into a smear, and the two things an icon has to say about a disc - which
## element, which tier - are exactly the two the foreshortening destroys. So it
## is baked from very nearly overhead. Not EXACTLY overhead, because look_at
## with an UP of Vector3.UP degenerates when the camera is straight above what
## it is looking at.
const ROSTERS: Dictionary = {
	"creeps": ["res://Resources/UnitStats/Creeps", "res://Scenes/Units/Creeps", 0.50],
	"discs": ["res://Resources/UnitStats/Discs", "res://Scenes/Units/Discs", 1.47],
	# The Basic towers only; the elemental ones share this folder and are
	# filtered out by _bakeable_name. Their elevation is the creeps' - a tower
	# stands up, so the three quarter view that suits a creature suits it too.
	"towers": ["res://Resources/UnitStats/Towers", "res://Scenes/Units/Towers", 0.50],
}

const OUT: String = "res://2DArt/Icons"

## Where the camera stands, as one round from the front. The angle UP is per
## roster now - see ROSTERS - because a creep and a disc want opposite ones.
const YAW: float = 0.55
## How much room is left around the unit inside the frame.
const MARGIN: float = 1.18

@export_group("References")
@export var _viewport: SubViewport
@export var _camera: Camera3D
@export var _stage: Node3D


func _ready() -> void:
	if _viewport == null || _camera == null || _stage == null:
		push_error("IconGen3D is missing its viewport, camera or stage")
		get_tree().quit(1)
		return

	var keys: PackedStringArray = _requested(OS.get_cmdline_user_args())
	if keys.is_empty():
		print("nothing to bake")
		get_tree().quit()
		return

	_camera.fov = 30.0
	_camera.near = 0.01
	var baked: int = 0
	for key: String in keys:
		if await _bake(key):
			baked += 1
	print("baked %d of %d icons" % [baked, keys.size()])
	get_tree().quit()


## What the command line asked for, resolved into unit keys.
##
## A roster keyword scans that roster's folder; `new` scans every roster and
## keeps only what has no PNG yet; anything else is taken as a key of its own,
## so one creep can be re-baked after its model is tweaked.
func _requested(args: PackedStringArray) -> PackedStringArray:
	if args.is_empty():
		return _scan("creeps")

	var keys: PackedStringArray = PackedStringArray()
	for arg: String in args:
		if arg == "new":
			for roster: String in ROSTERS:
				for key: String in _scan(roster):
					if !FileAccess.file_exists("%s/%s.png" % [OUT, key]):
						keys.append(key)
		elif ROSTERS.has(arg):
			keys.append_array(_scan(arg))
		else:
			keys.append(arg)
	return keys


## Every unit key of one roster, read off its stats folder.
##
## The STATS folder rather than the prefab one, because a stats file is what
## unit_data.md 8.1 makes the authority on a unit existing at all - a stray
## prefab with nothing pointing at it is not a unit.
func _scan(roster: String) -> PackedStringArray:
	var keys: PackedStringArray = PackedStringArray()
	var folder: String = (ROSTERS[roster] as Array)[0]
	for name: String in DirAccess.get_files_at(folder):
		if !name.ends_with("_stats.tres"):
			continue
		var key: String = name.trim_suffix("_stats.tres")
		if _bakeable_name(folder, key):
			keys.append(key)
	keys.sort()
	return keys


## Whether this unit's icon may be written under its KEY.
##
## An icon is looked up by DISPLAY NAME and written here by KEY, so the two have
## to be the same string or the file lands somewhere nothing reads. Rather than
## trusting that - which held for two rosters and broke on the third - it is
## checked, and a unit whose names disagree is skipped with a message.
##
## That is the whole of what keeps the eighty elemental towers out of a folder
## they share with the thirty Basic ones. See the note on ROSTERS.
func _bakeable_name(folder: String, key: String) -> bool:
	# No type hint, and that is not an oversight: passing a SCRIPT class name to
	# the loader returns null in an exported build. See CLAUDE.md.
	var stats: UnitStats = ResourceLoader.load(
		"%s/%s_stats.tres" % [folder, key], "") as UnitStats
	if stats == null:
		push_error("IconGen3D could not read stats for %s" % key)
		return false

	var slug: String = ""
	for character: String in stats.display_name.to_lower():
		if character == " " || character == "_":
			slug += "_"
		elif character.is_valid_identifier() || character.is_valid_int():
			slug += character
	if slug == key:
		return true

	print("skipped %s: its icon is named %s.png, not %s.png" % [key, slug, key])
	return false


## One unit. Reports whether an image was written, so a missing prefab is a
## message and a smaller count rather than a crash halfway down a roster.
func _bake(key: String) -> bool:
	var roster: String = _roster_of(key)
	if roster.is_empty():
		push_error("IconGen3D found no prefab for %s" % key)
		return false
	var scene: PackedScene = load(
		"%s/%s.tscn" % [(ROSTERS[roster] as Array)[1], key]) as PackedScene
	if scene == null:
		push_error("IconGen3D could not load the prefab for %s" % key)
		return false

	for child in _stage.get_children():
		child.free()

	# NEVER put the prefab in a tree: its _ready would run, and baking a
	# picture must not register a unit id or claim anything.
	var unit: Node3D = scene.instantiate() as Node3D
	var box: AABB = VisualUtil.copy_meshes(
		unit, _stage, VisualUtil.portrait_skips(unit))
	unit.free()
	if box.size.length() <= 0.0:
		push_error("IconGen3D found no meshes on %s" % key)
		return false

	_frame(box, float((ROSTERS[roster] as Array)[2]))
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	var file: String = "%s/%s.png" % [OUT, key]
	image.save_png(ProjectSettings.globalize_path(file))
	print("wrote %s" % file)
	return true


## Which roster a key belongs to, or empty when nothing has a prefab for it.
##
## Every folder is tried rather than the caller having to say which, so a
## single key on the command line works without knowing where it lives. The
## ROSTER rather than the scene, because the camera angle comes off it too.
func _roster_of(key: String) -> String:
	for roster: String in ROSTERS:
		if ResourceLoader.exists("%s/%s.tscn" % [(ROSTERS[roster] as Array)[1], key]):
			return roster
	return ""


## Puts the camera where the whole unit fits, whatever size it is, at the
## elevation this roster is read at.
func _frame(box: AABB, elevation: float) -> void:
	var centre: Vector3 = box.get_center()
	var radius: float = box.size.length() * 0.5
	var half_fov: float = deg_to_rad(_camera.fov) * 0.5
	var distance: float = radius / maxf(0.05, sin(half_fov)) * MARGIN
	var direction: Vector3 = Vector3(
		sin(YAW) * cos(elevation), sin(elevation), cos(YAW) * cos(elevation))
	_camera.global_position = centre + direction * distance
	_camera.look_at(centre, Vector3.UP)
