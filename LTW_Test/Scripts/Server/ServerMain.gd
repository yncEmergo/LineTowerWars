class_name ServerMain
extends Control

## The dedicated server's entry scene: what the process shows and says while it
## is not in a match.
##
## Deliberately a Control with a log view rather than a bare Node. Run from the
## editor it is a window that tells you what the server is doing, which is the
## difference between debugging a lobby and guessing at one. Exported with
## --headless there is no window and the same lines go to stdout, which is why
## log_line() writes to both - see multiplayer.md.
##
## It opens the listen socket through the `Net` autoload and reports what
## happens on it. It does not own the socket - NetworkService does - and it
## knows nothing about lobbies, which the `Lobby` autoload owns.
##
## This is also where the process comes BACK to when a match ends, so nothing
## here may assume it is running for the first time.

@export_group("References")
@export var _title_label: Label
## One line saying what the server is doing right now. Not history - the log
## view below is the history.
@export var _status_label: Label
@export var _log_view: RichTextLabel

@export_group("Settings")
## Lines kept in the view. The log is a debugging window, not a record: the
## file on disk is what a real deployment keeps.
@export var _max_lines: int = 500

## Newest last, exactly as displayed. Rebuilt into the view on every append,
## which is fine at the handful-of-events-per-second a lobby produces and would
## not be for a per-tick stream.
var _lines: Array[String] = []


func _ready() -> void:
	if _log_view != null:
		# Names typed by players end up in here. BBCode stays OFF so a display
		# name can never colour the log, hide a line or open a link.
		_log_view.bbcode_enabled = false
		_log_view.scroll_following = true
		_log_view.text = ""

	if _title_label != null:
		_title_label.text = "DEDICATED SERVER"

	_report_boot()

	# Signals before hosting, so a peer that arrives during the same frame as
	# the socket opening still gets reported.
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	_start_hosting()


## Appends one line to the log view AND to the ordinary log, because a headless
## run has no view and stdout is the only place it can say anything.
func log_line(text: String) -> void:
	Log.info("[server] %s" % text)

	_lines.append("[%s] %s" % [Time.get_time_string_from_system(), text])
	if _lines.size() > _max_lines:
		_lines = _lines.slice(_lines.size() - _max_lines)

	if _log_view != null:
		_log_view.text = "\n".join(_lines)


## The one line saying what the server is doing now, as opposed to what it has
## done. Replaced rather than appended.
func set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


## What this process is, said out loud at boot. Every one of these has been
## worth having at least once: which instance you are looking at, whether the
## feature tag actually applied, and whether it is really running headless.
func _report_boot() -> void:
	log_line("Server process started")
	log_line("Process id: %d" % OS.get_process_id())
	log_line("Feature tag dedicated_server: %s" % str(OS.has_feature("dedicated_server")))
	log_line("Display server: %s" % DisplayServer.get_name())
	log_line("Simulation tick: %d Hz" % Engine.physics_ticks_per_second)


## Opens the port. A server that cannot listen is not a server, so a failure
## here is said plainly in both places rather than logged and shrugged off -
## the usual cause is the port already being held by a previous run.
func _start_hosting() -> void:
	# Already listening when this scene is opened for the SECOND time: the
	# process comes back here when a match ends, and the socket outlived it -
	# that is the whole reason Net is an autoload. Re-hosting would refuse and
	# report a failure that has not happened.
	if Net.is_server():
		log_line("Back from a match, still listening on port %d" % _port())
		_report_population()
		return

	var result: NetworkService.Result = Net.host()
	if result != NetworkService.Result.OK:
		var reason: String = NetworkService.describe(result)
		set_status("NOT LISTENING - %s" % reason)
		log_line("Failed to open the port: %s" % reason)
		return

	log_line("Listening on port %d, up to %d peers" % [_port(), _max_peers()])
	_report_population()


func _on_peer_joined(peer_id: int) -> void:
	log_line("Peer %d connected" % peer_id)
	_report_population()


func _on_peer_left(peer_id: int) -> void:
	log_line("Peer %d disconnected" % peer_id)
	_report_population()


## The status line always answers "how many are on right now", which is the one
## thing worth reading at a glance while testing.
func _report_population() -> void:
	set_status("Listening on port %d  -  %d connected" % [_port(), Net.peer_ids().size()])


func _port() -> int:
	var config: NetworkConfig = References.network_config
	if config == null:
		return 0
	return config.resolved_port()


func _max_peers() -> int:
	var config: NetworkConfig = References.network_config
	if config == null:
		return 0
	return config.max_peers
