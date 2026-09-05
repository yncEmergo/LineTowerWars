class_name AnnihilationAuraPassive
extends CreepPassive

## Every tower it walks past hits softer while it is there.
##
## The Obsidian Statue trait. unit_data.md 6.6: "towers within 300 AoE deal 15%
## less attack damage."
##
## The first thing in the game that is an aura pointed at the MAZE rather than
## at a pack. Every other creep aura in the roster helps the creeps around it;
## this one reaches into the defender towers, which is what a creep sent one at
## a time for 600,000 gold ought to be doing.
##
## Its radius is its OWN rather than the shared creep aura radius, and that is
## deliberate. The shared radius exists so a player learns the size of an aura
## once - but what they learned it for is a field around a creep that helps
## other creeps, and a player reading this one is asking a different question
## about a different set of things. It is authored here, from the source own
## 300, and it is smaller than the shared one on purpose: a statue has to walk
## into a tower face to blunt it.
##
## Applied by TOUCHING each tower every tick with a short window rather than by
## the towers asking what is standing near them. A tower that walks out of
## range restores itself a fraction of a second later, and nothing has to
## search a lane of creeps on behalf of every tower in a maze. See
## TowerStatus.weaken_damage.

## How long one touch lasts. Longer than a tick so a creep briefly out of
## reach does not flicker the tower back to full, and short enough that a
## Statue that has died or walked on stops mattering almost at once.
const TOUCH_SECONDS: float = 0.5

@export_group("Settings")
## How far it reaches, in player cells. The source states 300, which snaps
## to 2.25 at the quarter every reach is stated in - unit_data.md 3.
@export var radius_cells: float = 2.25
## Share taken off the attack damage of every tower in range.
@export_range(0.0, 1.0, 0.01) var damage_share: float = 0.15


func on_tick(creep: Creep, delta: float) -> void:
	if damage_share <= 0.0 || !creep.is_alive():
		return
	# On a BEAT rather than every tick, which is what every other aura in this
	# game does and what TOUCH_SECONDS was already sized for - the hold is
	# twice the beat, so a tower standing in the aura never flickers out of it
	# and one walking clear of it keeps the weakness for at most half a second.
	#
	# The SCAN is why it matters: buildings_in_radius walks every building in
	# the lane, and an endgame maze is a couple of hundred of them. Running
	# that twenty times a second per Statue made this creep several times the
	# cost of an ordinary one, measured under load - see
	# Findings/2026-09-05-roster-sweep-and-endgame-load.md.
	if !creep.advance_passive_clock(self, TOUCH_SECONDS * 0.5, delta):
		return
	for tower: Building in TargetFinder.buildings_in_radius(
			creep.area, creep.global_position, radius_cells):
		tower.status().weaken_damage(damage_share, TOUCH_SECONDS, self)


func effect_text() -> String:
	return "Towers within %s deal %d%% less attack damage." \
		% [StringUtil.trim_number(radius_cells), roundi(damage_share * 100.0)]
