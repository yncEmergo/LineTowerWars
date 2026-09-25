class_name MatchHandoff

## The CONTRACTS between a lobby process and the match process it spawns (D44).
##
## Four things cross that boundary, and all four are fixed here rather than in
## whichever file happened to need one first:
##
##   the MATCH FILE   what the lobby writes and the child reads
##   the AUTH BYTES   what a client presents, and what a refusal says back
##   the RESULT       what the child writes and the lobby reads
##   the EXIT CODES   how the lobby tells a failed bind from a crash
##
## **They are settled in P2, before P3 is written**, because P3 writes what P2
## reads and a contract discovered by one side halfway through is a contract the
## other side already got wrong. The auth bytes are the strictest of the four:
## they are what an EXPORTED client build speaks, so changing them after a
## release costs a protocol bump.
##
## See `Docs/multi-match.md` §2 steps 1, 6 and 8.


## The match file's shape. The child refuses a file that does not carry this
## number, so a lobby and a child from different checkouts fail loudly at the
## boot rather than subtly at the first missing key.
const MATCH_FILE_FORMAT: int = 1

## How many bytes a seat token is. Sixteen from `Crypto.generate_random_bytes`,
## which is what P1 measured the auth path with. A message of any other length
## is refused without being looked at.
const TOKEN_BYTES: int = 16

# --- exit codes -----------------------------------------------------------
#
# **Between 65 and 126, and the range is not arbitrary.** A death by signal
# comes back from Godot as the raw wait status, which without a core dump is the
# signal number itself, and Linux signals run up to SIGRTMAX at 64. A code of 64
# or below is therefore ambiguous between "this process decided to exit" and
# "the kernel killed it", which is exactly the distinction the lobby needs.

## Ended normally. A RESULT file exists.
const EXIT_OK: int = 0
## The bind failed: something else holds that port. **The only code the lobby
## acts on** - it respawns once on the next free port.
const EXIT_PORT_TAKEN: int = 65
## The match file was missing, unreadable, or of another format.
const EXIT_BAD_MATCH_FILE: int = 66
## Refused to boot with `lockstep_enabled` off. The replication comparison runs
## in a single process, as it does today.
const EXIT_LOCKSTEP_OFF: int = 67

# --- auth statuses --------------------------------------------------------
#
# One byte, from an APPEND-ONLY list. A released client build knows these
# numbers, so a number may be added but never reused and never renumbered.
#
# There is no SUCCESS: success is `complete_auth` and carries no bytes.

## The token was not this match's, or the message was not a token at all.
const AUTH_WRONG_TOKEN: int = 1
## Another connection - admitted, or merely pending - already holds that seat.
## The client RETRIES this one: it is what a redial gets while the server has
## not yet noticed the dead link it is replacing.
const AUTH_SEAT_HELD: int = 2
## The seat is out of this match: it was still pending at the go signal, or its
## player's hold ran out. Never sent after go - see `MatchSeats.close_for_go`.
const AUTH_TOO_LATE: int = 3
## The match process is shutting down (D45).
const AUTH_SHUTTING_DOWN: int = 4


## What a client puts on screen for each refusal, and the one line it shows when
## it simply never got in.
##
## Here rather than on the client, because the status and its sentence are two
## halves of one contract: a number added above with no sentence would reach a
## player as a blank screen.
static func status_sentence(status: int) -> String:
	match status:
		AUTH_WRONG_TOKEN:
			return "The server did not recognise this match. Try creating a new lobby."
		AUTH_SEAT_HELD:
			return "Your seat is still held by an earlier connection. Try again in a moment."
		AUTH_TOO_LATE:
			return "The match started without you."
		AUTH_SHUTTING_DOWN:
			return "The server is restarting. The match was cancelled."
	return "The match could not be joined."


## A refusal as the single byte that goes on the wire.
static func status_bytes(status: int) -> PackedByteArray:
	var payload: PackedByteArray = PackedByteArray()
	payload.append(clampi(status, 0, 255))
	return payload


## The status a refusal payload carries, or 0 for anything that is not one.
##
## A payload of any other length is not a refusal this build knows about. It
## reads as 0 rather than as an error, so a LATER server that adds a longer
## message cannot make an older client fail to show anything at all.
static func status_of(payload: PackedByteArray) -> int:
	if payload.size() != 1:
		return 0
	return payload[0]


## A token as the 32 lowercase hex characters it travels as.
##
## **Hex rather than the bytes themselves**, because both places a token crosses
## are JSON or a Dictionary that gets serialised: `Crypto.generate_random_bytes`
## hands back a `PackedByteArray`, which does not survive a plain JSON round trip
## as one. It comes back as an Array of ints, or as a base64 string, depending on
## which way it went - and a token that compares unequal because of its container
## is a bug nobody would look for in the right place.
static func token_to_hex(token: PackedByteArray) -> String:
	var text: String = ""
	for value: int in token:
		text += "%02x" % value
	return text


## A hex token back to bytes, or an EMPTY array for anything malformed.
##
## Empty is never a valid token (`is_valid_token` refuses it), so a truncated or
## mistyped entry in a match file cannot accidentally match a seat.
static func token_from_hex(hex: String) -> PackedByteArray:
	var token: PackedByteArray = PackedByteArray()
	var text: String = hex.strip_edges().to_lower()
	if text.length() != TOKEN_BYTES * 2 || !text.is_valid_hex_number(false):
		return token
	for index: int in range(0, text.length(), 2):
		token.append(text.substr(index, 2).hex_to_int())
	return token


## Whether a token is the right shape to be one at all. Checked before anything
## is compared, so a zero-length or short payload is refused rather than matched
## against a seat that happens to hold the same nothing.
static func is_valid_token(token: PackedByteArray) -> bool:
	return token.size() == TOKEN_BYTES


## Whether two tokens are the same one.
##
## Byte by byte over a fixed length rather than `==` on the arrays, so this
## cannot be quietly changed into a comparison of two different containers by a
## later refactor. Not constant time, deliberately: guessing 16 random bytes
## over a network by timing is not a threat this project has.
static func tokens_equal(a: PackedByteArray, b: PackedByteArray) -> bool:
	if !is_valid_token(a) || !is_valid_token(b):
		return false
	for index: int in range(TOKEN_BYTES):
		if a[index] != b[index]:
			return false
	return true


## The match file, written whole and then moved into place.
##
## Keys: `format`, `setup`, `tokens` (slot as a STRING, token as hex),
## `countdown_ends` (Unix seconds) and `lobby_pid`.
##
## `countdown_ends` is Unix seconds from `Time.get_unix_time_from_system()`,
## which the lobby and the child may share because they run on one machine. It
## is when D15's clock would start if the child were already up; the child takes
## the LATER of it and its own READY, so a slow boot never shortens anybody's
## load window (§2 step 6).
##
## `lobby_pid` is LOGGED AND NOTHING MORE. A match never acts on its lobby's
## death, because stage (b) exists precisely so that matches outlive it.
static func write_match_file(
	path: String,
	setup: MatchSetup,
	tokens: Dictionary,
	countdown_ends: float,
	lobby_pid: int
) -> bool:
	if setup == null:
		Log.err("MatchHandoff was asked to write a match file with no setup", path)
		return false

	var hexed: Dictionary = {}
	for slot: int in tokens:
		hexed[str(slot)] = token_to_hex(tokens[slot])

	return write_json(path, {
		"format": MATCH_FILE_FORMAT,
		"setup": setup.to_dict(),
		"tokens": hexed,
		"countdown_ends": countdown_ends,
		"lobby_pid": lobby_pid,
	})


## Every handoff path, in the one spelling Godot's file access accepts.
##
## **A Windows path with backslashes silently does not exist.**
## `FileAccess.file_exists("C:\\run\\x.match")` is FALSE for a file that is
## plainly sitting there, and nothing anywhere says so - the match process simply
## exits with BAD_MATCH_FILE as though the lobby had written nonsense. It cost a
## debugging cycle on the first P2 run, where the harness passed a path
## PowerShell had built and the child died with one log line and no reason.
##
## Applied on the way in and on the way out, because a path reaches these
## functions from a command line as often as from code.
static func normalise(path: String) -> String:
	return path.strip_edges().replace("\\", "/")


## The match file back, or an EMPTY dictionary for anything the child must
## refuse. The caller exits with `EXIT_BAD_MATCH_FILE` on an empty one.
##
## Unlike `read_json`, a missing file is an ERROR here. This is a one-shot read
## of a file the lobby has already written, so its absence is a real failure and
## the process is about to exit over it - as against the polling reads, where a
## file not being there yet is the ordinary case.
static func read_match_file(path: String) -> Dictionary:
	var where: String = normalise(path)
	if where.is_empty() || !FileAccess.file_exists(where):
		Log.err("There is no match file where this process was told to look", {
			"given": path,
			"looked": where,
		})
		return {}
	var data: Dictionary = read_json(where)
	if data.is_empty():
		return {}
	if int(data.get("format", 0)) != MATCH_FILE_FORMAT:
		Log.err("Match file is of another format", {
			"file": path,
			"found": data.get("format", 0),
			"expected": MATCH_FILE_FORMAT,
		})
		return {}
	if !(data.get("setup") is Dictionary) || !(data.get("tokens") is Dictionary):
		Log.err("Match file is missing its setup or its tokens", path)
		return {}
	return data


## The token map out of a read match file: slot (int) to bytes.
##
## A malformed entry is DROPPED rather than kept as an unmatchable token, and
## says so. The seat it belonged to is then simply never claimable, which the
## load timeout handles - as against a token that silently never matches, which
## looks exactly like a client bug.
static func tokens_from(data: Dictionary) -> Dictionary:
	var tokens: Dictionary = {}
	var raw: Dictionary = data.get("tokens", {})
	for key: Variant in raw:
		var slot: int = int(str(key))
		var token: PackedByteArray = token_from_hex(str(raw[key]))
		if slot <= 0 || !is_valid_token(token):
			Log.err("Match file carries a token that is not one", {"slot": key})
			continue
		tokens[slot] = token
	return tokens


## Writes JSON to a temporary name and MOVES it into place, so nothing ever
## reads a half-written file. The reader on the other side is another process
## polling for this file to appear.
static func write_json(raw_path: String, data: Dictionary) -> bool:
	var path: String = normalise(raw_path)
	var temporary: String = path + ".part"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		Log.err("Could not write a handoff file", {
			"file": temporary,
			"error": FileAccess.get_open_error(),
		})
		return false
	file.store_string(JSON.stringify(data))
	file.close()

	# Windows refuses a rename onto an existing name, where POSIX replaces it.
	# Removing first is the one spelling that behaves the same on both.
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var error: Error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		Log.err("Could not move a handoff file into place", {"file": path, "error": error})
		return false
	return true


## JSON back from a file, or an EMPTY dictionary for missing, unreadable or
## malformed. Every failure says which, because these files are read across a
## process boundary where there is nothing else to look at.
static func read_json(raw_path: String) -> Dictionary:
	var path: String = normalise(raw_path)
	if path.is_empty() || !FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		Log.err("Could not read a handoff file", {
			"file": path,
			"error": FileAccess.get_open_error(),
		})
		return {}
	var text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if !(parsed is Dictionary):
		Log.err("A handoff file did not hold a JSON object", {"file": path})
		return {}
	return parsed
