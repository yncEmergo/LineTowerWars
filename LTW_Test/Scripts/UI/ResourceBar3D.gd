class_name ResourceBar3D
extends Bar3D

## Worldspace bar for a tower's SECOND RESOURCE, drawn under its health bar.
##
## Some towers run on a resource besides their health - usually mana, and not
## always - and for the ones that do it is the number that decides what they
## are worth right now. So unlike the health bar it is not the player's to
## switch off: it sits under the health bar and stays there whether or not that
## one is drawn, which is the same reasoning the job bar above is shown on.
##
## WHAT the resource is belongs to the tower, not here: it answers with a
## TowerResource carrying the count, the ceiling and its own colours, so a bar
## reading an Alchemist's devoured kills is violet and one reading mana is blue
## with nothing here having to know which tower is which.
##
## It POLLS its tower rather than being pushed at. A second resource moves from
## a dozen places - a passive's regeneration, an ability spending it, a kill
## being banked, a ceiling being lowered, and on a client from a replication
## update that went nowhere near any of those - and none of them raises a
## signal. Asking once a frame for one small object costs nothing next to
## keeping ten call sites in step, and it is what the unit panel already does
## with the same number.
##
## Hides itself when the tower has no second resource at all, so nothing has to
## decide whether to build one for a tier that might gain some later - and when
## the bar is FULL, the same way a health bar hides at full health.
##
## Full is the resting state of most of this roster: nearly every elemental
## ability is "fill up by attacking, then spend the lot", so a field of towers
## waiting to fire would otherwise be a field of identical full blue
## rectangles saying nothing. What is worth seeing is a bar that is PARTWAY,
## because that is a tower with something pending - and the bar appearing is
## then the event, rather than one more thing always drawn.
##
## Unlike the health bar it is not the player's to switch off, so this is a
## rule rather than a setting: there is no "always" mode to fall back to.

## Share of an ordinary bar's thickness this one is drawn at. Half, so a tower
## with a second resource does not read as a tower with two health bars: the
## health bar is the one a player scans a field for, and this is the one they
## read once they have already looked at the tower.
const HEIGHT_SHARE: float = 0.5

@export_group("References")
## The tower this reads. Its own owner, wired by the building that made it.
@export var _tower: Building

## Colours currently handed to the shader, so a bar only rebuilds them when the
## tower's answer actually changes kind - which is never, in practice, but a
## tower that gained a second passive mid-match would be drawn correctly.
var _fill_shown: Color = TowerResource.MANA_FILL
var _empty_shown: Color = TowerResource.MANA_EMPTY


func _ready() -> void:
	fill_color = _fill_shown
	empty_color = _empty_shown
	bar_height = BAR_HEIGHT * HEIGHT_SHARE
	super()
	# Straight away rather than on the first frame, or a tower built full - which
	# is the whole design of one of them - flashes empty on the tick it appears.
	_refresh()


## Assigns the tower to read. Call before the bar enters the tree, like the
## colours: _ready is what takes the first reading.
func watch(tower: Building) -> void:
	_tower = tower


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	if _tower == null || !is_instance_valid(_tower):
		visible = false
		return

	var resource: TowerResource = _tower.secondary_resource()
	# is_full() rather than the ratio, so the test is the same integer
	# comparison the simulation makes when it decides a tower may fire. A bar
	# that vanished a point early - or hung on at 0.999 - would be a second
	# opinion about what "full" means.
	visible = resource != null && !resource.is_full()
	if !visible:
		return

	_apply_colors(resource)
	set_ratio(resource.ratio())


## Repaints the bar when the tower's second resource is a different KIND from
## the one drawn last frame. Guarded on a change, because the material is what
## the shader reads and rewriting two uniforms every frame for two colours that
## never move would be work for nothing.
func _apply_colors(resource: TowerResource) -> void:
	if resource.fill_color == _fill_shown && resource.empty_color == _empty_shown:
		return
	_fill_shown = resource.fill_color
	_empty_shown = resource.empty_color
	set_colors(_fill_shown, _empty_shown)
