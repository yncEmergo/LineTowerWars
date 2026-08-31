class_name TowerResource
extends RefCounted

## The SECOND RESOURCE a tower runs on, as everything that draws one reads it.
##
## game_rules.md: a tower with one says so in a bar under its health bar and in
## a line under its portrait, and what it means is "the thing besides health
## that decides what this tower is worth right now". Mana is the usual answer
## and it is not the only one - the Alchemist line's whole ability is a count of
## what it has devoured, and that count is what its bar should be reading.
##
## So both arrive here in one shape. A panel and a worldspace bar ask
## Building.secondary_resource() once instead of asking about mana and then
## about everything else that might have taken its place, and the rule that the
## bar disappears at FULL is answered in one place for both.
##
## Carries its own COLOURS, because the point of a second kind is that it must
## not read as mana at a glance. Placeholder values, like every other colour in
## the game so far.

## Mana: the blue the panel and the worldspace bar have always drawn.
const MANA_FILL: Color = Color(0.35, 0.58, 0.98, 1.0)
const MANA_TEXT: Color = Color(0.42, 0.68, 1.0, 1.0)
const MANA_EMPTY: Color = Color(0.07, 0.10, 0.22, 1.0)

## A COUNTED resource - stacks a passive has banked rather than a pool it
## spends. Violet on purpose: away from the mana blue below it, away from the
## health green above it, and away from the amber a countdown uses.
const COUNT_FILL: Color = Color(0.72, 0.38, 0.90, 1.0)
const COUNT_TEXT: Color = Color(0.82, 0.58, 0.98, 1.0)
const COUNT_EMPTY: Color = Color(0.16, 0.07, 0.20, 1.0)

## What the tower holds and the most it can hold. Whole numbers, because every
## second resource in the game is counted rather than measured.
var current: int = 0
var maximum: int = 0
var fill_color: Color = MANA_FILL
var text_color: Color = MANA_TEXT
var empty_color: Color = MANA_EMPTY


## A tower's mana.
static func mana(held: int, ceiling: int) -> TowerResource:
	return _make(held, ceiling, MANA_FILL, MANA_TEXT, MANA_EMPTY)


## A count a passive has banked, e.g. the kills an Alchemist has devoured.
static func counted(held: int, ceiling: int) -> TowerResource:
	return _make(held, ceiling, COUNT_FILL, COUNT_TEXT, COUNT_EMPTY)


static func _make(held: int, ceiling: int, fill: Color, text: Color,
		empty: Color) -> TowerResource:
	var resource: TowerResource = TowerResource.new()
	resource.maximum = maxi(0, ceiling)
	resource.current = clampi(held, 0, resource.maximum)
	resource.fill_color = fill
	resource.text_color = text
	resource.empty_color = empty
	return resource


## How full it is, 0 to 1. 1 for a resource with no ceiling at all, so a caller
## that only asks this never divides by zero and never draws a bar for nothing.
func ratio() -> float:
	if maximum <= 0:
		return 1.0
	return clampf(float(current) / float(maximum), 0.0, 1.0)


## Whether it is at its ceiling, which is what the worldspace bar hides on.
## Compared as whole numbers rather than against the ratio, so "full" is the
## same question the simulation asks when it decides a tower may fire.
func is_full() -> bool:
	return maximum > 0 && current >= maximum


## The number under the bar, "40 / 125".
func text() -> String:
	return "%d / %d" % [current, maximum]
