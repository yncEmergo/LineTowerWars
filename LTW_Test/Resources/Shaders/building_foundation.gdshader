// Ground a building stands on, painted onto the floor instead of raised as a
// plinth - the way Warcraft III puts a stone tile under a structure.
//
// Everything here is procedural, there is no texture anywhere in the project.
// The blotches, the cracks and the ragged border all come out of value noise
// sampled in WORLD space rather than UV space, so two towers never show the
// same pattern and neighbouring patches read as one continuous floor rather
// than a row of identical stamps. Only the SHAPE is read from UV, so the patch
// stays centred on its own footprint whatever the tower's world position.
//
// Lit rather than unshaded: this is the ground, so it has to sit in the same
// light as the ground quad beneath it, or it reads as a sticker.
//
// TUNING BELONGS IN THE MATERIAL, not in this file. Every uniform below is a
// knob on Resources/Materials/building_foundation_material.tres: open it and
// the inspector lists them under the same groups, live in the viewport. The
// values here are only the fallback a fresh material starts from.
//
// Draw order is the whole point of the effect. The zone quads are opaque and
// go first, this patch is transparent at render_priority -1, and the build
// grid is transparent at 0, so the grid lines always end up drawn OVER the
// concrete and stay readable across it. See BuildGrid.GROUND_OFFSET for the
// heights those three sit at.

shader_type spatial;
render_mode cull_disabled, depth_draw_never;

group_uniforms Colors;
// Lit slab tone, the bulk of the surface.
uniform vec3 stone_color : source_color = vec3(0.70, 0.67, 0.60);
// Weathered tone the blotch noise mixes towards.
uniform vec3 stone_dark_color : source_color = vec3(0.53, 0.50, 0.44);
// Lines between slabs.
uniform vec3 crack_color : source_color = vec3(0.33, 0.30, 0.26);
// Broken rubble ring where the concrete meets the grass.
uniform vec3 rim_color : source_color = vec3(0.33, 0.30, 0.24);

group_uniforms Shape;
// 0 draws a circle, 1 a hard square. Between the two is a rounded square,
// which is what a one cell footprint wants.
uniform float squareness : hint_range(0.0, 1.0, 0.01) = 0.84;
// Half extent of the patch, as a fraction of the quad's own half size.
uniform float radius : hint_range(0.1, 1.0, 0.01) = 0.70;
// How far the border fades out, in the same units as radius.
uniform float edge_softness : hint_range(0.001, 0.5, 0.001) = 0.035;
// How much the noise is allowed to chew into the border.
uniform float edge_noise : hint_range(0.0, 0.5, 0.005) = 0.08;
// Noise frequency of that chewing, in cells.
uniform float edge_noise_scale : hint_range(0.5, 40.0, 0.5) = 6.0;
// Width of the darker rubble ring, measured inwards from the border.
uniform float rim_width : hint_range(0.0, 1.0, 0.01) = 0.13;

group_uniforms Surface;
// Frequency of the large tone variation, in cells.
uniform float blotch_scale : hint_range(0.5, 40.0, 0.5) = 3.0;
// Frequency of the slab lattice, in cells. Higher means smaller slabs.
uniform float crack_scale : hint_range(0.5, 40.0, 0.5) = 4.0;
uniform float crack_width : hint_range(0.0, 0.5, 0.005) = 0.09;
uniform float crack_strength : hint_range(0.0, 1.0, 0.01) = 0.35;
// Global fade, so a patch can be dialled back without touching its colours.
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 1.0;

group_uniforms Preview;
// Ghost colour washed over the stone while a build order is still being
// aimed: rgb is the colour, alpha how far to wash towards it. Alpha 0, the
// default, is an ordinary built patch.
//
// A plain uniform, NOT a per-instance one: the project renders with
// gl_compatibility, where instance uniforms do not exist. So the ghost gets
// a duplicate of this material to itself rather than an override on the
// shared one - see BuildingFoundation.
uniform vec4 preview_tint : source_color = vec4(0.0);

// World x/z of this fragment, the sampling space for every noise below.
varying vec2 world_pos;


float hash1(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}


vec2 hash2(vec2 p) {
	vec2 q = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(q) * 43758.5453);
}


float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 t = f * f * (3.0 - 2.0 * f);
	float a = hash1(cell);
	float b = hash1(cell + vec2(1.0, 0.0));
	float c = hash1(cell + vec2(0.0, 1.0));
	float d = hash1(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, t.x), mix(c, d, t.x), t.y);
}


/// Four octaves, enough for a surface this small on screen. Normalised back
/// to 0..1 by the total amplitude, so the result still averages 0.5 and a
/// smoothstep over it can be reasoned about rather than guessed at.
float fbm(vec2 p) {
	float sum = 0.0;
	float amplitude = 0.5;
	float total = 0.0;
	for (int i = 0; i < 4; i++) {
		sum += value_noise(p) * amplitude;
		total += amplitude;
		p *= 2.03;
		amplitude *= 0.5;
	}
	return sum / total;
}


/// Distance to the nearest border of a jittered point lattice. Straight
/// distance to the nearest point would give round blobs, so the second pass
/// measures against the midline between the winner and each neighbour, which
/// is what draws an even width crack between straight edged slabs.
float voronoi_edge(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);

	vec2 nearest_offset = vec2(0.0);
	vec2 nearest_site = vec2(0.0);
	float nearest = 8.0;

	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 offset = vec2(float(x), float(y));
			vec2 site = offset + hash2(cell + offset);
			float d = dot(f - site, f - site);
			if (d < nearest) {
				nearest = d;
				nearest_offset = offset;
				nearest_site = site;
			}
		}
	}

	float border = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 offset = nearest_offset + vec2(float(x), float(y));
			vec2 site = offset + hash2(cell + offset);
			vec2 diff = site - nearest_site;
			float len = length(diff);
			if (len > 0.0001) {
				border = min(border, dot(f - 0.5 * (site + nearest_site), diff / len));
			}
		}
	}
	return border;
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}


void fragment() {
	// Shape in local space so the patch is centred on the footprint, detail in
	// world space so no two patches look alike.
	vec2 p = UV * 2.0 - 1.0;
	float shape = mix(length(p), max(abs(p.x), abs(p.y)), squareness);
	shape += (fbm(world_pos * edge_noise_scale) - 0.5) * 2.0 * edge_noise;

	float mask = 1.0 - smoothstep(radius - edge_softness, radius + edge_softness, shape);

	float blotch = fbm(world_pos * blotch_scale);
	vec3 color = mix(stone_dark_color, stone_color, smoothstep(0.25, 0.75, blotch));

	float crack = 1.0 - smoothstep(0.0, crack_width, voronoi_edge(world_pos * crack_scale));
	color = mix(color, crack_color, crack * crack_strength);

	// Broken up towards the grass, so the border never reads as a cut edge.
	float rim = smoothstep(radius - rim_width, radius, shape);
	color = mix(color, rim_color, rim * 0.85);

	color = mix(color, preview_tint.rgb, preview_tint.a);

	ALBEDO = color;
	ALPHA = mask * opacity;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
