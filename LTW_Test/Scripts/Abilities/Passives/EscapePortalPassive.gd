class_name EscapePortalPassive
extends CreepPassive

## Runs the moment anything touches it, and can never take a life.
##
## The Treasure Goblin trait. unit_data.md 6.5: it "cannot steal lives and is
## removed the moment it takes any damage, giving its bounty to whoever hit
## it".
##
## NOT A CREEP THE DEFENDER HAS TO KILL. It is a pure income accelerator: what
## the sender is buying is the permanent income, and what the defender gets for
## noticing it is a large bounty for one shot. Both players want the same thing
## to happen to it, which is why it is the one creep in the roster nobody
## defends against.
##
## Two of the three halves are answered elsewhere and correctly. Its stats give
## it no lives to steal, which is what stops it stealing one and - see
## Creep._reach_end - also stops it being recycled into the next maze. And its
## bounty is already paid to whoever owns the maze it dies in, which for a
## creep removed by the first hit IS whoever hit it.
##
## What is here is the REMOVAL, which is a real rule rather than a consequence
## of its health: a Goblin does not have to be killed, it leaves. Written so
## that it holds even if the creep is ever given more than a token of health.

func on_damage_taken(creep: Creep, _lost: float,
		_damage_type: DamageTable.DamageType) -> void:
	if creep.is_alive():
		# Straight to zero rather than queue_free, so it goes through the
		# ordinary death: it pays its bounty, it runs the death passives, and
		# the defender sees the same popup any other kill gives them.
		creep.take_damage(maxi(1, creep.max_health()),
			DamageTable.DamageType.SPELL)


func effect_text() -> String:
	return ("Cannot steal a life, and leaves the moment anything damages it -"
		+ " paying its whole bounty to whoever hit it.")
