// The lawn a player mazes on.
//
// A flat green plane is the one surface the camera looks at the whole match,
// and a single albedo colour makes it read as a hole rather than as ground:
// nothing in it tells the eye how far away it is, and a tower's shadow is the
// only thing with any texture in the frame.
//
// So this is a lawn and nothing more ambitious. Three cheap layers, all
// procedural, none of them animated - a moving field would pull the eye off
// the creeps walking over it, which is the opposite of what the ground is for:
//
//   PATCHES   low frequency noise deciding which parts of the lawn are lush
//             and which are worn, plus a rarer dry tone on top of that. This
//             is the layer that gives the plane a sense of scale
//   BLADES    high frequency noise STRETCHED along one axis, so the grain
//             reads as blades leaning the same way rather than as a field of
//             dots. It is what stops the patches looking like clouds
//   BUMP      the blade layer perturbing the normal a little, so the sun
//             actually catches the lawn instead of lighting it evenly
//
// Everything is sampled in WORLD SPACE, not in UV. One material is shared by
// every player area, the zones it covers are different sizes, and UV on a
// PlaneMesh runs 0..1 whatever that size is - so a UV-sampled lawn would be a
// different scale on every plane. World space also makes the grain continuous
// across two planes that meet.
//
// The grain FADES OUT once a pixel covers more than a blade, the same
// anti-alias principle build_grid.gdshader uses on its lines. Without it the
// lawn boils whenever the camera pulls back.
//
// TUNING BELONGS IN THE MATERIAL. Every uniform is a knob on
// Resources/Materials/ground_grass_material.tres; the values here are only
// what a fresh material starts from.

shader_type spatial;
render_mode cull_back;

group_uniforms Colors;
// The bulk of the lawn.
uniform vec3 grass_color : source_color = vec3(0.30, 0.40, 0.29);
// What the worn parts fall towards.
uniform vec3 grass_dark_color : source_color = vec3(0.19, 0.27, 0.20);
// The rarer sun-bleached tone, laid over the two above.
uniform vec3 grass_dry_color : source_color = vec3(0.40, 0.42, 0.26);
// How much of the lawn the dry tone is allowed to claim. 0 turns it off.
uniform float dry_amount : hint_range(0.0, 1.0, 0.01) = 0.30;

group_uniforms Grain;
// Patches per world unit. Low: these are metres-wide areas, not texture.
uniform float patch_frequency : hint_range(0.01, 2.0, 0.01) = 0.30;
// Blades per world unit, across the grain.
uniform float blade_frequency : hint_range(0.5, 32.0, 0.5) = 9.0;
// How far the blade layer is stretched along Z. 1.0 is no stretch at all.
// Kept LOW on purpose: the lane is 30 units long and the grain runs down it,
// so anything much past 2.0 stops reading as turf and starts reading as
// combed fibres tracing the whole zone.
uniform float blade_stretch : hint_range(1.0, 12.0, 0.1) = 2.0;
// How much of the final shade the blades own, against the patches.
uniform float blade_weight : hint_range(0.0, 1.0, 0.01) = 0.35;
// Overall contrast between the light and dark tones.
uniform float grain_contrast : hint_range(0.0, 1.0, 0.01) = 0.75;

group_uniforms Surface;
// How hard the blade layer pushes the normal around.
uniform float bump_strength : hint_range(0.0, 1.0, 0.01) = 0.25;
uniform float roughness_value : hint_range(0.0, 1.0, 0.01) = 0.94;

varying vec2 world_xz;


float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}


float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	// Smoothstep the interpolant, or the cell edges show as a lattice.
	vec2 t = f * f * (3.0 - 2.0 * f);

	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));

	return mix(mix(a, b, t.x), mix(c, d, t.x), t.y);
}


// Three octaves is enough for ground seen from a fixed height, and the third
// one is already close to the blade layer's own frequency.
float fbm(vec2 p) {
	float sum = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 3; i++) {
		sum += value_noise(p) * amplitude;
		p *= 2.03;
		amplitude *= 0.5;
	}
	return sum / 0.875;
}


void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}


void fragment() {
	vec2 patch_uv = world_xz * patch_frequency;
	// Stretched along Z so the fine grain has a direction to it.
	vec2 blade_uv = world_xz * vec2(blade_frequency, blade_frequency / blade_stretch);

	// How much world the pixel covers, in blade cells. Past one the grain can
	// no longer be resolved and has to fade to its average or it shimmers.
	float pixel_blades = length(fwidth(world_xz)) * blade_frequency;
	float grain = 1.0 - smoothstep(0.5, 1.5, pixel_blades);

	float patch = fbm(patch_uv);
	float blade_noise = value_noise(blade_uv);

	float shade = mix(patch, mix(0.5, blade_noise, grain), blade_weight);
	shade = mix(0.5, shade, grain_contrast);

	vec3 color = mix(grass_dark_color, grass_color, smoothstep(0.15, 0.85, shade));

	// The dry tone rides the SECOND patch layer rather than the first, so a
	// bleached area does not simply mean a lush one.
	float dry = smoothstep(0.55, 0.95, fbm(patch_uv * 0.6 + vec2(17.3, 4.1)));
	color = mix(color, grass_dry_color, dry * dry_amount);

	// Bump from the blade layer's own gradient, sampled a fifth of a blade cell
	// out - close enough to a derivative, and it costs two lookups. Faded by
	// the same grain factor, so a lawn too far away to resolve is flat rather
	// than a sheet of sparkling noise.
	float slope_x = value_noise(blade_uv + vec2(0.2, 0.0)) - blade_noise;
	float slope_y = value_noise(blade_uv + vec2(0.0, 0.2)) - blade_noise;

	ALBEDO = color;
	NORMAL = normalize(NORMAL
		- TANGENT * slope_x * bump_strength * grain
		- BINORMAL * slope_y * bump_strength * grain);
	ROUGHNESS = roughness_value;
	SPECULAR = 0.15;
}
