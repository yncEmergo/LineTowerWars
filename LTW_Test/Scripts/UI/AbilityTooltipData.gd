class_name AbilityTooltipData
extends RefCounted

## Everything the hover tooltip on a command slot says about one ability.
##
## The ability fills this in, AbilityTooltip draws it. So an ability never has
## to know about colours or line order, and the tooltip never has to know what
## kind of ability it is describing: a send fills the price, the income, the
## creep's stats and its passives, while Move fills a title and stops there.
##
## Every optional number reads -1 for "this ability has none", so a real zero
## stays tellable from an absent value.

## Name on the first line. The creep's or the tower's own name where the
## ability produces one, so the card can never quote a name it does not spawn.
var title: String = ""
## Hotkey letter shown after the title, empty when it has none.
var hotkey: String = ""
## Gold for one use. For a send that is the price of the whole pack.
var gold_cost: int = -1
## Population one creep takes up while it is alive.
var population: int = -1
## Permanent income gained per use.
var income_gain: int = -1
## Free text under the header, for abilities with no numbers to show.
var description: String = ""
## Label and value per line, e.g. ["Health", "60"].
var stats: Array[PackedStringArray] = []
## Name and text of each passive, e.g. ["Fast Producing", "Replenishes ..."].
var specials: Array[PackedStringArray] = []


## One stat line, e.g. add_stat("Health", "60").
func add_stat(label: String, value: String) -> void:
	stats.append(PackedStringArray([label, value]))


## One passive block: what it is called and what it does.
func add_special(special_name: String, text: String) -> void:
	specials.append(PackedStringArray([special_name, text]))
