class_name TechDefinition
extends Resource

## One button in the Research Center: a technology a player can buy.
##
## Ten elements sell three technologies each (unit_data.md 2.1) - a BASIC that
## unlocks the element at all, and two PATH technologies that each unlock one
## of that element's two tower branches. That is the whole of what a technology
## is: it is bought once, it is owned for the rest of the match, and the towers
## that need it ask whether it is owned.
##
## A resource per technology rather than a table in a script, for the same
## reason an ability is one: the name, the description, the icon and the grid
## square are content, and content is authored rather than compiled.
##
## Deliberately NOT a UnitAbility. An ability is an entry on a UNIT's command
## card and runs on a unit; a technology is bought by a PLAYER with no unit
## involved at all, so it carries no targeting, no charges and no submenu. What
## the two do share is the shape: an authored id that a command names it by, a
## grid square the hotkey is read off, and a tooltip built from its own values.

## The ten elements, in the alphabetical order unit_data.md 2.1 lists them.
## The ORDER here is not the order the Research Center draws them in - that is
## the `slot` each technology authors - so a new element could only ever be
## appended, never inserted.
enum Element {
	ARCANE,
	EARTH,
	FIRE,
	HOLY,
	ICE,
	LIGHTNING,
	PRIMAL,
	UNHOLY,
	VOID,
	WATER,
}

## Which of an element's three technologies this is.
enum Kind {
	## Unlocks the element itself. Required before either of its paths.
	BASIC,
	## Unlocks path 1 of the element: its Lesser and Greater towers.
	PATH_1,
	## Unlocks path 2 of the element.
	PATH_2,
}

## Written out rather than derived from the enum names, so the display text is
## not hostage to how an identifier is spelled.
const ELEMENT_NAMES: Array[String] = [
	"Arcane", "Earth", "Fire", "Holy", "Ice", "Lightning",
	"Primal", "Unholy", "Void", "Water",
]

## The hue each element owns, in the same order as the enum above.
##
## PLACEHOLDER, and the one kind of colour CLAUDE.md lets a script hold: it
## stands in for the icon this technology will carry once there is art, so that
## thirty squares are not thirty identical grey boxes. Approximated from the
## source game's own icons.
##
## What is NOT placeholder is that an element HAS a hue and that it is the same
## one everywhere - game_rules.md says so under Presentation, and says why the
## Basic tower roster is forbidden from spending any of them. When real icons
## and elemental towers arrive they take these over rather than replacing them
## with a second set.
##
## Per ELEMENT rather than per technology, so an element's three squares cannot
## drift apart - which is exactly what authoring the colour into thirty .tres
## files would eventually let them do.
const ELEMENT_COLORS: Array[Color] = [
	Color(0.38, 0.29, 0.64),
	Color(0.55, 0.38, 0.20),
	Color(0.70, 0.29, 0.13),
	Color(0.74, 0.61, 0.21),
	Color(0.34, 0.63, 0.79),
	Color(0.60, 0.65, 0.74),
	Color(0.66, 0.20, 0.20),
	Color(0.30, 0.56, 0.24),
	Color(0.47, 0.24, 0.56),
	Color(0.17, 0.39, 0.68),
]

## Given to slot to mean "nowhere authored yet", which the registry reports.
const NO_SLOT: int = -1

@export_group("Identity")
## The number a network command names this technology by. Its own namespace,
## separate from ability_id and unit_type_id, and unique and permanent within
## it. 0 means nobody has assigned one, which TechRegistry reports at boot.
##
## The number itself carries no meaning: ids were handed out in creation order
## and any grouping in them is an accident. Nothing reads one.
@export var tech_id: int = 0
@export var element: Element = Element.ARCANE
@export var kind: Kind = Kind.BASIC
## Full name, e.g. "Fire Technology (1): Moonbeam" (unit_data.md 2.1).
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D

@export_group("Research grid")
## Which square of the Research Center grid this claims, counting from 0 at the
## top left and running left to right, then down.
##
## The same arrangement the command card uses: the square is the whole of the
## hotkey question, so a technology names where it sits and never which key it
## answers to. ControlsConfig turns the square into a letter, which is what
## keeps the keys stable when the grid is relaid out.
@export var slot: int = NO_SLOT

@export_group("Ultimate")
## The Ultimate tower this path leads to, e.g. "Ultimate Moonbeam". Empty on
## a Basic technology, which leads to no Ultimate of its own.
@export var ultimate_name: String = ""
## The PATH technology of another element that this path's Ultimate also
## requires (unit_data.md 2.3). Together with the two Basic technologies those
## two paths imply, that is the full four-technology requirement of one
## Ultimate tower.
##
## Named by tech_id rather than held as a resource, and that is forced: the
## twenty cross requirements form a single closed cycle, so a chain of
## ext_resources around it would be a reference cycle and would not load. An id
## costs nothing until something resolves it, exactly as a scene path does.
@export var ultimate_cross_tech_id: int = 0


## Whether this unlocks a tower path, as opposed to the element itself.
func is_path() -> bool:
	return kind != Kind.BASIC


## 1 or 2 for a path technology, 0 for a Basic one. What unit_data.md writes in
## the brackets of "Fire Technology (1)".
func path_number() -> int:
	match kind:
		Kind.PATH_1:
			return 1
		Kind.PATH_2:
			return 2
		_:
			return 0


func element_name() -> String:
	var index: int = int(element)
	if index < 0 || index >= ELEMENT_NAMES.size():
		return "Element %d" % index
	return ELEMENT_NAMES[index]


## Short label: "Fire" for a Basic, "Fire (1)" for a path. The form
## unit_data.md 2.3 writes a cross requirement in, and what a tooltip names
## another element-path by.
##
## Derived rather than authored, so it cannot drift from the element and the
## path it is describing.
func short_name() -> String:
	if !is_path():
		return element_name()
	return "%s (%d)" % [element_name(), path_number()]


## What a grid square draws until it has an icon: "F", "F1", "F2". Two
## characters at most, because the square is small and the colour behind it is
## carrying most of the meaning anyway.
##
## The initial rather than a name because all ten elements happen to start with
## a different letter. That is luck rather than design, so it is worth knowing
## that an eleventh element could break it - at which point this is the one
## place to change.
func grid_label() -> String:
	var initial: String = element_name().substr(0, 1)
	if !is_path():
		return initial
	return "%s%d" % [initial, path_number()]


## The hue this technology's element owns. Every square of an element draws the
## same one, which is what makes a row read as one element at a glance.
func element_color() -> Color:
	var index: int = int(element)
	if index < 0 || index >= ELEMENT_COLORS.size():
		return Color(0.16, 0.17, 0.22)
	return ELEMENT_COLORS[index]


## Reports everything authored wrong on this one file. The registry asks each
## technology in turn, at boot, the way the damage table is checked.
func validate() -> bool:
	var complete: bool = true
	if display_name.is_empty():
		Log.err("Technology has no display name", resource_path)
		complete = false
	if is_path() && ultimate_cross_tech_id == 0:
		Log.err("Path technology names no cross requirement for its Ultimate", display_name)
		complete = false
	if !is_path() && ultimate_cross_tech_id != 0:
		Log.err("Basic technology names a cross requirement, which only a path has",
			display_name)
		complete = false
	return complete
