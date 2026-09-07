class_name BlueprintLibrary
extends RefCounted

## The player's saved maze plans, and the files they live in.
##
## A blueprint IS a TowerLayout - the same resource the layout cheat already
## reads and writes, and deliberately so: it is the smallest honest description
## of a maze, it already survives being loaded into a different match, and it
## already carries the unit_type_id of every entry. Nothing here shows those
## types today, because a blueprint only answers WHERE. They are stored anyway,
## because the file that has them costs nothing extra and the file that threw
## them away could never grow the feature back.
##
## PURELY LOCAL, from end to end. A blueprint is a note the player wrote to
## themselves on this machine: the server has no business holding one, no other
## player has any business seeing one, and nothing here may ever decide what
## happens in a match. That is the same line UserSettings sits on, and this
## file is next to it for the same reasons - it is written at runtime, by
## whoever is sitting at the keyboard, and has to survive the game closing.
##
## Static rather than an autoload for the reason UserSettings is: it holds no
## node and nothing is routed to it, so an ability, the overlay and a tooltip
## all reach the same slots without one - and adding an autoload would mean
## editing [autoload] in project.godot, which breaks a running editor.
##
## **Two places a slot can come from, and one of them ships with the game.**
## A slot is read from user:// if the player has ever saved into it, and from
## the shipped defaults under res:// if they have not. So a fresh install opens
## with a full set of plans, and saving over one simply writes the user file
## that from then on shadows the default. Nothing is copied at boot and nothing
## is ever destroyed: a user file deleted by hand gives that slot its default
## back, which is as close to "reset this slot" as anything needs.

## How many plans a player keeps. Nine because that is what fits a command card
## alongside the way back out of it, which is the only place they are ever
## picked from.
const SLOT_COUNT: int = 9

## Where a plan the player saved goes. user:// rather than res://, because
## res:// is read-only in an exported build.
const USER_FOLDER: String = "user://blueprints"
## Where the plans that ship with the game live. Ordinary authored .tres files,
## so one is made by saving a slot in a dev build and moving the file here.
const DEFAULT_FOLDER: String = "res://Resources/Blueprints"
## File name of a slot, in both folders. The number is the SLOT, so a default
## and the file that overrides it are named the same thing in two places.
const FILE_PATTERN: String = "blueprint_%d.%s"

## What a resource file can be called. Two spellings because an exported build
## converts text resources to binary - the same reason AbilityRegistry carries
## this list. Only ever needed for the shipped defaults; a user file is written
## by us and is always .tres.
const RESOURCE_EXTENSIONS: Array[String] = ["tres", "res"]

## Slot number to the layout in it, or to null for a slot that is empty.
##
## **The empty answer is cached too, and that is the point of caching at all.**
## A command card polls every square it draws every frame - can it be used, what
## number does it carry - so an uncached miss would stat the filesystem nine
## times a frame for the nine squares nobody has saved into yet.
static var _cache: Dictionary = {}


## Whether a slot number is one of the nine. Slots count from 1, because the
## number is read by a person - on a card, in a log line, in a file name.
static func is_slot(slot: int) -> bool:
	return slot >= 1 && slot <= SLOT_COUNT


## The plan in a slot, or null when there is nothing in it.
##
## The user's own file wins over the shipped default, which is the whole of the
## rule that makes a default overwritable.
static func layout(slot: int) -> TowerLayout:
	if !is_slot(slot):
		return null
	if _cache.has(slot):
		return _cache[slot] as TowerLayout

	var found: TowerLayout = _read(user_path(slot))
	if found == null:
		found = _read(_default_path(slot))
	_cache[slot] = found
	return found


## Whether there is anything in a slot at all, however it got there.
static func has(slot: int) -> bool:
	return layout(slot) != null


## Whether a slot is still showing the plan that shipped with the game, rather
## than one this player saved. What the overwrite warning uses to say which of
## the two is about to go.
static func is_shipped_default(slot: int) -> bool:
	return has(slot) && !FileAccess.file_exists(user_path(slot))


## How many entries a slot holds, or -1 for an empty one.
##
## -1 rather than 0 because that is what a command card draws as NOTHING in the
## corner of a square, and an empty slot should carry no number rather than a
## zero. See UnitAbility.charge_count.
static func entry_count(slot: int) -> int:
	var found: TowerLayout = layout(slot)
	if found == null:
		return -1
	return found.entry_count()


## Writes a plan into a slot, over whatever was there.
##
## The caller is what asks the player first. This refuses nothing but a bad
## slot and an empty plan: saving no towers at all would leave a slot that
## looks used and shows nothing, which reads as a broken save rather than as an
## empty one.
static func store(slot: int, plan: TowerLayout) -> bool:
	if !is_slot(slot):
		Log.err("Blueprint slot is not one of the nine", slot)
		return false
	if plan == null || plan.entry_count() <= 0:
		Log.warn("There is nothing standing to save as a blueprint", {"slot": slot})
		return false

	if !plan.save_file(user_path(slot)):
		return false

	# Dropped rather than replaced with the plan we hold, so the next read goes
	# back to the file. If the write did something other than what we think it
	# did, the slot says so at once instead of the next time the game starts.
	_cache.erase(slot)
	Log.info("Blueprint saved", {"slot": slot, "towers": plan.entry_count()})
	return true


## Where a slot's user file goes. Public so a save can be told apart from a
## default without this file having to answer every question about one.
static func user_path(slot: int) -> String:
	return "%s/%s" % [USER_FOLDER, FILE_PATTERN % [slot, "tres"]]


## Forgets everything read so far, so the next read goes back to disk. Only
## needed by a tool or a test that writes these files behind our back.
static func clear_cache() -> void:
	_cache.clear()


## The shipped default for a slot, or "" when the build has none.
##
## Both spellings are tried because an exported build converts .tres to .res,
## and a default that only existed in the editor would be a slot that quietly
## emptied itself the day the game was exported.
static func _default_path(slot: int) -> String:
	for extension: String in RESOURCE_EXTENSIONS:
		var path: String = "%s/%s" % [DEFAULT_FOLDER, FILE_PATTERN % [slot, extension]]
		if FileAccess.file_exists(path):
			return path
	return ""


## One file, or null when there is nothing readable there.
##
## The existence check is here rather than left to load_file so an empty slot
## is silent: load_file says where it looked, which is right for a cheat key
## somebody pressed and wrong for nine squares that are simply unused.
static func _read(path: String) -> TowerLayout:
	if path.is_empty() || !FileAccess.file_exists(path):
		return null
	return TowerLayout.load_file(path)
