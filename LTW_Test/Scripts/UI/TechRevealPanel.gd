class_name TechRevealPanel
extends Control

## The screen a RANDOM technology match opens on: a reel of Ultimate towers that
## slows to a stop on the one this match rolled for everybody.
##
## **It runs while the tree is paused**, the same as the draft screen and for
## the same reason: the world is held still for the whole reveal, so every
## gameplay loop is stopped and the only things still processing are the network
## autoloads and whatever the player is being held FOR.
##
## **It decides nothing, and the reel is not a roll.** What was drawn is
## StartingTech's and was decided the moment the match started; this only draws
## the way there. So the animation is free to run on whatever clock this machine
## happens to have - a peer whose reel is a frame ahead lands on the same tower
## as everybody else, because the answer was never in the animation.
##
## That split is the whole design of the reveal. The HOLD is deterministic, in
## simulation ticks, counted by the turn stream; the PICTURES are local. Mixing
## the two - timing the hold off this reel - would put a render frame in charge
## of when a peer resumes, which is a desync with a very pretty cause.

## Where in the window the reel STOPS, as a share of it. The rest of the window
## is the answer standing still, which is the part a player actually reads - a
## reel that lands on the last frame before the world moves is a reel nobody
## saw the end of.
const LANDING_POINT: float = 0.7
## How many times the reel advances over the whole run. Enough that the early
## part is a blur and the last few are readable one at a time.
const REEL_STEPS: int = 42

@export_group("References")
@export var _icon_rect: TextureRect
@export var _background: ColorRect
## Fallback for a build with no art for the tower on the reel: the element and
## its path number, e.g. "F1".
@export var _fallback_label: Label
@export var _name_label: Label
@export var _element_label: Label
## Says what is happening, and then what was rolled.
@export var _status_label: Label

@export_group("Settings")
## How much the portrait swells when the reel stops, so the landing reads as an
## event rather than as the reel simply running out.
@export var _landed_scale: float = 1.12
@export var _landed_color: Color = Color(1.35, 1.22, 0.72, 1.0)

## Every Ultimate in the build, in registry order, which is what the reel runs
## through. Built once when the reveal opens.
var _reel: Array[TechDefinition] = []
## Where the reel starts, chosen so that running REEL_STEPS forward from it ends
## exactly on what was rolled. See _open.
var _start_index: int = 0
## What the portrait is currently showing, so an unchanged frame costs nothing.
var _drawn: TechDefinition = null
var _open: bool = false

var _opening: StartingTech:
	get:
		return References.starting_tech


func _ready() -> void:
	# The world is held still for the whole of this, so the screen it is being
	# held for has to keep running. See MatchSession.hold.
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()

	var opening: StartingTech = _opening
	if opening == null:
		# A HUD with no StartingTech is a scene run on its own, not a broken
		# match: there is simply never a reveal to show.
		Log.warn("TechRevealPanel found no StartingTech, no roll can be shown")
		return
	opening.opening_changed.connect(_on_opening_changed)
	_on_opening_changed()


func _on_opening_changed() -> void:
	var opening: StartingTech = _opening
	if opening == null:
		return

	if !opening.is_revealing():
		_open = false
		hide()
		return
	if _open:
		return
	_begin(opening)


## Lays the reel out so that running it forward from where it starts ends on the
## tower that was rolled.
##
## Worked out ONCE rather than searched for each frame, and it is what lets the
## reel be a plain index: the answer is already known, so the animation is
## arithmetic rather than a lottery being run a second time.
func _begin(opening: StartingTech) -> void:
	_reel = _path_techs()
	_drawn = null
	_open = true
	show()

	var rolled: TechDefinition = opening.rolled_tech()
	var landing: int = _reel.find(rolled)
	if _reel.is_empty() || landing < 0:
		# Nothing to run through, or an answer that is not in this build's own
		# list. Both are content faults rather than anything to animate around,
		# so the screen shows what it can and says nothing clever.
		_start_index = 0
		_draw_tech(rolled)
		_draw_status(opening, 1.0)
		return

	_start_index = posmod(landing - REEL_STEPS, _reel.size())
	_draw_status(opening, 0.0)


## The reel, on a render frame.
##
## Driven by how much of the HOLD is left rather than by an accumulator of its
## own, so the two can never come apart: a machine that hitched through half the
## reveal catches the reel up instead of finishing it after the world has
## already started moving.
func _process(_delta: float) -> void:
	var opening: StartingTech = _opening
	if !_open || opening == null || _reel.is_empty():
		return

	var progress: float = _progress(opening)
	var landed: bool = progress >= LANDING_POINT
	var position: float = minf(1.0, progress / maxf(0.01, LANDING_POINT))
	# Ease OUT, which is the whole feel of it: the reel is a blur while it is
	# cheap to be wrong and crawls once the answer is nearly readable.
	var step: int = int(round(ease(position, 0.25) * float(REEL_STEPS)))
	_draw_tech(_reel[posmod(_start_index + step, _reel.size())])
	_draw_landing(landed)
	_draw_status(opening, progress)


## How far through the hold the reveal is, 0 to 1.
##
## Read from the clock StartingTech is actually counting down, so nothing here
## has to know whether a turn stream or a physics frame is driving it.
func _progress(opening: StartingTech) -> float:
	var config: GameConfig = References.game_config
	var total: float = 0.0 if config == null else maxf(0.0, config.tech_reveal_seconds)
	if total <= 0.0:
		return 1.0
	return clampf(1.0 - opening.seconds_left() / total, 0.0, 1.0)


func _draw_tech(tech: TechDefinition) -> void:
	if tech == _drawn:
		return
	_drawn = tech
	if tech == null:
		return

	var picture: Texture2D = tech.ultimate_icon()
	if _icon_rect != null:
		_icon_rect.texture = picture
		_icon_rect.visible = picture != null
	if _fallback_label != null:
		_fallback_label.visible = picture == null
		_fallback_label.text = tech.grid_label()
	if _background != null:
		_background.color = tech.element_color()
	if _name_label != null:
		_name_label.text = tech.ultimate_name
	if _element_label != null:
		_element_label.text = tech.short_name()


## The swell and the lit tint once the reel has stopped. Applied to the portrait
## through this node's own modulate and scale, so nothing about the layout has
## to move for it.
func _draw_landing(landed: bool) -> void:
	if _icon_rect == null:
		return
	var parent: Control = _icon_rect.get_parent() as Control
	if parent == null:
		return
	parent.pivot_offset = parent.size * 0.5
	parent.scale = Vector2.ONE * (_landed_scale if landed else 1.0)
	parent.modulate = _landed_color if landed else Color.WHITE


func _draw_status(opening: StartingTech, progress: float) -> void:
	if _status_label == null:
		return
	if progress < LANDING_POINT:
		_status_label.text = "Rolling this match's Ultimate..."
		return
	var rolled: TechDefinition = opening.rolled_tech()
	if rolled == null:
		_status_label.text = "Every player opens on the same tower."
		return
	_status_label.text = "Every player opens on %s." % rolled.ultimate_name


func _path_techs() -> Array[TechDefinition]:
	var session: MatchSession = References.match_session
	if session == null:
		return []
	return session.techs().path_techs()
