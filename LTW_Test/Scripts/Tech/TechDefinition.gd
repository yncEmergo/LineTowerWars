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
## The tower this technology's square PICTURES, by `res://` path: an element's
## 800g upgrade for a Basic technology, and the 4,000g Lesser tower of the path
## for a path one (unit_data.md 4). Read for its icon and for nothing else.
##
## A PATH rather than the resource, for the reason CLAUDE.md gives for scenes.
## A tower's stats name the upgrade above them, so an `ext_resource` here would
## drag that element's whole chain - four more towers, their abilities, their
## projectiles - in behind it every time anything so much as read a
## technology's price. The path costs nothing until the Research Center is
## opened, and by then ContentWarmer is holding the file anyway.
##
## Named rather than worked out, because nothing on a tower says which element
## or which price tier it is: that shape lives in ModelGen's roster, not in the
## .tres. This is the one place the two are tied together.
@export_file("*.tres") var tower_stats_path: String = ""

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
## The Ultimate tower this path leads to, by `res://` path, on the same terms
## as tower_stats_path above. Empty on a Basic technology, which leads to no
## Ultimate of its own.
##
## What the Show Ultimates row draws each of its twenty buttons from. Also the
## authority on what `ultimate_name` says: the name is authored for the
## tooltips, this is the picture, and the checks below refuse a file whose
## display name is not the name.
@export_file("*.tres") var ultimate_stats_path: String = ""


## The two icons read off the towers above. Cached because every user of this
## SHARED resource would work out the same answer, which is the one kind of
## value an ability-shaped resource may hold (CLAUDE.md). Read flags rather
## than a null check, so a tower with no icon is not looked up again per frame.
var _tower_icon: Texture2D = null
var _tower_icon_read: bool = false
var _ultimate_icon: Texture2D = null
var _ultimate_icon_read: bool = false


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
	return element_name_of(element)


## The same answer for an element nothing has a definition of to hand.
##
## Static because a technology DISC names an element rather than a technology -
## its upgrades are gated on how many of that element three are owned - so it
## has an enum value and no resource to ask. See DiscUpgradeAbility.
static func element_name_of(which: Element) -> String:
	var index: int = int(which)
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


## The picture this technology's square carries: the tower it unlocks, or
## whatever was authored into `icon` for a technology that wants to override
## the roster.
##
## Read off the TOWER rather than copied into this file, so the square and the
## command card that builds that tower can never show two different pictures.
## Null while a build has no art for it, which the square draws grid_label()
## for instead.
func tech_icon() -> Texture2D:
	if icon != null:
		return icon
	if !_tower_icon_read:
		_tower_icon_read = true
		_tower_icon = _icon_on(tower_stats_path)
	return _tower_icon


## The picture of the Ultimate this path leads to. Null on a Basic technology,
## which leads to none.
func ultimate_icon() -> Texture2D:
	if !_ultimate_icon_read:
		_ultimate_icon_read = true
		_ultimate_icon = _icon_on(ultimate_stats_path)
	return _ultimate_icon


## The icon of the tower a path names, loaded on first ask.
##
## `load()` rather than an `ext_resource`, and that is the whole point of the
## path: nothing is read until somebody opens the Research Center, and by then
## ContentWarmer has already loaded every stats file in the build, so this is a
## cache hit rather than a disk read.
static func _icon_on(path: String) -> Texture2D:
	if path.is_empty():
		return null

	var stats: UnitStats = ResourceLoader.load(path) as UnitStats
	if stats == null:
		Log.err("Technology names a tower stats file that did not load", path)
		return null
	return stats.icon


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
	return _validate_towers() && complete


## The two tower paths, which the editor does NOT rewrite when a stats file is
## renamed - the same cost every other authored path in the project carries,
## and the same answer: check the lot at boot rather than leave the first
## player to open the screen to find a blank square.
func _validate_towers() -> bool:
	var complete: bool = true
	if !SceneUtil.exists(tower_stats_path):
		Log.err("Technology names a tower stats file that does not resolve", {
			"tech": display_name,
			"path": tower_stats_path,
		})
		complete = false

	if !is_path():
		if !ultimate_stats_path.is_empty():
			Log.err("Basic technology names an Ultimate tower, which only a path has",
				display_name)
			complete = false
		return complete

	if !SceneUtil.exists(ultimate_stats_path):
		Log.err("Path technology names an Ultimate stats file that does not resolve", {
			"tech": display_name,
			"path": ultimate_stats_path,
		})
		complete = false
	return complete
