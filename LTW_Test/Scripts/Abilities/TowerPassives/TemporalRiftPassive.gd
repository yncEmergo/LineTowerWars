class_name TemporalRiftPassive
extends TowerPassive

## Void 1, the whole Harbinger line: the tower that takes a creep's PROGRESS
## rather than its health.
##
## unit_data.md 4.9: it marks a creep in range; a few seconds later that creep
## is dragged back to where it came from and takes a share of its maximum
## health as Spell Damage. Half the mana comes back if it dies while waiting.
##
## Being sent backwards is what makes it worth its price. Against a Tier 4
## creep with an enormous health pool the damage barely registers, and having
## to walk a third of the maze again is worth several towers' output.
##
## IT FIRES ON AN ATTACK, not on a clock. The tower has to be shooting
## something for the rift to go off at all, and the creep it picks is chosen
## around WHAT IT IS SHOOTING rather than around the tower - so a Harbinger
## covering a corner rifts the pack going past the corner, not whatever
## happens to be nearest its own feet. Full mana is the price; the attack is
## the trigger.
##
## The Ultimate's other half - converting nearby Greater Harbingers - is a
## SEPARATE ability with a square of its own, because it is on a clock rather
## than on this one's mana and a repeating wait is something a player plans
## around. See VoidConversionPassive.

const MARK_KEY: String = "rift_target"
const DELAY_KEY: String = "rift_delay"
const POINT_KEY: String = "rift_point"

@export_group("Temporal Rift")
## Mana regenerated per second.
@export var regen_per_second: float = 10.0
## How far around the CREEP BEING SHOT it looks for something to mark, in
## player cells.
@export var radius_cells: float = 2.34
## Seconds between marking a creep and dragging it back.
@export var delay_seconds: float = 3.0
## Share of the creep's MAXIMUM health dealt as Spell Damage.
@export var health_share: float = 0.02
## Flat Spell Damage on top of that.
@export var flat_damage: int = 300
## Seconds before the same creep may be rifted again, counted from the moment
## it LANDS rather than from the moment it is marked. Those are not the same
## clock: started at the mark it would be eaten into by the delay, and a 9
## second cooldown on a 3.6 second rift would really be 5.4 seconds of freedom.
##
## So a creep is untouchable by this ability for delay_seconds + this, in one
## unbroken stretch - see on_attack for why the stretch has to be unbroken
## rather than handed over halfway.
@export var creep_cooldown: float = 9.0
## Share of the mana handed back when the creep dies during the delay.
@export var refund_share: float = 0.5
## Movement taken when it lands, ignoring every slow resistance, or 0 on the
## tiers that only damage.
@export var slow_amount: float = 0.0

@export_group("Visuals")
## Dropped where the creep will be sent back to, for as long as the delay
## lasts. A res:// path, and optional - an empty one is a rift nobody can see
## coming, which is a look rather than a fault.
@export_file("*.tscn") var marker_scene_path: String = ""
## Carried BY the marked creep until the rift collects, so a player can tell
## which creep in a pack is about to lose its progress. Parented to the creep,
## so it follows it and dies with it.
##
## AUTHORED EMPTY, on review: the mark that used to hang over a creep's head
## read as noise on a moving target rather than as a warning. The hook stays
## because carrying something IS the right shape for "this creep is in a state
## right now", and a better-looking one is a path away.
@export_file("*.tscn") var mark_scene_path: String = ""

## Cached scenes and whether loading them has been tried. Asked once per rift,
## so neither may go back to the loader every time one goes off.
var _cached_marker: PackedScene = null
var _cached_mark: PackedScene = null
var _marker_loaded: bool = false
var _mark_loaded: bool = false


func mana_per_second(_tower: Building) -> float:
	return regen_per_second


## The attack is the trigger. Nothing here spends anything unless there is a
## creep worth spending it on, so a Harbinger shooting a creep that is already
## rifted simply keeps its mana until there is something to use it on.
func on_attack(tower: Building, target: Unit) -> void:
	if tower.ability_state.has(MARK_KEY) || !tower.has_full_mana():
		return
	if tower.area == null || tower.stats == null || !MatchSession.is_authority():
		return

	var creep: Creep = _pick(tower, target as Creep)
	if creep == null:
		return

	# THE WHOLE WINDOW AT ONCE - the rift's own delay and the cooldown that
	# follows it - rather than the delay now and the cooldown on landing.
	#
	# Set as two pieces it has a SEAM, and the seam is a real hole rather than
	# a theoretical one. The creep's immunity and this tower's delay are the
	# same number counted down by different nodes, so they expire on the same
	# tick and which one moves first inside that tick is tree order. Half the
	# time the creep comes out of its immunity before the rift collects, and
	# any other Harbinger attacking in that frame marks a creep that is about
	# to be dragged somewhere else - which then collects to a point AHEAD of
	# where the creep ends up and throws it forward.
	#
	# Rare per frame, and not rare in play: this line converts its neighbours
	# into more of itself, so a lane that has one Ultimate Harbinger in it soon
	# has several, all sharing this one immunity key and all rolling that dice.
	creep.status().set_immune(resource_path, delay_seconds + creep_cooldown)
	tower.drain_mana()
	tower.ability_state[MARK_KEY] = creep.unit_id
	tower.ability_state[DELAY_KEY] = delay_seconds
	# WHERE, not only who. The whole effect is that the creep goes back to the
	# spot it was standing on when it was marked, so that spot has to be
	# remembered here - there is nothing to work it out from later, and the
	# mark on the ground and the destination are then the same point by
	# construction rather than by two computations agreeing.
	tower.ability_state[POINT_KEY] = creep.global_position
	_show_mark(creep, creep.global_position)


## Which creep the rift takes, searched around the one being SHOT.
##
## The target itself first, because that is the creep the player is watching
## and the one they would expect to go. Only when it cannot be taken - already
## rifted, or still inside its own cooldown - does it fall to the nearest creep
## to it that can. Nothing eligible at all means the rift does not fire, which
## is what keeps the mana for the next attack.
func _pick(tower: Building, target: Creep) -> Creep:
	if target == null || !is_instance_valid(target):
		return null
	if _may_take(target):
		return target

	var best: Creep = null
	var best_distance: float = INF
	for creep: Creep in TargetFinder.creeps_in_radius(
			tower.area, target.global_position, radius_cells):
		if creep == target || !_may_take(creep):
			continue
		if !TargetFinder.can_be_hit_by(creep, tower.stats.attack):
			continue
		var distance: float = target.global_position.distance_squared_to(
			creep.global_position)
		if distance < best_distance:
			best = creep
			best_distance = distance
	return best


## A creep may be taken when it is alive and is not already shut out by this
## ability.
##
## ONE immunity key covers the whole window - the rift running on the creep and
## the cooldown after it, unbroken - so this single question answers both "is
## it already marked" and "is it still on cooldown". Every tier of the line
## shares the key through its own resource_path, which is what stops two
## Harbingers rifting the same creep at once.
func _may_take(creep: Creep) -> bool:
	if creep == null || !is_instance_valid(creep) || !creep.is_alive():
		return false
	return !creep.status().is_immune(resource_path)


## The delay half, which does run on the clock: something has to be counting
## while the marked creep walks on.
func on_tick(tower: Building, delta: float) -> void:
	if !tower.ability_state.has(MARK_KEY):
		return

	var left: float = float(tower.ability_state.get(DELAY_KEY, 0.0)) - delta
	tower.ability_state[DELAY_KEY] = left
	if left > 0.0:
		return

	var session: MatchSession = References.match_session
	var id: int = int(tower.ability_state[MARK_KEY])
	tower.ability_state.erase(MARK_KEY)

	var point: Vector3 = tower.ability_state.get(POINT_KEY, Vector3.ZERO)
	tower.ability_state.erase(POINT_KEY)

	var creep: Creep = null if session == null else session.unit_for(id) as Creep
	if creep == null || !is_instance_valid(creep) || !creep.is_alive():
		# It died while waiting, so half the mana comes back.
		tower.gain_mana(float(tower.max_mana) * refund_share)
		return
	_collect(creep, point)


## Drags the creep back and hurts it.
##
## Back to the REMEMBERED point, which is the one thing the effect is actually
## about: the creep loses exactly the ground it covered during the delay.
## Creep.send_back_to checks the spot still exists and takes the nearest gap if
## a tower has gone up on it meanwhile.
func _collect(creep: Creep, point: Vector3) -> void:
	creep.send_back_to(point)
	# Topped back up to exactly the cooldown, measured from the landing. The
	# immunity set at the mark already covers this to within a tick, so this
	# changes almost nothing - what it buys is that the number is exact however
	# long the delay actually took to run out, and there is never a frame
	# between the two where the creep is free.
	creep.status().set_immune(resource_path, creep_cooldown)

	var damage: int = flat_damage + int(round(float(creep.max_health()) * health_share))
	creep.take_damage(damage, DamageTable.DamageType.SPELL)
	if slow_amount > 0.0 && creep.is_alive():
		creep.status().slow(self, resource_path, slow_amount,
			StatusEffects.DEFAULT_SLOW_SECONDS)


# --- visuals ----------------------------------------------------------------
#
# PRESENTATION, and it stands aside on a dedicated server the way every effect
# does: References.effects_root is null there, and that is the test for whether
# this machine draws anything at all.

## Puts up both halves of the warning: the spot on the ground the creep is
## going back to, and the mark it carries until it gets there.
func _show_mark(creep: Creep, point: Vector3) -> void:
	var root: Node3D = References.effects_root
	if root == null:
		return

	var marker: Node3D = _spawn(_marker_scene(), root)
	if marker != null:
		marker.global_position = point
		# The delay is per TIER, so the marker is told how long to stand rather
		# than authoring a life of its own that would be right for one of them.
		_hold_for(marker, delay_seconds)
		_play(marker)

	# Parented to the CREEP rather than to the effects root, so it rides along
	# and goes when the creep does - a mark left floating where a creep died
	# would point at nothing. Nothing authors one at the moment.
	var mark: Node3D = _spawn(_mark_scene(), creep)
	if mark != null:
		mark.position = Vector3(0.0, creep.health_bar_height, 0.0)
		_hold_for(mark, delay_seconds)
		_play(mark)


func _spawn(scene: PackedScene, parent: Node) -> Node3D:
	if scene == null:
		return null
	var effect: Node3D = scene.instantiate() as Node3D
	if effect == null:
		return null
	parent.add_child(effect)
	return effect


## Starts an effect's particles, LAST and only once it is where it belongs.
## Particles emit in world space and a burst fires the instant it is allowed
## to, so one started on the way into the tree leaves its whole spray wherever
## its parent's origin happened to be. See VisualEffect3D.play().
func _play(effect: Node3D) -> void:
	var visual: VisualEffect3D = effect as VisualEffect3D
	if visual != null:
		visual.play()


## Tells an effect how long to last, if it is the kind that can be told. An
## ImpactBurst holds at full size and then fades, which is exactly the shape a
## warning that has to last a known number of seconds wants.
func _hold_for(effect: Node3D, seconds: float) -> void:
	var burst: ImpactBurst = effect as ImpactBurst
	if burst != null:
		burst.duration = seconds


## Both of these treat an EMPTY path as the answer "this rift has no such
## visual", exactly as validate() below already does and as
## AttackDelivery.impact_scene() does for the same kind of optional path. An
## empty one never reaches the loader, which reports it as the fault it usually
## is - and mark_scene_path is authored empty on every Harbinger in the game,
## so without this every match logged an error for content that is correct.
func _marker_scene() -> PackedScene:
	if marker_scene_path.is_empty():
		return null
	if !_marker_loaded:
		_marker_loaded = true
		_cached_marker = SceneUtil.load_scene(marker_scene_path, "rift marker")
	return _cached_marker


func _mark_scene() -> PackedScene:
	if mark_scene_path.is_empty():
		return null
	if !_mark_loaded:
		_mark_loaded = true
		_cached_mark = SceneUtil.load_scene(mark_scene_path, "rift mark")
	return _cached_mark


func effect_text() -> String:
	var text: String = ("Regenerates %s mana per second. At full mana its next"
		+ " attack marks the creep it is shooting - or the nearest creep within"
		+ " %s cells of it, if that one cannot be marked - and %ss later that"
		+ " creep is returned to where it came from and takes %s%% of its"
		+ " maximum health plus %s as Spell Damage. A creep is then safe from"
		+ " it for %ss from the moment it lands, and %d%% of the mana is"
		+ " refunded if it dies waiting.") % [
		StringUtil.trim_number(regen_per_second),
		StringUtil.trim_number(radius_cells),
		StringUtil.trim_number(delay_seconds),
		StringUtil.trim_number(health_share * 100.0),
		StringUtil.compact_number(flat_damage),
		StringUtil.trim_number(creep_cooldown),
		int(round(refund_share * 100.0)),
	]
	if slow_amount > 0.0:
		text += " It is also slowed by %s%%, ignoring all slow resistance." \
			% StringUtil.trim_number(slow_amount * 100.0)
	return text


## Both scenes are optional, so only a filled-in path that does not resolve is
## a fault. An ability with no visuals still works.
func validate(seen: Dictionary) -> bool:
	var complete: bool = super(seen)
	for path: String in [marker_scene_path, mark_scene_path]:
		if !path.is_empty() && !SceneUtil.exists(path):
			Log.err("Temporal rift visual does not resolve", {
				"owner": display_name,
				"path": path,
			})
			complete = false
	return complete
