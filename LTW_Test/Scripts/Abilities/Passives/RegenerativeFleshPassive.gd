class_name RegenerativeFleshPassive
extends CreepPassive

## Mends faster the worse it is doing, and shrugs a maze slow off twice over.
##
## The Abomination trait, and three separate rules in one card entry
## (unit_data.md 6.6): "harmful slow durations -65% (max 1.4 sec); +2.4 health
## regen per missing health percentage, capped at 240/sec; at 50% health the
## current slow percentage is halved, once."
##
## The REGENERATION is what makes it read on the field. An Abomination at full
## health mends at nothing at all and one at a tenth mends at the cap, so a
## maze that gets it to a sliver and then cannot finish it watches the whole
## bar come back. It is the exact opposite of a creep with flat regeneration,
## which is worth most while nothing is shooting it.
##
## The two SLOW rules are the counterplay to that: an Abomination cannot be
## held in a killing field long enough for the maze to win the race. One of
## them shortens the clock as a slow lands, and the other reaches in ONCE, at
## half health, and cuts whatever has piled up in half.
##
## The duration rules are answered through the generic harmful-effect hooks
## rather than through a slow-only one, so they shorten a stun and a burn as
## well as a chill. That is broader than the source states and is deliberate:
## the roster has one duration knob, one place it is applied, and a second one
## that only slows would be a rule nobody could see from a stats file.

@export_group("Slow")
## Share of a harmful clock this creep serves.
@export_range(0.0, 1.0, 0.05) var duration_ratio: float = 0.35
## The longest any of them may run whatever it asked for, in seconds.
@export var duration_cap: float = 1.4
## Health share at or below which the running slow is cut in half, once.
@export_range(0.0, 1.0, 0.05) var shrug_at_health: float = 0.5

@export_group("Regeneration")
## Health per second gained per PERCENTAGE POINT of health the creep is
## missing, so a creep at 90% health regenerates ten times this.
@export var per_missing_percent: float = 2.4
## The most it may ever regenerate per second.
@export var regen_cap: float = 240.0


func harmful_duration_ratio() -> float:
	return duration_ratio


func harmful_duration_cap() -> float:
	return duration_cap


## Nothing at full health, the cap at death door, and a straight line between.
func health_regen(creep: Creep) -> float:
	if creep == null:
		return 0.0
	var maximum: float = float(creep.max_health())
	if maximum <= 0.0:
		return 0.0

	var missing: float = clampf(1.0 - creep.current_health / maximum, 0.0, 1.0)
	return minf(missing * 100.0 * per_missing_percent, regen_cap)


## The once-only half, checked as damage lands rather than on a clock: the
## moment worth reacting to is the hit that took the creep under the line, and
## a tick-driven check would fire it up to a twentieth of a second late.
##
## The single use is recorded on the CREEP, never here, for the reason every
## other once-only trait records it there: this resource is every Abomination
## on the field, so a flag stored on it would be spent for all of them at once.
func on_damage_taken(creep: Creep, _lost: float,
		_damage_type: DamageTable.DamageType) -> void:
	if creep.has_spent(self) || creep.max_health() <= 0:
		return
	if creep.current_health > float(creep.max_health()) * shrug_at_health:
		return

	creep.spend(self)
	var status: StatusEffects = creep.status_or_null()
	if status != null:
		status.halve_slows()


func effect_text() -> String:
	return ("Harmful effects last %d%% less and never more than %s seconds."
		+ " Regenerates %s health per second for every percent of health it is"
		+ " missing, up to %s. The first time it falls below %d%% health, the"
		+ " slow on it is halved.") % [
		roundi((1.0 - duration_ratio) * 100.0),
		StringUtil.trim_number(duration_cap),
		StringUtil.trim_number(per_missing_percent),
		StringUtil.trim_number(regen_cap),
		roundi(shrug_at_health * 100.0),
	]
