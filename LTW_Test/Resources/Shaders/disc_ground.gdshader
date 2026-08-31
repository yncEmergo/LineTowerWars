// A technology disc: the whole unit, painted onto the floor.
//
// A disc has no model at all and never will have. It is a thing set INTO the
// ground rather than built on top of it, creeps walk straight over one, and a
// top down camera would see almost nothing of a raised shape anyway - so the
// floor patch IS the unit, and this one shader draws both halves of it.
//
//   THE PLATE, in stone, identical on all thirty-one discs. It is the disc's
//   equivalent of building_foundation.gdshader and it is deliberately a
//   DIFFERENT PATTERN from that one: the tower's patch is a rounded square of
//   cracked slabs, this is a true circle cut with concentric rings and radial
//   spokes. A player glancing at a maze has to be able to tell which squares
//   are towers and which are discs, and the shape of the ground is the only
//   thing either of them has to say it with
//
//   THE GLYPH, in the element's own colour, and the only part that changes.
//   Its RADIUS is the tier: the base disc has none at all, and each of the two
//   upgrades grows it. Its SIDE COUNT is the element, the same count that
//   element's towers are built on, so the disc roster answers "which element"
//   on the two axes the tower roster already uses - colour first, shape second
//   - and stays readable to somebody who cannot tell the ten hues apart
//
// Everything is procedural and there is no texture anywhere in the project.
// The stone tone is sampled in WORLD space so neighbouring discs never show
// the same blotches; the rings, the spokes and the glyph are sampled in UV
// space so they stay centred on the disc's own cell whatever its position.
//
// TUNING BELONGS IN THE MATERIAL. Every uniform below is a knob on one of the
// generated materials in Resources/Materials/Discs, and those are written by
// Tools/ModelGen - so a change worth keeping goes in disc_models.py, not here
// and not in a .tres. The values here are only the fallback a fresh material
// would start from.
//
// Draw order matches the tower foundation exactly: the zone quads are opaque
// and go first, this is transparent at render_priority -1, and the build grid
// is transparent at 0, so the grid lines stay readable across a disc.

shader_type spatial;
render_mode cull_disabled, depth_draw_never;

group_uniforms Plate;
// Lit stone tone, the bulk of the plate.
uniform vec3 plate_color : source_color = vec3(0.62, 0.60, 0.56);
// Weathered tone the blotch noise mixes towards.
uniform vec3 plate_dark_color : source_color = vec3(0.44, 0.42, 0.39);
// Lines cut into the plate: the concentric rings and the radial spokes.
uniform vec3 groove_color : source_color = vec3(0.25, 0.24, 0.22);
// Worn band where the plate meets the grass.
uniform vec3 rim_color : source_color = vec3(0.30, 0.28, 0.25);
// Half extent of the plate, as a fraction of the quad's own half size.
uniform float radius : hint_range(0.1, 1.0, 0.01) = 0.68;
// How far the border fades out, in the same units as radius.
uniform float edge_softness : hint_range(0.001, 0.5, 0.001) = 0.03;
// How much noise is allowed to chew into that border. Much less than a tower
// patch is given: a disc is a MADE object set into the ground, so its outline
// stays a circle where a tower's concrete is allowed to crumble.
uniform float edge_noise : hint_range(0.0, 0.5, 0.005) = 0.025;
uniform float edge_noise_scale : hint_range(0.5, 40.0, 0.5) = 7.0;
// Width of the worn band, measured inwards from the border.
uniform float rim_width : hint_range(0.0, 1.0, 0.01) = 0.10;
// Frequency of the large tone variation, in cells.
uniform float blotch_scale : hint_range(0.5, 40.0, 0.5) = 3.5;

group_uniforms Grooves;
// How many concentric rings are cut into the plate.
uniform float ring_count : hint_range(0.0, 12.0, 1.0) = 3.0;
uniform float ring_width : hint_range(0.0, 0.2, 0.002) = 0.028;
// How many spokes run out from the centre. 0 for none.
uniform float spoke_count : hint_range(0.0, 24.0, 1.0) = 8.0;
uniform float spoke_width : hint_range(0.0, 0.5, 0.005) = 0.05;
uniform float groove_strength : hint_range(0.0, 1.0, 0.01) = 0.55;

group_uniforms Glyph;
// The element's colour, and the brighter tone its edge lights up in.
uniform vec3 glyph_color : source_color = vec3(0.5, 0.5, 0.5);
uniform vec3 glyph_edge_color : source_color = vec3(0.9, 0.9, 0.9);
// How far out the coloured part reaches. THE TIER, and 0 on a base disc,
// which draws no glyph at all.
uniform float glyph_radius : hint_range(0.0, 1.0, 0.01) = 0.0;
// How many sides the glyph has, matching this element's towers. 0 is a circle.
uniform float glyph_sides : hint_range(0.0, 12.0, 1.0) = 6.0;
uniform float glyph_softness : hint_range(0.001, 0.3, 0.001) = 0.02;
// Width of the lit rim around the glyph, inwards from its own edge.
uniform float glyph_edge_width : hint_range(0.0, 0.5, 0.005) = 0.10;
// How brightly the glyph gives off its own light.
uniform float glyph_emission : hint_range(0.0, 4.0, 0.05) = 1.1;
// Turns per second. Nonzero on the ULTIMATE tier and nowhere else - motion is
// the loudest signal a top down camera has, so it stays reserved for the top
// rung exactly as it is on the elemental towers. See style.py.
uniform float spin_speed : hint_range(-2.0, 2.0, 0.01) = 0.0;

group_uniforms Surface;
// How solid the stone plate is. Kept low, like the tower foundation it sits
// beside: both are ground rather than objects, and a fully opaque patch reads
// as a sticker laid over the grass.
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 0.45;
// How solid the GLYPH is, and deliberately much higher.
//
// Two figures rather than one because the two halves are different things: the
// plate is ground and wants to sink into it, and the glyph is the unit and has
// to be the thing a player picks out of a maze. One shared opacity would make
// whichever of those mattered more the one that lost.
uniform float glyph_opacity : hint_range(0.0, 1.0, 0.01) = 0.95;

group_uniforms Preview;
// Ghost colour washed over the whole disc while a build order is still being
// aimed: rgb is the colour, alpha how far to wash towards it.
//
// The SAME uniform name the tower foundation uses, which is what lets a disc
// reuse BuildingFoundation.gd unchanged - see that script, and note that this
// is a plain uniform rather than a per-instance one because the project renders
// with gl_compatibility, where instance uniforms silently do nothing.
uniform vec4 preview_tint : source_color = vec4(0.0);

varying vec2 world_pos;


float hash1(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
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


/// Four octaves, normalised back to 0..1 so a smoothstep over it can be
/// reasoned about rather than guessed at. The same one the tower foundation
/// uses, deliberately: the two patches are different PATTERNS and the same
/// stone, so a maze reads as one floor.
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


/// Distance from the centre to the edge of a regular polygon, in the direction
/// of p. Answers 1.0 for `sides` of 0, which is a circle.
///
/// This is what makes the glyph carry the element on a second axis. The count
/// is the same one that element's towers are built on, so a colourblind player
/// reads a five sided Earth disc against a four sided Ice one exactly as they
/// read the towers.
float polygon_distance(vec2 p, float sides) {
	float r = length(p);
	if (sides < 3.0 || r < 0.0001) {
		return r;
	}
	float segment = 6.28318530718 / sides;
	float angle = atan(p.y, p.x);
	// Fold the direction into one wedge, then measure across that wedge's flat
	// edge rather than to its corner.
	float folded = mod(angle + segment * 0.5, segment) - segment * 0.5;
	return r * cos(folded) / cos(segment * 0.5);
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}


void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);

	// --- the plate -------------------------------------------------------
	float edge = r + (fbm(world_pos * edge_noise_scale) - 0.5) * 2.0 * edge_noise;
	float mask = 1.0 - smoothstep(radius - edge_softness, radius + edge_softness, edge);

	float blotch = fbm(world_pos * blotch_scale);
	vec3 color = mix(plate_dark_color, plate_color, smoothstep(0.25, 0.75, blotch));

	// Rings, evenly spaced out to the plate's own border so a disc reads as one
	// object however its radius is tuned.
	float rings = 0.0;
	if (ring_count > 0.5) {
		float spacing = radius / (ring_count + 1.0);
		float phase = abs(fract(r / spacing) - 0.5) * spacing;
		rings = 1.0 - smoothstep(0.0, ring_width, phase);
	}

	// Spokes, faded out towards the centre so they meet at a hub rather than
	// collapsing into a smudge.
	float spokes = 0.0;
	if (spoke_count > 0.5) {
		float segment = 6.28318530718 / spoke_count;
		float angle = atan(p.y, p.x);
		float across = abs(mod(angle + segment * 0.5, segment) - segment * 0.5) * r;
		spokes = (1.0 - smoothstep(0.0, spoke_width * 0.5, across))
			* smoothstep(0.0, radius * 0.35, r);
	}
	color = mix(color, groove_color, max(rings, spokes) * groove_strength);

	float rim = smoothstep(radius - rim_width, radius, r);
	color = mix(color, rim_color, rim * 0.8);

	// --- the glyph -------------------------------------------------------
	vec3 emission = vec3(0.0);
	float solidity = opacity;
	if (glyph_radius > 0.001) {
		float turn = TIME * spin_speed * 6.28318530718;
		float ca = cos(turn);
		float sa = sin(turn);
		vec2 g = vec2(p.x * ca - p.y * sa, p.x * sa + p.y * ca);

		float shape = polygon_distance(g, glyph_sides);
		float fill = 1.0 - smoothstep(glyph_radius - glyph_softness,
			glyph_radius + glyph_softness, shape);
		// The lit rim is measured inwards from the glyph's own edge, so it
		// grows with the glyph rather than staying a fixed band that would
		// swallow a small one whole.
		float lip = smoothstep(glyph_radius - glyph_edge_width * glyph_radius,
			glyph_radius, shape) * fill;

		vec3 lit = mix(glyph_color, glyph_edge_color, lip);
		color = mix(color, lit, fill);
		emission = lit * fill * glyph_emission;
		solidity = mix(opacity, glyph_opacity, fill);
	}

	color = mix(color, preview_tint.rgb, preview_tint.a);
	// A ghost is one flat colour, glyph included: it is showing WHERE the disc
	// would go, and a lit element under a red refusal would read as a disc that
	// is already there.
	emission = mix(emission, vec3(0.0), preview_tint.a);

	ALBEDO = color;
	EMISSION = emission;
	ALPHA = mask * solidity;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
