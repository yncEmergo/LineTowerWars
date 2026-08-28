class_name StrikeAnimation3D
extends Node

## Chops something down and lets it recover, the moment its unit's attack
## lands.
##
## PRESENTATION ONLY. The damage is the AttackComponent's and this only
## listens.
##
## THE SIBLING OF SlamAnimation3D, and the difference between them is the whole
## reason this exists. A Slam is driven by `attack_started(target, windup)`, so
## a tower's hammer rises through the windup and lands exactly on the beat -
## which is right for a tower, whose windup is a real gameplay number that
## delays a real hit. A creep chop has NO windup: unit_data.md gives the
## Corrupted Treant a plain 0.5 second attack and nothing else, and authoring a
## windup so an animation had somewhere to play would be moving a gameplay
## value for a visual's sake. SlamAnimation3D's own docstring says a tower with
## no windup gets no swing and calls that the honest failure; this is what an
## attack with no windup gets instead.
##
## So it is driven by `attacked` - the moment the blow lands - and plays the
## whole chop after it. The limb is at rest when the damage is dealt and swings
## through immediately afterwards, which at two strikes a second reads as a
## creature hacking at a wall. Nothing about the timing can drift, because the
## animation is a consequence of the hit rather than a promise about one.
##
## ON THE PHYSICS TICK, for the reason WalkAnimation3D is: the thing this hangs
## off walks, and a limb that opted out of physics interpolation would be drawn
## at the tick position while its body glided between ticks.

@export_group("References")
## The unit that attacks. Its own parent in every prefab so far, wired
## explicitly rather than walked to.
@export var _unit: Unit
## What swings. A pivot at the shoulder, so the whole arm and whatever it is
## holding turn as one piece - hung on the weapon instead, the limb stays put
## and the axe spins in the creature's hand.
@export var _swing: Node3D

@export_group("Settings")
## How far the limb rises before it comes down, in degrees. Negative rotation
## about X, because Godot's forward is -Z and a limb hanging down swings
## FORWARD on a positive one.
@export var raise_degrees: float = 55.0
## How far past rest it follows through, in degrees.
@export var follow_through_degrees: float = 32.0
## Seconds the rise and the chop take together.
@export var strike_seconds: float = 0.22
## Share of that spent rising. Below 0.5 makes the chop the fast half, which is
## what something heavy being swung looks like.
@export_range(0.05, 0.95, 0.05) var raise_share: float = 0.45
## Seconds spent easing back to rest afterwards.
@export var recover_seconds: float = 0.20

## The angle the limb was authored at, so the chop is added to its own stance
## rather than replacing it.
var _rest: float = 0.0
## How far through the current chop, and how far through the recovery. Both
## zero means nothing is swinging.
var _elapsed: float = 0.0
var _striking: bool = false
var _recover_left: float = 0.0


func _ready() -> void:
	if _unit == null || _swing == null:
		Log.err("StrikeAnimation3D is missing a unit or a limb to swing", name)
		return

	_rest = _swing.rotation.x

	# The attack component registers itself on the unit in ITS _ready, which
	# may not have run yet.
	_unit.ready.connect(_connect_to_attack)
	if _unit.is_node_ready():
		_connect_to_attack()


func _connect_to_attack() -> void:
	var attack: AttackComponent = _unit.attack_component
	if attack == null:
		Log.err("StrikeAnimation3D's unit has no attack to swing for", _unit.name)
		return
	if !attack.attacked.is_connected(_on_attacked):
		attack.attacked.connect(_on_attacked)


func _on_attacked(_target: Unit) -> void:
	_striking = true
	_elapsed = 0.0
	_recover_left = 0.0


func _physics_process(delta: float) -> void:
	if _swing == null:
		return

	if _striking:
		_elapsed += delta
		if _elapsed >= strike_seconds:
			_striking = false
			_recover_left = recover_seconds
			_apply(deg_to_rad(follow_through_degrees))
			return
		_apply(_strike_angle(_elapsed / strike_seconds))
		return

	if _recover_left > 0.0:
		_recover_left = maxf(0.0, _recover_left - delta)
		var left: float = _recover_left / maxf(0.0001, recover_seconds)
		# Starts at the follow-through and unwinds to rest.
		_apply(deg_to_rad(follow_through_degrees) * left)


## Where the limb sits at a point through the chop, 0 to 1. Rises on a smoothed
## curve and falls on an accelerating one, so the weight reads.
func _strike_angle(progress: float) -> float:
	if progress <= raise_share:
		var up: float = progress / maxf(0.0001, raise_share)
		return deg_to_rad(-raise_degrees) * smoothstep(0.0, 1.0, up)

	var down: float = (progress - raise_share) / maxf(0.0001, 1.0 - raise_share)
	# Squared, so most of the fall happens in the last moments of it.
	return lerpf(deg_to_rad(-raise_degrees),
		deg_to_rad(follow_through_degrees), down * down)


func _apply(angle: float) -> void:
	_swing.rotation.x = _rest + angle
