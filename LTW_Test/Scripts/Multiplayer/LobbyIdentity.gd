class_name LobbyIdentity

## Who the local player is, as far as the menus are concerned.
##
## The one place in the project that answers "what is my name", so there is
## exactly one line to change when a real identity arrives. Whatever backend we
## settle on brings its own: Steam hands over a persona name and a SteamID, an
## account server hands over a profile.
##
## Until then the player TYPES one, once, and it is kept in `UserSettings` -
## the lobby browser asks for it the first time somebody opens multiplayer and
## will not let them past until they have chosen. The OS user name is no longer
## the answer; it is only what the prompt SUGGESTS, because a machine login is
## not a thing anybody picked to be known by.
##
## Nothing here is an identity in the security sense. A name a client states
## about itself can never be trusted by a server - see multiplayer.md. The
## rules below are about what makes a legible name, not about who somebody is.

const FALLBACK_NAME: String = "Player"
## Longest display name the server will keep. Matches MenuConfig's limit on a
## lobby name; both are strings a client states and everybody else is shown.
const MAX_NAME_LENGTH: int = 32
## Shortest one a player may choose. Two characters is a lobby row that reads
## as a typo rather than as a person.
const MIN_NAME_LENGTH: int = 3

## What a name may be made of: LETTERS and DIGITS, plus space, underscore and
## hyphen inside it, and it has to START with a letter or a digit.
##
## Deliberately unicode rather than ASCII - `\p{L}` takes Jurgen and Jürgen
## alike, and a player whose own name needs an umlaut should not have to spell
## it wrong. What it refuses is PUNCTUATION and SYMBOLS: the characters people
## use to impersonate somebody else, to draw shapes in a lobby list, or to pad
## a name out with things that are hard to say out loud.
##
## A raw string, because GDScript reads `\p` in an ordinary one as a bad escape
## and refuses to parse the file at all.
const NAME_PATTERN: String = r"^[\p{L}\p{N}][\p{L}\p{N} _-]*$"

## Compiled once and kept, because every keystroke in the name prompt asks it.
static var _name_regex: RegEx = null


## The display name to show for the local player, or the fallback while nobody
## has chosen one - which nothing in the menus should ever be showing, since the
## browser asks before it lets anybody in.
static func display_name() -> String:
	var chosen: String = UserSettings.player_name.strip_edges()
	return FALLBACK_NAME if chosen.is_empty() else chosen


## Whether this machine has a name to play under. What the lobby browser asks
## before it does anything else.
static func has_name() -> bool:
	return !UserSettings.player_name.strip_edges().is_empty()


## What to put in the prompt's box for somebody who has never chosen: the OS
## user name, if it happens to be a legal one, and nothing at all if it is not.
##
## A SUGGESTION rather than an answer. It is offered because typing a name from
## scratch is a worse first impression than accepting the obvious one, and it is
## dropped silently when it breaks a rule rather than being cleaned up into
## something the player did not type.
static func suggested_name() -> String:
	var user_name: String = ""
	if OS.has_environment("USERNAME"):
		user_name = OS.get_environment("USERNAME")
	elif OS.has_environment("USER"):
		user_name = OS.get_environment("USER")

	user_name = user_name.strip_edges()
	return user_name if rejection(user_name).is_empty() else ""


## Stores a name this machine has chosen, and reports whether it took. Refuses
## anything rejection() would refuse, so there is one gate rather than a rule
## in the prompt and a different one here.
##
## NOT `set_name`, which is what it was called for about ten minutes. A class
## name is an expression that evaluates to the SCRIPT - a Resource - so
## `LobbyIdentity.set_name(...)` binds to Resource's own inherited setter
## instead of to the static declared here. It parses, it runs, it returns null
## and it stores nothing, with no warning anywhere. See CLAUDE.md.
static func choose_name(raw: String) -> bool:
	var wanted: String = raw.strip_edges()
	if !rejection(wanted).is_empty():
		return false
	UserSettings.player_name = wanted
	UserSettings.save_to_disk()
	return true


## Why this name cannot be used, as a sentence to show the player, or an empty
## string when it is fine.
##
## A REASON rather than a bool, because a prompt that only greys its button out
## makes the player guess which rule they broke. One message per rule, in the
## order somebody hits them.
static func rejection(raw: String) -> String:
	var wanted: String = raw.strip_edges()
	if wanted.is_empty():
		return "Enter a name."
	if wanted.length() < MIN_NAME_LENGTH:
		return "At least %d characters." % MIN_NAME_LENGTH
	if wanted.length() > MAX_NAME_LENGTH:
		return "At most %d characters." % MAX_NAME_LENGTH
	if _regex().search(wanted) == null:
		return "Letters and numbers only, plus spaces, - and _."
	return ""


static func _regex() -> RegEx:
	if _name_regex == null:
		_name_regex = RegEx.new()
		if _name_regex.compile(NAME_PATTERN) != OK:
			Log.err("LobbyIdentity could not compile its name pattern", NAME_PATTERN)
	return _name_regex


## Makes a name a client stated about itself safe to show to everybody else.
##
## Run on the SERVER, on arrival, and the result is what every other client is
## told (1.6). Three separate problems, none of them optional:
##
## - **Control characters.** A newline or a carriage return in a name breaks
##   every log line and every list row it appears in. Stripped, not escaped.
## - **Length.** An unbounded name is a way to push everyone else's row off the
##   screen, and it is sent to every client on every list update.
## - **Emptiness.** A name that was only whitespace, or only control characters,
##   has to become something rather than a blank row.
##
## What this is NOT is an identity check. It makes a string harmless to display;
## it says nothing about who sent it. The peer id is the identity, and it is
## assigned by the server, never claimed by the client.
static func sanitise(raw: String, max_length: int = MAX_NAME_LENGTH) -> String:
	var cleaned: String = ""
	for index in range(raw.length()):
		var character: String = raw[index]
		# Everything below space, plus DEL. Ordinary letters, digits and
		# punctuation of any language are left alone.
		var code: int = character.unicode_at(0)
		if code >= 32 && code != 127:
			cleaned += character

	cleaned = cleaned.strip_edges()
	if cleaned.length() > max_length:
		cleaned = cleaned.substr(0, max_length).strip_edges()
	if cleaned.is_empty():
		return FALLBACK_NAME
	return cleaned
