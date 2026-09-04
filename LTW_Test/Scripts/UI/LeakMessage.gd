class_name LeakMessage
extends RichTextLabel

## One line in the leak log: "Red stole 2 lives from you!".
##
## A prefab rather than a label built in code, for the same reason
## PlayerStatRow is one: the line is going to grow. An icon for the creep that
## did it, a click that snaps the camera to the lane, a different shape for a
## Boss - none of those wants to be threaded through a builder function.
##
## It owns its own clock. The log adds it, tells it what it says, and never
## looks at it again until it asks to be forgotten: a message holds at full
## strength, fades, and then reports that it is done. That is what lets the
## same line be REFRESHED - a second leak from the same player restarts the
## clock and puts the alpha back, wherever in the fade it had got to.
##
## The COUNT is the number of lives, not a repeat count. Two leaks from the
## same player in a row read as one line saying two lives rather than as the
## same sentence twice, which is both shorter and the truth.

## Which line this is, so the log can tell whether a new leak belongs on it.
## The other player's slot and the direction together: taking a life off Red is
## not the same line as Red taking one off you.
var key: StringName = &""

var _other_slot: int = 0
var _is_gain: bool = false
var _lives: int = 0
var _held: float = 0.0
var _config: PresentationConfig:
	get:
		return References.presentation_config


## Starts this line off. `other_slot` is whoever is at the other end of it, and
## `is_gain` says which end the local player is at.
func show_leak(other_slot: int, is_gain: bool, lives: int) -> void:
	key = message_key(other_slot, is_gain)
	_other_slot = other_slot
	_is_gain = is_gain
	_lives = 0
	add_lives(lives)


## Another leak of the same kind. The number goes up rather than a second line
## appearing, and the clock starts again from full - including out of a fade
## that had already begun, which is what the alpha is put back for.
func add_lives(lives: int) -> void:
	_lives += maxi(1, lives)
	_held = 0.0
	modulate.a = 1.0
	text = _compose()


## The name two leaks have to share to be the same line.
static func message_key(other_slot: int, is_gain: bool) -> StringName:
	return StringName("%s:%d" % ["gain" if is_gain else "loss", other_slot])


## Whether this line has finished fading and should be dropped. Counted here
## rather than by the log, so a line that is refreshed is refreshed in one
## place and cannot be half-forgotten.
func advance(delta: float) -> bool:
	var config: PresentationConfig = _config
	var hold: float = 5.0 if config == null else config.leak_hold_seconds
	var fade: float = 0.75 if config == null else maxf(0.01, config.leak_fade_seconds)

	_held += delta
	if _held < hold:
		return false

	modulate.a = clampf(1.0 - (_held - hold) / fade, 0.0, 1.0)
	return _held >= hold + fade


## The line itself, colour and all.
##
## Built as BBCode rather than as three labels in a row because the sentence
## changes shape with the number: "1 life" and "2 lives", and a name that can
## be anything from "Red" to whatever somebody typed in the lobby. Laying that
## out in boxes would mean measuring text the label already measures.
func _compose() -> String:
	var config: PresentationConfig = _config
	var body: Color = Color.WHITE if config == null else config.leak_text_color
	var accent: Color = Color.WHITE
	if config != null:
		accent = config.leak_gain_color if _is_gain else config.leak_loss_color

	var count: String = _tint(str(_lives), accent)
	var word: String = StringUtil.plural("life", _lives, "lives")
	var who: String = _tint(_display_name(), _player_color())

	if _is_gain:
		return "[center]%s[/center]" % _tint(
			"You have stolen %s %s from %s!" % [count, word, who], body)
	return "[center]%s[/center]" % _tint(
		"%s stole %s %s from you!" % [who, count, word], body)


## What the other player is CALLED, which in an ANONYMOUS match is their colour
## rather than their name. Asked of the match rather than decided here, so this
## cannot forget the rule - see MatchSession.display_name_for.
func _display_name() -> String:
	var session: MatchSession = References.match_session
	if session == null:
		return "Player %d" % _other_slot
	return session.display_name_for(_other_slot)


func _player_color() -> Color:
	var config: PresentationConfig = _config
	var session: MatchSession = References.match_session
	if config == null || session == null:
		return Color.WHITE
	return config.player_color(session.color_index_for(_other_slot))


## Nested tags are fine and are what keeps this to one pass: the body colour
## wraps the whole sentence and the accents sit inside it.
func _tint(body: String, color: Color) -> String:
	return "[color=#%s]%s[/color]" % [color.to_html(false), body]
