class_name AiDirector
extends Node

## Creates one brain per AI seat, and nothing else.
##
## A node in the match scene beside PlayerManager, reached through References.
## Not an autoload: it is born with a match and dies with it, exactly as the
## session and the economy are, and it receives no `@rpc` of its own.
##
## It is deliberately thin. Everything about HOW an opponent plays is
## AiPlayer's and everything about how WELL is AiProfile's; what is here is only
## "which slots are not people, and which difficulty is each of them". Splitting
## it that way is what lets a match hold four opponents at four difficulties
## without anything in the brain knowing there is more than one.
##
## **A match with no AI in it costs nothing.** The setup says which slots are
## profiles, and a multiplayer setup says none - so this node sits in both match
## scenes, makes no children, and its process is switched off.

var _brains: Array[AiPlayer] = []


func _ready() -> void:
	# Nothing to do until the world exists. Main creates the areas, the builders
	# and the player states in its own _ready, which runs after every child's.
	set_physics_process(false)


## Stands up one brain per AI slot. Called by Main once the world is built.
##
## **After the builders, necessarily**: a brain measures its maze against the
## area's grid and gives its first order to a builder, and neither exists
## earlier.
func begin(setup: MatchSetup) -> void:
	_clear()
	if setup == null || !setup.has_ai():
		return

	# An AI orders units into the world, which is simulation. A machine that
	# only draws what it is told must not run one - see MatchSession 3.4.
	if !MatchSession.is_authority():
		Log.info("AI seats in this match are run elsewhere", setup.ai_slots())
		return

	var config: AiConfig = References.ai_config
	if config == null:
		Log.err("AiDirector found no AiConfig on References, no opponent can play")
		return
	if !config.validate():
		Log.err("AI difficulties are not usable, see the errors above")

	for slot: int in setup.ai_slots():
		_create_brain(slot, setup, config)

	Log.info("AI opponents ready", {"count": _brains.size()})


## How many computer opponents are playing, for a log line or a test.
func count() -> int:
	return _brains.size()


## The brain playing one slot, or null for a slot a person plays.
func brain_for(slot: int) -> AiPlayer:
	for brain in _brains:
		if brain != null && is_instance_valid(brain) && brain.slot() == slot:
			return brain
	return null


func _create_brain(slot: int, setup: MatchSetup, config: AiConfig) -> void:
	var player: MatchPlayer = setup.player_for(slot)
	if player == null:
		return

	var profile: AiProfile = config.profile_for(player.ai_difficulty)
	if profile == null:
		# A setup naming a difficulty this build does not contain, which is what
		# a saved or forwarded setup from another build looks like. Loud, and
		# then played at whatever this build considers ordinary rather than left
		# as a seat that never does anything.
		Log.err("An AI seat names a difficulty this build does not have", {
			"slot": slot, "difficulty": player.ai_difficulty,
		})
		profile = config.profile_for(config.default_index())
	if profile == null:
		return

	var brain: AiPlayer = AiPlayer.new()
	add_child(brain)
	brain.begin(slot, profile)
	_brains.append(brain)


func _clear() -> void:
	for brain in _brains:
		if brain != null && is_instance_valid(brain):
			brain.queue_free()
	_brains.clear()
