class_name MatchSettings
extends Resource

## The rules the HOST chose for one match: what everybody starts with, which
## creeps are in it, how the opening technology is handed out, and how players
## are named on screen.
##
## Chosen in the LOBBY rather than after the match has loaded. The source game
## asks these questions once everybody is in the world because Warcraft III
## gave it nowhere else to ask them; this build has a lobby, so the answer is
## known before a single area is placed and nothing has to be rebuilt when it
## arrives.
##
## Flat and made only of primitives, for the same reason MatchPlayer is: it
## travels on a LobbyInfo while the lobby is open and on a MatchSetup when the
## match begins, and both go over the wire as Dictionaries. Anything added here
## must stay serialisable - see multiplayer.md 7.
##
## **This is not a second GameConfig.** GameConfig still owns every one of these
## numbers as the DEFAULT, and `defaults()` is the only place the two meet: a
## fresh lobby copies them out and the host edits the copy. So changing the
## .tres still changes what every new match starts from, and a match that was
## started carries what was actually agreed rather than what the file said at
## the time.
##
## Nothing here is per player. What one player owns lives on their PlayerState;
## this is what the whole match agreed to.

## Which of the creep roster this match is played with.
##
## Two independent switches written as one exclusive choice, because that is
## how it is asked and answered - a lobby row with four entries rather than two
## checkboxes a player has to combine in their head.
enum CreepSet {
	## The whole roster.
	ALL,
	## No flyers. Towers that can only hit air have nothing to shoot.
	NO_AIR,
	## No attacker creeps, so nothing ever goes after a tower.
	NO_ATTACKERS,
	NO_AIR_OR_ATTACKERS,
}

## How a player's OPENING technology is decided - the free ones every player
## gets before anything is paid for (GameConfig.free_technologies).
##
## Named for what it decides rather than for the one option that is random,
## because all three answer the same question and only one of them rolls
## anything.
enum TechMode {
	## The player spends their free technologies themselves, in the Research
	## Center, whenever they like. What the game does today.
	PICK,
	## One Ultimate is rolled for the whole match and handed to everybody, so
	## every player opens on the same tower.
	RANDOM,
	## Three Ultimates are rolled for the whole match and every player picks
	## one of the three. The match does not start until they all have.
	DRAFT,
}

## Cosmetic rules that change nothing about the simulation.
enum Modifier {
	NONE,
	## Players are named by their COLOUR rather than by who they are. Nothing
	## else changes: the lobby still shows real names, because the anonymity is
	## a rule of the match rather than of the room.
	ANONYMOUS,
}

## Written out rather than derived from the enum names, so what a lobby row
## reads is not hostage to how an identifier is spelled.
const CREEP_SET_NAMES: Array[String] = [
	"All Creeps", "No Air", "No Attackers", "No Air + No Attackers",
]
const TECH_MODE_NAMES: Array[String] = ["Pick Tech", "Random", "Draft"]
const MODIFIER_NAMES: Array[String] = ["None", "Anonymous"]

## lives_per_player meaning "work it out from the player count", which is the
## rule in game_rules.md and the default. A real number is the host having
## overridden it, and then it stays put however many players turn up.
const AUTO_LIVES: int = 0
## Stands in for GameConfig.starting_lives when there is no config to ask,
## which is a bare test scene rather than anything a match runs in.
const FALLBACK_LIVES: int = 25
## How many Ultimates a DRAFT offers. Three is the user's call, and it is a
## rule rather than a tuning value: it is the number of buttons the draft
## screen draws.
const DRAFT_OPTIONS: int = 3

@export_group("Resources")
## Lives each player starts with, or AUTO_LIVES to follow the player count.
@export var lives_per_player: int = AUTO_LIVES
@export var starting_gold: int = 0
## Free technologies - "research points" - every player opens with.
@export var free_technologies: int = 0
@export var starting_income: int = 0
## Seconds between income payouts.
@export var income_interval: float = 0.0

@export_group("Gameplay")
## A ranked match is played on the DEFAULTS and nothing else: every setting
## above and below is forced back to what GameConfig says and locked, so two
## ranked results are always comparable.
##
## The one exception is the technology mode, which the host still chooses. That
## is the user's call and it is deliberate: how the opening is handed out
## changes what the match is ABOUT rather than how generous it is, and all
## three answers cost the same free technologies.
@export var is_ranked: bool = true
@export var creep_set: CreepSet = CreepSet.ALL
## Whether the roster is shuffled into the lanes on start, so who sends into
## whom is not the order people happened to join in.
@export var random_lanes: bool = true
@export var tech_mode: TechMode = TechMode.PICK
@export var modifier: Modifier = Modifier.NONE


## What a brand new lobby offers: every number as GameConfig has it, and the
## gameplay answers as authored above.
##
## The ONE place MatchSettings and GameConfig meet. Everything downstream reads
## the settings, so a value that is not copied here is a value the lobby cannot
## change - which is the honest way to add one later.
static func defaults(config: GameConfig) -> MatchSettings:
	var settings: MatchSettings = MatchSettings.new()
	settings.reset_to_defaults(config)
	return settings


static func from_dict(data: Dictionary) -> MatchSettings:
	var settings: MatchSettings = MatchSettings.new()
	settings.lives_per_player = int(data.get("lives", AUTO_LIVES))
	settings.starting_gold = int(data.get("gold", 0))
	settings.free_technologies = int(data.get("free_tech", 0))
	settings.starting_income = int(data.get("income", 0))
	settings.income_interval = float(data.get("interval", 0.0))
	settings.is_ranked = bool(data.get("ranked", true))
	settings.creep_set = int(data.get("creeps", CreepSet.ALL)) as CreepSet
	settings.random_lanes = bool(data.get("lanes", true))
	settings.tech_mode = int(data.get("tech", TechMode.PICK)) as TechMode
	settings.modifier = int(data.get("mod", Modifier.NONE)) as Modifier
	return settings


func to_dict() -> Dictionary:
	return {
		"lives": lives_per_player,
		"gold": starting_gold,
		"free_tech": free_technologies,
		"income": starting_income,
		"interval": income_interval,
		"ranked": is_ranked,
		"creeps": creep_set,
		"lanes": random_lanes,
		"tech": tech_mode,
		"mod": modifier,
	}


## An independent copy. Taken whenever settings cross from one owner to
## another - a lobby into the match it becomes - so that editing the lobby's
## copy afterwards cannot reach into a match that is already running, exactly
## as the player list is copied rather than handed over.
func duplicate_settings() -> MatchSettings:
	return MatchSettings.from_dict(to_dict())


## Puts every number back to what GameConfig says and every choice back to its
## authored answer. What a fresh lobby starts from, and what switching Ranked
## back on does.
##
## The technology mode is deliberately NOT reset by the ranked lock, so it is
## not reset here either - the caller decides, and only one caller wants it
## kept. See sanitise().
func reset_to_defaults(config: GameConfig) -> void:
	lives_per_player = AUTO_LIVES
	is_ranked = true
	creep_set = CreepSet.ALL
	random_lanes = true
	modifier = Modifier.NONE
	if config == null:
		Log.err("MatchSettings has no GameConfig to take its defaults from")
		return
	starting_gold = config.starting_gold
	free_technologies = config.free_technologies
	starting_income = config.starting_income
	income_interval = config.income_interval


## Lives one player starts this match with.
##
## AUTO follows the rule in game_rules.md - roughly a fixed pool split between
## however many players there are - which is why the lobby's reading of it
## MOVES as people come and go. A host who typed a number instead keeps that
## number whoever turns up.
func lives_for(player_count: int, config: GameConfig) -> int:
	if lives_per_player > AUTO_LIVES:
		return lives_per_player
	if config == null:
		return FALLBACK_LIVES
	return config.starting_lives(player_count)


## Whether lives are still following the player count rather than a number the
## host typed. What the lobby row says "(auto)" for.
func has_auto_lives() -> bool:
	return lives_per_player <= AUTO_LIVES


## Whether every setting but the technology mode is forced to its default,
## which is what a ranked match is.
func is_locked() -> bool:
	return is_ranked


## Whether this match contains a creep at all.
##
## Asked of the SEND CARD rather than of a creep about to spawn: a creep the
## match does not contain is not on anybody's card, so nothing can order one
## and the server refuses the order for the same reason it refuses an ability
## that is not on a unit. See SendBuilding.current_abilities.
func allows_creep(stats: CreepStats) -> bool:
	if stats == null:
		return false
	if stats.is_flying && !_allows_air():
		return false
	if stats.is_attacker && !_allows_attackers():
		return false
	return true


## Makes a settings block a client stated safe to run a match on. Run on the
## SERVER, on arrival, and the result is what every other client is told - the
## same shape LobbyIdentity.sanitise has, and for the same reason: the sender
## is not trusted about anything.
##
## Two jobs. The RANKED LOCK is the rule, and it is enforced here rather than
## only greyed out on the host's screen: a ranked match is played on the
## defaults, so anything else that arrived with the flag set is thrown away.
## The CLAMPS are the ordinary distrust - an unbounded starting gold or a zero
## income interval is a match nobody can play.
func sanitise(config: GameConfig, limits: MenuConfig) -> void:
	if is_ranked:
		# The technology mode survives the lock, alone. Everything else is put
		# back, which is what makes two ranked matches comparable.
		var mode: TechMode = tech_mode
		reset_to_defaults(config)
		tech_mode = mode
		return

	lives_per_player = maxi(AUTO_LIVES, lives_per_player)
	starting_gold = maxi(0, starting_gold)
	free_technologies = maxi(0, free_technologies)
	starting_income = maxi(0, starting_income)
	income_interval = maxf(_min_interval(limits), income_interval)
	if limits == null:
		return
	lives_per_player = mini(limits.max_lives_per_player, lives_per_player)
	starting_gold = mini(limits.max_starting_gold, starting_gold)
	free_technologies = mini(limits.max_free_technologies, free_technologies)
	starting_income = mini(limits.max_starting_income, starting_income)
	income_interval = minf(limits.max_income_interval, income_interval)


## For logs, and for the one line the lobby room prints when the host changes
## something. Short on purpose: the point of reading it is usually to compare
## it with the same line on the other machine.
func describe() -> String:
	return "%s, %s, %s, %s%s" % [
		"ranked" if is_ranked else "unranked",
		creep_set_name(),
		tech_mode_name(),
		modifier_name(),
		", random lanes" if random_lanes else "",
	]


func creep_set_name() -> String:
	return _name_from(CREEP_SET_NAMES, int(creep_set))


func tech_mode_name() -> String:
	return _name_from(TECH_MODE_NAMES, int(tech_mode))


func modifier_name() -> String:
	return _name_from(MODIFIER_NAMES, int(modifier))


func _allows_air() -> bool:
	return creep_set == CreepSet.ALL || creep_set == CreepSet.NO_ATTACKERS


func _allows_attackers() -> bool:
	return creep_set == CreepSet.ALL || creep_set == CreepSet.NO_AIR


func _min_interval(limits: MenuConfig) -> float:
	if limits == null:
		return 1.0
	return maxf(0.1, limits.min_income_interval)


func _name_from(names: Array[String], index: int) -> String:
	if index < 0 || index >= names.size():
		return "Unknown"
	return names[index]
