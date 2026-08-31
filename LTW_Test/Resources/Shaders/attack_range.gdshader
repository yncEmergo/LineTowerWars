shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// Every range a selection carries, drawn as ONE shape.
//
// A circle per tower as its own transparent mesh looked right until two of them
// overlapped: the fills blended over each other and the shared ground came out
// darker than either. This draws the UNION instead - every pixel asks whether it
// is inside ANY range and is painted at most once - so ten towers standing on
// top of each other read exactly like one.
//
// TWO GROUPS, because two questions are being answered at once: how far a tower
// SHOOTS, and how far its ability REACHES. Each is its own list with its own
// colour, and the union rule holds inside each - so an aura is still one shape
// however many towers share it. Two groups rather than N on purpose: no tower
// in the roster carries more than one ability range, so a third colour would be
// a colour nobody could learn.
//
// Which of the two colours a pixel takes is decided by SIZE and not by group:
// the smallest circle covering it wins. See fragment().
//
// Positions are world space, so the quad this runs on only has to be big enough
// to cover the circles; it does not have to line up with anything.

const int MAX_CIRCLES = 32;

// xy is the centre on the ground plane, z is the radius. Radius 0 is unused.
uniform vec3 attack_circles[MAX_CIRCLES];
uniform int attack_count = 0;
uniform vec3 ability_circles[MAX_CIRCLES];
uniform int ability_count = 0;

uniform vec4 fill_color : source_color = vec4(1.0, 0.45, 0.25, 0.10);
uniform vec4 ring_color : source_color = vec4(1.0, 0.45, 0.25, 0.85);
uniform vec4 ability_fill_color : source_color = vec4(0.35, 0.85, 1.0, 0.10);
uniform vec4 ability_ring_color : source_color = vec4(0.35, 0.85, 1.0, 0.85);
uniform float ring_thickness = 0.02;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 point = world_position.xz;

	// THE SMALLEST CIRCLE COVERING A PIXEL DECIDES ITS COLOUR, whichever group
	// that circle came from. So a tight aura sitting inside a long attack reach
	// paints its own disc rather than vanishing into the bigger one - and with
	// several towers selected the answer is still per pixel, so the innermost
	// thing covering a patch of ground is always the thing naming it.
	//
	// Tracked as a radius rather than a flag because "smallest" cannot be
	// answered by two booleans: -1 means nothing has covered this pixel yet.
	float fill_radius = -1.0;
	bool fill_is_ability = false;
	float ring_radius = -1.0;
	bool ring_is_ability = false;

	for (int i = 0; i < MAX_CIRCLES; i++) {
		if (i >= attack_count) {
			break;
		}
		float distance_to_centre = length(point - attack_circles[i].xy);
		float radius = attack_circles[i].z;
		if (distance_to_centre <= radius && (fill_radius < 0.0 || radius < fill_radius)) {
			fill_radius = radius;
			fill_is_ability = false;
		}
		// An outline of one range that falls inside another is still drawn, so
		// the player can tell which tower reaches where rather than seeing one
		// merged blob.
		if (abs(distance_to_centre - radius) <= ring_thickness
				&& (ring_radius < 0.0 || radius < ring_radius)) {
			ring_radius = radius;
			ring_is_ability = false;
		}
	}

	// <= rather than <, so two circles of the SAME radius go to the ability.
	// A tower whose ability reaches exactly as far as it shoots has one circle
	// to draw and the ability is the half worth naming; the attack range is
	// already written on the panel.
	for (int i = 0; i < MAX_CIRCLES; i++) {
		if (i >= ability_count) {
			break;
		}
		float distance_to_centre = length(point - ability_circles[i].xy);
		float radius = ability_circles[i].z;
		if (distance_to_centre <= radius && (fill_radius < 0.0 || radius <= fill_radius)) {
			fill_radius = radius;
			fill_is_ability = true;
		}
		if (abs(distance_to_centre - radius) <= ring_thickness
				&& (ring_radius < 0.0 || radius <= ring_radius)) {
			ring_radius = radius;
			ring_is_ability = true;
		}
	}

	if (fill_radius < 0.0 && ring_radius < 0.0) {
		discard;
	}

	// An outline always beats a fill, so an edge stays visible wherever it
	// crosses another circle.
	vec4 chosen;
	if (ring_radius >= 0.0) {
		chosen = ring_is_ability ? ability_ring_color : ring_color;
	} else {
		chosen = fill_is_ability ? ability_fill_color : fill_color;
	}

	ALBEDO = chosen.rgb;
	ALPHA = chosen.a;
}
