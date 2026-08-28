class_name BountyPopup
extends Label3D

## The gold a creep was worth, popped over the spot it died on and floating
## away.
##
## PRESENTATION ONLY, and local to the machine drawing it. It reports a payment
## that has already happened; nothing here decides, changes or even reads the
## player's gold.
##
## WHY IT EXISTS. Bounty is paid to whoever owns the maze a creep died in, and
## before this the only sign of that was a number in the corner of the screen
## ticking up while the player was looking at their maze. A tower defence is
## watched at the maze, not at the resource bar, so the payout is drawn where
## the player is already looking - the same reason every action game since
## Diablo has put its numbers on the corpse.
##
## Built in code rather than instanced from a scene, following ReviveLight and
## HealthBar3D: it is worldspace UI owned by a unit, not an effect somebody
## authors. That also means there is no scene path to validate at boot and
## nothing for a dedicated server to fail to load.
##
## FIXED SIZE, so the number is exactly as readable however far the camera has
## been pulled back, and NO DEPTH TEST, so a payout behind a tower is still
## seen. Both are what a floating number is for; a legible one that is
## sometimes hidden is worse than none.

## How high it climbs before it is gone, in world units.
const RISE: float = 0.62
## Seconds from spawn to freed.
const LIFETIME: float = 1.15
## Share of the life spent fully opaque. The rest fades out.
const HOLD: float = 0.45
## How far the spawn point is jittered, so a pack dying together does not
## stack four numbers into one unreadable smear. Sideways and upwards both,
## because a fixed-size label overlaps in SCREEN space and a jitter along one
## axis alone leaves them in a neat unreadable column.
const SPREAD: float = 0.30
const RISE_SPREAD: float = 0.14
## How far above the creep's own origin it starts.
const OFFSET: float = 0.34

const GOLD: Color = Color(1.0, 0.84, 0.34, 1.0)
const OUTLINE: Color = Color(0.10, 0.07, 0.02, 1.0)

## How far through its life it is, and where it started climbing from.
var _elapsed: float = 0.0
var _start_y: float = 0.0


## Draws what a creep was worth over where it is standing.
##
## Takes the UNIT rather than a number so both callers stay one line, and
## because the two of them notice a death in completely different places: the
## authority pays the bounty in Creep._pay_bounty, and a client only ever sees
## the creep vanish out of a snapshot. Neither needed a new field on the wire
## and neither needed a new method on Creep.
static func show_for(unit: Unit) -> void:
	if unit == null:
		return
	var stats: CreepStats = unit.stats as CreepStats
	if stats != null:
		show_gold(unit.global_position, stats.bounty)


## Draws `gold` over `at`. Does nothing at all when there is no effects root,
## which is what a dedicated server has - so this is safe to call from the
## simulation without asking whether anybody is watching.
static func show_gold(at: Vector3, gold: int) -> void:
	if gold <= 0:
		return
	var root: Node3D = References.effects_root
	if root == null:
		return

	var popup: BountyPopup = BountyPopup.new()
	popup.name = "BountyPopup"
	popup.text = "+%d" % gold
	root.add_child(popup)
	popup.global_position = at + Vector3(
		randf_range(-SPREAD, SPREAD),
		OFFSET + randf_range(-RISE_SPREAD, RISE_SPREAD),
		randf_range(-SPREAD, SPREAD))


func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Constant on screen whatever the camera is doing, which is the whole point
	# of a floating number.
	fixed_size = true
	# Together these are the on-screen SIZE of the number, and the pair is what
	# matters rather than either one: a fixed-size label is drawn at
	# pixel_size * font_size of the viewport's height whatever the resolution
	# or the zoom. The first pass had it at a sixth of the screen per creep.
	pixel_size = 0.00055
	font_size = 48
	outline_size = 10
	modulate = GOLD
	outline_modulate = OUTLINE
	no_depth_test = true
	# Above the health bars, which are transparent too and would otherwise sort
	# against this by camera distance.
	render_priority = 4
	outline_render_priority = 3
	shaded = false

	_start_y = position.y
	# Animated on the RENDER frame, so it opts out of physics interpolation the
	# way every other render-frame animation in the project does. Safe here in
	# a way it is not for a creep's leg: nothing above this moves on the tick.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= LIFETIME:
		queue_free()
		return

	var through: float = _elapsed / LIFETIME
	# Fast out of the corpse and slowing as it goes, which is what makes it
	# read as thrown rather than as scrolled.
	position.y = _start_y + RISE * (1.0 - pow(1.0 - through, 2.4))

	var alpha: float = 1.0
	if through > HOLD:
		alpha = 1.0 - (through - HOLD) / (1.0 - HOLD)
	modulate = Color(GOLD.r, GOLD.g, GOLD.b, alpha)
	outline_modulate = Color(OUTLINE.r, OUTLINE.g, OUTLINE.b, alpha)
