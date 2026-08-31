@abstract
class_name DiscPassive
extends TowerPassive

## What a technology disc DOES. One subclass per element, one .tres per tier.
##
## A TowerPassive like an elemental tower's named ability, and for the same
## reasons: it is an entry on a command card, it is never pressed, it is a
## shared resource that holds no per-disc state, and it gets its tick from
## Building._advance_passives without anything special being wired. What it
## adds is the two shapes every disc in unit_data.md 5.2 is one of.
##
## AN AURA reaches the friendly towers standing around the disc and lends them
## something, re-granting the whole set on a slow beat. Eight of the ten. It
## never removes anything: a boon expires on its own a moment after the disc
## stops calling, which is what makes selling a disc, morphing it, or a tower
## being built just outside the radius all work with no bookkeeping at all. See
## Combat/TowerBuffs.gd.
##
## AN ON-STEP trigger fires on the creeps standing ON the disc. Two of the ten,
## Arcane and Fire, and they are the reason a disc is walkable rather than a
## wall: a creep can only step on something creeps walk over. See
## PlayerArea.CELL_WALKABLE and game_rules.md.
##
## The two never mix. A disc is one or the other and the subclass says which by
## overriding _reach_towers or _reach_creeps, so nothing has to carry a flag
## and no disc pays for the half it does not use.
##
## AUTHORITY. Every hook here runs on both machines exactly as a tower
## passive's does, and every write stands aside at the door of the thing it
## calls: TowerBuffs.grant, StatusEffects and take_damage all refuse a client.
## A subclass that reaches past those writes its own check. multiplayer.md 3.4.

@export_group("Disc")
## How far this disc reaches, in cells, for an aura. 0 for an ON-STEP disc,
## which reaches only its own square and takes its radius from the grid.
##
## unit_data.md 5.2 states these in WC3 map units - 300 for most, 500 for Holy
## and Lightning - and they are divided by the game's shared 128 before they
## land here, exactly as every other range in the roster is.
@export var radius_cells: float = 0.0

## Half a player cell, which is how far from its own centre a disc counts a
## creep as standing ON it.
##
## A radius rather than the square the footprint really is, because every
## distance in this game is measured flat and round (see TargetFinder) and the
## corners of one cell are not worth a second kind of test. One world unit is
## one player cell, so this is the circle inscribed in the disc's own square.
const STEP_RADIUS: float = 0.5


## Runs the disc on its own slow beat rather than every tick.
##
## FINAL in practice: a subclass overrides _reach_towers or _reach_creeps and
## never this, so every disc in the game shares one clock and one place where
## the "am I standing, and is anything there" questions are asked.
func on_tick(tower: Building, delta: float) -> void:
	if !aura_due(tower, resource_path, delta, _refresh_seconds()):
		return
	# Counted down on the BEAT rather than on the tick, so a gate authored as
	# thirty seconds is thirty seconds of beats. Deterministic on both machines
	# for the same reason the beat itself is: it is the same interval on each.
	for key: String in _gate_keys():
		_advance_gate(tower, key)
	if radius_cells > 0.0:
		_reach_towers(tower)
	else:
		_reach_creeps(tower)


## Lends something to every friendly tower this disc reaches. Overridden by the
## eight discs that are auras.
##
## The list comes from TargetFinder, which finds only ATTACKABLE buildings - so
## it is towers and never other discs, structurally rather than by filtering,
## which is what every one of these effects says in unit_data.md.
func _reach_towers(_disc: Building) -> void:
	pass


## Fires on every ground creep standing on the disc. Overridden by the two
## discs that are on-step triggers.
##
## GROUND only, and the subclass does not have to remember: a flyer reads none
## of the maze and is not standing on anything, so _creeps_on filters it out
## before a subclass ever sees it.
func _reach_creeps(_disc: Building) -> void:
	pass


## Every friendly tower inside this disc's radius.
func _towers_in_range(disc: Building) -> Array[Building]:
	return TargetFinder.buildings_in_radius(disc.area, disc.global_position,
		radius_cells)


## Every ground creep currently standing on this disc's own square.
##
## Flyers are dropped here rather than in each subclass, because "steps on the
## disc" is what both on-step effects in 5.2 say and neither of them means
## something passing overhead.
func _creeps_on(disc: Building) -> Array[Creep]:
	var standing: Array[Creep] = []
	for creep: Creep in TargetFinder.creeps_in_radius(disc.area,
			disc.global_position, STEP_RADIUS):
		if !creep.is_flying():
			standing.append(creep)
	return standing


## Grants one boon to one tower for the shared hold window. The line every aura
## disc is written in terms of, so the window is decided once.
func _lend(tower: Building, kind: TowerBuffs.Kind, value: float) -> void:
	tower.buffs().grant(kind, value, _hold_seconds(), self)


## How often this disc re-reads what is standing around it.
func _refresh_seconds() -> float:
	var config: GameConfig = References.game_config
	if config == null:
		return AURA_REFRESH_SECONDS
	return maxf(0.05, config.disc_aura_refresh_seconds)


## How long each grant lasts before it has to be re-granted.
func _hold_seconds() -> float:
	var config: GameConfig = References.game_config
	if config == null:
		return AURA_HOLD_SECONDS
	return maxf(_refresh_seconds() * 2.0, config.disc_aura_hold_seconds)


## Whether a per-disc gate keyed like this has run out, counting it down along
## the way. The two on-step discs both have one - "can trigger once per second",
## "the disc has its own cooldown" - and neither may write it on a client.
##
## Stored on the DISC in `ability_state`, never on this resource, for the reason
## every shared ability stores state that way: one .tres is every disc of its
## kind on the field at once. See UnitAbility.
func _gate_ready(disc: Building, key: String, seconds: float) -> bool:
	if !MatchSession.is_authority():
		return false
	var left: float = float(disc.ability_state.get(key, 0.0))
	if left > 0.0:
		return false
	disc.ability_state[key] = maxf(0.01, seconds)
	return true


## The gates this disc keeps, so on_tick can count them down without knowing
## what any of them mean. Empty for every aura disc, which keeps none.
##
## Named rather than discovered, because ability_state is the DISC's dictionary
## and holds whatever else the disc is remembering - the aura beat itself is in
## there. A walk of its keys would count that down too.
func _gate_keys() -> Array[String]:
	var none: Array[String] = []
	return none


## Counts one gate down by a beat.
func _advance_gate(disc: Building, key: String) -> void:
	var left: float = float(disc.ability_state.get(key, 0.0))
	if left <= 0.0:
		return
	disc.ability_state[key] = maxf(0.0, left - _refresh_seconds())


## The reach worth drawing on the ground when a disc is selected, which for an
## aura disc is exactly the radius its effect covers.
##
## An aura's radius is the hand-picked case game_rules.md names first: it is
## the number that decides where the thing goes, which is the whole of a disc.
## An on-step disc answers 0 and draws nothing, because its reach is the square
## it is standing on and a ring around that says nothing a player cannot see.
func display_radius(_unit: Unit) -> float:
	return radius_cells
