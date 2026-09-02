class_name SpawnOnDeathPassive
extends CreepPassive

## Leaves more creeps behind when it dies.
##
## The Obsidian Statue Exhume Ghouls, and the first thing in the game where a
## creep spawns another creep: "spawns 3 Ghouls on death" (unit_data.md 6.6).
##
## What it does to the defender is turn ONE kill into four, at the spot where
## the first one fell - so a maze that only just manages to bring a Statue down
## at its far end has three more things walking out of the wreck with a short
## run left to the exit. Killing it EARLY is worth much more than killing it at
## all, which is a real decision rather than a stat.
##
## Written generically rather than as one Statue trait, because what varies
## between one of these and the next is only WHAT and HOW MANY - both of which
## belong in a .tres. It names the spawned creep by its STATS, exactly as a
## send ability does, so nothing ever instantiates a prefab to find out what it
## is spawning.
##
## The spawned creeps belong to whoever sent the parent, walk the maze the
## parent was walking, and are ordinary creeps in every other way - they pay
## bounty, they steal lives, they count as population. They are NOT a pack
## companion: a companion arrives with a send and is charged for, and these are
## not paid for at all.

@export_group("Settings")
## What one death leaves behind.
@export var spawned_stats: CreepStats
## How many of them.
@export var count: int = 3
## How far from the spot each one is scattered, in player cells, so three do
## not arrive standing in the same place.
@export var scatter_cells: float = 0.35


## Runs on death and does NOT call the death off - the parent still dies, still
## pays its bounty and still leaves. Returning false is what says so.
func on_death(creep: Creep) -> bool:
	if spawned_stats == null || count <= 0 || creep.area == null:
		return false

	var scene: PackedScene = spawned_stats.scene()
	if scene == null:
		Log.err("A creep spawned on death names no loadable prefab",
			spawned_stats.display_name)
		return false

	for index in range(count):
		_spawn_one(creep, scene)
	return false


## One spawned creep, placed near where the parent fell.
##
## Rolled on the match RNG like every other roll in the simulation, so two
## machines running the same match scatter them identically - three creeps a
## step apart is a difference that compounds the moment a tower picks one.
func _spawn_one(parent: Creep, scene: PackedScene) -> void:
	var spawned: Creep = scene.instantiate() as Creep
	if spawned == null:
		Log.err("A creep spawned on death has no Creep script on its root",
			spawned_stats.display_name)
		return

	var rng: RandomNumberGenerator = MatchSession.match_rng()
	var offset: Vector3 = Vector3(
		rng.randf_range(-scatter_cells, scatter_cells), 0.0,
		rng.randf_range(-scatter_cells, scatter_cells))

	parent.area.creeps_root().add_child(spawned)
	# The PARENT owner rather than the maze owner: what a creep leaves behind
	# is still the sender creep, and the lives it goes on to steal are theirs.
	spawned.spawn(parent.owner_player_id, parent.area,
		parent.area.clamp_point(parent.global_position + offset))


## Reports a spawn that could never happen, at boot rather than the first time
## one of these dies at the far end of somebody maze.
func validate(seen: Dictionary) -> bool:
	var complete: bool = super(seen)
	if spawned_stats == null:
		Log.err("A spawn-on-death passive names no creep", display_name)
		return false
	return spawned_stats.validate(seen) && complete


func effect_text() -> String:
	var name_text: String = "creeps" if spawned_stats == null \
		else spawned_stats.display_name
	return "Leaves %d %s behind where it dies." % [count, name_text]
