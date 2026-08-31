class_name SunLight
extends DirectionalLight3D

## The match's sun, and the one node that decides what shadows cost to draw.
##
## PRESENTATION ONLY. A dedicated server has no light at all and never runs a
## line of this - see multiplayer.md.
##
## It exists because a shadowed directional light is not one extra pass over
## what the camera can see, it is one pass per cascade over everything inside
## its CAST DISTANCE, however little of that the camera is pointed at. Godot's
## default distance reaches comfortably past the far edge of this map, so every
## cascade was redrawing all twelve lanes to light one. Measured on a 1v1 with
## full mazes and full lanes, that was the great majority of every frame's draw
## calls and most of its render time - far more than the geometry it was
## shadowing.
##
## Trimming the distance to roughly what the camera can see keeps the shadows
## and drops the rest, which is why this is a number rather than a switch. The
## switch is UserSettings.shadows_enabled, for a machine that cannot afford
## them even so.

## Every sun in the tree, so the options screen can refresh them when the
## player flips the setting mid match. One entry in practice; a group anyway,
## for the same reason HealthBar3D uses one - the screen has no way to reach a
## node inside a match scene it does not own.
const GROUP: String = "sun_lights"

@export_group("Settings")
## How far from the camera the sun still casts shadows, in world units.
##
## Wants to be a little more than the camera can see at its furthest zoom, and
## no more than that: every unit of it is geometry redrawn per cascade. Too
## small and shadows visibly stop partway down the lane; too large and they
## cost several times what they are worth. Tuned against the RTS camera's own
## limits rather than against the map, because what is off screen never needed
## a shadow.
@export var shadow_cast_distance: float = 35.0


func _ready() -> void:
	add_to_group(GROUP)
	directional_shadow_max_distance = shadow_cast_distance
	refresh_shadows()


## Re-reads the player's choice. Called once on the way up, and on the whole
## group by the options screen when that choice changes mid match.
func refresh_shadows() -> void:
	shadow_enabled = UserSettings.shadows_enabled
