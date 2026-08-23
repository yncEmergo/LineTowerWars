class_name LobbyIdentity

## Who the local player is, as far as the menus are concerned.
##
## The one place in the project that answers "what is my name", so there is
## exactly one line to change when a real identity arrives. Whatever backend we
## settle on brings its own: Steam hands over a persona name and a SteamID, an
## account server hands over a profile. Until then this is the OS user name,
## which is enough to tell two test machines apart.
##
## Nothing here is an identity in the security sense. A name a client states
## about itself can never be trusted by a server - see multiplayer.md.

const FALLBACK_NAME: String = "Player"
## Longest display name the server will keep. Matches MenuConfig's limit on a
## lobby name; both are strings a client states and everybody else is shown.
const MAX_NAME_LENGTH: int = 32


## The display name to show for the local player.
static func display_name() -> String:
	var user_name: String = ""
	if OS.has_environment("USERNAME"):
		user_name = OS.get_environment("USERNAME")
	elif OS.has_environment("USER"):
		user_name = OS.get_environment("USER")

	user_name = user_name.strip_edges()
	if user_name.is_empty():
		return FALLBACK_NAME
	return user_name

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
