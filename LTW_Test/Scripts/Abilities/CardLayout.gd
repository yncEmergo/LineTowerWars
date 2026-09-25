class_name CardLayout
extends RefCounted

## The boot check behind Docs/hotkeys.md section 2: what may sit where on a
## command card.
##
## Run once per card from the content walk Main starts at boot - every unit's
## own card, a building's job cards, and every menu a card opens. A card that
## breaks a rule would still mostly work in play, and that is the problem: the
## mistake has to be a line at boot rather than a square a player stumbles over.
## The panel only lays cards out and trusts that this has been said.
##
## What it refuses:
##   - an ability that names no square, or a square off the grid
##   - two abilities on one square
##   - a passive anywhere but the passive squares, and a trait anywhere but the
##     trait squares. That is also what keeps a passive off R, which belongs to
##     the one ability a unit has that is pressed
##   - a command with a key of its own that is not on its OWN square: every Sell
##     on Sell's square, every Cancel on Cancel's, Build on Build's. So the
##     promise that a command is on one square everywhere is a rule of the build
##     rather than of the files happening to agree
##   - on a menu, anything on Cancel's square, which the panel fills with the
##     Cancel that backs out of the menu

## Squares a card has when no ControlsConfig is wired, which is a stripped-down
## test scene. The same fallback the panel draws with.
const FALLBACK_SQUARES: int = 12


## Checks one card and answers whether it passes. `where` names the card in the
## log; `menu` is true for a card a submenu opens.
static func validate(card: Array, where: String, menu: bool = false) -> bool:
	var config: ControlsConfig = References.controls_config
	var squares: int = FALLBACK_SQUARES
	if config != null:
		squares = config.command_slot_count()

	var complete: bool = true
	var taken: Dictionary = {}
	for entry in card:
		var ability: UnitAbility = entry as UnitAbility
		if ability == null:
			continue
		if ability.slot < 0 || ability.slot >= squares:
			_report("An ability on a card names no square on it", where, ability)
			complete = false
			continue
		if taken.has(ability.slot):
			_report("Two abilities on one card claim the same square", where, ability,
				taken[ability.slot] as UnitAbility)
			complete = false
			continue
		taken[ability.slot] = ability
		if config != null && !_fits_square(ability, config, where, menu):
			complete = false

	return complete


## The rules that depend on WHAT an ability is rather than on the card around
## it. Only asked with a config, which is where the squares are authored.
static func _fits_square(ability: UnitAbility, config: ControlsConfig, where: String,
		menu: bool) -> bool:
	if ability.targeting == UnitAbility.Targeting.PASSIVE:
		var trait_entry: bool = ability is TraitPassive
		var allowed: PackedInt32Array = config.trait_squares if trait_entry \
			else config.passive_squares
		if !allowed.has(ability.slot):
			_report("A trait is off the trait squares" if trait_entry
				else "A passive is off the passive squares", where, ability)
			return false

	var action: HotkeyAction = ability.hotkey_action
	if action != null && action.is_on_card() && ability.slot != action.card_square:
		_report("A command is off the square it answers to on every other card", where,
			ability)
		return false

	var cancel: HotkeyAction = config.cancel_action
	if menu && cancel != null && cancel.is_on_card() && ability.slot == cancel.card_square:
		_report("A menu entry sits on Cancel's square, which the panel fills with Cancel",
			where, ability)
		return false

	return true


static func _report(problem: String, where: String, ability: UnitAbility,
		other: UnitAbility = null) -> void:
	var details: Dictionary = {
		"card": where,
		"ability": ability.display_name,
		"id": ability.ability_id,
		"square": ability.slot,
	}
	if other != null:
		details["other"] = other.display_name
	Log.err(problem, details)
