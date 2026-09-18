class_name RelayMatchStats
extends RefCounted

## What one match cost the relay, gathered while it runs and written to the
## journal as ONE line when it ends.
##
## **So a capacity question is answered by the journal rather than by `sar`.**
## Playtest 8 asked how much of the rented box a match uses, and the only answer
## was the machine's ten-minute averages - which cannot tell a match from the
## lobby beside it, or one match from the next. This line says it per match:
## how long, how much traffic, how much CPU, and the biggest thing it had to send.
##
## Owned by `LockstepService` rather than folded into it, because that file is
## already over gdlint's public-method ceiling for reasons it cannot refactor
## away (`CLAUDE.md`, Known weaknesses). Nothing here is simulation, nothing
## here is read by the simulation, and all of it is wall clock.
##
## ## What it cannot say
##
## Traffic is the whole ENet host, not one match and not one peer - see
## `NetworkService.pop_traffic`. CPU is read from `/proc/self/stat`, so it is
## the whole process and exists on Linux only; anywhere else it reads -1 rather
## than pretending.

## A seal's payload above this many bytes will not fit in one packet once ENet's
## own headers are added, and goes out FRAGMENTED - which the unreliable echo
## survives far worse than a whole packet. Playtest 8 sent one of 2708 bytes.
## ENet's datagram ceiling is 1392; the margin is its per-command overhead.
const PACKET_WARN_BYTES: int = 1300

## Linux's clock tick for the utime/stime fields of `/proc/self/stat`. The kernel
## has reported 100 for these on every mainstream distribution for decades, and
## the relay box was checked on 2026-09-15.
const PROC_TICKS_PER_SECOND: float = 100.0

## A tick interval this many times the authored one counts as a missed tick.
const LATE_TICK_FACTOR: float = 2.0

var _match_id: String = ""
var _players: int = 0
var _started_msec: int = 0
var _cpu_at_start: float = -1.0
var _turns: int = 0
var _orders: int = 0
var _largest_bytes: int = 0
var _largest_turn: int = -1
var _oversized: int = 0
var _last_tick_usec: int = 0
var _worst_tick_ms: float = 0.0
var _late_ticks: int = 0
var _open: bool = false


## Whether a match is being measured, which is also whether `summary` has
## anything to say.
func is_open() -> bool:
	return _open


## Starts measuring a match. Clears the traffic counters, so what `summary`
## reports afterwards is this match's.
func begin(match_id: String, players: int) -> void:
	_match_id = match_id
	_players = players
	_started_msec = Time.get_ticks_msec()
	_cpu_at_start = _process_cpu_seconds()
	_turns = 0
	_orders = 0
	_largest_bytes = 0
	_largest_turn = -1
	_oversized = 0
	_last_tick_usec = 0
	_worst_tick_ms = 0.0
	_late_ticks = 0
	_open = true
	Net.pop_traffic()


## One relay tick. Per-tick, so two integers and a comparison and nothing else.
func note_tick(authored_rate: int) -> void:
	var now: int = Time.get_ticks_usec()
	if _last_tick_usec != 0:
		var interval_ms: float = float(now - _last_tick_usec) / 1000.0
		_worst_tick_ms = maxf(_worst_tick_ms, interval_ms)
		if interval_ms > LATE_TICK_FACTOR * 1000.0 / float(maxi(1, authored_rate)):
			_late_ticks += 1
	_last_tick_usec = now


## One sealed turn, and the echo it is about to go out in.
##
## **Measured only when the turn carries orders.** An empty seal is a turn number
## and an empty array, the same few bytes every time, and it is twenty a second -
## so encoding it to learn that would be a per-tick cost for a known answer. A
## turn with orders is a player action, and that is where a big one comes from.
func note_seal(turn: int, orders: Array, echo: Array) -> void:
	_turns += 1
	if orders.is_empty():
		return
	_orders += orders.size()
	var bytes: int = var_to_bytes(echo).size()
	if bytes > _largest_bytes:
		_largest_bytes = bytes
		_largest_turn = turn
	if bytes <= PACKET_WARN_BYTES:
		return
	_oversized += 1
	# The engine's own warning names neither the turn nor what was in it, so
	# playtest 8's could only be matched to an order by its clock.
	Log.warn("A seal is too large for one packet", {
		"match": _match_id, "turn": turn, "bytes": bytes, "orders": orders.size(),
	})


## The one line, as a Dictionary. Closes the measurement.
func summary(repairs_served: int, repair_seals_sent: int) -> Dictionary:
	_open = false
	var seconds: float = float(Time.get_ticks_msec() - _started_msec) / 1000.0
	var cpu_now: float = _process_cpu_seconds()
	var cpu: float = -1.0
	if cpu_now >= 0.0 && _cpu_at_start >= 0.0:
		cpu = cpu_now - _cpu_at_start
	var out: Dictionary = {
		"match": _match_id,
		"players": _players,
		"seconds": snappedf(seconds, 0.1),
		"turns": _turns,
		"orders": _orders,
		"largest_seal_bytes": _largest_bytes,
		"largest_seal_turn": _largest_turn,
		"oversized_seals": _oversized,
		"worst_tick_ms": snappedf(_worst_tick_ms, 0.1),
		"late_ticks": _late_ticks,
		"repairs_served": [repairs_served, repair_seals_sent],
		"cpu_seconds": snappedf(cpu, 0.01),
		"cpu_pct_of_core": -1.0 if cpu < 0.0 || seconds <= 0.0
			else snappedf(100.0 * cpu / seconds, 0.01),
		"rss_mb": _resident_mb(),
		"static_mb": snappedf(float(OS.get_static_memory_usage()) / 1048576.0, 0.1),
	}
	out.merge(Net.pop_traffic())
	return out


## User plus system CPU time of this process, in seconds, or -1 where there is
## no `/proc` to ask.
static func _process_cpu_seconds() -> float:
	var text: String = _read_proc("/proc/self/stat")
	if text.is_empty():
		return -1.0
	# The second field is the executable's name in parentheses and may itself
	# hold spaces, so the fields are counted from the LAST closing parenthesis.
	# After it, utime and stime are the 12th and 13th.
	var fields: PackedStringArray = text.substr(text.rfind(")") + 2).split(" ")
	if fields.size() < 13:
		return -1.0
	return (float(fields[11]) + float(fields[12])) / PROC_TICKS_PER_SECOND


## Resident memory of this process in megabytes, or -1 where there is no `/proc`.
static func _resident_mb() -> float:
	for line: String in _read_proc("/proc/self/status").split("\n"):
		if line.begins_with("VmRSS:"):
			var kilobytes: float = float(line.substr(6).strip_edges().split(" ")[0])
			return snappedf(kilobytes / 1024.0, 0.1)
	return -1.0


## A `/proc` file as text. **Read by line, not by length**: the kernel reports
## every one of these as zero bytes long, so anything that sizes a buffer from
## the length reads nothing at all.
static func _read_proc(path: String) -> String:
	if OS.get_name() != "Linux":
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var lines: PackedStringArray = PackedStringArray()
	while !file.eof_reached():
		var line: String = file.get_line()
		if line.is_empty() && file.eof_reached():
			break
		lines.append(line)
	return "\n".join(lines)
