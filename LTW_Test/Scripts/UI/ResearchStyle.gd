class_name ResearchStyle
extends RefCounted

## How a Research Center square says which of the three states it is in, for
## the two squares that have them: TechSlot and UltimateButton.
##
## **IT IS HERE BECAUSE A MULTIPLY CANNOT SAY IT.** Both squares used to carry
## three `modulate` constants - lit for owned, white for available, grey for
## blocked - laid over a background that is one of the ten ELEMENT HUES. A
## modulate is a multiply, so what it produces depends on what it multiplies:
## 0.55 on the yellow element lands brighter than 1.0 on the deep blue one. The
## three states were therefore thirty appearances that overlapped, and the
## comparison a player actually makes is between squares of DIFFERENT elements
## rather than against a remembered baseline of the same one. No other set of
## three multipliers fixes that; the fix is to stop multiplying.
##
## So the two dimmed states are given an ABSOLUTE value - every available
## square is exactly as dark as every other, whatever its hue - and only the
## saturation is scaled, which is what keeps a row still reading as one
## element. Owned squares keep the authored hue untouched and are the only
## full-strength colour on the screen, so "colourful is mine" is the first
## thing the grid says.
##
## Colour is the fast channel and not the only one: an owned square also
## carries the tick, which is the same on all ten hues and survives a player
## who cannot tell two of them apart. See the badge in `tech_slot.tscn`.

## Which of the three a square is in. Worked out by the square from TechManager
## - nothing here knows a rule, it only knows what each state looks like.
enum State {
	## Already researched. Full authored hue, full icon, and the tick.
	OWNED,
	## Not owned and could be bought right now.
	AVAILABLE,
	## Not owned and refused: the element it rests on is missing, or there is
	## not enough gold.
	BLOCKED,
}

## Value every AVAILABLE square is drawn at, whatever its element. Below the
## darkest authored hue with room to spare - they run roughly 0.55 to 0.79 - so
## no available square can be mistaken for an owned one of another element.
const AVAILABLE_VALUE: float = 0.34
## How much of the element's saturation an available square keeps. Enough to
## group a row at a glance, not enough to compete with an owned square.
const AVAILABLE_SATURATION: float = 0.55

## The same two for a BLOCKED square, another clear step down.
const BLOCKED_VALUE: float = 0.21
const BLOCKED_SATURATION: float = 0.30

## What the square's picture is tinted by. The icons are colour renders of the
## towers themselves, so they carry as much of the confusion as the background
## does and are dimmed with it.
const OWNED_ICON: Color = Color(1.0, 1.0, 1.0, 1.0)
const AVAILABLE_ICON: Color = Color(0.82, 0.83, 0.88, 1.0)
const BLOCKED_ICON: Color = Color(0.52, 0.53, 0.60, 1.0)

## The two-letter fallback label, for a build with no picture for that tower.
## Kept brighter than the icon at every step, because it is text.
const OWNED_TEXT: Color = Color(0.99, 0.98, 0.92, 1.0)
const AVAILABLE_TEXT: Color = Color(0.86, 0.88, 0.94, 1.0)
const BLOCKED_TEXT: Color = Color(0.56, 0.58, 0.66, 1.0)

## The hotkey letter, on the same ladder. It is already gold, so it only loses
## strength rather than changing colour.
const OWNED_HOTKEY: Color = Color(1.0, 0.89, 0.62, 1.0)
const AVAILABLE_HOTKEY: Color = Color(0.86, 0.76, 0.55, 1.0)
const BLOCKED_HOTKEY: Color = Color(0.55, 0.50, 0.40, 1.0)


## The square's background, given the element hue it was authored with.
##
## Only the two dimmed states are computed. An owned square is handed its hue
## back exactly as authored: that colour IS the element, and re-deriving it
## would put a second opinion about the palette in a file that is not
## TechDefinition.
static func background_for(element: Color, state: State) -> Color:
	if state == State.OWNED:
		return element

	var hue: float = element.h
	if state == State.AVAILABLE:
		return Color.from_hsv(hue, element.s * AVAILABLE_SATURATION, AVAILABLE_VALUE)
	return Color.from_hsv(hue, element.s * BLOCKED_SATURATION, BLOCKED_VALUE)


static func icon_tint_for(state: State) -> Color:
	match state:
		State.OWNED:
			return OWNED_ICON
		State.AVAILABLE:
			return AVAILABLE_ICON
		_:
			return BLOCKED_ICON


static func text_color_for(state: State) -> Color:
	match state:
		State.OWNED:
			return OWNED_TEXT
		State.AVAILABLE:
			return AVAILABLE_TEXT
		_:
			return BLOCKED_TEXT


static func hotkey_color_for(state: State) -> Color:
	match state:
		State.OWNED:
			return OWNED_HOTKEY
		State.AVAILABLE:
			return AVAILABLE_HOTKEY
		_:
			return BLOCKED_HOTKEY
