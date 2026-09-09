class_name BarrelCycleAnimation3D
extends Node

## Fires a rack of barrels IN TURN: the first shot leaves the first barrel, the
## next leaves the second, and after the last one it comes back round to the
## first.
##
## PRESENTATION ONLY, like every other animation component. It decides nothing
## about damage, targeting or timing - it listens to the AttackComponent and
## moves things.
##
## It replaces a plain RecoilAnimation3D on the whole rack, which kicked every
## barrel at once. That reads as a salvo, and this tower launches ONE missile
## per attack - so six tubes recoiling for one shot was the model claiming
## something the simulation does not do. Anything that reads as a MECHANISM is
## making a claim, and the claim has to be true.
##
## THREE THINGS HAPPEN PER SHOT, and the order is the whole difficulty:
##
##   1. pick the next barrel          on `attack_started`
##   2. move the shared muzzle to it  on `attack_started`, immediately after
##   3. kick that barrel backwards    on `attacked`
##
## STEPS 1 AND 2 CANNOT WAIT FOR `attacked`. AttackComponent reads the muzzle
## inside its own _fire and only emits `attacked` afterwards, so a component
## that advanced on `attacked` would spawn every shot from the barrel that
## fired LAST time - correct-looking for the recoil and one barrel out of step
## for the projectile, which is exactly the sort of fault that survives a code
## review and is obvious in motion. `attack_started` is emitted before the shot
## in every case, including a zero windup, where it lands in the same frame.
##
## The KICK stays on `attacked` because a recoil is the consequence of a shot
## leaving, which is the same reasoning RecoilAnimation3D is built on.
##
## WHY THE MUZZLE MOVES rather than the attack being told which node to use:
## `Turret/Muzzle` is one exported reference that every tower in the game
## keeps, read once per shot by AttackComponent.muzzle_position(). Moving that
## node is a far smaller change than teaching every attack in the project that
## a tower might have several muzzles, and nothing outside this file has to
## know the rack has more than one barrel.

@export_group("References")
## The unit that attacks.
@export var _unit: Unit
## The shared muzzle node - `Turret/Muzzle` - which this moves onto whichever
## barrel is firing next.
@export var _muzzle: Node3D
## The barrels, in the order they should fire. Each one kicks when its turn
## comes.
@export var _barrels: Array[Node3D] = []
## Where a shot leaves each barrel, one per entry in `_barrels` and in the same
## order. A child of its barrel in every prefab so far.
##
## A SECOND ARRAY rather than walking to a child by name, because a node path
## typed as a string is the one kind of reference this project does not use -
## a renamed node then fails at runtime instead of in the editor.
@export var _tips: Array[Node3D] = []

@export_group("Settings")
## How far a barrel travels back, in world units.
@export var distance: float = 0.05
## Seconds to snap back at the moment of the shot. Very short: the kick should
## look instant and the RETURN is what the eye actually follows.
@export var kick_seconds: float = 0.04
## Seconds spent easing back to rest.
@export var recover_seconds: float = 0.18

## Which barrel fires next.
var _next: int = 0
## Which barrel each shot armed, so a cancelled attack can give its turn back.
var _armed: int = -1
## Where each barrel was authored, which its kick is measured from.
var _rest: Array[Vector3] = []
## Where the muzzle belongs for each barrel, in the TURRET's own space.
##
## Cached rather than read off the tip every shot, because the tip rides its
## barrel and a barrel that is mid-recoil would drag the muzzle back with it -
## so a fast rack would fire each shot from a slightly different place.
var _muzzle_rest: Array[Vector3] = []
## Per barrel, counting up through the kick and then down through the recovery.
var _kick_left: PackedFloat32Array = PackedFloat32Array()
var _recover_left: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	if _unit == null || _muzzle == null:
		Log.err("BarrelCycleAnimation3D is missing its unit or muzzle", name)
		return
	if _barrels.is_empty() || _barrels.size() != _tips.size():
		Log.err("BarrelCycleAnimation3D needs a tip for every barrel", {
			"node": name,
			"barrels": _barrels.size(),
			"tips": _tips.size(),
		})
		return

	for index: int in range(_barrels.size()):
		var barrel: Node3D = _barrels[index]
		# Animated on the RENDER frame, so it opts out of physics interpolation
		# the way every other animation component does, or it jitters.
		barrel.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_rest.append(barrel.position)
		# The tip is a child of its barrel, so its position in the TURRET's
		# space is the barrel's own transform applied to it.
		_muzzle_rest.append(barrel.transform * _tips[index].position)
	_kick_left.resize(_barrels.size())
	_recover_left.resize(_barrels.size())

	_aim_muzzle(0)

	# The component registers itself on the unit in ITS _ready, which may not
	# have run yet, so this waits for the unit rather than reaching for it now.
	_unit.ready.connect(_connect_to_attack)
	if _unit.is_node_ready():
		_connect_to_attack()


func _connect_to_attack() -> void:
	var attack: AttackComponent = _unit.attack_component
	if attack == null:
		Log.err("BarrelCycleAnimation3D's unit has no attack", _unit.name)
		return
	if !attack.attack_started.is_connected(_on_attack_started):
		attack.attack_started.connect(_on_attack_started)
	if !attack.attacked.is_connected(_on_attacked):
		attack.attacked.connect(_on_attacked)
	if !attack.attack_cancelled.is_connected(_on_attack_cancelled):
		attack.attack_cancelled.connect(_on_attack_cancelled)


## Claims the next barrel and puts the muzzle on it, BEFORE the shot is
## delivered. See the note at the top on why this cannot wait for `attacked`.
func _on_attack_started(_target: Unit, _windup: float) -> void:
	_armed = _next
	_next = (_next + 1) % _barrels.size()
	_aim_muzzle(_armed)


func _on_attacked(_target: Unit) -> void:
	if _armed < 0:
		return
	_kick_left[_armed] = kick_seconds
	_recover_left[_armed] = 0.0
	_armed = -1


## Gives the armed barrel its turn back. The shot never left, so the rack
## should not have advanced - without this a cancelled order silently skips a
## barrel and the cycle drifts out of step with what a player is watching.
func _on_attack_cancelled() -> void:
	if _armed < 0:
		return
	_next = _armed
	_aim_muzzle(_armed)
	_armed = -1


func _process(delta: float) -> void:
	for index: int in range(_barrels.size()):
		if _kick_left[index] <= 0.0 && _recover_left[index] <= 0.0:
			continue
		_advance(index, delta)


func _advance(index: int, delta: float) -> void:
	var amount: float = 0.0
	if _kick_left[index] > 0.0:
		_kick_left[index] = maxf(0.0, _kick_left[index] - delta)
		# Out fast, so the kick reads as the shot rather than as a slide.
		amount = 1.0 - _kick_left[index] / maxf(0.0001, kick_seconds)
		if _kick_left[index] <= 0.0:
			_recover_left[index] = recover_seconds
			amount = 1.0
	else:
		_recover_left[index] = maxf(0.0, _recover_left[index] - delta)
		amount = _recover_left[index] / maxf(0.0001, recover_seconds)

	# Backwards along the BARREL'S OWN Z, not the rack's. Every tube on this
	# roster is a tilted pivot, and a kick along the parent's axis would shove
	# it sideways through its own bore instead of back down it.
	var barrel: Node3D = _barrels[index]
	barrel.position = _rest[index] + barrel.transform.basis.z * (distance * amount)


func _aim_muzzle(index: int) -> void:
	if _muzzle == null || index < 0 || index >= _muzzle_rest.size():
		return
	_muzzle.position = _muzzle_rest[index]
