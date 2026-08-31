class_name SlamAnimation3D
extends Node

## Raises something and brings it down, timed to land exactly when its unit's
## attack does.
##
## PRESENTATION ONLY, and it decides nothing: the damage is the
## AttackComponent's, and this only listens. It is driven by
## `attack_started(target, windup)` rather than by a duration of its own, so
## the swing is in step with the tower's real attack timing however that gets
## retuned - if the windup changes, the animation changes with it and stays
## landing on the beat. See AttackStats.windup_seconds.
##
## A tower with NO windup gets no visible swing: there is no time to play one
## in, so the hammer simply stays at rest and the damage lands. That is the
## honest failure and it is why the windup is a gameplay number rather than an
## animation one.
##
## The shockwave is spawned by the ANIMATION rather than by the attack's
## delivery, because it belongs to the tower and not to the shot: a Crusher's
## blast is centred on itself and looks the same whatever it swung at, so
## routing it through an impact visual - which lands on the target - would draw
## it in the wrong place.

@export_group("References")
## The unit that attacks. Its own parent's unit in every prefab so far, wired
## explicitly rather than walked to.
@export var _unit: Unit
## What swings. A pivot above the arm, so the arm and head turn together.
@export var _swing: Node3D

@export_group("Settings")
## How far back the swing rises before it comes down, in degrees.
@export var raise_degrees: float = 52.0
## How far past rest it follows through on impact, in degrees.
@export var follow_through_degrees: float = 14.0
## Share of the windup spent rising. The rest is the drop, so below 0.5 makes
## the fall the fast half - which is what a heavy thing falling looks like.
@export_range(0.05, 0.95, 0.05) var raise_share: float = 0.62
## Seconds spent easing back to rest after the hit.
@export var recover_seconds: float = 0.35
## Whether the swing runs on the SIMULATION TICK rather than the render frame.
##
## Off for a tower, which is the common case and the better looking one: a
## tower never moves, so its swing is free to be as smooth as the monitor and
## a 20 Hz version of a third of a second is visibly stepped.
##
## On for anything that WALKS while it swings - the builder. Physics
## interpolation assumes a transform only changes on a tick, so a limb animated
## on the render frame is drawn at its body's tick position while the body
## glides between ticks, and the arm detaches. The same lesson
## StrikeAnimation3D and AttackTargetMarker both carry, reached from the two
## opposite directions.
@export var on_physics_tick: bool = false

@export_group("Shockwave")
## Ring dropped on the ground when the blow lands, as a res:// path. Optional:
## a swing with no shockwave is a perfectly good animation.
@export_file("*.tscn") var shockwave_scene_path: String = ""

## Seconds the current swing runs for, and how far through it is. Zero means
## nothing is swinging.
var _windup: float = 0.0
var _elapsed: float = 0.0
## Counts down while easing back to rest after a hit.
var _recover_left: float = 0.0

var _shockwave: PackedScene = null
var _shockwave_loaded: bool = false


func _ready() -> void:
	# Exactly one of the two runs, whichever the export asked for.
	set_process(!on_physics_tick)
	set_physics_process(on_physics_tick)

	if _unit == null || _swing == null:
		Log.err("SlamAnimation3D is missing a unit or a swing node", name)
		return

	# Animated on the RENDER frame, so it must opt out of physics interpolation
	# the way SpinAnimation3D does, or it jitters.
	_swing.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	# The component registers itself on the unit in ITS _ready, which may not
	# have run yet, so this waits for the unit rather than reaching for it now.
	_unit.ready.connect(_connect_to_attack)
	if _unit.is_node_ready():
		_connect_to_attack()


func _connect_to_attack() -> void:
	var attack: AttackComponent = _unit.attack_component
	if attack == null:
		Log.err("SlamAnimation3D's unit has no attack to swing for", _unit.name)
		return
	if !attack.attack_started.is_connected(_on_attack_started):
		attack.attack_started.connect(_on_attack_started)
	if !attack.attacked.is_connected(_on_attacked):
		attack.attacked.connect(_on_attacked)


func _on_attack_started(_target: Unit, windup: float) -> void:
	if windup <= 0.0:
		return
	_windup = windup
	_elapsed = 0.0
	_recover_left = 0.0


func _on_attacked(_target: Unit) -> void:
	_windup = 0.0
	_elapsed = 0.0
	_recover_left = recover_seconds
	_spawn_shockwave()


func _process(delta: float) -> void:
	_advance(delta)


func _physics_process(delta: float) -> void:
	_advance(delta)


func _advance(delta: float) -> void:
	if _swing == null:
		return

	if _windup > 0.0:
		_elapsed = minf(_elapsed + delta, _windup)
		_apply(_swing_angle(_elapsed / _windup))
		return

	if _recover_left > 0.0:
		_recover_left = maxf(0.0, _recover_left - delta)
		var left: float = _recover_left / maxf(0.0001, recover_seconds)
		# Starts at the follow-through and unwinds to rest.
		_apply(deg_to_rad(-follow_through_degrees) * left)


## Where the swing sits at a point through the windup, 0 to 1. Rises on a
## smoothed curve and drops on an accelerating one, so the weight reads.
func _swing_angle(progress: float) -> float:
	if progress <= raise_share:
		var up: float = progress / maxf(0.0001, raise_share)
		return deg_to_rad(raise_degrees) * smoothstep(0.0, 1.0, up)

	var down: float = (progress - raise_share) / maxf(0.0001, 1.0 - raise_share)
	# Squared, so most of the fall happens in the last moments of it.
	var fallen: float = down * down
	return lerpf(deg_to_rad(raise_degrees), deg_to_rad(-follow_through_degrees), fallen)


func _apply(angle: float) -> void:
	_swing.rotation.x = angle


## The ring, parented to the shared effects root rather than to the tower, so
## selling the tower mid animation cannot take the effect with it. A dedicated
## server leaves that root null and gets no effect at all, which is correct.
func _spawn_shockwave() -> void:
	if !_shockwave_loaded:
		_shockwave_loaded = true
		_shockwave = SceneUtil.load_scene(shockwave_scene_path, "shockwave")
	if _shockwave == null:
		return

	var root: Node3D = References.effects_root
	if root == null:
		return

	var effect: Node3D = _shockwave.instantiate() as Node3D
	if effect == null:
		Log.err("Shockwave scene's root is not a Node3D", shockwave_scene_path)
		return

	# BEFORE it enters the tree. ImpactBurst captures its scale in _ready and
	# then animates from that, so a scale applied afterwards is overwritten on
	# the very next frame - which quietly gave every tier the same sized ring.
	_scale_to_blast(effect)
	root.add_child(effect)
	effect.global_position = _unit.global_position

	# After the position, for the reason in VisualEffect3D.play().
	var visual: VisualEffect3D = effect as VisualEffect3D
	if visual != null:
		visual.play()


## Sizes the ring to the tower's own blast, read off its attack, so the ring a
## player learns to read is never a different size to the damage it stands for.
## An Ultimate Crusher's blast is wider than a Lesser one's and its ring says so
## without either being authored twice.
##
## The shockwave scene is authored at RADIUS 1, so the scale IS the radius in
## world units, and a player who learns the ring has learned the blast.
func _scale_to_blast(effect: Node3D) -> void:
	if _unit.stats == null || _unit.stats.attack == null:
		return
	for entry: AttackEffect in _unit.stats.attack.effects:
		var blast: SelfSplashEffect = entry as SelfSplashEffect
		if blast != null && blast.radius > 0.0:
			effect.scale = Vector3.ONE * blast.radius
			return
