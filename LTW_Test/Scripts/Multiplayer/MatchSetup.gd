class_name MatchSetup
extends Resource

## Everything a match needs to know about who is playing it.
##
## Main used to read player_count and local_player_id straight off
## game_config.tres. That file is IDENTICAL on every machine, so it can say how
## many players there are but never which one you are - which is exactly the
## question a networked match has to answer. This carries both, plus the seed
## every machine's random stream starts from. See multiplayer.md.
##
## Built by the lobby today and by the server later. Nothing in the match reads
## the config for these facts any more.
##
## Flat and serialisable throughout, for the same reason as MatchPlayer.

@export var match_id: String = ""
@export var players: Array[MatchPlayer] = []
## Which slot this client controls. Meaningless on a dedicated server, which
## controls none of them, so 0 is allowed and means "watching everything".
@export var local_slot: int = 0
## Seed for the one shared match RNG, so every machine rolls the same numbers.
@export var rng_seed: int = 0
## The rules this match is played under, chosen by the host in the lobby
## (multiplayer.md 8.2). Never null - a match with no settings is one nothing
## could work out a starting life total from - so a stand-in is created here
## and replaced by whatever the lobby agreed.
@export var settings: MatchSettings = MatchSettings.new()


## The single-player stand-in, used when Main.tscn is run straight from the
## editor with no lobby in front of it. Keeps that workflow working unchanged,
## which matters because it is how the game is tested.
static func from_config(config: GameConfig) -> MatchSetup:
	var setup: MatchSetup = MatchSetup.new()
	# Before the null check, so even the broken path carries a settings block
	# that reads back as something rather than as a match with no income.
	setup.settings = MatchSettings.defaults(config)
	if config == null:
		Log.err("MatchSetup cannot stand in for a lobby without a GameConfig")
		setup.players.append(MatchPlayer.create(1, "Player 1"))
		setup.local_slot = 1
		return setup

	for slot in range(1, config.player_count + 1):
		setup.players.append(MatchPlayer.create(slot, "Player %d" % slot))
	setup.local_slot = clampi(config.local_player_id, 1, maxi(1, config.player_count))
	# Varies per run so single player is not the same match every time. A real
	# match takes its seed from the server instead.
	setup.rng_seed = randi()
	return setup


static func from_dict(data: Dictionary) -> MatchSetup:
	var setup: MatchSetup = MatchSetup.new()
	setup.match_id = str(data.get("match_id", ""))
	setup.local_slot = int(data.get("local_slot", 0))
	setup.rng_seed = int(data.get("rng_seed", 0))
	setup.settings = MatchSettings.from_dict(data.get("settings", {}) as Dictionary)

	var raw_players: Array = data.get("players", []) as Array
	for entry in raw_players:
		if entry is Dictionary:
			setup.players.append(MatchPlayer.from_dict(entry as Dictionary))
	return setup


func to_dict() -> Dictionary:
	var player_dicts: Array = []
	for player in players:
		if player != null:
			player_dicts.append(player.to_dict())
	return {
		"match_id": match_id,
		"local_slot": local_slot,
		"rng_seed": rng_seed,
		"settings": settings.to_dict(),
		"players": player_dicts,
	}


func player_count() -> int:
	return players.size()


func player_for(slot: int) -> MatchPlayer:
	for player in players:
		if player != null && player.slot == slot:
			return player
	return null


func local_player() -> MatchPlayer:
	return player_for(local_slot)


## Whether this machine plays one of the slots. False on a dedicated server,
## which simulates every lane and commands none of them.
func has_local_player() -> bool:
	return local_player() != null


## Reports every way the setup is unusable, all at once rather than one crash
## at a time. Slots must be 1..count with no gaps or repeats, because the areas
## and PlayerState both index by slot.
func validate() -> bool:
	if players.is_empty():
		Log.err("MatchSetup has no players")
		return false

	var seen: Dictionary = {}
	var complete: bool = true
	for player in players:
		if player == null:
			Log.err("MatchSetup holds a null player")
			complete = false
			continue
		if player.slot < 1 || player.slot > players.size():
			Log.err("MatchSetup player slot is out of range", {
				"slot": player.slot,
				"players": players.size(),
			})
			complete = false
		if seen.has(player.slot):
			Log.err("MatchSetup has two players in one slot", player.slot)
			complete = false
		seen[player.slot] = true

	if local_slot != 0 && !seen.has(local_slot):
		Log.err("MatchSetup local_slot names a slot nobody is in", local_slot)
		complete = false
	return complete
