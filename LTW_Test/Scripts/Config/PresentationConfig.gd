class_name PresentationConfig
extends Resource

## Settings that only change what the local player SEES.
##
## Nothing in here may reach the simulation. A dedicated server never wires
## this resource and runs the same match without it, so a value in this file
## can never decide a gameplay outcome - which is exactly the line
## multiplayer.md draws between simulation and presentation.
##
## That makes it the home for the knobs that have nowhere else to live: the
## ones about how a thing is drawn rather than what it does. GameConfig stays
## the file for rules, CameraConfig for the camera.
##
## Stored as Resources/Config/presentation_config.tres, reached via
## References.presentation_config.

## How the minimap decides what colour a unit's owner gets.
##
## The numbers are pinned because this is authored into a .tres as an int, so
## reordering the list would otherwise silently change what a saved file means.
enum OwnerColors {
	## Yours white, everyone else's red. Tells your own from an opponent's at a
	## glance and says nothing else, which is all a free for all with no teams
	## strictly needs.
	SELF_WHITE_ENEMIES_RED = 0,
	## Yours white, everyone else's in their own player colour. Keeps your own
	## units the easiest thing on the map to find while still saying WHOSE
	## creeps are in your maze.
	SELF_WHITE_OTHERS_COLORED = 1,
	## Everyone in their own player colour, yours included.
	ALL_COLORED = 2,
}

@export_group("Build Preview")
## Whether the ground patch under a building shows while a build order is
## still being aimed. Off shows the ghost's shape alone, on also shows the
## footprint it is about to pave.
@export var preview_shows_foundation: bool = true
## How far the ghost's colour washes over that patch. 0 leaves the stone as
## it is, 1 replaces it with flat colour.
@export_range(0.0, 1.0, 0.05) var preview_foundation_tint: float = 0.55

@export_group("Command Card", "card_")
## Seconds of a one-off wait that the cooldown fill actually sweeps through.
##
## The fill answers "how much longer", and it can only read as an answer over a
## span a player can feel. A creep that opens five minutes into a match would
## otherwise sit under a fill that has not visibly moved since the match began,
## which looks broken rather than patient - so a wait longer than this is drawn
## covered whole, and the sweep starts when the wait comes inside the window.
##
## The COUNTDOWN in the middle of the square is unaffected and counts the whole
## way down: the number is the precise answer, the fill is the glanceable one.
@export var card_lockout_sweep_seconds: float = 60.0

@export_group("Status Effects", "status_")
## Seconds of a debuff's remaining life that its icon's wedge sweeps through.
##
## The mirror of the card's lockout sweep, and a window for the same reason:
## nothing records what a debuff's duration STARTED at - a chill refreshed by a
## second hit keeps the longer of two countdowns and has forgotten both - so
## there is no fraction of a whole to draw. The window answers the question a
## player actually asks of a debuff icon, which is whether it is about to fall
## off, and anything with longer left than this simply draws clear.
@export var status_expiry_sweep_seconds: float = 5.0

@export_group("Minimap", "minimap_")
## Ground under everything, and what an empty map slot looks like. Black,
## because the world itself is black outside the player areas.
@export var minimap_background_color: Color = Color(0.0, 0.0, 0.0, 1.0)
## The strip creeps appear on, the grey cap at the top of every lane.
@export var minimap_spawn_color: Color = Color(0.55, 0.55, 0.55, 1.0)
## The buildable middle, the green body of every lane.
@export var minimap_build_color: Color = Color(0.24, 0.31, 0.15, 1.0)
## The strip creeps leak out of, at the bottom of every lane.
@export var minimap_end_color: Color = Color(0.3, 0.3, 0.3, 1.0)
## Which of the three owner colour schemes to paint with. Nothing in the game
## changes this yet - there is no options menu - so it is set here.
@export var minimap_owner_colors: OwnerColors = OwnerColors.SELF_WHITE_ENEMIES_RED
## Everything the local player owns, in the two schemes that single you out.
@export var minimap_own_color: Color = Color(1.0, 1.0, 1.0, 1.0)
## Everything anybody else owns, including their creeps walking in YOUR maze.
## There are no teams, so one colour covers every opponent - see game_rules.md.
## Only SELF_WHITE_ENEMIES_RED uses it; the other two schemes ask the palette.
@export var minimap_enemy_color: Color = Color(0.87, 0.16, 0.16, 1.0)
## Outline of what the camera can currently see.
@export var minimap_camera_color: Color = Color(1.0, 1.0, 1.0, 0.85)
@export var minimap_camera_width: float = 1.0
## Side of the square EVERY building is drawn as, in pixels. One size for all
## of them: at this scale the shape of a maze is not readable anyway, only
## roughly where its towers stand.
@export var minimap_building_px: float = 5.0
## Side of a mobile unit's square as a share of a building's, so a creep or a
## builder reads as clearly smaller than a tower.
@export_range(0.1, 1.0, 0.05) var minimap_unit_scale: float = 0.5

@export_group("Player Colours", "player_")
## One colour per slot, in slot order. The Warcraft III player colours, since
## that is the game being copied.
##
## PER-MATCH IDENTITY, chosen in the lobby. A player picks one of these and it
## rides on MatchPlayer.color_index all the way into the match, so every machine
## draws the same player the same colour - see multiplayer.md 8.1.
##
## THE ORDER IS THE DEFAULT DEAL. A lobby hands out the first free entry, so
## the first player in is red, the second blue, and so on down the list; and
## the order is the source game's own, which is what makes it read as an RTS
## palette rather than as twelve arbitrary hues. Reordering it re-colours every
## default. Read it through player_color() rather than indexing it.
##
## The INDEX is not the slot. A player keeps the colour they chose when the
## lane shuffle moves their slot, and a lobby somebody has left has a gap in
## its colours and none in its slots.
@export var player_colors: PackedColorArray = PackedColorArray([
	Color("ff0303"), Color("0042ff"), Color("1ce6b9"), Color("540081"),
	Color("fffc01"), Color("feba0e"), Color("20c000"), Color("e55bb0"),
	Color("959697"), Color("7ebff1"), Color("106246"), Color("4e2a04"),
])
## What each of those colours is CALLED, in the same order.
##
## Needed because a colour can be shown but not read out: the ANONYMOUS match
## modifier names players by their colour instead of by who they are
## (MatchSettings.Modifier), and a row in the player table is text.
##
## A second list rather than a name authored beside each colour, because
## PackedColorArray is what every other reader wants and splitting it into a
## resource per player would cost twelve files for one string each. The two are
## indexed the same way and player_color_name() falls back to the slot number
## when they disagree, so a short list is a plain reading rather than a crash.
@export var player_color_names: PackedStringArray = PackedStringArray([
	"Red", "Blue", "Teal", "Purple", "Yellow", "Orange",
	"Green", "Pink", "Gray", "Light Blue", "Dark Green", "Brown",
])


## How many colours a lobby has to hand out. The server checks a request
## against this, so a palette that is edited is the whole of what decides which
## colours exist.
func color_count() -> int:
	return player_colors.size()


## The colour a unit whose owner picked `color_index` is drawn in on the
## minimap.
##
## Both arguments are worked out by the caller rather than here: who "you" are
## is the PlayerManager's answer and which colour a slot owns is the match's,
## and a config resource has no business asking either. See
## MatchSession.color_index_for.
func minimap_color_for(color_index: int, is_local: bool) -> Color:
	match minimap_owner_colors:
		OwnerColors.SELF_WHITE_ENEMIES_RED:
			return minimap_own_color if is_local else minimap_enemy_color
		OwnerColors.SELF_WHITE_OTHERS_COLORED:
			return minimap_own_color if is_local else player_color(color_index)
		OwnerColors.ALL_COLORED:
			return player_color(color_index)

	Log.err("PresentationConfig has an owner colour scheme it does not know",
		minimap_owner_colors)
	return minimap_own_color


## One colour out of the palette, 0-based.
##
## Wraps rather than failing when the index is off the end, so a palette that
## has been trimmed since a match was set up costs two players the same colour
## instead of costing one of them any colour at all.
func player_color(color_index: int) -> Color:
	if player_colors.is_empty():
		Log.err("PresentationConfig has no player colours, nothing could be told apart")
		return minimap_own_color
	return player_colors[maxi(0, color_index) % player_colors.size()]


## What that colour is CALLED, which is how a player is named in an ANONYMOUS
## match and what the lobby's colour dropdown lists. It wraps exactly as
## player_color() does, so the name and the colour can never come from
## different places in the list.
func player_color_name(color_index: int) -> String:
	if player_color_names.is_empty():
		return "Color %d" % (maxi(0, color_index) + 1)
	return player_color_names[maxi(0, color_index) % player_color_names.size()]
