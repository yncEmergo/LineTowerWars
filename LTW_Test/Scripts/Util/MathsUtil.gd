class_name MathsUtil

static func multiply_and_floor(a: int, b: float) -> int:
	return int(floor(float(a) * b))

static func round_to_decimals(value: float, decimal_places: int) -> float:
	var factor: float = 10.0 ** max(decimal_places, 0)
	return round(value * factor) / factor
