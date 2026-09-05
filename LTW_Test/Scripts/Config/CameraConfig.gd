class_name CameraConfig
extends Resource

## Settings for the top-down RTS camera.
## Stored as Resources/Config/camera_config.tres, reached via References.camera_config.

@export_group("Settings")
## Downward tilt. -90 would be straight down, -60 reads as a normal RTS view.
@export var pitch_degrees: float = -60.0
## Distance from the ground focus point back along the view direction.
##
## Also the FURTHEST OUT the wheel can zoom: a match opens fully zoomed out and
## the wheel only ever moves in. That way this one number stays the answer to
## "how much of the lane does a player see", which is what the whole layout was
## tuned against, and zoom cannot quietly become a way to see more of the map
## than the game intends.
@export var distance: float = 12.0
## Vertical field of view. Wider values fit more of the lane but shrink it.
@export var field_of_view: float = 50.0
## World units per second while panning.
@export var pan_speed: float = 20.0
## How close the cursor must get to a screen edge to start panning.
##
## WHETHER it pans at all is not here: that is a preference of whoever is
## sitting at the machine rather than authored data, so it lives on
## UserSettings with the rest of the options screen. This is only how wide the
## strip is once they have switched it on.
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

@export_group("Zoom")
## Mouse wheel zoom, between `distance` above and the closest setting below.
@export var allow_zoom: bool = true
## How much of a lane's width the CLOSEST zoom shows, in player cells.
##
## Expressed in cells rather than as a distance on purpose: a tower is exactly
## one cell, so this reads directly as "how many towers fill the screen", and
## it stays true if the pitch or the field of view is ever retuned. The camera
## works out the distance from it.
##
## 3.5 keeps the lens clear of the tallest tower. Going much below 3 puts the
## camera at roughly the height of an Ultimate, and one standing just in front
## of the focus point ends up in the lens.
@export var min_visible_width_cells: float = 3.5
## What one wheel notch multiplies the distance by, so zooming is a constant
## RATIO rather than a constant step - the alternative crawls when close and
## leaps when far out.
@export_range(0.5, 0.99, 0.01) var zoom_step: float = 0.85
## How fast the camera catches up to a new zoom level. 0 snaps instantly.
@export var zoom_smoothing: float = 14.0
## Keeps the ground point under the cursor fixed while zooming, so pointing at
## a tower and rolling in arrives at that tower. The same thing the middle drag
## does with the point it grabbed.
@export var zoom_to_cursor: bool = true
