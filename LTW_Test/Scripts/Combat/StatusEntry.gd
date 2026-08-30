class_name StatusEntry
extends RefCounted

## One debuff currently running on a unit, as anything that DRAWS one needs to
## read it: what it is, who put it there, how strong it is, how long is left and
## how many stacks it holds.
##
## The read side of StatusEffects. That class owns the simulation and is
## deliberately shaped for it - a chill per source, one merged burn, a permanent
## erosion with no clock at all - so a panel asking it "what is on this creep"
## would otherwise have to know all fourteen of those shapes. `entries()` flattens
## them into this one record, and the HUD knows only this.
##
## It is also what crosses the WIRE, because a client runs no simulation and so
## has no StatusEffects of its own to ask (multiplayer.md 3.4). The source is
## named by AUTHORED ability_id rather than by a path, like everything else that
## is sent.
##
## The TEXT lives here rather than on the fourteen passives that apply these,
## for the reason a creep's armour text lives on UnitStats: two towers applying
## the same kind of chill describe it identically, and a line per passive is a
## line that drifts. What a passive says on its own card is its own business and
## stays there - that is `TowerPassive.effect_text()`, which describes what the
## tower DOES; this describes what the creep HAS.

## Every shape of thing that can sit on a unit. One per effect StatusEffects
## keeps separately, so the two never fall out of step.
##
## The ORDER is the order the HUD draws them in, which is why it runs from the
## effects a player reacts to - held, then slowed - down to the quiet ones.
enum Kind {
	STUNNED,
	PARALYZED,
	SLOWED,
	BURNING,
	POISONED,
	ARMOR_ERODED,
	ARMOR_CHANGED,
	ARMOR_TYPE_ALTERED,
	SPELL_VULNERABLE,
	PHYSICALLY_VULNERABLE,
	ATTACK_SLOWED,
	ATTACK_WEAKENED,
	SLOWS_LENGTHENED,
	GRIPPED,
}

## How the magnitude of a kind should be read, which is the whole of what the
## description lines differ by.
enum Measure {
	## Nothing to say. "Cannot move or act" carries no number.
	NONE,
	## A share, written out of a hundred.
	PERCENT,
	## Whole armour points.
	POINTS,
	## Seconds, for the effects whose magnitude IS a length of time.
	SECONDS,
	## An index into UnitStats.ArmorType.
	ARMOR_TYPE,
	## A plain amount of damage, per second or stored.
	DAMAGE,
}

## Given to seconds_left by an effect that has no clock at all: eroded armour is
## gone for the rest of the creep's life. Negative rather than 0, so an effect
## expiring on this very tick stays tellable from one that never expires.
const PERMANENT: float = -1.0

## Fields one entry takes in a snapshot: the unit it is on, the kind, the
## ability that applied it, the magnitude, the seconds left, the stacks held and
## the most it could hold.
const RECORD_SIZE: int = 7

## Ability id meaning "nothing authored applied this".
const NO_SOURCE: int = 0

const TITLES: Dictionary = {
	Kind.STUNNED: "Stunned",
	Kind.PARALYZED: "Paralyzed",
	Kind.SLOWED: "Slowed",
	Kind.BURNING: "Burning",
	Kind.POISONED: "Poisoned",
	Kind.ARMOR_ERODED: "Armor Eroded",
	Kind.ARMOR_CHANGED: "Armor Broken",
	Kind.ARMOR_TYPE_ALTERED: "Armor Type Altered",
	Kind.SPELL_VULNERABLE: "Spell Vulnerability",
	Kind.PHYSICALLY_VULNERABLE: "Physical Vulnerability",
	Kind.ATTACK_SLOWED: "Attacks Slowed",
	Kind.ATTACK_WEAKENED: "Attacks Weakened",
	Kind.SLOWS_LENGTHENED: "Frozen Marrow",
	Kind.GRIPPED: "Gripped",
}

## What each kind does to the creep, with its own magnitude filled in. One "%s"
## per line at most, which is what keeps _magnitude_text a single question.
const TEMPLATES: Dictionary = {
	Kind.STUNNED: "Cannot move, attack or act.",
	Kind.PARALYZED: "Held in place, and can be reached by attacks that only hit ground.",
	Kind.SLOWED: "Moves %s%% slower.",
	Kind.BURNING: "Takes %s spell damage per second.",
	Kind.POISONED: "Holds %s poison damage, dealt at once when it is detonated.",
	Kind.ARMOR_ERODED: "Armor permanently reduced by %s.",
	Kind.ARMOR_CHANGED: "Armor reduced by %s.",
	Kind.ARMOR_TYPE_ALTERED: "Counts as %s armor.",
	Kind.SPELL_VULNERABLE: "Takes %s%% more spell damage.",
	Kind.PHYSICALLY_VULNERABLE: "Takes %s%% more physical damage.",
	Kind.ATTACK_SLOWED: "Attacks %s%% more slowly.",
	Kind.ATTACK_WEAKENED: "Deals %s%% less attack damage.",
	Kind.SLOWS_LENGTHENED: "Every slow applied lasts %ss longer.",
	Kind.GRIPPED: "Held by an aura, which is stronger the longer it holds on.",
}

const MEASURES: Dictionary = {
	Kind.STUNNED: Measure.NONE,
	Kind.PARALYZED: Measure.NONE,
	Kind.SLOWED: Measure.PERCENT,
	Kind.BURNING: Measure.DAMAGE,
	Kind.POISONED: Measure.DAMAGE,
	Kind.ARMOR_ERODED: Measure.POINTS,
	Kind.ARMOR_CHANGED: Measure.POINTS,
	Kind.ARMOR_TYPE_ALTERED: Measure.ARMOR_TYPE,
	Kind.SPELL_VULNERABLE: Measure.PERCENT,
	Kind.PHYSICALLY_VULNERABLE: Measure.PERCENT,
	Kind.ATTACK_SLOWED: Measure.PERCENT,
	Kind.ATTACK_WEAKENED: Measure.PERCENT,
	Kind.SLOWS_LENGTHENED: Measure.SECONDS,
	Kind.GRIPPED: Measure.NONE,
}

var kind: Kind = Kind.SLOWED
## ability_id of whatever applied it, so an icon can be found for it. For the
## effects StatusEffects deliberately MERGES - one burn however many towers lit
## it - this is whichever of them currently owns the value, which is what the
## icon should picture and is honest about the number beside it.
var source_id: int = NO_SOURCE
## What the effect is worth, read as its kind's Measure says.
var magnitude: float = 0.0
## Seconds before it wears off, or PERMANENT for one that never does.
var seconds_left: float = 0.0
## How many stacks are held, or 0 for an effect that does not stack.
var stacks: int = 0
## The most this effect could stack to, or 0 when it has no ceiling.
var max_stacks: int = 0


## Everything currently on a unit, from whichever source this machine has one.
##
## Two sources, because there are two kinds of machine. The authority reads the
## creep's own StatusEffects, which is the real thing. A CLIENT runs no
## simulation and has none to read (multiplayer.md 3.4), so it reads what the
## server sent for the unit it asked to be told about - which is the one unit
## its panel is showing, and no other.
##
## Here rather than on the panel that first wanted it, because two readouts now
## ask the same question - the debuff row and the armour line above it - and
## two copies of this branch is how those two end up disagreeing.
static func for_unit(unit: Unit) -> Array[StatusEntry]:
	var empty: Array[StatusEntry] = []
	if unit == null || !is_instance_valid(unit):
		return empty

	if !MatchSession.is_authority():
		return Replication.effects_for(unit.unit_id)

	var creep: Creep = unit as Creep
	if creep == null:
		return empty
	var status: StatusEffects = creep.status_or_null()
	return empty if status == null else status.entries()


## Armour points these effects have added to or taken off a unit, which is a
## negative number nearly every time. For a CLIENT, which has no StatusEffects
## to ask and so reads its creep's base armour without any of this in it.
static func armor_delta_in(entries: Array[StatusEntry]) -> int:
	var delta: float = 0.0
	for entry in entries:
		if entry.kind == Kind.ARMOR_ERODED || entry.kind == Kind.ARMOR_CHANGED:
			delta += entry.magnitude
	return int(round(delta))


## The armour TYPE these effects have altered a unit into, or `fallback` when
## none of them has. One tower does this; see ArmorTypeChoiceAbility.
static func armor_type_in(entries: Array[StatusEntry],
		fallback: UnitStats.ArmorType) -> UnitStats.ArmorType:
	for entry in entries:
		if entry.kind == Kind.ARMOR_TYPE_ALTERED:
			return int(entry.magnitude) as UnitStats.ArmorType
	return fallback


## One entry, built in the order the fields are declared.
static func make(entry_kind: Kind, source: int, size: float, seconds: float,
		held: int = 0, ceiling: int = 0) -> StatusEntry:
	var entry: StatusEntry = StatusEntry.new()
	entry.kind = entry_kind
	entry.source_id = source
	entry.magnitude = size
	entry.seconds_left = seconds
	entry.stacks = held
	entry.max_stacks = ceiling
	return entry


## Reads one entry back out of a snapshot, starting at `at`.
static func from_record(records: PackedFloat32Array, at: int) -> StatusEntry:
	return make(
		int(records[at + 1]) as Kind,
		int(records[at + 2]),
		records[at + 3],
		records[at + 4],
		int(records[at + 5]),
		int(records[at + 6]),
	)


## Writes this entry into a snapshot, tagged with the unit it sits on.
func append_to(records: PackedFloat32Array, unit_id: int) -> void:
	records.append_array(PackedFloat32Array([
		unit_id, kind, source_id, magnitude, seconds_left, stacks, max_stacks,
	]))


## What this debuff is called.
func title() -> String:
	return String(TITLES.get(kind, "Affected"))


## What it is doing to the unit, with its own number in it.
func text() -> String:
	var template: String = String(TEMPLATES.get(kind, ""))
	if !template.contains("%s"):
		return template
	return template % _magnitude_text()


## Time left as the panel writes it, or an empty string for an effect with no
## clock - a permanent one says so in its own line rather than in a duration.
##
## Whole seconds ROUNDED UP, the same way a tower's countdown is written: a
## tooltip is rebuilt while it is open, and tenths would have it redraw and
## resize ten times a second under the cursor. Rounding up also means it never
## reads 0 for something still running.
func duration_text() -> String:
	if seconds_left < 0.0:
		return ""
	return "%ds" % ceili(maxf(seconds_left, 0.0))


## Stacks as the panel writes them, "3 / 5" where there is a ceiling and "3"
## where there is not. Empty for anything that does not stack at all.
func stacks_text() -> String:
	if stacks <= 0:
		return ""
	if max_stacks <= 0:
		return str(stacks)
	return "%d / %d" % [stacks, max_stacks]


## How far through its life the effect is, 0 for freshly applied and 1 for about
## to wear off, measured over the last `window` seconds of it.
##
## Over a WINDOW rather than over the effect's own full duration, because
## nothing stores that: a chill refreshed by a second hit keeps the longer of
## the two countdowns and has no memory of what either started at. The window
## answers the question a player is actually asking of a debuff icon - "is this
## about to fall off" - and a longer effect simply sits at 0 until it comes
## inside the window. Same shape as CommandSlot's lockout sweep.
func expiry_progress(window: float) -> float:
	if seconds_left < 0.0 || window <= 0.0:
		return 0.0
	return clampf(1.0 - seconds_left / window, 0.0, 1.0)


## The ability that applied this, or null when nothing authored did or the
## registry has not been built yet.
func source_ability() -> UnitAbility:
	if source_id == NO_SOURCE:
		return null
	var session: MatchSession = References.match_session
	if session == null:
		return null
	return session.abilities().ability_for(source_id)


func _magnitude_text() -> String:
	match int(MEASURES.get(kind, Measure.NONE)):
		Measure.PERCENT:
			return StringUtil.trim_number(absf(magnitude) * 100.0, 1)
		Measure.POINTS:
			return StringUtil.trim_number(absf(magnitude), 1)
		Measure.ARMOR_TYPE:
			return _armor_type_text()
	return StringUtil.trim_number(absf(magnitude), 1)


## The altered armour type spelled out, e.g. "Light". Lowercased before
## capitalising for the same reason UnitStats.armor_type_text does it: an
## all-caps enum name would be split on every letter.
func _armor_type_text() -> String:
	var index: int = int(magnitude)
	var keys: Array = UnitStats.ArmorType.keys()
	if index < 0 || index >= keys.size():
		return "unknown"
	return String(keys[index]).replace("_", " ").to_lower().capitalize()
