class_name CreepStats
extends MobileUnitStats

## Stats for one creep type, covering both what it is and what sending it does.
##
## The send price lives here rather than on the ability, for the same reason a
## tower's price lives on its BuildingStats: one file per unit type, so a value
## can never drift between two places that both claim to own it.
##
## Three of the roster's traits are answered HERE rather than by a passive on
## the creep's card, and the line between them is worth stating once. A passive
## MODIFIES an existing rule - skittering changes which creep a tower picks,
## an aura changes a number. These three decide something STRUCTURAL before any
## passive could be asked: how the creep moves at all, whether its prefab
## carries an attack, and how many one press puts on the field. Their card
## entry is a TraitPassive, which carries the text and no mechanics, so there is
## still exactly one place each answer lives.

@export_group("Sending")
## Creeps spawned per send. Three for a normal creep, one for a boss.
@export var pack_size: int = 3
## Anything ELSE the same send spawns, which is the Sheep's Timber Wolf and
## nothing else in the whole roster so far. See CreepPackEntry.
@export var pack_companions: Array[CreepPackEntry] = []
## Gold for one send, i.e. for the whole pack rather than per creep.
@export var gold_cost: int = 10
## Permanent income the sender gains per send. The ratio of this to gold_cost
## is what makes early sends compound, see game_rules.md.
@export var income_gain: int = 2
## Population one creep of this type takes up while it is alive. The rules
## count a player's population as their currently alive sent creeps, so an
## ordinary creep is 1 and a boss can be worth more. See game_rules.md.
@export var population: int = 1
## Seconds into the match before this creep can be sent at all.
##
## Every creep carries its OWN delay and unlocks on its own, one at a time in
## ascending cost order - a tier is a cost bracket and never unlocks as a
## block. unit_data.md 6.1 is the authority on that and 6.2 on the times.
@export var unlock_seconds: float = 0.0
## Sends held in reserve. One is spent per send and they regenerate over time,
## which is what stops a single creep type being sent without limit. Special
## creeps get their own, lower, number.
@export var max_stock: int = 32
## Seconds to regenerate one stock.
@export var stock_regen_seconds: float = 8.0
## Reserve a player has the moment this creep unlocks. Negative means HALF of
## max_stock, which is what the source game gives nearly everything; the
## attacker creeps are the exception and start at exactly 1.
@export var initial_stock: int = -1
## Whether this creep is refused outright once its sender is over the income
## cap, rather than merely paying less for being over it.
##
## One creep in the roster: the Treasure Goblin is nothing BUT income, so a
## Goblin that paid a quarter would be a creep with no purpose left rather than
## a weaker one (unit_data.md 6.5). Refused before any gold moves, so there is
## nothing to refund.
@export var refused_above_income_cap: bool = false

@export_group("Creep")
## Half the creep's width. Must stay under half an internal cell, since the
## rules give creeps a single free internal cell to walk through - so a Boss is
## a bigger MODEL rather than a bigger footprint.
@export var body_radius: float = 0.18
## Gold paid to the player whose maze this creep dies in, per creep rather than
## per pack. See game_rules.md.
@export var bounty: int = 0
## Lives taken from the defender when this creep reaches the end zone. One for
## everything except a Boss, which takes two.
@export var lives_stolen: int = 1

@export_group("Creep Mana")
## The mana pool one of this creep's traits runs on, or 0 for a creep with no
## such trait - which is nearly all of them.
##
## Here rather than on the passive for the reason every other stat is: mana is
## the CREEP's resource and the passive is a shared stateless resource that may
## hold nothing per creep. The passive owns the RULE - what fills the pool and
## what happens at the top - and this owns the pool. See CreepMana.
@export var max_mana: int = 0
## Mana the creep spawns holding. Absolute rather than the share of maximum a
## tower authors, because the source game states these as whole numbers and one
## of them is deliberately part full: Wind Rush starts at 10 of 14, so its
## creep is four points from its first cast rather than fourteen.
@export var starting_mana: int = 0
## Mana this creep gets back per second, for the traits whose pool fills on a
## clock rather than on being hit.
##
## `?` A CHOICE, not a reading. The source game states the ceiling every one of
## these traits fires at and never states how the pool gets there, because in
## Warcraft III it is the unit's ordinary mana regeneration - a number this
## game has no equivalent of. So it is authored per creep here, next to the
## ceiling it has to reach, and the figure a creep carries is chosen from how
## often its trait should fire rather than copied from anywhere.
##
## Zero for every creep whose pool is filled by something else: Chaotic Void
## and Siren's Song fill on damage taken, and Chaos Barrier only ever drains.
@export var mana_regen_per_second: float = 0.0

@export_group("Creep Kind")
## Attacker creeps go after the towers standing in the area rather than walking
## past them, and they are the only creep their owner can command. Their attack
## itself is an ordinary AttackStats on this file, with its target class set to
## buildings. See game_rules.md and unit_data.md 1.5.
@export var is_attacker: bool = false
## Flyers ignore the maze entirely and are only reachable by towers that can
## hit air.
@export var is_flying: bool = false
## How high above the ground a flyer is drawn, in world units. Visual only -
## nothing is measured in three dimensions, so this never changes what can
## reach it. Ignored by anything that does not fly.
@export var fly_height: float = 1.2


## Reserve this creep starts a match with, resolved from initial_stock.
##
## Here rather than in CreepStock so the "negative means half" convention has
## one home and the tooltip could quote the real number if it ever wanted to.
func starting_stock() -> int:
	if initial_stock >= 0:
		return mini(initial_stock, maxi(0, max_stock))
	@warning_ignore("integer_division")
	var half: int = maxi(0, max_stock) / 2
	return half


## Everything one send puts on the field, as [CreepStats, count] pairs, with
## this creep itself first.
##
## Built here rather than in the send building, so "what does a send spawn" is
## answered by the creep's own file and a tooltip could ask the same question
## the spawn does.
func pack_contents() -> Array:
	var contents: Array = [[self, maxi(1, pack_size)]]
	for entry: CreepPackEntry in pack_companions:
		if entry != null && entry.creep_stats != null && entry.count > 0:
			contents.append([entry.creep_stats, entry.count])
	return contents


## Creeps one send puts on the field in total, which is what the population it
## costs is counted from.
func pack_creep_count() -> int:
	var total: int = 0
	for entry: Array in pack_contents():
		total += int(entry[1])
	return total


## Population one whole send costs, since population is charged per CREEP and
## never per send. A companion is charged at its own rate, not at this one's.
func pack_population() -> int:
	var total: int = 0
	for entry: Array in pack_contents():
		total += (entry[0] as CreepStats).population * int(entry[1])
	return total


## Unlock time as shown in the UI, e.g. "3:30".
func unlock_text() -> String:
	var whole: int = maxi(0, int(unlock_seconds))
	@warning_ignore("integer_division")
	var minutes: int = whole / 60
	return "%d:%02d" % [minutes, whole % 60]


## The companions are walked as well as this creep, so a Timber Wolf whose
## prefab has been moved is reported at boot rather than the first time
## somebody sends a Sheep.
##
## validate() rather than _validate_paths(), because a companion is a whole
## unit type with a card of its own rather than another path on this one. The
## seen dictionary is threaded through and checked here too, so a pack that
## ever pointed back at itself is one lookup rather than an infinite descent.
func validate(seen: Dictionary) -> bool:
	var first_visit: bool = !seen.has(self)
	var complete: bool = super(seen)
	if !first_visit:
		return complete

	for entry: CreepPackEntry in pack_companions:
		if entry == null || entry.creep_stats == null:
			Log.err("Creep pack companion names no creep", display_name)
			complete = false
		elif !entry.creep_stats.validate(seen):
			complete = false
	return complete
