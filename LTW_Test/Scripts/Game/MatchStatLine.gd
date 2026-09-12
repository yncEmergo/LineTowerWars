class_name MatchStatLine
extends Resource

## One player's record of ONE match: what they earned, what they spent, what
## they sent, what they killed and where they finished.
##
## A Resource rather than a Dictionary because it is read twice in two places -
## the end panel over the match, and the summary screen after it - and a typo in
## a string key is a blank number rather than a parse error. It also has to
## survive the scene change between those two readings, which a Resource does
## without being written anywhere.
##
## **It holds NOTHING the simulation reads.** Nothing here is checksummed,
## nothing here changes a rule, and a machine that recorded none of it plays
## exactly the same match. That is what makes it safe for `MatchStats` to count
## from wherever the event happens to be raised.
##
## Everything is a running total EXCEPT the four standings at the top, which are
## read off PlayerState when the summary is taken.

@export_group("Identity")
@export var slot: int = 0
@export var display_name: String = ""
## Which colour in PresentationConfig's palette this player owned, so the
## summary draws them in the colour they played in.
@export var color_index: int = 0
## 1 for the winner, counting up to the first player out. 0 for a match that was
## abandoned before it was decided.
@export var placement: int = 0
@export var is_local: bool = false

@export_group("Standing")
@export var lives_left: int = 0
@export var income: int = 0
@export var peak_income: int = 0
@export var value: int = 0
@export var peak_value: int = 0

@export_group("Lives")
## Lives taken off other players by this player's creeps.
@export var lives_stolen: int = 0
## Lives taken off this player by everybody else's.
@export var lives_lost: int = 0

@export_group("Gold")
@export var gold_from_income: int = 0
@export var gold_from_bounty: int = 0
@export var gold_on_towers: int = 0
@export var gold_on_sends: int = 0
@export var gold_on_tech: int = 0

@export_group("Offence")
## Presses of a send button that went through. One press is one pack.
@export var sends: int = 0
## Individual creeps those presses put on the field, which is more.
@export var creeps_sent: int = 0

@export_group("Defence")
## Creeps that died in THIS player's maze, whoever sent them.
@export var creeps_killed: int = 0
@export var towers_built: int = 0
@export var towers_sold: int = 0
## Towers an attacker creep brought down.
@export var towers_lost: int = 0

@export_group("Technology")
@export var technologies: int = 0
## Every Ultimate tower this player had all four technologies of at the end, by
## name. Usually one - the opening is exactly one Ultimate's worth of free
## research - and more only in a match that ran long enough to buy another.
@export var ultimates: PackedStringArray = PackedStringArray()


## Everything this player put into the field and the send ring together, which
## is the one figure that says how big their match was.
func gold_spent() -> int:
	return gold_on_towers + gold_on_sends + gold_on_tech


func gold_earned() -> int:
	return gold_from_income + gold_from_bounty


## How they finished, written the way a person says it. Empty for a match that
## never decided, which is what leaving early gives.
func placement_text() -> String:
	if placement <= 0:
		return "-"
	return "%d%s" % [placement, StringUtil.ordinal_suffix(placement)]
