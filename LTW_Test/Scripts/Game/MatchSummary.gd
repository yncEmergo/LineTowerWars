class_name MatchSummary
extends Resource

## The whole record of one finished match: every player's line, and the few
## facts that belong to the match rather than to anybody in it.
##
## Taken ONCE, at the moment the match is decided, and then never changed. That
## is what lets it survive the scene change into the summary screen without
## anything having to still be alive behind it - the match scene is gone by
## then, and a summary that reached back into PlayerManager would have nothing
## to reach.
##
## Handed over on `MenuNavigation.pending_summary`, the same way a MatchSetup is
## handed to the game scene, and consumed once for the same reason.

@export var match_id: String = ""
## Seconds of match clock, which is play time rather than wall time: a match
## held still for a draft or a stall did not get longer for it.
@export var duration_seconds: float = 0.0
## The slot that won, or 0 for a match nobody won - one abandoned, or a single
## player run, which is never over.
@export var winner_slot: int = 0
## Whether the match ran long enough to reach Sudden Death.
@export var reached_sudden_death: bool = false
## What the lobby agreed to, as MatchSettings.describe() writes it. A STRING
## rather than the settings themselves, because the summary outlives the match
## and nothing on the screen needs to ask the rules a question.
@export var settings_text: String = ""
## One per player, already in finishing order: the winner first, then whoever
## was knocked out last. See sort_by_placement.
@export var lines: Array[MatchStatLine] = []


## Puts the lines in the order a results table is read in: the winner at the
## top, then back down the eliminations, and anybody with no placement at all
## after the lot of them.
##
## By SLOT within an equal placement, so two machines that show the same summary
## show it the same way round - which matters the day a summary is compared
## between two players rather than only read by one.
func sort_by_placement() -> void:
	lines.sort_custom(func(a: MatchStatLine, b: MatchStatLine) -> bool:
		var left: int = a.placement if a.placement > 0 else 9999
		var right: int = b.placement if b.placement > 0 else 9999
		if left != right:
			return left < right
		return a.slot < b.slot
	)


func line_for(slot: int) -> MatchStatLine:
	for line in lines:
		if line != null && line.slot == slot:
			return line
	return null


func local_line() -> MatchStatLine:
	for line in lines:
		if line != null && line.is_local:
			return line
	return null


## The line holding the biggest value of one field, for the "best of the match"
## row the summary screen draws. Null when nobody scored anything at all, which
## is what an empty summary and a field nobody touched both look like.
##
## Takes the field by NAME because the alternative is a Callable per row, and
## every row asks exactly the same question of a different number.
func best_at(field: StringName) -> MatchStatLine:
	var best: MatchStatLine = null
	var top: int = 0
	for line in lines:
		if line == null:
			continue
		var value: int = int(line.get(field))
		if best == null || value > top:
			best = line
			top = value
	return null if top <= 0 else best


## The duration as a clock, which is how a match length is read.
func duration_text() -> String:
	var whole: int = int(maxf(0.0, duration_seconds))
	@warning_ignore("integer_division")
	var minutes: int = whole / 60
	return "%d:%02d" % [minutes, whole % 60]
