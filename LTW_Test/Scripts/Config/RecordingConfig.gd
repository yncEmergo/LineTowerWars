class_name RecordingConfig
extends Resource

## How a match recording is written. Stored as
## Resources/Config/recording_config.tres, reached via References.recording_config.
##
## Whether a match is recorded at all is NOT here: that is the player's choice,
## made per machine in the lobby, and lives on MatchRecorder. This is only the
## shape of the file once somebody has asked for one.

@export_group("Settings")
## Seconds of MATCH TIME between two snapshots of every player's economy and
## maze.
##
## A snapshot is redundant with the event stream - the events alone rebuild
## every maze - and exists so a reader can jump to any moment of a match without
## replaying everything before it. So this trades file size against how far a
## reader ever has to walk. Match time, not wall clock: a paused match takes no
## snapshots, and two machines recording the same match take theirs on the same
## ticks.
##
## Zero or less takes no periodic snapshots at all, only the opening and the
## closing one. The script default is that on purpose: the .tres is the
## authority, and a default matching it would be stripped from the file on the
## next editor save (CLAUDE.md).
@export var snapshot_interval_seconds: float = 0.0


## Snapshot spacing in simulation ticks, or 0 for "only the opening and closing
## ones".
func snapshot_interval_ticks(tick_seconds: float) -> int:
	if snapshot_interval_seconds <= 0.0 || tick_seconds <= 0.0:
		return 0
	return maxi(1, roundi(snapshot_interval_seconds / tick_seconds))
