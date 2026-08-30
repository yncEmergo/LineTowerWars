@abstract
class_name Unit
extends Node3D

## Base class for everything that carries a unit panel: the builder, creeps,
## towers and other buildings.
##
## Holds only what every unit has regardless of what it can do - ownership,
## stats, health, selection. Anything that applies to some units but not
## others belongs elsewhere:
##   - split by what a unit IS, use a subclass (Building, MobileUnit)
##   - optional capability that crosses that split, use a child component
## Attacking and taking damage cross the split in both directions, so they
## become components rather than more subclasses.
##
## Visuals live in each unit's prefab, never in script, so they can be seen
## and edited in the editor.

signal selection_changed(is_selected: bool)
signal health_changed(current: float, maximum: int)
signal died()
## Raised when the command card should be rebuilt, e.g. a building finishing
## construction and swapping its cancel button for its real abilities.
signal abilities_changed()

## Which units may share a selection. Two units can be selected together only
## when these match, so a box drawn across a whole area comes back as towers
## OR as the builder rather than as a mixture no command card can describe.
##
## Deliberately COARSER than the unit type: every tower is one class, so any
## tower boxes and groups with any other regardless of element or tier. It is
## the double click sweep that stays exact - see is_same_type_as.
const SELECT_MOBILE: StringName = &"mobile"
const SELECT_TOWER: StringName = &"tower"
const SELECT_SEND_BUILDING: StringName = &"send_building"

@export_group("References")
## Stats for this unit type. Assigned per prefab, so every unit type carries
## its own without a central registry.
@export var stats: UnitStats
@export var _selection_ring: MeshInstance3D

@export_group("Health")
## Height above the unit's origin for the worldspace health bar.
@export var health_bar_height: float = 1.5

@export_group("Selection")
## World-space radius used for click picking. Usually a little wider than the
## body so the unit stays comfortable to click.
@export var select_radius: float = 0.55
## Height above the unit's origin that the click test projects from, so
## clicking the visible body works rather than only the ground under it.
@export var select_height: float = 0.55

## Player that owns this unit. For creeps this is the sender, not the player
## whose area they happen to be walking through.
## The name both machines call this unit by, handed out by the match when the
## unit is set up. MatchSession.NO_UNIT until then.
##
## Object references cannot cross a network, so any command or state update
## naming a unit names this instead. Ids are given out in spawn order, which
## two machines spawning the same things in the same order agree on without
## being told; once the server is authoritative it assigns them and clients
## adopt what they are given. See multiplayer.md.
var unit_id: int = MatchSession.NO_UNIT

var owner_player_id: int = 1
## Area this unit currently occupies.
var area: PlayerArea
## Read by the unit panel. A unit with no health component never loses any,
## which is how the builder stays invulnerable without a special case.
##
## A FLOAT, because regeneration is a share of maximum health per second and
## one tick of that is a fraction of a point - rounding it away would leave a
## small tower regenerating nothing at all. The player is never shown this
## number directly: display_health() rounds it up to a whole one.
var current_health: float = 0.0
## This unit's attack, or null for anything that cannot attack. Registered by
## the component itself in its _ready, from the @export it already carries
## pointing back here, so no prefab has to wire the same link twice.
##
## A plain var rather than a getter because abilities reach it by name on a
## duck-typed unit, and because a unit with no attack simply leaves it null.
var attack_component: AttackComponent = null
## The chain of orders this unit is working through, or null while nobody has
## ever given it one.
##
## Lazily built by OrderQueue.of(), so the hundreds of creeps in a maze - none
## of which takes an order at all - pay one null field and nothing else. A
## plain var rather than a getter for the same reason attack_component is: it
## is reached by name from abilities that were handed some unit, and a unit
## that has never been ordered simply leaves it null.
var order_queue: OrderQueue = null

var _selected: bool = false
var _health_bar: HealthBar3D


func _ready() -> void:
	if stats == null:
		Log.err("Unit has no UnitStats assigned in its prefab", name)
	else:
		current_health = float(stats.max_health)

	# An invulnerable unit can never lose health, so a bar would only ever be
	# a full green rectangle. See game_rules.md on the builder.
	if !is_invulnerable():
		_create_health_bar()

	# Both of these are about a unit STANDING somewhere. A unit that is not in
	# the world has no ring to draw and nothing to be clicked on, so neither
	# the error nor the group applies to it - see is_in_world().
	if is_in_world():
		if _selection_ring == null:
			Log.err("Unit has no selection ring assigned in its prefab", name)

		# Every unit in the world is selectable, so registering here means a
		# new unit type never has to remember to opt in at its spawn site.
		add_to_group(SelectionController.UNIT_GROUP)
	_apply_selection_visual()


## Assigns ownership and the area this unit belongs to.
## Call after the unit is in the tree. Subclasses extend this to place
## themselves and set up their own state.
func setup(player_id: int, home_area: PlayerArea) -> void:
	owner_player_id = player_id
	area = home_area
	_claim_unit_id()


## Adopts a unit the SERVER spawned, under the id the server chose (3.2).
##
## The mirror of setup(): same fields, but the id comes in rather than being
## handed out, which is what keeps two machines calling the same unit by the
## same name. MatchSession.claim_unit_id() also drags the local counter past
## it, so a unit spawned here later can never collide with one handed down.
##
## Call after the node is in the tree. Subclasses extend it the way they extend
## setup(), because a replicated tower still has to claim its grid cells.
func adopt(id: int, player_id: int, home_area: PlayerArea, world_pos: Vector3) -> void:
	var session: MatchSession = References.match_session
	if session != null && session.claim_unit_id(self, id):
		unit_id = id
	setup(player_id, home_area)
	global_position = world_pos
	# Placed, not moved: the interpolator would otherwise streak a newly
	# adopted unit in from the world origin.
	reset_physics_interpolation()


## Takes an id from the match, once. Silent when there is no session, so a bare
## test scene still runs - the unit simply stays unaddressable, which is only a
## problem the moment something tries to send it over a wire.
func _claim_unit_id() -> void:
	if unit_id != MatchSession.NO_UNIT:
		return
	var session: MatchSession = References.match_session
	if session != null:
		unit_id = session.register_unit(self)


## Runs the order chain for one tick, if this unit has one.
##
## Called explicitly from each unit type's own `_physics_process` rather than
## from one on Unit, and that is forced: Godot calls only the MOST DERIVED
## `_physics_process`, and Creep deliberately replaces MobileUnit's outright
## rather than calling super(). A base class implementation would therefore be
## silently skipped by exactly the units that take the most orders.
##
## Private, because it is the tick and not an order - everything that GIVES an
## order goes through OrderQueue.
func _advance_orders(delta: float) -> void:
	if order_queue != null:
		order_queue.advance(delta)


## Gives the id back when the unit dies or the scene ends, so the registry does
## not fill up with freed units over a long match.
func _exit_tree() -> void:
	if unit_id == MatchSession.NO_UNIT:
		return
	var session: MatchSession = References.match_session
	if session != null:
		session.unregister_unit(unit_id)
	unit_id = MatchSession.NO_UNIT


## Abilities on this unit's command card right now. Overridable, because a
## building under construction offers a different card to a finished one.
func current_abilities() -> Array:
	if stats == null:
		return []
	return stats.abilities


# --- Ownership ----------------------------------------------------------

## Whether this unit belongs to the player sitting at this client.
## Defaults to true when there is no PlayerManager, so a bare test scene
## stays usable.
func is_owned_by_local_player() -> bool:
	var manager: PlayerManager = References.player_manager
	if manager == null:
		return true
	return owner_player_id == manager.local_player_id()


## There are no team modes, so anything owned by a different player is an
## enemy. That stays true for the whole 2-12 player range.
func is_hostile_to(other: Unit) -> bool:
	return other != null && other.owner_player_id != owner_player_id


## Exactly the same unit type, which is what double click selects.
##
## Identity is the stats resource itself: every Cannon references the one
## cannon_stats.tres, so they match, while a different tower carries its own
## stats and is not swept up with them. That is also what makes double click
## pick up ONE TIER rather than a whole upgrade line - a Greater Cannon is a
## different resource, so it stays out. See game_rules.md.
func is_same_type_as(other: Unit) -> bool:
	if other == null || stats == null:
		return false
	return other.stats == stats && other.owner_player_id == owner_player_id


## Buildings occupy grid cells and never move. Used instead of a type check so
## selection stays duck-typed, and so future non-tower buildings inherit it.
func is_structure() -> bool:
	return false


## Which selection this unit may join. Anything that moves by default, which
## covers the builder and the creeps.
##
## Separate from is_structure() rather than derived from it, because the two
## answer different questions: the technology discs are structures and still
## must not be selected alongside towers, so being a building is not on its
## own enough to say what a unit groups with.
func selection_class() -> StringName:
	return SELECT_MOBILE


## The node whose meshes stand for this unit in a portrait or a baked icon.
##
## Itself by default, which is right for a creep - its meshes hang directly off
## it. A building overrides it with the model it swaps out, so a portrait shows
## the tower rather than the tower plus whatever the prefab has bolted on
## around it. What is never wanted either way - the selection ring, the health
## bar, the ground patch - is VisualUtil.portrait_skips()'s job rather than
## this one, because that list is the same for everything.
func visual_root() -> Node3D:
	return self


## Whether this unit STANDS somewhere a player can point at.
##
## True for everything with a body. False for the send buildings, which are
## reached through the four buttons over the unit panel and have no presence on
## the map at all - so nothing may click one, box one, sweep one up with a
## double click, draw a marker for one or centre the camera on one.
##
## A question of its own rather than "has no meshes", because every one of
## those callers is asking the same thing and each would otherwise have to
## name the class. See SendBuilding.
func is_in_world() -> bool:
	return true


## Whether this unit may share a selection with anything at all, its own kind
## included.
##
## selection_class() is the finer rule - which OTHER kinds may join - and this
## is the coarse one that comes first. The send buildings answer no: there are
## four of them and each shows a different card, so a selection holding two
## would have to pick one card to draw and silently drop the other.
func allows_multi_selection() -> bool:
	return true


## Whether this unit takes orders from its owner. False for ordinary creeps,
## which can be clicked and inspected but never commanded, and true again for
## attacker creeps once those exist. See game_rules.md.
##
## Separate from ownership: a creep you sent is yours and still not yours to
## steer, so selection needs both answers rather than one combined flag.
func is_controllable() -> bool:
	return true


# --- Health -------------------------------------------------------------

func max_health() -> int:
	if stats == null:
		return 1
	return maxi(1, stats.max_health)


## The health to SHOW, which is the real one rounded UP.
##
## Up rather than to nearest so that a unit still standing never reads as 0 -
## anything above nothing is at least one point to the player - and so a tower
## that has regenerated a sliver reads as having gained it rather than as
## having gained nothing. The cost is that a full tower one hair below its
## maximum reads as full, which is the harmless half of the trade.
func display_health() -> int:
	return mini(max_health(), ceili(current_health))


## Invulnerability is a property of the armour type, so it needs no per-unit
## flag and no special case anywhere else.
func is_invulnerable() -> bool:
	return stats == null || stats.armor_type == UnitStats.ArmorType.INVULNERABLE


func is_alive() -> bool:
	return current_health > 0.0


## Applies damage and kills the unit if it runs out. Invulnerable units
## silently ignore it.
##
## Everything the DEFENDER brings is applied here, because the defender is what
## knows its own armour type, its armour points, its resistances and its
## blocks. An attacker only ever states what kind of damage it deals and
## whether that damage covers an area.
func take_damage(amount: int, damage_type: DamageTable.DamageType,
		is_aoe: bool = false) -> void:
	if amount <= 0 || is_invulnerable():
		return
	# Only the authority decides what a hit did. A client still fires, still
	# flies the shot and still lands it - all of which is presentation - but
	# health arrives from the server, so applying it here as well would show a
	# number the server never agreed to and then have it snap back (3.4).
	if !MatchSession.is_authority():
		return
	_set_health(current_health - float(resolve_damage(amount, damage_type, is_aoe)))


## What a raw damage amount actually costs this unit, once the whole pipeline
## has run. Public so a tooltip can quote a matchup without dealing the damage.
##
## Falls back to the plain amount when no table is wired, silently: a missing
## table is a setup problem that DamageTable.validate() reports once at boot,
## not something worth logging on every hit of a fight.
func resolve_damage(amount: int, damage_type: DamageTable.DamageType,
		is_aoe: bool = false) -> int:
	if amount <= 0 || is_invulnerable():
		return 0

	var table: DamageTable = References.damage_table
	if table == null || stats == null:
		return amount

	return table.apply(
		amount, damage_type, armor_type_value(), armor_value(),
		_damage_taken_ratio(is_aoe, DamageTable.is_spell(damage_type)),
		_damage_block()
	)


## Armour TYPE this unit counts as RIGHT NOW, which is a different question to
## the armour points above it.
##
## Its own by default. Overridable for the same reason armor_value() is: the
## Ultimate Alchemist alters the type of the creeps it hits, and the stats file
## cannot know that. See Combat/StatusEffects.gd.
func armor_type_value() -> UnitStats.ArmorType:
	if stats == null:
		return UnitStats.ArmorType.UNARMORED
	return stats.armor_type


## Armour points this unit has RIGHT NOW: its own, plus anything granted to it
## while it stands where it stands. Overridden by anything an aura can reach,
## which is why the panel asks the unit rather than reading its stats file.
func armor_value() -> int:
	if stats == null:
		return 0
	return stats.armor


## Restores health, never past the maximum.
##
## Deliberately refuses a unit that is already down. A heal is not a revive,
## and letting one bring a creep back would make the difference between the two
## a matter of arriving a frame earlier. Reviving has its own path, see
## Creep.revive().
func heal(amount: float) -> void:
	if amount <= 0.0 || is_invulnerable() || !is_alive():
		return
	_set_health(current_health + amount)


## Share of incoming damage this unit takes, applied after the damage matrix
## and before its armour points. 1.0 is no resistance at all.
##
## Both questions the pipeline can ask arrive together rather than as two
## hooks, because the answer is ONE number however many of them apply: a creep
## that resists both area damage and spells multiplies the two, and doing that
## here keeps the order it happens in out of the caller's hands.
##
## Protected rather than public: it is one step of the pipeline above, not a
## question anything outside the unit should be asking. Creeps override it to
## fold in their passives.
func _damage_taken_ratio(_is_aoe: bool, _is_spell: bool) -> float:
	return 1.0


## Flat points removed from a hit last of all, after every multiplier.
func _damage_block() -> int:
	return 0


## The SECOND RESOURCE this unit runs on, drawn under its portrait as a bar and
## a number, or null for anything that runs on nothing but its health.
##
## Null here rather than on the panel, because "does this unit have one" is the
## unit's own answer. Towers override it with mana or with whatever their
## ability has banked; the creeps that carry a mana trait override it with
## their pool; everything else - the builder, a Basic tower, an ordinary creep -
## says nothing and the panel draws no line at all. See game_rules.md under
## Interface.
func secondary_resource() -> TowerResource:
	return null


## Whether this unit is in a state where its attack may fire, if it has one.
func can_attack() -> bool:
	return is_alive()


## Multiplier on how fast this unit attacks RIGHT NOW, above 1 being faster.
##
## Asked of the unit rather than read off its AttackStats for the same reason
## armor_value() is: an aura standing over it changes the answer, and the
## stats file cannot know that. 1.0 for anything nothing is buffing, which is
## every tower.
func attack_speed_ratio() -> float:
	return 1.0


func _set_health(value: float) -> void:
	var clamped: float = clampf(value, 0.0, float(max_health()))
	if clamped == current_health:
		return

	current_health = clamped
	if _health_bar != null:
		_health_bar.set_ratio(current_health / float(max_health()))
	health_changed.emit(current_health, max_health())

	if current_health <= 0.0:
		_die()


## Health handed down by the server, which is the ONLY way it changes on a
## client (3.2).
##
## Deliberately not routed through _set_health: that kills a unit at zero, and
## on a client a death is the server removing it from the snapshot rather than
## a number this machine noticed. Going through both would pay a bounty twice
## and free the node underneath the code that is still reading it.
func set_replicated_health(value: float) -> void:
	var clamped: float = clampf(value, 0.0, float(max_health()))
	if clamped == current_health:
		return

	current_health = clamped
	if _health_bar != null:
		_health_bar.set_ratio(current_health / float(max_health()))
	health_changed.emit(current_health, max_health())


## Overridable, so a building can free its grid cells or a creep can pay a
## bounty before it goes.
func _die() -> void:
	died.emit()
	queue_free()


func _create_health_bar() -> void:
	_health_bar = HealthBar3D.new()
	_health_bar.name = "HealthBar"
	add_child(_health_bar)
	_health_bar.position = Vector3(0.0, health_bar_height, 0.0)
	_health_bar.set_ratio(current_health / float(max_health()))


# --- Selection ----------------------------------------------------------

## World point the selection test projects to screen.
func selection_anchor() -> Vector3:
	return global_position + Vector3(0.0, select_height, 0.0)


func selection_radius() -> float:
	return select_radius


func is_selected() -> bool:
	return _selected


func set_selected(value: bool) -> void:
	if _selected == value:
		return
	_selected = value
	_apply_selection_visual()
	selection_changed.emit(_selected)


func _apply_selection_visual() -> void:
	if _selection_ring != null:
		_selection_ring.visible = _selected
