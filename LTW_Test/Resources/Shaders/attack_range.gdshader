shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// The reach of every selected unit, drawn as ONE shape.
//
// A circle per tower as its own transparent mesh looked right until two of them
// overlapped: the fills blended over each other and the shared ground came out
// darker than either. This draws the UNION instead - every pixel asks whether it
// is inside ANY range and is painted at most once - so ten towers standing on
// top of each other read exactly like one.
//
// Positions are world space, so the quad this runs on only has to be big enough
// to cover the circles; it does not have to line up with anything.

const int MAX_CIRCLES = 32;

// xy is the centre on the ground plane, z is the radius. Radius 0 is unused.
uniform vec3 circles[MAX_CIRCLES];
uniform int circle_count = 0;
uniform vec4 fill_color : source_color = vec4(1.0, 0.45, 0.25, 0.10);
uniform vec4 ring_color : source_color = vec4(1.0, 0.45, 0.25, 0.85);
uniform float ring_thickness = 0.04;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	bool inside = false;
	bool on_ring = false;

	for (int i = 0; i < MAX_CIRCLES; i++) {
		if (i >= circle_count) {
			break;
		}

		float distance_to_centre = length(world_position.xz - circles[i].xy);
		float radius = circles[i].z;

		if (distance_to_centre <= radius) {
			inside = true;
		}
		// An outline of one range that falls inside another is still drawn, so
		// the player can tell which tower reaches where rather than seeing one
		// merged blob.
		if (abs(distance_to_centre - radius) <= ring_thickness) {
			on_ring = true;
		}
	}

	if (!inside && !on_ring) {
		discard;
	}

	vec4 chosen = on_ring ? ring_color : fill_color;
	ALBEDO = chosen.rgb;
	ALPHA = chosen.a;
}
