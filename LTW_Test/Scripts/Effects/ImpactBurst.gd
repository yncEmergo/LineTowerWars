@tool
class_name ImpactBurst
extends VisualEffect3D

## A short lived flash where an attack landed: a ring that expands and fades,
## and then frees itself.
##
## PRESENTATION ONLY. It is spawned by AttackDelivery.spawn_impact() into the
## shared effects root, which a dedicated server leaves null - so a server
## never creates one and nothing here may ever decide anything. The damage was
## already resolved before this existed.
##
## Parented to the effects root rather than to the tower that fired, so selling
## the tower mid flash cannot take the flash with it.
##
## The fade goes through VisualEffect3D.set_fade() rather than being applied
## directly, so it MULTIPLIES the effect's opacity instead of overwriting it -
## an effect dialled down to a third stays dialled down while it fades.

@export_group("Settings")
## Seconds from spawn to gone.
@export var duration: float = 0.28
## Scale at the start and the end of that, multiplying whatever the prefab
## authored.
@export var start_scale: float = 0.35
@export var end_scale: float = 1.0
## How the expansion eases. Below 1 it snaps out and then slows, which is what
## an explosion does.
@export var scale_curve: float = 0.45
## Share of the duration spent EXPANDING. The rest is spent at full size,
## fading.
##
## Below 1 this splits the effect into a fast growth and a hold, which is what
## an effect that has to say "this much ground" wants: the growth is the event,
## and the hold is the reading. A ring that is still creeping outwards the whole
## time it is on screen never actually shows the player a radius.
##
## 1.0 grows across the whole life and never holds, which is the plain flash
## every ordinary impact wants.
@export_range(0.05, 1.0, 0.01) var grow_share: float = 1.0

var _elapsed: float = 0.0
var _base_scale: Vector3 = Vector3.ONE


func _ready() -> void:
	super()
	_base_scale = scale
	if Engine.is_editor_hint():
		# In the editor this is a still picture to look at, not an animation.
		# Without this it would play once on open and leave the scene showing
		# whatever frame it stopped on.
		return

	# Animated on the RENDER frame, so it must opt out of physics interpolation
	# the way SpinAnimation3D does, or it jitters.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_apply(0.0)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	_elapsed += delta
	if _elapsed >= duration:
		queue_free()
		return
	_apply(clampf(_elapsed / maxf(0.0001, duration), 0.0, 1.0))


func _apply(progress: float) -> void:
	# Clamped, so anything past the growth window sits exactly at end_scale
	# rather than drifting past it.
	var growth: float = clampf(progress / maxf(0.01, grow_share), 0.0, 1.0)
	var eased: float = pow(growth, maxf(0.01, scale_curve))
	scale = _base_scale * lerpf(start_scale, end_scale, eased)

	# The fade waits for the growth to finish and then runs out the rest of the
	# life, so an effect that holds is at FULL strength while it holds. Fading
	# across the whole life instead would leave a ring half gone by the time it
	# reached the size it was drawn to show.
	set_fade(1.0 - _fade_progress(progress))


## How far through its fade the effect is, 0 to 1. Zero until the growth is
## done, then straight through to gone.
func _fade_progress(progress: float) -> float:
	if grow_share >= 1.0:
		return progress
	if progress <= grow_share:
		return 0.0
	return (progress - grow_share) / (1.0 - grow_share)
