class_name MatchAudio
extends Node

## What a MATCH EVENT sounds like. One file between the simulation and the
## mixer, so no gameplay script ever reaches for AudioConfig itself.
##
## AudioHub owns the players, the cache and the budget and knows nothing about
## a match. This knows which sound a leak makes, whether a refused build is the
## local player's business, and which of the three ways to play a sound each
## event wants - and gameplay code calls one named line instead of repeating
## that decision at every site. The line between the two is the same one
## AudioConfig draws: the hub is the mixer, this is the score.
##
## **IT IS BOTH A NODE AND A SET OF STATICS, deliberately.** Some of these
## events already have a signal to listen to - a leak arrives on
## ReplicationService, which is an autoload and outlives a match scene - and
## listening is strictly better than a call, because it fires on the same terms
## under both netcode paths and cannot be forgotten by the next caller. Others
## have no signal and never will: nothing emits "a tower landed" and adding one
## for audio alone would be a channel with a single subscriber. So the node
## half listens where there is something to listen to, and the static half is
## called where there is not.
##
## It is AudioHub's own child, for exactly the reason ButtonSoundBinder is:
## audio is wanted wherever the hub is wanted and nowhere else, and a second
## [autoload] line is a change that breaks a running editor - see CLAUDE.md. It
## is therefore never built on a headless process, since the hub returns before
## adding its children there.
##
## **PRESENTATION, NEVER SIMULATION.** Every static here is safe to call with
## no autoload, no config and no match, so a probe or a bare --script run is a
## no-op rather than a crash. Several are called from inside gameplay loops and
## several read who the LOCAL player is, which is a different answer on every
## machine - so nothing in this file may ever be read back by anything that
## advances the world. See multiplayer.md.


func _ready() -> void:
	# The one match event that already has a channel of its own. Under lockstep
	# every peer emits this locally when it applies the turn, so both machines
	# play it on the same turn with nothing new crossing the wire; under the
	# replication path it only ever fires on the server, which is the same
	# asymmetry LeakLog documents and not this file's to fix.
	Replication.leak_reported.connect(_on_leak_reported)


# --- what the local player is told ------------------------------------------

## A leak, as the authority saw it. FLAT: the lane it happened in is precisely
## the one the player was not watching.
##
## Silently ignores every leak the local player is not part of, which is most
## of them in a big match - the same filter LeakLog's message applies, for the
## same reason.
func _on_leak_reported(thief: int, victim: int, _lives: int) -> void:
	var config: AudioConfig = _config_or_null()
	if config == null:
		return
	if _is_local(victim):
		AudioHub.play_event(config.match_life_lost_path)
	elif _is_local(thief):
		AudioHub.play_event(config.match_life_taken_path)


# --- what the simulation says happened --------------------------------------

## The income payout landed. FLAT, and once for the whole match rather than
## once per player: every player is paid on the same tick and only one of them
## is sitting here.
static func income_paid() -> void:
	var config: AudioConfig = _config_or_null()
	if config != null:
		AudioHub.play_event(config.match_gold_path)


## A tower landed on the grid. WORLD, at the tower.
##
## Not filtered to the local player, and that is the point of it being a world
## sound: under lockstep every client places every player's towers, and the
## distance gate is what decides whose building anybody hears.
static func tower_placed(at: Vector3) -> void:
	var config: AudioConfig = _config_or_null()
	if config != null:
		AudioHub.play_at(config.build_placed_path, at)


## A build order that came to nothing: the spot was taken while the builder
## walked, or the gold ran out before it arrived. FLAT, and only for the player
## whose order it was.
##
## Filtered where tower_placed is not, because this one has no place: there is
## no tower to play it at, and the whole news is that there is not.
static func build_denied(player_id: int) -> void:
	var config: AudioConfig = _config_or_null()
	if config == null || !_is_local(player_id):
		return
	AudioHub.play_event(config.build_denied_path)


## A freshly sent creep arriving. WORLD, at the creep.
##
## `stats` may be null - a creep with no CreepStats is already an error
## somewhere else - in which case the roster default is used. A pack arrives on
## one tick and asks for this three to six times over; the same-sound gap lets
## one through, which is both cheaper and closer to what a pack should sound
## like. See AudioHub._claim_gap.
static func creep_spawned(stats: CreepStats, at: Vector3) -> void:
	# Asked before the config is reached for, unlike everything above it. These
	# two are the only calls in this file on a PER-UNIT path - every creep in
	# every lane spawns and dies - and a dedicated server runs that loop with
	# no output device at all. One static bool is what it pays instead.
	if !AudioHub.is_available():
		return
	AudioHub.play_at(_creep_sound(stats, false), at)


## A creep that really died - after its passives have had their turn and none
## of them kept it standing. WORLD, where it fell.
static func creep_died(stats: CreepStats, at: Vector3) -> void:
	if !AudioHub.is_available():
		return
	AudioHub.play_at(_creep_sound(stats, true), at)


# --- asking -----------------------------------------------------------------

## What this creep sounds like, preferring its own stats over the roster
## default. An empty path either way is a creep that makes no sound, which
## AudioHub answers by doing nothing.
static func _creep_sound(stats: CreepStats, dying: bool) -> String:
	if stats != null:
		var own: String = stats.death_sound_path if dying else stats.spawn_sound_path
		if !own.is_empty():
			return own
	var config: AudioConfig = _config_or_null()
	if config == null:
		return ""
	return config.creep_death_path if dying else config.creep_spawn_path


## The config, or null when References has not been wired - which is every
## process that is not running a match scene, and is not an error here.
static func _config_or_null() -> AudioConfig:
	return References.audio_config


## Whether this slot is the player sitting at this machine.
##
## LOCAL, and so never readable by the simulation: it is a different answer on
## every machine running the same match. False with no session at all, which
## keeps a tool scene from announcing somebody else's refusals.
static func _is_local(player_id: int) -> bool:
	var session: MatchSession = References.match_session
	return session != null && session.is_local_player(player_id)
