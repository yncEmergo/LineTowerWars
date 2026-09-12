class_name MatchPlayer
extends Resource

## One player in a match.
##
## Deliberately flat and made only of primitives, because this has to survive a
## trip over the network: Godot cannot send a custom Resource over RPC safely,
## so everything here goes through to_dict() and comes back through from_dict().
## Anything added must stay serialisable.
##
## slot is the player's identity INSIDE the match - the number the areas, the
## grid and PlayerState already use, counting from 1. network_id is who they
## are on the wire, and the two are deliberately separate: a player keeps their
## slot for the whole match even if their connection changes.

## color_index meaning "nothing has been chosen". Readers fall back to the slot
## for it, which is what a single player run and a bare test scene both get.
const NO_COLOR: int = -1
## ai_difficulty meaning "this is a person", which is what nearly every row in
## nearly every match is.
const HUMAN: int = -1


## Position in the match, 1..player_count. Chooses which area is theirs.
@export var slot: int = 1
@export var display_name: String = "Player"
## Peer id on the wire. 0 while there is no network.
@export var network_id: int = 0
## Which colour in PresentationConfig's palette this player chose, 0-based, or
## NO_COLOR while they have none.
##
## PER-MATCH IDENTITY, which is why it rides here beside slot and network_id
## rather than being worked out from either. A colour is CHOSEN in the lobby
## and a slot is dealt out by the server - the lane shuffle moves the slot and
## leaves this alone - so the two must not be the same number. It is also the
## only thing naming a player in an ANONYMOUS match, where the display name is
## never shown.
##
## Unique within a lobby: the server assigns a free one on join and refuses a
## taken one, exactly as it refuses a full lobby. See multiplayer.md 8.1.
@export var color_index: int = NO_COLOR
## Which AI profile plays this slot, by its index in AiConfig, or HUMAN for a
## person.
##
## ONE field rather than a bool and a level, because they are never separately
## true: a slot is a person or it is a profile, and a profile IS the difficulty.
## It rides here beside the slot and the colour because it is per-match identity
## in exactly the same way - the lane shuffle moves the slot and leaves this
## alone - and because a single player match is built by the same code a lobby
## builds one with.
##
## A networked match never sets it today. Nothing refuses one either: the field
## is serialisable like everything else here, so a lobby that one day offers an
## AI seat costs no wire format change.
@export var ai_difficulty: int = HUMAN


## Whether a profile plays this slot rather than a person.
func is_ai() -> bool:
	return ai_difficulty != HUMAN


static func create(player_slot: int, name_text: String, peer_id: int = 0,
		color: int = NO_COLOR, difficulty: int = HUMAN) -> MatchPlayer:
	var player: MatchPlayer = MatchPlayer.new()
	player.slot = player_slot
	player.display_name = name_text
	player.network_id = peer_id
	player.color_index = color
	player.ai_difficulty = difficulty
	return player


static func from_dict(data: Dictionary) -> MatchPlayer:
	var player: MatchPlayer = MatchPlayer.new()
	player.slot = int(data.get("slot", 1))
	player.display_name = str(data.get("display_name", "Player"))
	player.network_id = int(data.get("network_id", 0))
	player.color_index = int(data.get("color_index", NO_COLOR))
	player.ai_difficulty = int(data.get("ai", HUMAN))
	return player


func to_dict() -> Dictionary:
	return {
		"slot": slot,
		"display_name": display_name,
		"network_id": network_id,
		"color_index": color_index,
		"ai": ai_difficulty,
	}
