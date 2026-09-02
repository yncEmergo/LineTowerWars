class_name UnitStats
extends Resource

## Stats shared by every unit type, whatever it can do.
## One resource per unit type, e.g. Resources/UnitStats/builder_stats.tres,
## assigned on that unit's prefab.
##
## Anything that only some units have belongs on a subclass, so each stats
## file shows only fields that apply. Movement lives on MobileUnitStats.

## Armour types index the rows of the damage matrix, see Config/DamageTable.gd.
##
## INVULNERABLE stays first so it remains the default for anything that has not
## been given a type yet, and it is not a row in the matrix: it is the absence
## of damage rather than a resistance to it.
enum ArmorType {
	## Cannot be damaged at all, and shows no health bar. The builder.
	INVULNERABLE,
	## No armour type at all. The neutral row, and the placeholder anything
	## carries until somebody gives it a real type.
	UNARMORED,
	LIGHT,
	MEDIUM,
	HEAVY,
	FORTIFIED,
	HERO,
}

@export_group("Identity")
## The number the network names this KIND of unit by, so a spawn can be
## replicated as an id rather than as a resource path. Must be unique across
## every unit type the game contains, and must never change once it has
## shipped.
##
## Authored here for exactly the reasons UnitAbility.ability_id is (D12):
## deriving it from a position in a list would renumber everything else the
## moment a unit is added or removed, and there would be a list to keep in
## step. 0 means nobody has assigned one, which UnitTypeRegistry reports at
## boot.
##
## Ids are never reused. A new unit type takes the next free number.
@export var unit_type_id: int = 0
## Shown as the unit name in the UI panel.
@export var display_name: String = "Unit"
## The picture of this unit, wherever one is shown: the button that builds it,
## the button that upgrades into it, the button that sends it, and its tile in
## a multi-unit selection.
##
## HERE rather than on those buttons, for the same reason a tower's price is
## here rather than on the ability that buys it: the picture belongs to the
## thing it is a picture OF, and one authored in four places drifts the first
## time three of them are updated.
##
## Currently a generated placeholder - a render of the unit's own primitive
## model. See 2DArt/Icons.
@export var icon: Texture2D

@export_group("Stats")
@export var max_health: int = 100
@export var armor_type: ArmorType = ArmorType.INVULNERABLE
## Armour POINTS, which is a separate question to the armour TYPE. The type
## decides how a given damage type fares against this unit; the points decide
## how much of what is left actually lands, on a curve with diminishing
## returns. Negative armour amplifies damage rather than reducing it.
## See Config/DamageTable.gd and game_rules.md.
@export var armor: int = 0

@export_group("Attack")
## What this unit's attack does, or null when it has none. Creeps and the send
## building cannot attack, towers can, and the builder will.
##
## Held here rather than on the attacking unit's own component so the whole
## attack can be read off a prefab without spawning it. That is what lets a
## build tooltip quote a tower's damage and range before the tower exists.
@export var attack: AttackStats

@export_group("Abilities")
## Entries on this unit's command card, in slot order. The builder, creeps and
## towers each declare their own, which is why the card is generic.
@export var abilities: Array[UnitAbility] = []
## Ability a right click resolves to. Ground clicks use this today, and once
## attacking exists a click on an enemy will resolve to Attack instead.
@export var default_ability: UnitAbility

@export_group("Prefab")
## The prefab this stats resource describes, as a res:// path.
##
## A PATH and not a PackedScene, for two reasons. The prefab already points
## back here through its own stats @export, so holding it as a PackedScene
## would be a reference cycle; and a PackedScene in a .tres is a hard
## load-time dependency that takes the whole resource down with it when the
## file goes missing. See Util/SceneUtil.gd.
##
## Empty is legal for a unit no ability spawns - the builder and the send
## building are placed from node-level PackedScene @exports instead.
@export_file("*.tscn") var scene_path: String = ""

## Cached prefab and whether loading it has been tried, see scene().
var _cached_scene: PackedScene = null
var _scene_loaded: bool = false

## Every ability this unit's card can EVER show, in no particular order.
##
## Not the same question as "what is on the card right now", which is the
## unit's to answer and changes as it builds, sells or dies. This is the
## complete set, and it exists so a walk of the content graph can find every
## ability without knowing which state shows which.
##
## Deliberately explicit rather than duck typed, exactly like
## UnitAbility.reached_stats(): a subclass that adds a card of its own has to
## say so here, or its abilities are invisible to the registry. Getting that
## wrong once already cost Cancel Build and Cancel Sell their ids.
func card_abilities() -> Array[UnitAbility]:
	var every: Array[UnitAbility] = abilities.duplicate()
	if default_ability != null:
		every.append(default_ability)
	return every


## Damage range as shown in the UI panel, e.g. "12 - 15", or a dash for a unit
## with no attack at all. Read off the attack rather than stored twice, so the
## panel and the tower can never quote different numbers.
##
## `bonus` is damage the unit's own abilities have added to it PERMANENTLY, and
## it is folded into the range rather than written beside it: the range is what
## the tower hits for, and a player reading the line wants that number and not
## an addition to do. The bonus is then repeated on the end, because a tower
## that has grown is the whole point of the line it grew on and the panel is
## the only place it is ever visible. Taken as an argument rather than read
## here for the reason armor_text() takes its points: this resource describes
## the TYPE, and what is standing on the field is not always it.
##
## `ratio` is everything currently making the unit hit harder or softer - a
## Void disc lending it damage, an Obsidian Statue drifting past taking some
## away - and is folded in WITHOUT a tail of its own. That is the difference
## between the two: a bonus is something the tower has EARNED and keeps, and is
## worth naming; a ratio is a condition of where it happens to be standing, and
## the honest answer to "what does this tower hit for" is just the number.
func damage_text(bonus: int = 0, ratio: float = 1.0) -> String:
	if attack == null:
		return "-"
	var text: String = "%s (%s)" % [
		attack.damage_text(bonus, ratio), attack.damage_type_text()
	]
	if bonus <= 0:
		return text
	return "%s   +%s" % [text, StringUtil.compact_number(bonus)]


## Armour type as shown in the UI panel, e.g. "Invulnerable".
## Lowercased before capitalising, because capitalize() would otherwise split
## an all-caps enum name on every letter.
func armor_type_text() -> String:
	return armor_type_name(armor_type)


## Any armour type as shown in the UI, for the readouts that have to name one
## this unit does not currently have.
static func armor_type_name(kind: ArmorType) -> String:
	var raw: String = String(ArmorType.keys()[kind])
	return raw.replace("_", " ").to_lower().capitalize()


## Armour as shown in the UI, e.g. "3  (Heavy)". Takes the points rather than
## reading them off this resource, because a unit standing in an aura has more
## armour than its prefab says and the panel has to be able to show that.
##
## `shown_type` is the same allowance for the TYPE, which one tower in the game
## alters for a few seconds at a time - see ArmorTypeChoiceAbility. -1 leaves it
## as this resource's own, which is what every caller but the panel wants.
##
## Anything invulnerable shows only the word: a point value next to the absence
## of damage would read as though the two were on the same scale.
func armor_text(points: int, shown_type: int = -1) -> String:
	var kind: ArmorType = armor_type
	if shown_type >= 0:
		kind = shown_type as ArmorType
	if kind == ArmorType.INVULNERABLE:
		return armor_type_name(kind)
	return "%d  (%s)" % [points, armor_type_name(kind)]


## The prefab this describes, loaded the first time something spawns one.
##
## Cached, which breaks no rule about resources holding state: it is derived
## purely from this resource's own @export, so every user of the shared .tres
## would compute the identical answer. The attempt is remembered as well as the
## result, so a path that does not resolve is reported once rather than on
## every spawn.
func scene() -> PackedScene:
	if !_scene_loaded:
		_scene_loaded = true
		_cached_scene = SceneUtil.load_scene(scene_path, display_name)
	return _cached_scene


## Reports every scene path on this unit and everything it reaches that does
## not resolve, and answers whether all of them do.
##
## Meant for one call at boot. A path string is not rewritten by the editor
## when a scene moves, so this is what turns a renamed file into a message at
## startup instead of a broken button in the middle of a match.
##
## seen guards against a stats resource reachable through two abilities, and
## against a cycle - unlikely now that the prefab link is a string, but cheap
## to rule out. It is also what keeps a shared resource from being reported
## twice.
func validate(seen: Dictionary) -> bool:
	if seen.has(self):
		return true
	seen[self] = true

	var complete: bool = _validate_paths()

	if attack != null && !attack.validate(display_name):
		complete = false

	for entry in abilities:
		var ability: UnitAbility = entry as UnitAbility
		if ability != null && !ability.validate(seen):
			complete = false

	return complete


## The scene paths this stats resource declares itself. Subclasses that add
## their own override this rather than validate(), so the seen check above runs
## exactly once per resource however deep the hierarchy goes.
func _validate_paths() -> bool:
	# Empty is legal here, see scene_path. A path that was filled in and does
	# not resolve never is.
	if scene_path.is_empty() || SceneUtil.exists(scene_path):
		return true

	Log.err("Unit scene_path does not resolve", {
		"unit": display_name,
		"path": scene_path,
	})
	return false


## The Attack entry on this unit's card, or null for a unit that cannot be
## given an attack order.
##
## Read off the card rather than stored a second time, so a unit that can be
## told to attack is exactly a unit that shows the button for it. The right
## click uses this to resolve to Attack on a creep and to the default ability
## on the ground.
func attack_ability() -> UnitAbility:
	for entry in abilities:
		if entry is AttackAbility:
			return entry
	return null
