class_name WorldDigest
extends RefCounted

## The accumulator a world checksum is built into.
##
## **An object rather than a string, and that is a cost fix and a precision fix at
## once.** `WorldChecksum` used to build a `PackedStringArray` with a `%`-format
## per field, and `_point()` allocated two packed arrays per unit on top, then
## joined the lot into one large string and hashed that. At the ten-lane world the
## bench measures - three thousand units - on the shipped checksum cadence, that
## was thousands of allocations and a several-hundred-kilobyte string four times a
## second, on the machine whose tick budget is already the binding constraint.
##
## Numbers go in as numbers here. Two packed arrays grow, and the bytes behind
## them are hashed once at the end.
##
## **It also lets a float be compared EXACTLY.** Everything reached through
## `Unit.checksum_state` used to be rounded to a thousandth before it could be put
## in a string - health, cooldowns, construction progress, the aura fields - which
## is the same tolerance that was already removed from positions and wrong for the
## same reason: under lockstep two peers agree to the last bit or they have
## already diverged, and slack only delays the report until the drift crosses the
## rounding.

## Everything integral, and the hashes of everything textual.
var _ints: PackedInt64Array = PackedInt64Array()
## Everything real, exactly as its bits.
var _floats: PackedFloat64Array = PackedFloat64Array()


## One integer.
func i(value: int) -> WorldDigest:
	_ints.append(value)
	return self


## One real number, EXACTLY - no rounding, no tolerance.
func f(value: float) -> WorldDigest:
	_floats.append(value)
	return self


## One position or vector.
func vec(value: Vector3) -> WorldDigest:
	_floats.append(value.x)
	_floats.append(value.y)
	_floats.append(value.z)
	return self


## One piece of text, as its hash. Godot's String hash walks the character data
## and is the same on every platform, so this is safe to compare across machines
## and costs nothing beyond the string that already existed.
func text(value: String) -> WorldDigest:
	_ints.append(value.hash())
	return self


## A label, so two fields that happen to hold the same number in different places
## cannot cancel out. Cheap: it is one more integer.
func key(name: StringName) -> WorldDigest:
	_ints.append(String(name).hash())
	return self


## The whole thing, as one number.
##
## Godot's own `hash()` over the two packed arrays, which runs in C++ over the
## raw buffers rather than walking them in GDScript. Deterministic across
## machines: the integer half is hashed byte for byte, and the float half goes
## through the engine's float hash, which normalises negative zero and NaN to one
## representation - the same on every platform, which is what matters here.
func result() -> int:
	return hash([_ints, _floats])
