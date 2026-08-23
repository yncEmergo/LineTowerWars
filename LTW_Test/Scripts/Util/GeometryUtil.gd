class_name GeometryUtil

static var directional_vectors: Array[Vector2] = [Vector2(0, 1), Vector2(1, 0), Vector2(0, -1), Vector2(-1, 0)]

# float Vector2.angle() const 
# Returns this vector's angle with respect to the positive X axis, or (1, 0) vector, in radians.
# For example, Vector2.RIGHT.angle() will return zero, Vector2.DOWN.angle() will return PI / 2 (a quarter turn, or 90 degrees), 
# and Vector2(1, -1).angle() will return -PI / 4 (a negative eighth turn, or -45 degrees).


## Calculates and returns the angle between two Vector2s in degrees
static func get_angle_between_vectors(v1: Vector2, v2: Vector2) -> float:
	return rad_to_deg(v1.angle_to(v2))

## Returns the vector from the directional_vectors array, that is closest to the input vector
static func get_closest_directional_vector(v1: Vector2) -> Vector2:
	v1 = v1.normalized()
	var best_distance: float = INF
	var best_pick: Vector2 = directional_vectors[0]
	for vector: Vector2 in directional_vectors:
		var distance := v1.distance_to(vector)
		if distance < best_distance:
			best_distance = distance
			best_pick = vector
	
	return best_pick

static func vector2_to_radians (v: Vector2) -> float:
	return atan2(v.y, v.x)
