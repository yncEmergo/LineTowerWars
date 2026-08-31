class_name BloodthirstPassive
extends TowerPassive

## Primal 2, the whole Beastmaster line: strikes two creeps at a time, and at
## full mana sends a beast tearing down the lane through everything in its path.
##
## unit_data.md 4.7: the beast is a LINE rather than a splash - it runs from the
## tower on a committed heading, damaging and stunning the ground creeps it
## passes through, and a creep can only be knocked down by one every few
## seconds. That is the whole reason the line exists: it is the only thing in
## the game that reaches down a lane rather than around a point.
##
## It is a THING THAT RUNS, not an instant line, and that is a rule rather than
## a decoration: the beast takes about two seconds to cover its distance, so
## creeps walk into it and out of it while it is on its way, and where it will
## be is something both players can read off the field. See BeastCharge, which
## is the run itself.
##
## RELEASE IS MANA AND NOTHING ELSE. There is no cooldown on the tower - it
## sends one the moment it is full, however often that is. The eight seconds
## belongs to the CREEP: one that has been knocked down cannot be knocked down
## again for that long, and it takes the damage either way.
##
## WHERE IT RUNS is the ability's one choice. By default the heading is
## whatever the attack that filled the tower landed on, taken once at release
## and then committed to. A tower that has been LINKED with StampedeTarget
## sends every beast towards the linked tower instead, whatever it is shooting
## - and only the DIRECTION is taken from it, never the distance, so a link
## across the map and a link one cell away send the same beast the same way.

const IMMUNE_KEY: String = "beast_stun"
## Where the tower remembers it has already sent the beast it is holding.
##
## Only a CLIENT ever reads back true. The server empties its own mana on
## release, so it is no longer full by the next hit and the latch clears
## itself; a client cannot empty anything - it is TOLD what its mana is - so
## without this its copy of a full tower would send a beast on every hit until
## the drain arrived in a snapshot. See on_hit.
const RELEASED_KEY: String = "beast_released"

@export_group("Bloodthirst")
## Creeps struck alongside the primary target.
@export var additional_targets: int = 1
## How far this tower's multishot reaches, in player cells. Named rather than
## taking the game's shared reach, because the source states its own.
@export var multishot_cells: float = 3.12
## Mana gained per creep struck.
@export var mana_per_target: float = 5.0

@export_group("The beast")
## What actually runs down the lane, as a res:// path. Its root must carry the
## BeastCharge script. A path rather than a PackedScene, so reading this
## tower's price never drags a model into memory - see CLAUDE.md.
@export_file("*.tscn") var beast_scene_path: String = ""
## How far it runs, in player cells.
@export var beast_cells: float = 5.47
## How fast it runs, in cells per second. Authored against the distance rather
## than tuned by feel: it is slow enough to be walked into and walked out of,
## which is the whole difference between this and an instant line.
@export var beast_speed: float = 4.7
## Half the width of what it flattens, in cells, on top of each creep's own
## body. A whole cell, so the band it clears is two cells across - wider than
## the model on purpose, because a beast that visibly missed a creep it caught
## reads worse than one that visibly spared a creep it missed.
@export var beast_radius: float = 1.0
## Siege Physical Damage it deals to each creep it goes through.
@export var beast_damage: int = 240
## How long it knocks one down for.
@export var stun_seconds: float = 0.5
## Seconds before the same creep may be knocked down again. It still takes the
## damage while it is immune - the immunity is to the stun alone.
@export var stun_cooldown: float = 8.0

@export_group("Stampede")
## Extra damage per cell of range to the target, as a share, or 0 on the tiers
## that do not scale with distance.
@export var range_bonus_per_cell: float = 0.0
## The most that may reach.
@export var max_range_bonus: float = 0.0

## The beast, loaded the first time one is actually sent. Cached on the
## resource because every tower running this passive would load the same scene,
## which is exactly the kind of answer an ability is allowed to keep.
var _cached_beast: PackedScene = null
var _beast_loaded: bool = false


func extra_targets(_tower: Building) -> int:
	return additional_targets


func extra_target_range(_tower: Building) -> float:
	return multishot_cells


## The Ultimate hits harder the further away its target is, which is the
## opposite of every other tower in the game and is what makes a Beastmaster
## want to sit at the BACK of a maze rather than in the thick of it.
func bonus_damage(tower: Building, target: Unit, rolled: int) -> int:
	if range_bonus_per_cell <= 0.0 || target == null:
		return 0
	var offset: Vector3 = target.global_position - tower.global_position
	var cells: float = Vector2(offset.x, offset.z).length()
	var share: float = minf(max_range_bonus, range_bonus_per_cell * cells)
	return int(round(float(rolled) * share))


## Fills the tower, and sends the beast the moment it is full.
##
## The LATCH is what keeps one release to one beast on both machines - see
## RELEASED_KEY. It is cleared by the tower not being full rather than by the
## drain, so the server and a client clear it off the same observation.
func on_hit(tower: Building, target: Unit, _dealt: int, is_primary: bool) -> void:
	tower.gain_mana(mana_per_target)
	if !is_primary || target == null:
		return

	if !tower.has_full_mana():
		tower.ability_state[RELEASED_KEY] = false
		return
	if bool(tower.ability_state.get(RELEASED_KEY, false)):
		return

	tower.ability_state[RELEASED_KEY] = true
	tower.drain_mana()
	_release(tower, target)


## One creep going under the beast. Called by BeastCharge, once per creep, and
## the reason the damage and the knockdown live here rather than on the thing
## running: this resource is the authority on what THIS tower's beast is worth,
## and the beast is only the shape of its arrival.
##
## The stun carries its own per-creep cooldown, so a Beastmaster firing
## constantly cannot lock a pack in place - but the damage lands every time.
func trample(creep: Creep) -> void:
	creep.take_damage(beast_damage, DamageTable.DamageType.SIEGE, true)
	var status: StatusEffects = creep.status()
	if status.is_immune(IMMUNE_KEY):
		return
	status.set_immune(IMMUNE_KEY, stun_cooldown)
	status.stun(self, stun_seconds)


## The scene the beast is built from, loaded on the first release.
func beast_scene() -> PackedScene:
	if !_beast_loaded:
		_beast_loaded = true
		_cached_beast = SceneUtil.load_scene(beast_scene_path, "beast charge")
	return _cached_beast


## Sends it. The heading is taken ONCE, here, and never revisited.
func _release(tower: Building, target: Unit) -> void:
	var direction: Vector3 = _heading(tower, target)
	if direction == Vector3.ZERO || tower.area == null:
		return

	var root: Node3D = References.projectiles_root
	var scene: PackedScene = beast_scene()
	var beast: BeastCharge = null
	if scene != null:
		beast = scene.instantiate() as BeastCharge
	if root == null || beast == null:
		# Better a beast that arrives everywhere at once than a tower that
		# silently does nothing, which reads as a broken ability rather than as
		# a missing prefab. Same trade PierceDelivery makes.
		Log.err("Beastmaster cannot send its beast, striking the line instantly", {
			"tower": tower.name,
			"scene": beast_scene_path,
		})
		if beast != null:
			beast.queue_free()
		_trample_line(tower, direction)
		return

	root.add_child(beast)
	# From the floor the tower stands on rather than from the tower's own
	# origin, so the beast runs along the ground it is about to clear.
	var from: Vector3 = tower.global_position
	from.y = tower.area.global_position.y
	beast.launch(self, tower.area, from, direction)


## Which way this tower's beast runs: at the linked tower if there is one, and
## at whatever the attack landed on otherwise.
##
## Only the direction is read off the link. A tower linked ten cells away and
## one linked one cell away send the same beast the same distance, which is
## what makes the link an AIM rather than a reach.
##
## A tower linked to ITSELF is the same as no link at all, which is how
## StampedeTarget spells "back to normal" - see it for why that is the clear.
func _heading(tower: Building, target: Unit) -> Vector3:
	var towards: Vector3 = target.global_position
	var linked: Unit = tower.active_ability.linked_unit()
	if linked != null && linked != tower:
		towards = linked.global_position

	var direction: Vector3 = towards - tower.global_position
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return Vector3.ZERO
	return direction.normalized()


## The fallback with no beast to send: everything standing on the heading takes
## it at once. What this ability was before it had a body, kept because a
## missing prefab should cost the look and not the rule.
func _trample_line(tower: Building, direction: Vector3) -> void:
	if tower.stats == null:
		return
	var towards: Vector3 = tower.global_position + direction * beast_cells
	for creep: Creep in HitPattern.line(tower.area, tower.global_position,
			towards, beast_cells, 64, tower.stats.attack):
		if creep.is_flying():
			continue
		trample(creep)


func effect_text() -> String:
	var text: String = ("Strikes %d additional creep within %s cells and gains"
		+ " %s mana per creep hit. At full mana it sends a beast %s cells down"
		+ " the lane, dealing %s Siege damage to every ground creep in its path"
		+ " and stunning them for %ss - once every %ss per creep.") % [
		additional_targets,
		StringUtil.trim_number(multishot_cells),
		StringUtil.trim_number(mana_per_target),
		StringUtil.trim_number(beast_cells),
		StringUtil.compact_number(beast_damage),
		StringUtil.trim_number(stun_seconds),
		StringUtil.trim_number(stun_cooldown),
	]
	text += (" It runs towards whatever the attack landed on, or towards the"
		+ " linked tower while this one is linked.")
	if range_bonus_per_cell > 0.0:
		text += "\n\nDamage rises %s%% per cell of range to the target, up to +%s%%." % [
			StringUtil.trim_number(range_bonus_per_cell * 100.0),
			StringUtil.trim_number(max_range_bonus * 100.0)]
	return text


## The beast's own scene, checked once at boot like every other declared path -
## the editor does not rewrite one when a scene moves. See Main._validate_content.
func validate(_seen: Dictionary) -> bool:
	if SceneUtil.exists(beast_scene_path):
		return true
	Log.err("Bloodthirst names a beast scene that does not resolve", {
		"ability": display_name,
		"path": beast_scene_path,
	})
	return false
