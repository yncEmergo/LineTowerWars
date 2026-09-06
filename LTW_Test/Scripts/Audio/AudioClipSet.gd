class_name AudioClipSet
extends AudioStreamRandomizer

## Several takes of ONE sound, plus a level trim for the set.
##
## Godot's own AudioStreamRandomizer already picks a clip at random and can
## scatter pitch and volume around each play. What it has no room for is a
## CONSTANT trim for the whole set, and that is the one number a set always
## needs: placeholder audio arrives at whatever level it was rendered at, and
## every sound in the game would otherwise have to be balanced twice - once
## against the others in its own set, and again in every .tres that names it.
##
## `random_volume_offset_db` is the engine's field and is a RANGE either side of
## zero. This is the centre that range moves around.
##
## Comes from another project, where it was EmergoAudioStreamRandomizer. Renamed
## on the way in: a class name is read in an inspector dropdown next to thirty
## engine types, and the studio it came from is not what a reader needs to know
## there.

@export_group("Settings")
## Decibels added to every clip in this set, before the engine's own random
## offset. Negative to pull a set down, which is the common case - a rendered
## sound is normalised to near full scale and almost nothing wants to play there.
@export_range(-40.0, 12.0, 0.5) var volume_offset_db: float = 0.0
