class_name SendCreepAbility
extends UnitAbility

## Buys one pack of a creep type from the send building.
##
## IMMEDIATE targeting: sending needs no aim, the destination is decided by the
## send ring rather than by the player. Price, pack size, stock and the income
## it grants all come off the creep's own stats, so the button can never quote
## a number the send does not actually charge.
##
## Points at the creep's STATS, not at its prefab, for the same reason a build
## ability does: the stats resource is the authority on what the creep is, and
## it names its own prefab by path. So drawing this slot costs nothing, where
## probing a prefab for its stats meant instantiating and freeing a creep every
## frame for every slot on the card.
##
## Holds no stock of its own. Abilities are shared stateless resources, so the
## reserve lives on the building and this only ever reads it.

@export_group("Send")
## Everything this sends, and the only thing this ability names. The prefab
## comes off it through creep_stats.scene().
@export var creep_stats: CreepStats


## The creep this names, so the registry finds the abilities on its card.
## The creep's own picture. A send describes the CREEP, and that goes for what
## it looks like as much as for what it costs.
func icon_texture() -> Texture2D:
	if creep_stats != null && creep_stats.icon != null:
		return creep_stats.icon
	return icon


func reached_stats() -> Array[UnitStats]:
	var reached: Array[UnitStats] = []
	if creep_stats != null:
		reached.append(creep_stats)
	return reached


func execute(unit: Unit, _target: AbilityTarget) -> void:
	if unit == null || !unit.has_method("send_creeps"):
		return
	if creep_stats == null:
		Log.err("SendCreepAbility has no creep stats assigned", display_name)
		return
	unit.send_creeps(creep_stats)


func can_execute(unit: Unit) -> bool:
	if unit == null || creep_stats == null || !unit.has_method("send_creeps"):
		return false
	return unit.can_send(creep_stats)


## Sends held in reserve on this unit, or -1 when the concept does not apply.
func charge_count(unit: Unit) -> int:
	var stock: CreepStock = _stock_on(unit)
	if stock == null:
		return -1
	return stock.count


## How far along the next stock is, 0 to 1, for the cooldown sweep. Reads as 1
## whenever there is stock in hand, so the sweep only appears when the player is
## actually waiting on one.
func charge_progress(unit: Unit) -> float:
	var stock: CreepStock = _stock_on(unit)
	if stock == null || stock.has_stock():
		return 1.0
	return stock.regen_progress()


## Seconds until this creep's start delay is served, so a slot the player
## cannot press yet says how long rather than only that it is greyed out.
##
## Read off the BUILDING, which is the authority on both the match clock and
## the cheat that waives the wait - the ability itself is shared by everyone
## and could not tell one player's wait from another's.
func lockout_seconds(unit: Unit) -> float:
	if unit == null || creep_stats == null || !unit.has_method("unlock_remaining"):
		return -1.0
	return unit.unlock_remaining(creep_stats)


## Describes the creep, not the send. Name, price, income and stats all come
## off the creep's own stats file, so the card can never quote a number the
## send does not actually charge or spawn.
func tooltip_data(hotkey_label: String = "",
		unit: Unit = null) -> AbilityTooltipData:
	var data: AbilityTooltipData = super(hotkey_label, unit)
	var info: CreepStats = creep_stats
	if info == null:
		return data

	data.title = info.display_name
	# Dropped on purpose: the send's own sentence would only repeat the price
	# and the income line standing right above it.
	data.description = ""
	data.gold_cost = info.gold_cost
	# What the whole SEND costs in population rather than what one creep of it
	# does. Population is charged per creep, so a pack of three costs three -
	# and quoting the per creep figure next to a per pack price would be two
	# different questions on one line.
	data.population = info.pack_population()
	data.income_gain = info.income_gain

	# Filled in reading order, since the tooltip lays stats out in pairs across
	# rather than down: health beside armour, speed beside bounty, and what one
	# press puts on the field beside when it can first be pressed.
	data.add_stat("Health", str(info.max_health))
	data.add_stat("Armor", info.armor_text(info.armor))
	data.add_stat("Speed", StringUtil.trim_number(info.move_speed))
	data.add_stat("Bounty", str(info.bounty))
	data.add_stat("Sent", _pack_text(info))
	# Off the BUILDING where there is one, for the reason lockout_seconds() is:
	# a Sudden Death creep carries no start delay of its own and would read
	# "0:00" off its own file. Falls back to the creep for a tooltip asked
	# about an ability that is on nobody's card yet.
	var unlocks: String = _fallback_unlock_text(info)
	if unit != null && unit.has_method("unlock_text"):
		unlocks = unit.unlock_text(info)
	data.add_stat("Unlocks", unlocks)
	_add_passives(data, info)
	return data


## What one press puts on the field, e.g. "3" or "2 + 1 Timber Wolf".
##
## Spelled out only where a pack holds more than one KIND, which in the whole
## roster is the Sheep and its Timber Wolf. Everything else reads as a plain
## count, because naming the creep again on its own tooltip would be noise.
func _pack_text(info: CreepStats) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for entry: Array in info.pack_contents():
		var stats: CreepStats = entry[0] as CreepStats
		if stats == info:
			parts.append(str(int(entry[1])))
		else:
			parts.append("%d %s" % [int(entry[1]), stats.display_name])
	return " + ".join(parts)


## A send with no stats, or stats naming a prefab which is not there, is a dead
## button. Both are worth one message at boot.
func validate(seen: Dictionary) -> bool:
	if creep_stats == null:
		Log.err("SendCreepAbility has no creep stats assigned", display_name)
		return false

	var complete: bool = creep_stats.validate(seen)
	if creep_stats.scene_path.is_empty():
		Log.err("Sendable creep has no scene_path, nothing could be spawned", {
			"ability": display_name,
			"creep": creep_stats.display_name,
		})
		complete = false

	return complete


## The creep's own answer, with the opening phase added the way the sender
## would add it. Only ever reached by a tooltip asked about a send that is on
## nobody's card - but a number quoted from a resource that skipped the phase
## would be one whole opening early, and there is no reading allowed to
## disagree with the slot. See GameConfig.start_delay_seconds.
func _fallback_unlock_text(info: CreepStats) -> String:
	var config: GameConfig = References.game_config
	if config == null:
		return info.unlock_text()
	return CreepStats.clock_text(config.unlock_clock(info.unlock_seconds))


func _stock_on(unit: Unit) -> CreepStock:
	if unit == null || !unit.has_method("stock_for"):
		return null
	return unit.stock_for(creep_stats)


## The creep's own passives, which is the block the tooltip closes on: auras,
## flying, a faster reserve. Read off the creep rather than listed on the send,
## so a creep that gains one says so everywhere it is described.
##
## A CreepPassive describes itself from its own numbers, so what is quoted here
## can never drift from what the passive actually does. Anything else falls
## back to the text it was authored with.
func _add_passives(data: AbilityTooltipData, info: CreepStats) -> void:
	for entry in info.abilities:
		var passive: UnitAbility = entry as UnitAbility
		if passive == null || passive.targeting != UnitAbility.Targeting.PASSIVE:
			continue

		var creep_passive: CreepPassive = passive as CreepPassive
		var text: String = passive.description_text(info)
		if creep_passive != null:
			text = creep_passive.passive_text(info)
		data.add_special(passive.display_name, text)
