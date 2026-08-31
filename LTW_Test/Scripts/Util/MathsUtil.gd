class_name MathsUtil

static func multiply_and_floor(a: int, b: float) -> int:
	return int(floor(float(a) * b))

static func round_to_decimals(value: float, decimal_places: int) -> float:
	var factor: float = 10.0 ** max(decimal_places, 0)
	return round(value * factor) / factor


## Flat dot product of an offset against a direction, for ordering things along
## a line of travel. The game is played on the xz plane and a flyer's height is
## only ever visual, so y is dropped rather than weighed.
static func flat_dot(offset: Vector3, direction: Vector3) -> float:
	return offset.x * direction.x + offset.z * direction.z


## Flat distance from a point to the SEGMENT from -> to.
##
## Shared by everything that sweeps a line through creeps in one tick - a
## piercing shot, a charging beast - because the endpoint is never the right
## test: anything fast covers more than a creep's width between two ticks and
## would step straight over it.
static func flat_segment_distance(point: Vector3, from: Vector3, to: Vector3) -> float:
	var line: Vector2 = Vector2(to.x - from.x, to.z - from.z)
	var offset: Vector2 = Vector2(point.x - from.x, point.z - from.z)
	var length: float = line.length_squared()
	if length < 0.000001:
		return offset.length()
	var share: float = clampf(offset.dot(line) / length, 0.0, 1.0)
	return (offset - line * share).length()
