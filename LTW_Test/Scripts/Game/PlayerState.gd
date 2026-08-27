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
## What this player has researched, and what they can still take back. Here
## rather than in a manager of its own for exactly the reason gold is here: it
## is per player, it is handed down by the server, and a static handle to "the
## player's technology" would break the moment there were two players.
##
## The RULES that decide whether any of it may change are TechManager's. This
## only holds the record.
var tech: PlayerTech = PlayerTech.new()


func setup(id: int, starting_gold: int, starting_income: int, starting_lives: int) -> void:
	player_id = id
	gold = starting_gold
	income = starting_income
	lives = starting_lives
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


func gain(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
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


## Gold, income and lives handed down by the server (3.2), which on a client is
## the only way any of them change: nothing here is earned locally.
##
## Deliberately not spend()/gain()/steal(): those enforce rules - you cannot
## spend what you do not have, a life has to come from somebody - and a value
## that has already been through those rules on the server must not be put
## through them a second time here. This just says what the numbers are.
func set_replicated(
	new_gold: int, new_income: int, new_lives: int, new_value: int, new_placement: int
) -> void:
	if gold != new_gold:
		gold = new_gold
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
## or invent a life. Reports whether it went through, so a leak into a player
## who is already out cannot pay out twice.
##
## A Boss takes two rather than one, and the count is CAPPED at what the victim
## actually has: a player on their last life loses that one and no more, so a
## Boss can never invent a life by taking more than was there. Which creep
## takes how many is CreepStats.lives_stolen.
func steal_life_from(victim: PlayerState, count: int = 1) -> bool:
	if victim == null || victim == self || victim.is_eliminated():
		return false

	var stolen: int = clampi(count, 1, victim.lives)
	victim.lives -= stolen
	lives += stolen
	victim.lives_changed.emit(victim.lives)
	lives_changed.emit(lives)
	return true
