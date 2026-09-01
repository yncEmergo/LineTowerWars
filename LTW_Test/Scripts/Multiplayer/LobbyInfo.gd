class_name LobbyInfo
extends Resource

## One lobby: what it advertises in the browser, and who is sitting in it.
##
## The roster lives here rather than in a second type, because a lobby IS a
## match waiting to happen (D22). Its members are `MatchPlayer`s - the same flat
## record a match runs on - so pressing Start wraps this list rather than
## converting it, and there is one serialisable player type in the project
## rather than two that must be kept in step.
##
## lobby_id is a String because the thing handing them out may change: our
## server issues a counter today, a Steam lobby id is a 64 bit number and a
## master server would issue a token. None of them has to be made to look like
## the others.
##
## Godot cannot send a custom Resource over RPC, so this travels as a Dictionary
## through to_dict() / from_dict(). Everything added here must stay serialisable
## - see multiplayer.md 7.

@export var lobby_id: String = ""
@export var lobby_name: String = ""
## Peer id of whoever created it. The host is only a label: the lobby lives on
## the server and nothing technical depends on them, they are simply the one
## who may press Start. When they leave, the lobby closes (D23).
@export var host_id: int = 0
@export var max_players: int = 2
## Set once the match has begun, so a running lobby can still be listed but not
## joined.
@export var is_in_progress: bool = false
## Set while the start countdown is running (D24). A separate flag from
## is_in_progress because it is a separate thing: the match has NOT begun, and
## the countdown can still be cancelled back to nothing. Both make a lobby
## unjoinable, but only one of them is permanent.
@export var is_starting: bool = false
## Round trip to the server in milliseconds. -1 means not measured.
@export var ping_ms: int = -1
## Everyone in the lobby, in join order, slots renumbered 1..n as people come
## and go so this is always a valid basis for a MatchSetup.
@export var members: Array[MatchPlayer] = []
## The rules this lobby will be played under, chosen by the host and shown to
## everybody (multiplayer.md 8.2). Never null: a lobby with no settings is a
## match nobody could start, so one is stood in rather than left empty.
@export var settings: MatchSettings = MatchSettings.new()


static func from_dict(data: Dictionary) -> LobbyInfo:
	var lobby: LobbyInfo = LobbyInfo.new()
	lobby.lobby_id = str(data.get("lobby_id", ""))
	lobby.lobby_name = str(data.get("lobby_name", ""))
	lobby.host_id = int(data.get("host_id", 0))
	lobby.max_players = int(data.get("max_players", 2))
	lobby.is_in_progress = bool(data.get("is_in_progress", false))
	lobby.is_starting = bool(data.get("is_starting", false))
	lobby.ping_ms = int(data.get("ping_ms", -1))
	lobby.settings = MatchSettings.from_dict(data.get("settings", {}) as Dictionary)

	var raw_members: Array = data.get("members", []) as Array
	for entry in raw_members:
		if entry is Dictionary:
			lobby.members.append(MatchPlayer.from_dict(entry as Dictionary))
	return lobby


func to_dict() -> Dictionary:
	var member_dicts: Array = []
	for player in members:
		if player != null:
			member_dicts.append(player.to_dict())
	return {
		"lobby_id": lobby_id,
		"lobby_name": lobby_name,
		"host_id": host_id,
		"max_players": max_players,
		"is_in_progress": is_in_progress,
		"is_starting": is_starting,
		"ping_ms": ping_ms,
		"members": member_dicts,
		"settings": settings.to_dict(),
	}


## The match this lobby becomes. Server side: it is the server that decides
## the id and the seed, which is why both are arguments rather than rolled here.
##
## local_slot is left at 0 - "watching everything, playing nothing" - because a
## lobby has no local player. Each machine is told its own slot when the setup
## is sent to it, since that is the one field whose value differs per machine.
##
## The members are COPIED rather than handed over. A lobby carries on existing
## after the match starts, and renumbering its slots when somebody leaves must
## not reach into a match that is already running.
func to_match_setup(id: String, seed_value: int) -> MatchSetup:
	var setup: MatchSetup = MatchSetup.new()
	setup.match_id = id
	setup.rng_seed = seed_value
	setup.local_slot = 0
	setup.settings = settings.duplicate_settings()
	for player in members:
		if player != null:
			setup.players.append(MatchPlayer.from_dict(player.to_dict()))

	if setup.settings.random_lanes:
		_shuffle_lanes(setup, seed_value)
	return setup


## Deals the roster out into the lanes at random, so who sends into whom is not
## the order people happened to join in.
##
## Server side, once, on a generator seeded from the MATCH seed rather than on
## the global randi(): the roll is then reproducible from the one number the
## match already carries, which is what makes a strange draw something that can
## be looked into rather than only complained about. Every machine is told the
## result rather than rolling it, so nothing here has to agree with anything.
##
## The slots are handed out afterwards, in the new order, because a slot IS the
## lane - the areas, the build grid and PlayerState all index by it.
func _shuffle_lanes(setup: MatchSetup, seed_value: int) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	for index in range(setup.players.size() - 1, 0, -1):
		var other: int = rng.randi_range(0, index)
		var held: MatchPlayer = setup.players[index]
		setup.players[index] = setup.players[other]
		setup.players[other] = held

	var slot: int = 1
	for player in setup.players:
		if player != null:
			player.slot = slot
			slot += 1


func player_count() -> int:
	return members.size()


func is_full() -> bool:
	return player_count() >= max_players


## Nobody may join during the countdown (D24), which is why is_starting refuses
## here as flatly as a match already running does.
func is_joinable() -> bool:
	return !is_in_progress && !is_starting && !is_full()


## The host's display name, looked up rather than stored, so it cannot drift
## from the roster the browser is showing.
func host_name() -> String:
	var host: MatchPlayer = member_for(host_id)
	if host == null:
		return "Unknown"
	return host.display_name


func member_for(peer_id: int) -> MatchPlayer:
	for player in members:
		if player != null && player.network_id == peer_id:
			return player
	return null


func has_member(peer_id: int) -> bool:
	return member_for(peer_id) != null


## Adds a player and gives them the next free slot. Server side only - a client
## never edits its own copy, it is told what the roster is.
func add_member(player: MatchPlayer) -> void:
	if player == null || has_member(player.network_id):
		return
	members.append(player)
	renumber_slots()


func remove_member(peer_id: int) -> void:
	var player: MatchPlayer = member_for(peer_id)
	if player == null:
		return
	members.erase(player)
	renumber_slots()


## Slots are 1..n with no gaps, because the areas, the build grid and
## PlayerState all index by slot and MatchSetup.validate() rejects anything
## else. Renumbering on every change means the roster is always a legal match.
##
## The cost is that leaving a lobby can move somebody else's slot, which is
## fine while a slot is just a lane number and nobody has chosen one.
func renumber_slots() -> void:
	var slot: int = 1
	for player in members:
		if player != null:
			player.slot = slot
			slot += 1


func players_text() -> String:
	return "%d / %d" % [player_count(), max_players]


## Starting beats Full, because "Starting..." is the more useful thing to know
## about a lobby that happens to be both.
func status_text() -> String:
	if is_in_progress:
		return "In progress"
	if is_starting:
		return "Starting..."
	if is_full():
		return "Full"
	return "Open"


func ping_text() -> String:
	if ping_ms < 0:
		return "-"
	return "%d ms" % ping_ms
