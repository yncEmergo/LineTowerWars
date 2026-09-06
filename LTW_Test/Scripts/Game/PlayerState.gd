class_name PlayerState
extends RefCounted

## Everything the game tracks per player: gold, income, lives, what they have
## built and where they finished.
##
## Deliberately not on References. References holds things there is exactly
## one of, and per-player state is the opposite of that - a static handle to
## "the player" would quietly break the moment a second one exists.

signal gold_changed(gold: int)
signal income_changed(income: int)
signal lives_changed(lives: int)
## Anything the stats panel draws that is not gold: value and placement.
signal standing_changed()

var player_id: int = 1
var gold: int = 0
## Gold paid out on every income tick. Raised permanently by sending creeps,
## which is what makes early sends compound. See game_rules.md.
var income: int = 0
## Lives left. Starts at max(25, 200 / players) rounded to the nearest 5, so
## fewer players means more lives each - GameConfig.starting_lives() is the
## authority on the number. Reaching zero is elimination.
var lives: int = 0
## Gold currently standing on the field: every building this player owns, at
## what it cost. Later it also carries upgrades and researched technology, which
## is why it is a running total rather than "towers times price".
##
## Computed by the authority and handed down, like everything else - a client
## adding up its own copy would quote a number the server never agreed.
var value: int = 0
## Where this player finished, or 0 while they are still in it. 1 is the winner,
## and the first player out of a five player game takes 5.
var placement: int = 0
## Developer cheat: every creep's start delay counts as already served, so the
## whole send card is available from the first second. Per player rather than
## per match for the same reason the gold cheat is - a cheat is granted to
## whoever pressed it - and handed down by the server like everything else, so
## a client's card greys and counts down the same way the server decides.
var creeps_unlocked: bool = false
## What this player has researched, and what they can still take back. Here
## rather than in a manager of its own for exactly the reason gold is here: it
## is per player, it is handed down by the server, and a static handle to "the
## player's technology" would break the moment there were two players.
##
## The RULES that decide whether any of it may change are TechManager's. This
## only holds the record.
var tech: PlayerTech = PlayerTech.new()

var _config: GameConfig:
	get:
		return References.game_config


func setup(id: int, starting_gold: int, starting_income: int, starting_lives: int) -> void:
	player_id = id
	gold = _capped(starting_gold)
	income = starting_income
	lives = starting_lives
	creeps_unlocked = false
	gold_changed.emit(gold)
	income_changed.emit(income)
	lives_changed.emit(lives)


func can_afford(amount: int) -> bool:
	return gold >= amount


## Spends gold if there is enough, and reports whether it went through, so
## callers cannot forget to check.
func spend(amount: int) -> bool:
	if amount <= 0:
		return true
	if !can_afford(amount):
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true


## Pays gold in, up to the ceiling. Anything over it is LOST rather than
## banked, which is what the cap means: a player sitting at the top earns
## nothing more until they spend.
##
## Silent about it on purpose - it fires on every income tick and every bounty,
## and a player who has reached the ceiling has not made a mistake worth
## telling them about.
func gain(amount: int) -> void:
	if amount <= 0:
		return
	var wanted: int = _capped(gold + amount)
	if wanted == gold:
		return
	gold = wanted
	gold_changed.emit(gold)


## Raises income permanently. Takes effect from the next tick onwards, never
## retroactively, so sending just before a tick is not worth more than sending
## just after one.
func add_income(amount: int) -> void:
	if amount <= 0:
		return
	income += amount
	income_changed.emit(income)


## Pays one income tick.
func pay_income() -> void:
	gain(income)


## Gold, income, lives and the creep cheat handed down by the server (3.2),
## which on a client is the only way any of them change: nothing here is earned
## locally.
##
## Deliberately not spend()/gain()/steal(): those enforce rules - you cannot
## spend what you do not have, a life has to come from somebody - and a value
## that has already been through those rules on the server must not be put
## through them a second time here. This just says what the numbers are.
func set_replicated(
	new_gold: int, new_income: int, new_lives: int, new_value: int, new_placement: int,
	new_creeps_unlocked: bool
) -> void:
	creeps_unlocked = new_creeps_unlocked
	# Capped here as well, though the authority has already capped it: this is
	# the one number a client takes on trust, and a build whose config says
	# something different should not be able to draw a figure its own rules
	# forbid.
	var capped_gold: int = _capped(new_gold)
	if gold != capped_gold:
		gold = capped_gold
		gold_changed.emit(gold)
	if income != new_income:
		income = new_income
		income_changed.emit(income)
	if lives != new_lives:
		lives = new_lives
		lives_changed.emit(lives)
	if value != new_value || placement != new_placement:
		value = new_value
		placement = new_placement
		standing_changed.emit()


# --- Lives --------------------------------------------------------------

## A player with no lives left is out (game_rules.md). The ring skips them,
## their maze is erased and they are given a placement; see PlayerManager.
func is_eliminated() -> bool:
	return lives <= 0


## The authority's own figures, set rather than earned. Emits only on a change,
## because this runs every tick.
func set_standing(new_value: int, new_placement: int) -> void:
	if value == new_value && placement == new_placement:
		return
	value = new_value
	placement = new_placement
	standing_changed.emit()


## Takes lives off `victim` and adds them to this player, which is what a leak
## does: lives are STOLEN rather than merely lost, so the pool never shrinks.
##
## One method rather than a lose() and a gain() at two call sites, because the
## two halves must never happen separately - half a steal would quietly destroy
## or invent a life. Answers HOW MANY actually moved, and 0 for a steal that
## did not go through - so a leak into a player who is already out cannot pay
## out twice, and the message on screen quotes the number that really changed
## hands rather than the number that was asked for.
##
## A Boss takes two rather than one, and the count is CAPPED at what the victim
## actually has: a player on their last life loses that one and no more, so a
## Boss can never invent a life by taking more than was there. Which creep
## takes how many is CreepStats.lives_stolen.
func steal_life_from(victim: PlayerState, count: int = 1) -> int:
	if victim == null || victim == self || victim.is_eliminated():
		return 0

	var stolen: int = clampi(count, 1, victim.lives)
	victim.lives -= stolen
	lives += stolen
	victim.lives_changed.emit(victim.lives)
	lives_changed.emit(lives)
	return stolen


## An amount held down to the ceiling GameConfig names, or left alone when it
## names none. Never below zero: gold is spent through spend(), which refuses
## what cannot be afforded, so a negative here would be a bug elsewhere.
func _capped(amount: int) -> int:
	var config: GameConfig = _config
	if config == null || config.gold_cap <= 0:
		return maxi(0, amount)
	return clampi(amount, 0, config.gold_cap)
