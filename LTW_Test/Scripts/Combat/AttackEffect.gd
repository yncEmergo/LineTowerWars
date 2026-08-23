@abstract
class_name AttackEffect
extends Resource

## Something an attack does once it has landed, beyond damaging what it hit.
##
## An attack carries a list of these rather than a flag per trick, so a tower
## that splashes and slows is two entries instead of a new combination nobody
## can name. They run in order, after the primary target has taken its damage.
##
## Not a UnitAbility. An ability is an entry on a command card and owns a
## hotkey, an icon and a targeting mode, none of which an on-hit effect has.
## Same idea, a resource carrying its own behaviour, different thing.
##
## Shared like every other resource, so effects must stay STATELESS. Anything
## one shot needs is in the AttackHit it is handed.


## Runs the effect. target is the creep that was struck and may be null when it
## died before the attack arrived, which is why the impact point is passed
## separately rather than read off the target.
@abstract func apply(hit: AttackHit, target: Unit, impact_point: Vector3) -> void


## Short name for this effect's block in a tooltip, e.g. "Splash". Empty means
## the effect stays out of tooltips entirely.
func effect_name() -> String:
	return ""


## One line describing what this effect does, for the tooltip. Subclasses fill
## in their own numbers, so a tooltip can never quote a radius the effect does
## not actually use.
func description_text() -> String:
	return ""


## Reports any scene path this effect declares that does not resolve. Nothing
## carries one yet; the hook exists so an effect that gains a prefab is covered
## by the boot check without AttackStats having to learn about it.
func validate(_owner_name: String) -> bool:
	return true
