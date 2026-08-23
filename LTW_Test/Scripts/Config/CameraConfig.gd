class_name CameraConfig
extends Resource

## Settings for the top-down RTS camera.
## Stored as Resources/Config/camera_config.tres, reached via References.camera_config.

@export_group("Settings")
## Downward tilt. -90 would be straight down, -60 reads as a normal RTS view.
@export var pitch_degrees: float = -60.0
## Distance from the ground focus point back along the view direction.
@export var distance: float = 12.0
## Vertical field of view. Wider values fit more of the lane but shrink it.
@export var field_of_view: float = 50.0
## World units per second while panning.
@export var pan_speed: float = 20.0
## Panning by pushing the cursor against a screen edge.
@export var allow_edge_panning: bool = true
## How close the cursor must get to a screen edge to start panning.
@export var edge_margin_px: int = 12
## Arrow-key panning, used alongside edge panning.
@export var allow_key_panning: bool = true
## Hold the middle mouse button and drag to pan.
@export var allow_middle_drag_pan: bool = true
## True keeps the grabbed ground point under the cursor, like dragging a map.
## False moves the camera in the direction of the drag instead.
@export var middle_drag_grabs_world: bool = true
## Extra world units the focus point may pan beyond the player areas.
@export var bounds_margin: float = 5.0
