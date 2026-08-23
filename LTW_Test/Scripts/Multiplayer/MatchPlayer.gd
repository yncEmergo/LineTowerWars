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

## Position in the match, 1..player_count. Chooses which area is theirs.
@export var slot: int = 1
@export var display_name: String = "Player"
## Peer id on the wire. 0 while there is no network.
@export var network_id: int = 0


static func create(player_slot: int, name_text: String, peer_id: int = 0) -> MatchPlayer:
	var player: MatchPlayer = MatchPlayer.new()
	player.slot = player_slot
	player.display_name = name_text
	player.network_id = peer_id
	return player


static func from_dict(data: Dictionary) -> MatchPlayer:
	var player: MatchPlayer = MatchPlayer.new()
	player.slot = int(data.get("slot", 1))
	player.display_name = str(data.get("display_name", "Player"))
	player.network_id = int(data.get("network_id", 0))
	return player


func to_dict() -> Dictionary:
	return {
		"slot": slot,
		"display_name": display_name,
		"network_id": network_id,
	}
