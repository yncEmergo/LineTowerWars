class_name CreepStats
extends MobileUnitStats

## Stats for one creep type, covering both what it is and what sending it does.
##
## The send price lives here rather than on the ability, for the same reason a
## tower's price lives on its BuildingStats: one file per unit type, so a value
## can never drift between two places that both claim to own it.

@export_group("Sending")
## Creeps spawned per send. Three for normal creeps, one for a boss.
@export var pack_size: int = 3
## Gold for one send, i.e. for the whole pack rather than per creep.
@export var gold_cost: int = 10
## Permanent income the sender gains per send. The ratio of this to gold_cost
## is what makes early sends compound, see game_rules.md.
@export var income_gain: int = 2
## Population one creep of this type takes up while it is alive. The rules
## count a player's population as their currently alive sent creeps, so an
## ordinary creep is 1 and a boss can be worth more. See game_rules.md.
@export var population: int = 1
## Sends held in reserve. One is spent per send and they regenerate over time,
## which is what stops a single creep type being sent without limit. Special
## creeps get their own, lower, number.
@export var max_stock: int = 32
## Seconds to regenerate one stock.
@export var stock_regen_seconds: float = 3.0
## Whether players start a match with the stock full. Full is the WC3 original:
## the opening burst is part of the game, and the regeneration rate is what
## limits sending after it.
@export var starts_at_max_stock: bool = true

@export_group("Creep")
## Half the creep's width. Must stay under half an internal cell, since the
## rules give creeps a single free internal cell to walk through.
@export var body_radius: float = 0.18
## Attacker creeps can be commanded by their owner inside the enemy area, which
## no other creep type can. Not implemented yet, the flag exists so selection
## already asks the right question.
@export var is_attacker: bool = false
## Flyers are only reachable by towers that can hit air. Nothing flies yet and
## flying creeps will also have to ignore the maze, but the flag exists so an
## attack's ground versus air setting has something real to test against.
@export var is_flying: bool = false
## Gold paid to the player who kills this creep, per creep rather than per
## pack. Bounty is NOT BUILT and its values are TBD per game_rules.md, so this
## stays 0 until somebody balances it - the tooltip already quotes it.
@export var bounty: int = 0
