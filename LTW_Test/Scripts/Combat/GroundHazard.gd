@tool
class_name GroundHazard
extends VisualEffect3D

## A patch of ground that keeps hurting whatever stands on it, and then goes
## out. Lit where an attack landed, by BurningGroundEffect.
##
## SIMULATION rather than decoration, which is why it lives under the
## projectiles root instead of the effects root and why its clock runs on the
## physics tick. It is safe on both machines for exactly the reason a
## projectile is: a client lights it, ticks it and lets it go out, and
## Unit.take_damage is the single gate deciding whether health actually moves
## (multiplayer.md 3.4). Nothing here re-states that rule.
##
## Armed ONCE, by whoever lit it, and then left alone. Everything it needs
## arrives in light(), so selling the tower that started the fire cannot put it
## out - the same rule AttackHit follows for a shot already in the air.
##
## AUTHORED AT RADIUS 1 and scaled to the real one, exactly as shockwave.tscn
## is, so the ring a player reads is the ground that is actually burning.
##
## @tool only so the flames preview in the editor, like every other effect. The
## clock stands aside there.

@export_group("References")
## The part that licks upwards, pulsed on the render frame. Its own child in
## every scene so far. Optional: a hazard that is only a stain on the floor is
## a perfectly good hazard.
@export var _flames: Node3D

@export_group("Settings")
## Share of the life spent going out. The rest burns at full strength, so a
## short fire still reads as a fire rather than as something already fading.
@export_range(0.05, 1.0, 0.01) var fade_share: float = 0.35
## How far the flames stretch and shrink either side of their authored height.
@export var flicker: float = 0.22
## Full stretch-and-shrink cycles per second.
@export var flicker_rate: float = 2.6

## Everything the fire needs, handed over in light() so it survives its source.
var _area: PlayerArea
var _radius: float = 0.0
var _damage: int = 0
var _tick_seconds: float = 0.5
var _seconds_left: float = 0.0
var _life: float = 1.0
var _damage_type: DamageTable.DamageType = DamageTable.DamageType.SPELL
## Counts down to the next tick. Starts at the full interval, so the ground
## does not deal a tick the instant it catches - the attack that lit it has
## already hit everything standing there.
var _until_tick: float = 0.0
var _lit: bool = false
## Seconds this has been on screen, kept apart from the simulation clock above.
var _shown: float = 0.0
## Authored height of the flames, which the flicker is measured from.
var _flame_scale: Vector3 = Vector3.ONE


func _ready() -> void:
	super()
	if _flames != null:
		_flame_scale = _flames.scale
		# Animated on the RENDER frame, so it opts out of physics interpolation
		# for the reason BobAnimation3D does.
		_flames.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Starts the fire. Call AFTER the hazard is in the tree and standing where it
## belongs, since it scales itself to the ground it covers.
##
## damage is what ONE tick deals, already worked out by whoever lit this: the
## share is the attack's business and the burning is this node's.
func light(burning_area: PlayerArea, radius_cells: float, damage_per_tick: int,
		tick_seconds: float, seconds: float,
		damage_type: DamageTable.DamageType) -> void:
	_area = burning_area
	_radius = maxf(0.0, radius_cells)
	_damage = maxi(0, damage_per_tick)
	_tick_seconds = maxf(0.05, tick_seconds)
	_life = maxf(0.05, seconds)
	_seconds_left = _life
	_damage_type = damage_type
	_until_tick = _tick_seconds
	_lit = true

	scale = Vector3.ONE * maxf(0.01, _radius)

	# ON THE GROUND, whatever height the shot that lit it was flying at. An
	# impact point is where the SHOT arrived - partway up a creep's body, or a
	# flyer's cruising height - and a scorch mark hanging over the floor reads
	# as a bug. The area's own origin IS the floor: every ground unit in it is
	# placed at its local y of zero. See Creep._ground_height.
	if _area != null:
		global_position = Vector3(
			global_position.x, _area.global_position.y, global_position.z)

	# Placed rather than moved, so the interpolator does not streak the patch
	# in from wherever this node was last drawn. Same reason Projectile does it.
	reset_physics_interpolation()
	play()


## The clock and the damage, on the simulation tick because both are gameplay:
## how long the ground burns decides how much it deals, and a render frame is
## whatever the player's GPU felt like doing.
func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() || !_lit:
		return

	_seconds_left -= delta
	if _seconds_left <= 0.0:
		queue_free()
		return

	_until_tick -= delta
	if _until_tick > 0.0:
		return
	_until_tick += _tick_seconds
	_burn()


## One tick of damage to everything standing in the fire.
##
## Always area damage: a patch of burning ground is the definition of covering
## ground, whatever the attack that lit it was set up as. Same rule
## SplashEffect follows.
func _burn() -> void:
	if _area == null || _damage <= 0 || _radius <= 0.0:
		return
	for creep: Creep in TargetFinder.creeps_in_radius(_area, global_position, _radius):
		creep.take_damage(_damage, _damage_type, true)


## The look, on the render frame: flames licking, and the whole fire going out
## over the last share of its life.
##
## It keeps its own clock rather than reading the one above, because that one
## only moves twenty times a second and a flicker stepping at the tick rate
## reads as a stutter rather than as fire.
func _process(delta: float) -> void:
	if Engine.is_editor_hint() || !_lit:
		return

	_shown += delta
	if _flames != null:
		var wave: float = sin(_shown * flicker_rate * TAU)
		_flames.scale = Vector3(
			_flame_scale.x,
			_flame_scale.y * (1.0 + wave * flicker),
			_flame_scale.z
		)

	set_fade(_fade_left())


## How much of the fire is left to see, 1 until the fade starts and then
## straight down to nothing.
func _fade_left() -> float:
	var burnt: float = 1.0 - clampf(_seconds_left / _life, 0.0, 1.0)
	if burnt <= 1.0 - fade_share:
		return 1.0
	return clampf((1.0 - burnt) / fade_share, 0.0, 1.0)
