class_name TutorialIncomeStep
extends TutorialStep

## Finished once income has been PAID since the lesson opened.
##
## The lesson about income is a lesson about a beat, and the way to teach a beat
## is to let the player watch it land. It needs the match clock running - a step
## that holds the clock can never see a payout - so validate() refuses that.


func is_complete(director: TutorialDirector) -> bool:
	return director != null && director.payouts_this_step() >= 1


func validate() -> bool:
	var complete: bool = super()
	if holds_clock:
		Log.err("An income lesson holds the clock, so no payout can ever arrive", title)
		complete = false
	return complete
