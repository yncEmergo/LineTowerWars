@tool
class_name LightningBolt3D
extends VisualEffect3D

## A jagged arc drawn between two points, and then gone.
##
## PRESENTATION ONLY, and it has to be: it is spawned through
## AttackDelivery.spawn_impact into the shared effects root, which a dedicated
## server leaves null. The damage was resolved before this existed and nothing
## here decides anything - which is also why it may use plain randf() for its
## jitter where nothing in the simulation ever could.
##
## The one effect in the game that needs BOTH ends of a hit rather than just
## where it landed, which is what aim_from exists for: spawn_impact puts the
## effect on the creep and then hands it the point the hit came from, and this
## strings itself between the two.
##
## Its segments are AUTHORED, not built. The scene carries however many boxes
## the look wants, each one unit long down -Z, and this only places them - so
## the number of kinks in a bolt is an art decision in a .tscn rather than a
## number in a script.
##
## Everything is worked out in the bolt's own LOCAL space through to_local, so
## whatever rotation spawn_impact gave the root is already accounted for.

@export_group("References")
## Parent of the segment meshes. Each child is one straight piece of the arc,
## authored one unit long pointing down -Z, and gets stretched to fit.
@export var _segments: Node3D

@export_group("Settings")
## Seconds from struck to gone. Very short: an arc that lingers reads as a
## beam, and a beam is a different weapon.
@export var duration: float = 0.22
## How far a kink may sit off the straight line, as a share of the bolt's own
## length. Scaled rather than absolute so a long arc bends more than a short
## one instead of looking ruler-straight next to it.
@export var jitter: float = 0.09

var _elapsed: float = 0.0
var _struck: bool = false


func _ready() -> void:
	super()
	if Engine.is_editor_hint():
		# A still picture to look at in the editor, not an animation.
		return
	# Animated on the RENDER frame, so it opts out of physics interpolation the
	# way every other effect that moves itself does.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Where the hit came from. Called by spawn_impact once this is in place, which
## is the only reason this effect can draw a line at all.
func aim_from(point: Vector3) -> void:
	strike(point, global_position)


## Strings the arc between two world points.
func strike(from: Vector3, to: Vector3) -> void:
	if _segments == null:
		Log.err("LightningBolt3D has no segments assigned in its scene", name)
		return

	var count: int = _segments.get_child_count()
	if count <= 0:
		return

	_struck = true
	var points: PackedVector3Array = _path(to_local(from), to_local(to), count)
	for index: int in range(count):
		var piece: Node3D = _segments.get_child(index) as Node3D
		if piece != null:
			_lay(piece, points[index], points[index + 1])


## The kinked path from one end to the other, as count + 1 points.
##
## Every interior point is pushed off the straight line SIDEWAYS and upwards
## rather than in any direction: a bolt that wanders towards the camera reads
## as a wobble, where one that stays in its own vertical plane reads as an arc.
func _path(from: Vector3, to: Vector3, count: int) -> PackedVector3Array:
	var points: PackedVector3Array = PackedVector3Array()
	points.append(from)

	var line: Vector3 = to - from
	var length: float = line.length()
	var flat: Vector3 = Vector3(line.x, 0.0, line.z)
	var sideways: Vector3 = Vector3(-flat.z, 0.0, flat.x)
	if sideways.length_squared() > 0.0001:
		sideways = sideways.normalized()

	var spread: float = length * jitter
	for step: int in range(1, count):
		var along: float = float(step) / float(count)
		var point: Vector3 = from + line * along
		# Strongest in the middle and nothing at either end, so the arc still
		# starts at the muzzle and finishes on the creep.
		var taper: float = sin(along * PI)
		point += sideways * randf_range(-spread, spread) * taper
		point.y += randf_range(-spread * 0.4, spread) * taper
		# Never below the lower of its two ends, so an arc strung down at a
		# creep cannot kink through the floor on the way.
		point.y = maxf(point.y, minf(from.y, to.y))
		points.append(point)

	points.append(to)
	return points


## Stretches one authored segment to span from one point to the next.
func _lay(piece: Node3D, from: Vector3, to: Vector3) -> void:
	var line: Vector3 = to - from
	var length: float = line.length()
	if length < 0.0001:
		piece.visible = false
		return

	piece.visible = true
	piece.position = (from + to) * 0.5
	# looking_at points -Z down the line, which is the axis every segment is
	# authored along. Falls back to leaving the piece alone when the line is
	# straight up, where there is no usable heading.
	var up: Vector3 = Vector3.UP
	if absf(line.normalized().dot(up)) > 0.999:
		up = Vector3.FORWARD
	piece.basis = Basis.looking_at(line, up).scaled(Vector3(1.0, 1.0, length))


func _process(delta: float) -> void:
	if Engine.is_editor_hint() || !_struck:
		return

	_elapsed += delta
	if _elapsed >= duration:
		queue_free()
		return
	# Straight down rather than eased. An arc is over the instant it is over.
	set_fade(1.0 - clampf(_elapsed / maxf(0.0001, duration), 0.0, 1.0))
