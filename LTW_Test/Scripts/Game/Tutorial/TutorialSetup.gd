class_name TutorialSetup
extends RefCounted

## The MATCH the tutorial is played in.
##
## **It is a real match and not a diorama**, which is the whole design: two
## lanes, a real economy, real towers, a real opponent and a real send ring. The
## only things that differ are the ones a lesson has to control, and each of
## them is here rather than scattered through the lessons:
##
##   NO INCOME to begin with. The tutorial hands out gold a lesson at a time so
##   a player is never choosing between what they are being taught and something
##   else - and the economy lesson turns income on, which is the first moment it
##   starts behaving like a real game.
##
##   NO OPENING PHASE. Nothing can be sent at the player until a lesson says so
##   anyway, so twenty seconds of the match clock standing still before the
##   first creep unlocks would only be twenty seconds of nothing.
##
##   A SPARRING PARTNER in the other lane rather than an opponent. It builds a
##   short maze so there is something for the player's creeps to walk through,
##   and it never sends anything back. See ai_tutorial.tres.
##
## Everything else is the defaults, deliberately: what is being taught is the
## game, so a player who finishes the tutorial and opens a lobby should
## recognise every number they saw.
##
## Static rather than a resource, because there is exactly one tutorial and its
## shape is not content. What IS content is the lessons - see TutorialScript.

## Which AI difficulty the sparring partner plays.
##
## By NAME rather than by index, and this is the one place that is worth doing:
## an index into AiConfig is a position in a list somebody may reorder, and the
## tutorial would then be played against whatever moved into that slot. The name
## is authored on the profile itself.
const PARTNER_NAME: String = "Sparring Partner"

## What the player is called in their own tutorial. Not their multiplayer name:
## the lessons talk about "you", and a tutorial is not somewhere anybody needs
## to be told who they are.
const PLAYER_NAME: String = "You"


## Builds it. Handed to the loading screen exactly as a skirmish is, so the
## tutorial warms its content and builds its world down the same road every
## other match takes.
static func create(config: GameConfig, ai: AiConfig) -> MatchSetup:
	var setup: MatchSetup = MatchSetup.new()
	setup.mode = MatchSetup.Mode.TUTORIAL
	setup.match_id = "tutorial"
	setup.local_slot = 1
	setup.rng_seed = randi()
	setup.settings = _settings(config)

	setup.players.append(MatchPlayer.create(1, PLAYER_NAME, 0, 0))
	setup.players.append(MatchPlayer.create(
		2, PARTNER_NAME, 0, 1, _partner_difficulty(ai)
	))
	return setup


## The rules the tutorial is played under.
##
## Everything is the default except the three the lessons have to own, and each
## of those has a comment for the same reason: a number changed here silently
## changes what a lesson is teaching.
static func _settings(config: GameConfig) -> MatchSettings:
	var settings: MatchSettings = MatchSettings.defaults(config)
	# Not a rated game, and nothing about it should read as one.
	settings.is_ranked = false
	# Nothing is dealt: the technology lesson takes the player to the Research
	# Center and has them spend the allowance themselves, which is the thing
	# being taught.
	settings.tech_mode = MatchSettings.TechMode.PICK
	# Two lanes, and which one is which is the whole of the send ring lesson.
	# Shuffling them would change nothing and cost the lesson its example.
	settings.random_lanes = false
	# **NO INCOME AND NO OPENING GOLD.** A lesson hands over what it is about to
	# talk about, so the player's first tower is bought with the first lesson's
	# gold rather than from a pile they were given for no reason. The economy
	# lesson turns income on. See TutorialStep.grant_gold.
	settings.starting_gold = 0
	settings.starting_income = 0
	return settings


## Which profile the sparring partner plays, found by name.
##
## Falls back to the FIRST difficulty in the build rather than to none: a
## tutorial whose opponent never appears has an empty lane to send into, which
## is a worse failure than one whose opponent is a little too keen. Loud either
## way, because it means the profile was renamed or dropped.
static func _partner_difficulty(ai: AiConfig) -> int:
	if ai != null:
		for index in range(ai.count()):
			var profile: AiProfile = ai.profile_for(index)
			if profile != null && profile.display_name == PARTNER_NAME:
				return index

	Log.err("The tutorial cannot find its sparring partner profile", PARTNER_NAME)
	return 0
