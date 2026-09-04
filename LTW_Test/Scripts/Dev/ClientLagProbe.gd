class_name ClientLagProbe
extends Node

## THROWAWAY. Turns "it feels laggy" into numbers, in the CLIENT's own log.
##
## **Delete this and its scene when the lag question is closed.** `Scripts/Dev`
## is scaffolding (`CLAUDE.md`).
##
## The question it answers: when a client hitches, is it the SERVER missing its
## tick, or the client choking on its own work? Those look identical to a player
## and have completely different fixes, and nothing currently distinguishes them.
##
## Three things get logged, all to `Log.warn` so they survive at the default
## level and land in the file this session can read afterwards:
##
##   SPIKE     a render frame that took far longer than it should, with what the
##             client did on it - how many units it built, how many it destroyed
##   BURST     a frame that instantiated several units at once, which is the
##             suspected cause and is worth seeing even when it did not spike
##   SUMMARY   every few seconds: frame and snapshot statistics, so a run can be
##             judged as a whole rather than by its worst moment
##
## It counts by watching the unit registry rather than by hooking
## `ReplicationService`, so the shipping path is untouched and nothing has to be
## put back afterwards.

## A frame slower than this is worth a line. 33 ms is two frames at 60 Hz.
const SPIKE_MS: float = 33.0

## This many new units in one frame is a burst worth seeing on its own.
const BURST_UNITS: int = 6

## Seconds between summary lines.
const SUMMARY_SECONDS: float = 5.0

var _known: int = 0
var _frames: int = 0
var _spikes: int = 0
var _worst_ms: float = 0.0
var _worst_built: int = 0
var _total_ms: float = 0.0
var _since_summary: float = 0.0
var _built_total: int = 0


func _ready() -> void:
	# Presentation only, and it must never run on the server: a headless server
	# has no render frame worth measuring and would only add noise to its log.
	if MatchSession.is_authority() && Net.is_online():
		queue_free()
		return
	Log.warn("ClientLagProbe active", {"spike_ms": SPIKE_MS, "burst_units": BURST_UNITS})


## _process, NOT _physics_process: a hitch is something a PLAYER sees, and what
## they see is a render frame that did not arrive. The simulation tick can be
## perfectly healthy while this is not.
func _process(delta: float) -> void:
	var session: MatchSession = References.match_session
	if session == null:
		return

	var now: int = session.unit_count()
	var built: int = maxi(0, now - _known)
	var removed: int = maxi(0, _known - now)
	_known = now

	var frame_ms: float = delta * 1000.0
	_frames += 1
	_total_ms += frame_ms
	_built_total += built

	if frame_ms > _worst_ms:
		_worst_ms = frame_ms
		_worst_built = built

	if frame_ms >= SPIKE_MS:
		_spikes += 1
		Log.warn("SPIKE", {
			"ms": snappedf(frame_ms, 0.1),
			"units_built": built,
			"units_removed": removed,
			"units_now": now,
		})
	elif built >= BURST_UNITS:
		Log.warn("BURST", {
			"units_built": built, "ms": snappedf(frame_ms, 0.1), "units_now": now,
		})

	_since_summary += delta
	if _since_summary >= SUMMARY_SECONDS:
		_report()
		_since_summary = 0.0


func _report() -> void:
	if _frames == 0:
		return
	Log.warn("SUMMARY", {
		"avg_fps": snappedf(1000.0 / (_total_ms / float(_frames)), 0.1),
		"avg_ms": snappedf(_total_ms / float(_frames), 0.2),
		"worst_ms": snappedf(_worst_ms, 0.1),
		"worst_frame_built": _worst_built,
		"spikes": _spikes,
		"frames": _frames,
		"units_built": _built_total,
		"units_now": _known,
	})
	_frames = 0
	_total_ms = 0.0
	_worst_ms = 0.0
	_worst_built = 0
	_spikes = 0
	_built_total = 0
