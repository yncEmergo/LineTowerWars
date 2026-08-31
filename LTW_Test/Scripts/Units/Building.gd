class_name Building
extends Unit

## A unit that occupies grid cells instead of moving: towers, and later the
## creep sending building.
##
## The footprint is claimed the moment the order completes, so a building
## still under construction blocks pathing exactly like a finished one. That
## matches WC3 and, more importantly, means the no-full-block rule cannot be
## dodged by placing a tower and mazing around it before it finishes.
##
## While building, health climbs from 1 to full over the build time, which
## doubles as the construction progress bar. Damage taken meanwhile lowers the
## result without slowing the timer, so an attacked tower finishes on schedule
## but arrives hurt.

signal construction_finished()
signal sell_started()
signal sell_cancelled()
signal upgrade_started()
signal upgrade_cancelled()

## Height the building's visuals start at while they rise into place.
const CONSTRUCTION_START_HEIGHT: float = 0.15

## Gap between the health bar and the job bar sitting above it. A little more
## than a bar's own height, so the two read as two bars rather than one thick
## one. Placeholder visual values, so they live here rather than in a .tres.
const JOB_BAR_GAP: float = 0.16
const JOB_BAR_FILL: Color = Color(0.93, 0.74, 0.24, 1.0)
const JOB_BAR_EMPTY: Color = Color(0.16, 0.13, 0.06, 1.0)

## Gap between the health bar and the second-resource bar sitting UNDER it, on
## the same reasoning as the one above. The two stacks read outwards from the
## health bar: what the tower is doing above it, what it is running on below.
const RESOURCE_BAR_GAP: float = 0.16

@export_group("References")
## Meshes that rise during construction. Separate from the root so the health
## bar does not get squashed along with them.
@export var _visual_root: Node3D

## Top-left internal cell of this building's footprint, or -1 when unplaced.
var cell: Vector2i = Vector2i(-1, -1)
## Gold sunk into this building, which the sell refund is a share of. Upgrades
## will add to this rather than being tracked separately.
var invested_gold: int = 0

## Mana this tower holds right now, whole points. 0 for every tower that uses
## none, which is every Basic one.
var current_mana: int = 0
## Maximum mana this tower has RIGHT NOW, which is not always its stats figure:
## the Ultimate Orb Keeper lowers its own ceiling as it fires, and resets it
## when it runs out. -1 until _ready reads the stats.
var max_mana: int = -1
## Scratch space the tower's own passives keep their per-tower state in, keyed
## by whatever each passive calls it.
##
## It lives here rather than on the passive because a passive is a SHARED
## resource - one .tres is every tower of that type at once - and because the
## state is genuinely the tower's: how much damage it has eaten, which creep it
## has been ramping up on, when it last idled. See TowerPassive.
var ability_state: Dictionary = {}
## What this tower's ACTIVE ability - the one a player presses - is waiting on
## and what it has been aimed at. Its own object rather than two more fields
## here, and unlike ability_state above BOTH of its numbers are drawn on a
## card, so both come down the wire. See ActiveAbilityState.
var active_ability: ActiveAbilityState = ActiveAbilityState.new()
## Permanent attack damage this tower's passives have banked, as the SERVER
## last reported it, and meaningful on a CLIENT only.
##
## A client runs no simulation, so nothing of its own ever fills ability_state
## for a bonus bought by KILLING - the kill happens on the server. Without this
## a player would be looking at their own Alchemist's damage line and its stack
## bar reading zero all match. See ReplicationService, which sets it, and
## DevourEssencePassive, which reads it instead of its own key off a client.
##
## One number for the whole tower rather than one per passive: a tower with two
## passives that both bank damage does not exist and would need its own record
## anyway.
var replicated_damage_bonus: int = 0
## Which option a CYCLED ability on this tower is set to, as the SERVER last
## reported it, and meaningful on a CLIENT only.
##
## Same reason as the line above and the Prioritize flag beside it in the
## snapshot: it is a setting the player changed, the change is the server's to
## make, and a card that went on drawing the old answer would read as a button
## that does nothing. One number per tower, because no tower carries two
## abilities that cycle.
var replicated_ability_choice: int = 0

## The tower's own passives, read off its stats once. Cached because they are
## asked on every tick and every hit, and because the card can swap underneath
## while a tower builds or sells without the mechanics changing.
var _tower_passives: Array[TowerPassive] = []
## Fraction of a mana point regeneration has built up but not handed over yet,
## so a rate below one point a tick still fills.
var _mana_carry: float = 0.0
var _under_construction: bool = false
var _construction_elapsed: float = 0.0
var _selling: bool = false
var _sell_elapsed: float = 0.0
var _upgrading: bool = false
var _upgrade_elapsed: float = 0.0
## Whether the morph currently running is a RETURN to an Elemental Core rather
## than an upgrade. The two share every mechanism and differ in exactly three
## places - the clock, the money and what is carried over - so this marks which
## one is running rather than duplicating the machinery. See return_to_core.
var _returning: bool = false
## What this tower is turning into, held only while the upgrade runs.
##
## Per-unit state and so it lives here rather than on the ability, which is
## shared between every tower of this type and must stay stateless.
var _upgrade_target: BuildingStats = null
## The TARGET tier's model, standing in for this one while the upgrade runs.
##
## An upgrade shows what you are buying, not what you are replacing: the new
## tower rises out of the ground over the countdown and the old one is hidden
## behind it. Anything else makes an upgrade look like a tower being rebuilt
## into the same thing it already was.
##
## Only the LOOK is swapped early. The unit, its stats, its card and its
## attack are still the old tier's until the upgrade actually completes, which
## is what keeps a cancel free and keeps the server and this client agreeing
## about what is standing here.
var _upgrade_preview: Node3D = null
## Damage suffered while still building, kept apart from the construction ramp
## so attacks never slow the timer.
var _construction_damage: int = 0
## Worldspace bar over this tower's head while it is selling or morphing.
##
## Built on the FIRST job rather than in _ready, because most towers stand in a
## maze for a whole match and never have one. Kept afterwards rather than freed
## with the job, since a tower that sold once is a tower somebody is fiddling
## with and will probably sell again.
var _job_bar: Bar3D = null
## Worldspace bar under this tower's health bar, on the towers that run on a
## second resource. Built in _ready rather than lazily, unlike the job bar:
## a tower that has one has it from the moment it is standing.
var _resource_bar: ResourceBar3D = null

var _building_stats: BuildingStats:
	get:
		return stats as BuildingStats

var _config: GameConfig:
	get:
		return References.game_config


func _ready() -> void:
	super()
	if stats != null && _building_stats == null:
		Log.err("Building needs BuildingStats but got plain UnitStats", name)
	_collect_passives()
	_reset_mana()
	if secondary_resource() != null:
		_create_resource_bar()


## Reads this building's passives off its stats once. They are asked on every
## tick and every hit, not because the list is expensive to build.
func _collect_passives() -> void:
	_tower_passives.clear()
	if stats == null:
		return
	for entry in stats.abilities:
		var passive: TowerPassive = entry as TowerPassive
		if passive != null:
			_tower_passives.append(passive)


func _reset_mana() -> void:
	if _building_stats == null:
		max_mana = 0
		return
	max_mana = maxi(0, _building_stats.max_mana)
	current_mana = int(round(float(max_mana) * clampf(
		_building_stats.starting_mana_ratio, 0.0, 1.0)))


# --- Mana ---------------------------------------------------------------

## The tower's passives, for whatever needs to ask all of them at once. Empty
## for every Basic tower, which is what makes them cost nothing.
func tower_passives() -> Array[TowerPassive]:
	return _tower_passives


## Whether this tower uses mana at all, which is what decides whether the panel
## draws a mana bar for it.
func uses_mana() -> bool:
	return max_mana > 0


## How full the tower is, 0 to 1. 0 for a tower with no mana, so a caller never
## has to divide by a ceiling that might be zero.
func mana_ratio() -> float:
	if max_mana <= 0:
		return 0.0
	return clampf(float(current_mana) / float(max_mana), 0.0, 1.0)


func has_full_mana() -> bool:
	return max_mana > 0 && current_mana >= max_mana


## The SECOND RESOURCE this tower runs on, or null for one that runs on
## nothing but its health - which is every Basic tower.
##
## A passive's own count comes FIRST, and that order is the rule rather than a
## preference: a tower whose ability BANKS something is saying that the bank is
## what decides what it is worth right now, which is the whole of what the
## second bar means (game_rules.md). The Alchemist line is the case - it holds
## mana it can never spend on anything, and the number worth a bar is the one
## its ability actually reads.
func secondary_resource() -> TowerResource:
	for passive in _tower_passives:
		var banked: TowerResource = passive.tower_resource(self)
		if banked != null:
			return banked
	if !uses_mana():
		return null
	return TowerResource.mana(current_mana, max_mana)


## Which option this tower's cycled ability is set to, or 0 for a tower with no
## such ability - which is nearly every tower. See UnitAbility.choice_index.
##
## The one place the two answers are chosen between, so nothing that draws the
## setting has to know whether it is running on the server or watching one.
func ability_choice() -> int:
	if !MatchSession.is_authority():
		return replicated_ability_choice
	if stats == null:
		return 0
	for entry in stats.abilities:
		var index: int = entry.choice_index(self)
		if index >= 0:
			return index
	return 0


## Attack damage this tower's passives have added to it for good, on top of
## whatever its stats say. 0 for every tower that grows into nothing.
##
## Summed here rather than at each reader, because the damage line, the stack
## bar and the snapshot all want the same answer. Each passive is asked for its
## own figure and is the one that knows whether a client may trust its own copy
## of it - see replicated_damage_bonus.
func permanent_damage_bonus() -> int:
	var total: int = 0
	for passive in _tower_passives:
		total += passive.permanent_bonus(self)
	return total


## Adds mana, never past the ceiling and never below zero. Fractional amounts
## are carried between calls, so a regeneration slower than one point a tick
## still fills rather than doing nothing at all.
##
## Authority only, exactly as health is: a client is TOLD how much mana a tower
## has, so filling it locally would show a number the server never agreed to.
func gain_mana(amount: float) -> void:
	if max_mana <= 0 || amount == 0.0 || !MatchSession.is_authority():
		return

	_mana_carry += amount
	var whole: int = int(_mana_carry)
	if whole == 0:
		return
	_mana_carry -= float(whole)
	current_mana = clampi(current_mana + whole, 0, max_mana)


## Takes mana if there is enough, and answers whether there was. All or
## nothing, because every ability that spends mana in unit_data.md spends a
## fixed amount and does nothing at all when it cannot.
func spend_mana(amount: int) -> bool:
	if amount <= 0:
		return true
	if !MatchSession.is_authority() || current_mana < amount:
		return false
	current_mana -= amount
	return true


## Empties the tower and answers what was in it, for the abilities that spend
## whatever they have rather than a fixed price - the Ultimate Moonbeam's
## flames and the Hurricane Elemental's fork both scale with what was left.
func drain_mana() -> int:
	if !MatchSession.is_authority():
		return 0
	var stored: int = current_mana
	current_mana = 0
	_mana_carry = 0.0
	return stored


## Lowers this tower's own ceiling, which only the Ultimate Orb Keeper does.
## Answers the new ceiling so the caller can act on it having bottomed out.
func set_max_mana(value: int) -> int:
	max_mana = maxi(0, value)
	current_mana = mini(current_mana, max_mana)
	return max_mana


## Takes over what the tier below this one had banked. Called by the upgrade
## that replaced it, after the replacement is standing.
##
## Mana is carried across but CLAMPED to the new ceiling, and only when the new
## tier does not author a starting ratio of its own - a Lesser Moonbeam is
## built full on purpose and must not inherit an empty Magma Well.
func inherit_ability_state(banked: Dictionary, mana: int,
		active: ActiveAbilityState = null) -> void:
	for key in banked:
		ability_state[key] = banked[key]
	active_ability.inherit(active)
	if _building_stats != null && _building_stats.starting_mana_ratio > 0.0:
		return
	current_mana = clampi(mana, 0, max_mana)


## Mana handed down by the server, which is the ONLY way it changes on a client
## (3.2). Not routed through gain_mana for the same reason health is not routed
## through _set_health: this has already been through the rules once.
func set_replicated_mana(value: int, maximum: int) -> void:
	max_mana = maxi(0, maximum)
	current_mana = clampi(value, 0, max_mana)


## Footprint in internal cells, which is what the grid works in.
func footprint() -> Vector2i:
	if _building_stats == null || area == null:
		return Vector2i(2, 2)
	return area.cells_to_internal(_building_stats.footprint_cells)


## Anchors the building to a grid cell and starts construction.
## Call after the node is in the tree.
##
## start_built skips the construction phase entirely, which is what the far
## side of an upgrade wants: the wait already happened on the tower that was
## standing here, and making the replacement serve it again would charge the
## player twice for one timer.
func place(player_id: int, home_area: PlayerArea, grid_cell: Vector2i, spent_gold: int,
		start_built: bool = false) -> void:
	setup(player_id, home_area)
	cell = grid_cell
	invested_gold = spent_gold

	# Named after its grid cell, so the scene tree stays readable once a maze
	# has thirty towers in it rather than a wall of @Node3D@7.
	if _building_stats != null:
		name = "%s_%d_%d" % [
			_building_stats.display_name.replace(" ", ""), grid_cell.x, grid_cell.y
		]

	var size: Vector2i = footprint()
	home_area.occupy(grid_cell, size)
	global_position = home_area.footprint_world_center(grid_cell, size)
	reset_physics_interpolation()

	if start_built:
		_under_construction = false
		_apply_visual_height(1.0)
		_apply_animation_state()
		return
	_begin_construction()


## A replicated tower has to claim its grid cells too, or this client would let
## the player place another one on top of it and draw a green ghost while doing
## it - the build preview reads the local grid, not the server's.
##
## The cell is DERIVED from the position rather than sent. place() puts a
## building at its footprint's world centre, so snapping that centre back gives
## the cell it came from, and the message stays one position shorter.
##
## invested_gold is taken from the tower TYPE rather than sent, because there
## is exactly one path to owning any given tower and so exactly one figure it
## can have sunk into it. That makes the sell refund quoted here right even for
## a tower that was already standing when this machine joined, and it costs the
## snapshot nothing. See BuildingStats.total_gold_cost.
func adopt(id: int, player_id: int, home_area: PlayerArea, world_pos: Vector3) -> void:
	var session: MatchSession = References.match_session
	if session != null && session.claim_unit_id(self, id):
		unit_id = id

	global_position = world_pos
	var size: Vector2i = _adopted_footprint(home_area)
	var spent: int = 0 if _building_stats == null else _building_stats.total_gold_cost
	place(player_id, home_area, home_area.snap_footprint(world_pos, size), spent)


func _adopted_footprint(home_area: PlayerArea) -> Vector2i:
	if _building_stats == null:
		return Vector2i(2, 2)
	return home_area.cells_to_internal(_building_stats.footprint_cells)


## What the server says this building is doing, which on a client is the only
## thing that says so: the timers that would normally flip these are switched
## off (3.4).
##
## The upgrade squashes the model the same way construction does, so a client
## can see that something is happening to a tower that has otherwise not
## changed. It is only ever a phase here - the swap to the new tower type
## arrives as an ordinary snapshot, see ReplicationService.
func set_replicated_phase(under_construction: bool, selling: bool,
		upgrading: bool, returning: bool, progress: float) -> void:
	if _under_construction && !under_construction:
		_finish_construction()

	var was_upgrading: bool = _upgrading
	_under_construction = under_construction
	_selling = selling
	_upgrading = upgrading
	_returning = returning
	_apply_replicated_progress(progress)

	if upgrading != was_upgrading:
		if upgrading && _upgrade_target != null:
			_show_upgrade_preview(_upgrade_target)
		elif !upgrading:
			_clear_upgrade_preview()
		_apply_visual_height(0.0 if upgrading else 1.0)
		_apply_animation_state()
		abilities_changed.emit()

	# The model rises across the countdown here as well as on the change, so a
	# client watching a tower go up or morph sees the same thing the server
	# does. Without the progress it had only the two ends of the movement and
	# the tower sat squashed until the job finished.
	if _under_construction || _upgrading:
		_apply_visual_height(progress)

	_refresh_job_bar()


## Puts the countdown clocks where the server says they are.
##
## Written INTO the same _elapsed fields a single player run uses rather than
## kept beside them, so current_job, upgrade_progress and the rising model all
## read one number through one path on both machines. A client never advances
## them itself - _physics_process stands aside (3.4) - so a snapshot is the
## only thing that ever moves them here.
func _apply_replicated_progress(progress: float) -> void:
	if _under_construction:
		_construction_elapsed = progress * _build_time()
	elif _selling:
		_sell_elapsed = progress * _sell_time()
	elif _upgrading:
		_upgrade_elapsed = progress * _upgrade_time()


func is_under_construction() -> bool:
	return _under_construction


## A tower still going up has nothing to shoot with, and neither does one in
## the middle of an upgrade - it is being rebuilt into something else. A tower
## being SOLD still shoots: it is standing, it still blocks the maze, and the
## sale can still be called off, so it goes on defending until it is actually
## gone.
func can_attack() -> bool:
	return super() && !_under_construction && !_upgrading


func is_structure() -> bool:
	return true


## Every tower is one selection class, so any two of them box and group
## together whatever their element or tier.
##
## A BUILDING THAT IS NOT A TOWER MUST OVERRIDE THIS. The technology discs are
## the case that is coming: they occupy a tower footprint and extend from here,
## and inheriting this line would quietly let them be selected among the towers,
## which game_rules.md says they never are.
func selection_class() -> StringName:
	return SELECT_TOWER


## The model, not the whole building. During an upgrade that is the model of
## the tier being BOUGHT, so a portrait shows what the player is waiting for
## rather than what is being replaced.
func visual_root() -> Node3D:
	return _rising_visual()


## A building in the middle of something offers only that job's card, which is
## what makes construction and selling interruptible and stops anything else
## being ordered meanwhile.
func current_abilities() -> Array:
	if _building_stats != null:
		if _under_construction:
			return _building_stats.construction_abilities
		if _upgrading:
			return _building_stats.upgrading_abilities
		if _selling:
			return _building_stats.selling_abilities
	return super()


# --- Selling ------------------------------------------------------------

## The state of whoever owns this building, or null outside a real match.
func _owner_state() -> PlayerState:
	var manager: PlayerManager = References.player_manager
	if manager == null:
		return null
	return manager.state_for(owner_player_id)


## Gold returned for selling right now.
func sell_refund() -> int:
	var ratio: float = 0.6
	if _config != null:
		ratio = _config.sell_refund_ratio
	return int(floor(float(invested_gold) * ratio))


## Aborts an unfinished building and returns the full price. Cancelling is not
## selling: nothing was gained, so nothing is kept.
func cancel_construction() -> void:
	if !_under_construction:
		return

	var manager: PlayerManager = References.player_manager
	if manager != null:
		var state: PlayerState = manager.state_for(owner_player_id)
		if state != null:
			state.gain(invested_gold)

	Log.info("Construction cancelled", {"building": name, "refund": invested_gold})
	queue_free()


func is_selling() -> bool:
	return _selling


## Begins a sale. The building stays standing and keeps blocking pathing for
## the whole countdown, so cancelling costs nothing and changes nothing.
func sell() -> void:
	if _selling || _under_construction || _upgrading:
		return

	var duration: float = _sell_time()

	if duration <= 0.0:
		_complete_sell()
		return

	_selling = true
	_sell_elapsed = 0.0
	_refresh_job_bar()
	sell_started.emit()
	# Swaps the card down to just cancel while the sale runs.
	abilities_changed.emit()


## Calls off a sale in progress and restores the normal command card.
func cancel_sell() -> void:
	if !_selling:
		return
	_selling = false
	_sell_elapsed = 0.0
	_refresh_job_bar()
	Log.info("Sale cancelled", {"building": name})
	sell_cancelled.emit()
	abilities_changed.emit()


## Removes the building and refunds its owner. The grid frees itself in
## _exit_tree, so selling and being destroyed take the same path.
func _complete_sell() -> void:
	var refund: int = sell_refund()
	var manager: PlayerManager = References.player_manager
	if manager != null:
		var state: PlayerState = manager.state_for(owner_player_id)
		if state != null:
			state.gain(refund)

	Log.info("Building sold", {"building": name, "refund": refund})
	queue_free()


# --- Upgrading ----------------------------------------------------------

func is_upgrading() -> bool:
	return _upgrading


## What this tower is turning into, or null when it is not upgrading.
func upgrade_target() -> BuildingStats:
	return _upgrade_target


## Whether the morph running is a RETURN to an Elemental Core rather than an
## upgrade. Both are one phase with one clock, so this is what tells them
## apart for anything outside this class - the panel, and the snapshot.
func is_returning() -> bool:
	return _returning


## How far through whatever countdown is running, 0 to 1, and 0 when none is.
##
## The RAW phase clock, which is not quite current_job(): construction is in
## here because a client has to be told about it, and left out of a job because
## a tower going up already shows its progress in its health. One number
## because a tower only ever runs one of these at a time.
func phase_progress() -> float:
	if _under_construction:
		return _construction_progress()
	if _selling:
		return _sell_progress()
	if _upgrading:
		return upgrade_progress()
	return 0.0


## Stands the target tier's model up in place of this one, flat to the ground,
## ready to rise. Its own visuals are hidden rather than removed, so cancelling
## is a matter of putting them back.
func _show_upgrade_preview(target_stats: BuildingStats) -> void:
	_clear_upgrade_preview()

	var scene: PackedScene = target_stats.model_scene()
	if scene == null:
		# No model to show, so the tower simply stays as it is for the
		# countdown. model_scene() has already reported why.
		return

	var preview: Node3D = scene.instantiate() as Node3D
	if preview == null:
		Log.err("Upgrade target's model root is not a Node3D",
			target_stats.display_name)
		return

	preview.name = "UpgradeVisual"
	add_child(preview)
	_upgrade_preview = preview
	if _visual_root != null:
		_visual_root.visible = false


func _clear_upgrade_preview() -> void:
	if _upgrade_preview != null && is_instance_valid(_upgrade_preview):
		_upgrade_preview.queue_free()
	_upgrade_preview = null
	if _visual_root != null:
		_visual_root.visible = true


## How far through the upgrade this is, 0 to 1. Drives the model rising back
## into place; a progress bar can read the same number later.
func upgrade_progress() -> float:
	var total: float = _upgrade_time()
	if total <= 0.0:
		return 1.0
	return clampf(_upgrade_elapsed / total, 0.0, 1.0)


## Begins turning this tower into another one, charging that tier's own price.
##
## Only the tier is charged, never the total: `invested_gold` accumulates, so a
## Watch Tower that cost 10 + 30 + 150 + 1,000 sells back a share of 1,190
## rather than of the last rung it climbed. The player table's Value column
## reads the same number, so both follow from one place.
##
## The tower stays standing and keeps blocking the maze for the whole
## countdown, exactly as a sale does, so an upgrade can never be used to open a
## path. What it does NOT do is keep shooting - it is being rebuilt.
func upgrade_to(target_stats: BuildingStats) -> void:
	if target_stats == null:
		Log.err("Building was told to upgrade into nothing", name)
		return
	if _under_construction || _selling || _upgrading:
		return

	var cost: int = target_stats.gold_cost
	var state: PlayerState = _owner_state()
	if state != null && !state.spend(cost):
		Log.warn("Not enough gold to upgrade", {
			"building": name, "into": target_stats.display_name, "cost": cost,
		})
		return

	invested_gold += cost
	# Same commitment a new tower makes: the gold is on the field, so the
	# technology choice behind it stops being undoable. See TechManager.
	if References.tech_manager != null:
		References.tech_manager.notify_construction_started(owner_player_id)

	_upgrade_target = target_stats
	_upgrading = true
	_upgrade_elapsed = 0.0
	_show_upgrade_preview(target_stats)
	_apply_visual_height(0.0)
	_apply_animation_state()
	_refresh_job_bar()

	Log.info("Upgrade started", {
		"building": name, "into": target_stats.display_name, "cost": cost,
	})
	upgrade_started.emit()
	# Swaps the card down to just cancel while the upgrade runs.
	abilities_changed.emit()


## Begins taking this tower back down to a bare Elemental Core.
##
## The way out of an element, and the reason it is a MORPH rather than a sale
## is the cell: the tower stays standing and keeps blocking for the whole
## countdown, a Core is standing there when it ends, and the maze never opens.
##
## Charges nothing. What it hands back arrives when the countdown COMPLETES,
## exactly as a sale's refund does - so calling it off costs nothing and
## changes nothing, and there is no gold to take back. See _refund_return for
## the share and for what stays sunk in the cell.
func return_to_core(core_stats: BuildingStats) -> void:
	if core_stats == null:
		Log.err("Building was told to return to nothing", name)
		return
	if _under_construction || _selling || _upgrading:
		return

	_upgrade_target = core_stats
	_upgrading = true
	_returning = true
	_upgrade_elapsed = 0.0
	_show_upgrade_preview(core_stats)
	_apply_visual_height(0.0)
	_apply_animation_state()
	_refresh_job_bar()

	Log.info("Return to Core started", {"building": name, "value": invested_gold})
	upgrade_started.emit()
	# Swaps the card down to just cancel while the return runs.
	abilities_changed.emit()


## Calls off the morph in progress, whichever one it is.
##
## An UPGRADE hands back only the tier that was being paid for, leaving
## everything sunk into the tower before it exactly where it was. A RETURN
## hands back nothing, because it charged nothing and pays out at the end -
## see return_to_core. Either way the tower goes back to what it was.
func cancel_upgrade() -> void:
	if !_upgrading:
		return

	# A return charged nothing and refunds on completion, so calling one off
	# moves no gold at all. Only an upgrade has a tier to hand back.
	var refund: int = 0
	if !_returning && _upgrade_target != null:
		refund = _upgrade_target.gold_cost
	invested_gold -= refund

	var state: PlayerState = _owner_state()
	if state != null:
		state.gain(refund)

	_upgrading = false
	_returning = false
	_upgrade_elapsed = 0.0
	_upgrade_target = null
	_clear_upgrade_preview()
	_apply_visual_height(1.0)
	_apply_animation_state()
	_refresh_job_bar()

	Log.info("Morph cancelled", {"building": name, "refund": refund})
	upgrade_cancelled.emit()
	abilities_changed.emit()


# --- Jobs ---------------------------------------------------------------

## What this tower is busy with, or null when it is simply standing there.
##
## The one question the UI asks about a countdown, whichever countdown it is.
## Selling, upgrading and returning to a Core are three timers with three
## different meanings and one identical presentation - a bar over the tower's
## head and a row on its panel - so they are answered here together rather than
## by three sets of getters the panel would have to try in turn.
##
## CONSTRUCTION is not one of them on purpose: a tower going up already says so
## by its health climbing from 1 to full, and a second bar would say it twice.
func current_job() -> BuildingJob:
	if _selling:
		return _make_job(BuildingJob.Kind.SELLING, _sell_progress(), _sell_time(),
			_sell_icon())

	if _upgrading:
		var kind: BuildingJob.Kind = BuildingJob.Kind.UPGRADING
		if _returning:
			kind = BuildingJob.Kind.RETURNING
		return _make_job(kind, upgrade_progress(), _upgrade_time(), _morph_icon())

	return null


func _make_job(kind: BuildingJob.Kind, progress: float, total: float,
		icon: Texture2D) -> BuildingJob:
	var job: BuildingJob = BuildingJob.new()
	job.kind = kind
	job.progress = progress
	job.seconds_left = maxf(0.0, total * (1.0 - progress))
	job.icon = icon
	return job


## How far through the sale this is, 0 to 1, on the same terms as
## upgrade_progress.
func _sell_progress() -> float:
	var total: float = _sell_time()
	if total <= 0.0:
		return 1.0
	return clampf(_sell_elapsed / total, 0.0, 1.0)


## The Sell button's own icon, taken off the tower's normal card rather than
## authored a second time here - it is literally the button that was pressed.
##
## The tower's own picture if it has no Sell ability at all, which is not a
## case that exists yet but is a blank square if it ever does.
func _sell_icon() -> Texture2D:
	if stats != null:
		for entry in stats.abilities:
			if entry is SellAbility:
				return (entry as UnitAbility).icon_texture()
	return null if stats == null else stats.icon


## What a morph is turning this tower into, because that is what the player is
## waiting for - the same reason the upgrade preview stands the TARGET's model
## up rather than this one's.
##
## Falls back to this tower's own picture, which is what a CLIENT gets: the
## target is never sent over the wire, only the phase and the progress are.
func _morph_icon() -> Texture2D:
	if _upgrade_target != null:
		return _upgrade_target.icon
	return null if stats == null else stats.icon


## Puts the worldspace bar in step with the job, building it the first time one
## is needed.
##
## The bar sits ABOVE the health bar and is shown for as long as the job runs,
## whatever the player has health bars set to. A sale is something the player
## started and can still call off, so it is not theirs to switch off - see
## game_rules.md.
func _refresh_job_bar() -> void:
	var job: BuildingJob = current_job()
	if job == null:
		if _job_bar != null:
			_job_bar.visible = false
		return

	if _job_bar == null:
		_create_job_bar()
	_job_bar.visible = true
	_job_bar.set_ratio(job.progress)


## Builds the second-resource bar and hangs it UNDER the health bar.
##
## Offset from where the health bar sits rather than from the bar itself, for
## the same reason the job bar is: the player may have health bars switched
## off, and a tower's second resource is not theirs to switch off with them.
func _create_resource_bar() -> void:
	_resource_bar = ResourceBar3D.new()
	_resource_bar.name = "ResourceBar"
	_resource_bar.watch(self)
	add_child(_resource_bar)
	_resource_bar.position = Vector3(0.0, health_bar_height - RESOURCE_BAR_GAP, 0.0)


func _create_job_bar() -> void:
	_job_bar = Bar3D.new()
	_job_bar.name = "JobBar"
	_job_bar.fill_color = JOB_BAR_FILL
	_job_bar.empty_color = JOB_BAR_EMPTY
	add_child(_job_bar)
	# Offset from where the health bar sits rather than from the health bar
	# itself, so the job bar stands in the same place whether or not that one
	# is being drawn.
	_job_bar.position = Vector3(0.0, health_bar_height + JOB_BAR_GAP, 0.0)


## Seconds this morph takes. An upgrade takes the build time - every tower
## shares one figure at every tier per unit_data.md 1.4 - and a return takes
## its own, because coming back down to a Core is a different job from going
## up. Both figures live on GameConfig.
func _upgrade_time() -> float:
	if _returning:
		return 0.0 if _config == null else _config.return_to_core_seconds
	return _build_time()


func _advance_upgrade(delta: float) -> void:
	_upgrade_elapsed += delta
	var progress: float = upgrade_progress()
	_apply_visual_height(progress)

	if progress >= 1.0:
		_complete_upgrade()
		return
	_refresh_job_bar()


## Swaps this tower for the one it was becoming.
##
## A REPLACEMENT rather than a change of clothes: the new tier is a different
## unit type with its own prefab, its own model and its own card, and
## replication already knows how to draw a unit type it has been handed. What
## carries over is the unit id, the grid cell and the gold - so to every other
## machine, and to the player's selection, this is still the same tower.
##
## The order below is load bearing:
##   1. the replacement enters the tree, so anything told about it finds a unit
##      that has run its _ready and knows its own health
##   2. the swap is ANNOUNCED while this tower is still standing, so the
##      selection and the control groups can put the replacement where this one
##      was. Announcing it afterwards would let tree_exiting empty them first
##   3. only then does this tower leave, which frees the grid cells and hands
##      the unit id back
##   4. the replacement claims that id and takes the cells
func _complete_upgrade() -> void:
	var target: BuildingStats = _upgrade_target
	var returning: bool = _returning
	_upgrading = false
	_returning = false
	_upgrade_elapsed = 0.0
	_upgrade_target = null

	_clear_upgrade_preview()

	var upgraded: Building = _instantiate_upgrade(target)
	if upgraded == null:
		# Nothing to become, so the tower goes back to what it was. The gold
		# stays spent, which is visible and wrong-looking on purpose: a missing
		# prefab is a content bug and should not be quietly absorbed.
		_apply_visual_height(1.0)
		abilities_changed.emit()
		return

	var parent: Node = get_parent()
	var kept_id: int = unit_id
	var kept_cell: Vector2i = cell
	var kept_gold: int = invested_gold
	# A RETURN pays out here rather than at the press, on the same terms a sale
	# does, and hands nothing else down: what arrives is a bare Core, so an
	# Alchemist's banked damage and a Moonbeam's mana are gone with the tower
	# that earned them. Only an UPGRADE is the same tower one tier further on.
	var kept_state: Dictionary = ability_state
	var kept_mana: int = current_mana
	var kept_active: ActiveAbilityState = active_ability
	if returning:
		kept_gold = _refund_return(target)
		kept_state = {}
		kept_mana = 0
		kept_active = null
	var home: PlayerArea = area
	var player: int = owner_player_id

	# Set before the node enters the tree, so nothing ever sees it owned by the
	# default player - which would read as an enemy tower for one call.
	upgraded.owner_player_id = player
	parent.add_child(upgraded)

	var session: MatchSession = References.match_session
	if session != null:
		session.replace_unit(self, upgraded)

	# remove_child runs _exit_tree straight away - queue_free would not - which
	# is what gives the grid cells and the unit id back before the replacement
	# asks for them.
	parent.remove_child(self)
	queue_free()

	if session != null && session.claim_unit_id(upgraded, kept_id):
		upgraded.unit_id = kept_id

	upgraded.place(player, home, kept_cell, kept_gold, true)
	# Everything the old tier's passives had banked comes across, because
	# unit_data.md says so in several places at once: an Alchemist keeps the
	# damage it has eaten, an Apprentice keeps its mana when it becomes a
	# Sorcerer. A passive whose new tier does not use a key simply never reads
	# it, which costs nothing.
	upgraded.inherit_ability_state(kept_state, kept_mana, kept_active)
	Log.info("Morph finished", {"tower": upgraded.name, "value": kept_gold})


## Hands back the sell share of everything sunk into this tower ABOVE the Core,
## and answers what stays sunk in the cell.
##
## The Core's own gold is not refunded, because the Core is not being sold - one
## is left standing on the cell. That is the rule the free morph already states
## from the other side: the 200 was paid for the Core and stays in that cell,
## so the sell refund reads the same either side of the morph. See
## game_rules.md, The Elemental Core.
##
## The share is sell_refund_ratio rather than a second number, since this IS a
## sale of the part that goes away, and two numbers would drift.
func _refund_return(core_stats: BuildingStats) -> int:
	var kept: int = 0 if core_stats == null else core_stats.total_gold_cost
	kept = clampi(kept, 0, invested_gold)

	var ratio: float = 0.6
	if _config != null:
		ratio = _config.sell_refund_ratio
	var refund: int = int(floor(float(invested_gold - kept) * ratio))

	var state: PlayerState = _owner_state()
	if state != null:
		state.gain(refund)

	Log.info("Returned to Core", {
		"building": name, "refund": refund, "kept": kept,
	})
	return kept


## Swaps this tower for another one FREE and AT ONCE: no gold, no countdown,
## and the value already sunk into this cell carried over unchanged.
##
## The Void element is what this exists for. A Voidling that fills its mana
## turns one of its neighbours into another Voidling, and the neighbour's owner
## pays nothing and waits for nothing - so upgrade_to(), which charges and
## starts a timer, is the wrong road entirely.
##
## The gold is DELIBERATELY not adjusted. A 10g Lesser Archer that becomes a
## 200g Voidling still has 10g sunk into it and still refunds a share of 10g,
## because 10g is what its owner actually spent. Anything else would let the
## Void line print gold through the sell button.
func transform_into(target_stats: BuildingStats) -> void:
	if target_stats == null || _under_construction || _selling || _upgrading:
		return
	if !MatchSession.is_authority():
		return

	# NOTHING IS HANDED DOWN. An upgrade is the same tower one tier further on
	# and carries its mana and whatever its ability had banked; a conversion is
	# a DIFFERENT tower, arriving because somebody else's ability reached over
	# and made it - so what stands here afterwards starts empty, at zero mana,
	# the way a freshly built one would.
	#
	# It matters more than it looks. A Voidling that has already grown keeps a
	# full bar and a spent flag; passing those on would give the Voidalisk it
	# becomes a bar it never had to fill and a flag saying it had already used
	# it - born finished, on the same tick.
	ability_state = {}
	current_mana = 0
	_upgrade_target = target_stats
	_complete_upgrade()


## The replacement tower, or null with a reason logged. Split out so
## _complete_upgrade reads as the sequence it is, rather than as three failure
## branches with a swap buried among them.
func _instantiate_upgrade(target: BuildingStats) -> Building:
	if target == null || area == null || get_parent() == null:
		Log.err("Upgrade completed with nothing to become", name)
		return null

	var scene: PackedScene = target.scene()
	if scene == null:
		Log.err("Upgrade target names no loadable prefab", target.display_name)
		return null

	var upgraded: Building = scene.instantiate() as Building
	if upgraded == null:
		Log.err("Upgrade target's prefab root is not a Building", target.display_name)
		return null
	return upgraded


## Leaves rubble where it stood, then goes.
##
## Only a DESTROYED tower reaches here: selling and upgrading both remove the
## node directly, so neither leaves rubble and neither has to say so. That is
## the whole distinction - rubble is what an attacker creep earns, and a player
## must not be able to lock their own cells by selling.
func _die() -> void:
	if cell.x >= 0 && is_instance_valid(area):
		area.mark_rubble(cell, footprint())
	super()


# --- Construction -------------------------------------------------------

func take_damage(amount: int, damage_type: DamageTable.DamageType,
		is_aoe: bool = false) -> void:
	if amount <= 0 || is_invulnerable():
		return

	# While building, health is driven by the ramp, so damage is banked and
	# subtracted from it rather than applied directly. The matrix still applies:
	# what is banked is what the hit actually cost.
	if _under_construction:
		_construction_damage += resolve_damage(amount, damage_type, is_aoe)
		_apply_construction_health()
		return

	super(amount, damage_type, is_aoe)


## Seconds a build - and so an upgrade - takes. One figure for every tower at
## every tier, so it comes off GameConfig rather than off the stats file of
## whichever tower happens to be going up. 0 with no config means instant,
## which is the same graceful answer an authored 0 would give.
func _build_time() -> float:
	if _config == null:
		return 0.0
	return _config.build_seconds


## Seconds a sale takes, on the same terms as _build_time.
func _sell_time() -> float:
	if _config == null:
		return 0.0
	return _config.sell_seconds


func _begin_construction() -> void:
	var total: float = _build_time()

	_construction_damage = 0
	_construction_elapsed = 0.0

	if total <= 0.0:
		_under_construction = false
		_apply_visual_height(1.0)
		_apply_animation_state()
		return

	_under_construction = true
	_apply_visual_height(0.0)
	_apply_construction_health()
	_apply_animation_state()


func _construction_progress() -> float:
	var total: float = _build_time()
	if total <= 0.0:
		return 1.0
	return clampf(_construction_elapsed / total, 0.0, 1.0)


## Health climbs from 1 to full across the build, minus anything taken on the
## way, so the bar reads as a construction progress bar.
func _apply_construction_health() -> void:
	var target: float = lerpf(1.0, float(max_health()), _construction_progress())
	_set_health(target - float(_construction_damage))


func _apply_visual_height(progress: float) -> void:
	var root: Node3D = _rising_visual()
	root.scale = Vector3(1.0, lerpf(CONSTRUCTION_START_HEIGHT, 1.0, progress), 1.0)


## Whatever is currently rising out of the ground: the upgrade's preview if one
## is standing, otherwise this building's own visuals.
func _rising_visual() -> Node3D:
	if _upgrade_preview != null && is_instance_valid(_upgrade_preview):
		return _upgrade_preview
	return _visual_root if _visual_root != null else self


## Holds this building's own motion still while it is being assembled, and lets
## it run once it is finished. Decoration only - see UnitModel.set_animated().
func _apply_animation_state() -> void:
	var model: UnitModel = _visual_root as UnitModel
	if model != null:
		model.set_animated(!_under_construction && !_upgrading)

	var preview: UnitModel = _upgrade_preview as UnitModel
	if preview != null && is_instance_valid(preview):
		# The thing being built never animates. It is not finished.
		preview.set_animated(false)


## Simulation, so it runs on the fixed tick rather than the render frame.
## See multiplayer.md: every machine must advance this the same way, and a
## render frame is whatever the player's GPU felt like doing.
func _physics_process(delta: float) -> void:
	# 3.4: a client runs no simulation of its own. What it draws is what the
	# server sent, so anything that would advance the world here has to stand
	# aside. See MatchSession.is_authority().
	if !MatchSession.is_authority():
		return

	if _building_stats == null:
		return

	if _under_construction:
		_advance_construction(delta)
		return

	# A tower's only order is Attack, and its whole task is waiting for the
	# creep it was aimed at to die. Below the construction gate, because a
	# tower still going up cannot be aimed at anything.
	_advance_orders(delta)

	# Regeneration runs for anything STANDING, whatever else it is doing. A
	# tower mid-upgrade or mid-sale is still a body in the maze that creeps
	# are hitting, and both jobs can be called off, so neither is a reason to
	# stop healing. Only a building still going up is excluded, because its
	# health is the construction ramp's to drive - see _apply_construction_health.
	_regenerate(delta)

	if _upgrading:
		_advance_upgrade(delta)
		return
	if _selling:
		_advance_sell(delta)

	# A tower being SOLD still runs its passives, exactly as it still shoots:
	# it is standing, the sale can be called off, and stopping its aura for
	# three seconds would be a hole in a maze nobody asked for.
	_advance_passives(delta)
	active_ability.advance(delta)


## Health every standing building gets back per second, all sources summed.
##
## Its base is a share of its own maximum rather than a flat rate, so the rule
## is one number for a roster whose health spans two orders of magnitude. See
## GameConfig.building_health_regen_ratio and unit_data.md 1.4.
##
## Its own function rather than a line inside _regenerate for the same reason
## armor_value() is asked of the unit rather than read off its stats: the Holy
## line's aura grants tower regeneration on top of this, and the config cannot
## know what is standing nearby. Nothing adds to it yet.
func _health_regen_per_second() -> float:
	if _config == null:
		return 0.0
	return float(max_health()) * _config.building_health_regen_ratio


## Heals the building back up on its own clock.
##
## No fraction is carried between ticks, because current_health IS a float - a
## tenth of a point regenerated is a tenth of a point held, and what the player
## reads is display_health() rounding it back up. A building already full or
## already down needs no guard here: heal() turns the first into a clamp that
## changes nothing and refuses the second outright.
func _regenerate(delta: float) -> void:
	heal(_health_regen_per_second() * delta)


## Runs the tower's own passives: their mana, and whatever each of them does on
## a clock of its own.
##
## Mana is summed across every passive and applied once, so two passives that
## both regenerate add up and neither has to know about the other. It is
## deliberately applied BEFORE the ticks, so a passive that spends at full mana
## sees the point that filled it on the same tick it arrives.
func _advance_passives(delta: float) -> void:
	if _tower_passives.is_empty():
		return

	var per_second: float = 0.0
	for passive in _tower_passives:
		per_second += passive.mana_per_second(self)
	if per_second != 0.0:
		gain_mana(per_second * delta)

	for passive in _tower_passives:
		passive.on_tick(self, delta)


func _advance_construction(delta: float) -> void:
	_construction_elapsed += delta
	var progress: float = _construction_progress()
	_apply_visual_height(progress)
	_apply_construction_health()

	if progress >= 1.0:
		_finish_construction()


func _advance_sell(delta: float) -> void:
	_sell_elapsed += delta
	if _sell_elapsed >= _sell_time():
		_complete_sell()
		return
	_refresh_job_bar()


func _finish_construction() -> void:
	_under_construction = false
	_apply_visual_height(1.0)
	_apply_animation_state()
	_set_health(float(max_health() - _construction_damage))
	construction_finished.emit()
	# Swaps the cancel button for the finished building's real card.
	abilities_changed.emit()


## Frees the grid again, so a sold or destroyed tower never leaves a permanent
## hole that would silently narrow the maze.
##
## super() FIRST and unconditionally, because Unit._exit_tree gives the unit id
## back and this used to return before ever reaching it - so every tower ever
## sold left its id in the registry. Harmless while nothing walked the registry;
## replication does (3.2).
func _exit_tree() -> void:
	super()
	if cell.x < 0 || !is_instance_valid(area):
		return
	area.release(cell, footprint())
	cell = Vector2i(-1, -1)
