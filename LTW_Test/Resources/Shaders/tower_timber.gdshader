// Timber: what a Basic tower is made of before it can afford stone.
//
// The other half of the pair with tower_masonry.gdshader - same three tone
// uniforms, same wrapped lambert, same rim light, and only the pattern
// differs. Read that file first; the reasoning about world space, about the
// tier ladder this replaces and about metallic under gl_compatibility is
// written out there and is not repeated here.
//
// WHAT MAKES A SURFACE READ AS WOOD is two things and they work at different
// distances. The PLANK SEAMS are the silhouette-scale signal: dark gaps at a
// regular pitch that break a post into boards, visible from the match camera.
// The GRAIN is the close-up one: streaks running along the plank's own length,
// which is what stops each board being a flat rectangle of colour. Neither
// alone reads; the seams without grain look like corrugation, and the grain
// without seams looks like dirt.
//
// PLANKS RUN THE WAY THE PART DOES. On an upright face the boards stand
// vertically and the grain runs up them, which is how a palisade, a post and a
// tower gallery are all built. On a face pointing up or down - a platform, a
// walkway, the top of a beam - they lie flat and run along x instead. Getting
// that wrong is what makes a wooden floor read as a wall lying down.

// The pattern is projected in the mesh's OWN space so it rides the model.
// tower_masonry.gdshader has the long version of why, and it matters: it was
// authored in world space first, and everything that moved slid through it.
// World height is still passed for the damp at the foot, which is a fact about
// the ground rather than about the model.

shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

group_uniforms Colors;
// The face of an average board.
uniform vec3 timber_color : source_color = vec3(0.55, 0.42, 0.28);
// What the seams, the grain, the shaded sides and the damp foot fall towards.
uniform vec3 timber_dark_color : source_color = vec3(0.30, 0.22, 0.14);
// The lightest a board gets. Boards are scattered between the dark tone and
// this, which is where nearly all of the life in a timber wall comes from -
// no two planks off the same tree are the same colour.
uniform vec3 timber_light_color : source_color = vec3(0.70, 0.56, 0.38);

group_uniforms Planks;
// Width of one board across the face, in world units. A player cell is 1.0.
uniform float plank_width : hint_range(0.02, 1.0, 0.005) = 0.09;
// Width of the dark seam between two boards, as a share of a board.
uniform float seam_width : hint_range(0.0, 0.4, 0.005) = 0.07;
// How dark that seam goes.
uniform float seam_strength : hint_range(0.0, 1.0, 0.01) = 0.75;
// How far apart the lightest and darkest boards are. 0 is one flat colour.
uniform float plank_variation : hint_range(0.0, 1.0, 0.01) = 0.42;

group_uniforms Grain;
// Streaks per world unit ALONG a board. High and thin reads as sawn timber;
// low and broad reads as a split log.
uniform float grain_frequency : hint_range(0.0, 120.0, 0.5) = 34.0;
uniform float grain_strength : hint_range(0.0, 1.0, 0.01) = 0.30;
// How much the grain wanders across the board rather than running dead
// straight. Straight grain reads as machined and is wrong for a palisade.
uniform float grain_wander : hint_range(0.0, 1.0, 0.01) = 0.35;

group_uniforms Weathering;
// World height below which the timber darkens, as if wet from the ground up.
// 0 turns it off.
uniform float damp_height : hint_range(0.0, 3.0, 0.01) = 0.26;
uniform float damp_strength : hint_range(0.0, 1.0, 0.01) = 0.38;

group_uniforms Shading;
uniform float ambient_wrap : hint_range(0.0, 1.0, 0.01) = 0.40;
uniform vec3 rim_color : source_color = vec3(1.00, 0.92, 0.78);
uniform float rim_strength : hint_range(0.0, 3.0, 0.05) = 0.55;
uniform float rim_power : hint_range(0.5, 8.0, 0.1) = 2.6;

group_uniforms Surface;
uniform float roughness_value : hint_range(0.0, 1.0, 0.01) = 0.80;
// Zero, for the reason written out in tower_masonry.gdshader.
uniform float metallic_value : hint_range(0.0, 1.0, 0.01) = 0.0;

// The mesh's own space, which is what the pattern is drawn in.
varying vec3 local_pos;
varying vec3 local_normal;
// World height, for the damp at the foot of a tower and nothing else.
varying float ground_height;


float hash11(float p) {
	return fract(sin(p * 78.233) * 43758.5453);
}


float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(41.7, 289.1))) * 43758.5453);
}


void vertex() {
	local_pos = VERTEX;
	// Passed from the vertex stage because fragment() cannot work it out:
	// Godot hands NORMAL to fragment() in VIEW space, and a view-space normal
	// turns with the camera - so the axis the pattern is projected onto would
	// change as the player rotates and the whole surface would crawl.
	local_normal = NORMAL;
	ground_height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}


void fragment() {
	vec3 n = normalize(local_normal);
	vec3 a = abs(n);

	// `across` runs the way the boards are counted, `along` runs down their
	// own length. On an upright face that is horizontal and vertical; on a
	// floor it is z and x, so the decking lies flat instead of standing up.
	float across = mix(local_pos.x, local_pos.z, step(a.z, a.x));
	float along = local_pos.y;
	if (a.y > max(a.x, a.z)) {
		across = local_pos.z;
		along = local_pos.x;
	}

	float plank = floor(across / plank_width);
	float plank_f = fract(across / plank_width);

	// The seam between two boards.
	float to_seam = 1.0 - abs(plank_f - 0.5) * 2.0;
	float seam = 1.0 - smoothstep(0.0, seam_width, to_seam);

	// This board's own colour, and its own phase down its length, so two
	// neighbours never share a grain pattern.
	float pick = hash11(plank);
	vec3 scattered = mix(timber_dark_color, timber_light_color, pick);
	vec3 color = mix(timber_color, scattered, plank_variation);

	// GRAIN. A stack of streaks along the board, pushed sideways by a slow
	// wave so they wander rather than running dead straight, plus a coarse
	// hashed break-up so they are not a clean sine.
	float wander = sin(along * 2.3 + pick * 19.0) * grain_wander * plank_width;
	float lines = sin((across + wander) * (grain_frequency / max(0.01,
		plank_width * 8.0)) + pick * 31.0);
	float fibres = hash21(vec2(plank, floor(along * grain_frequency * 0.5)));
	float grain = clamp(lines * 0.5 + 0.5, 0.0, 1.0) * 0.65 + fibres * 0.35;
	color = mix(color, timber_dark_color, grain * grain_strength);

	color = mix(color, timber_dark_color, seam * seam_strength);

	if (damp_height > 0.0) {
		float damp = 1.0 - smoothstep(0.0, damp_height, ground_height);
		color = mix(color, timber_dark_color, damp * damp_strength);
	}

	float up = n.y * 0.5 + 0.5;
	color = mix(color, mix(timber_dark_color, color, up), ambient_wrap);

	ALBEDO = color;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	SPECULAR = 0.3;
}


void light() {
	float lambert = clamp(dot(NORMAL, LIGHT) * 0.5 + 0.5, 0.0, 1.0);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * lambert * (1.0 / PI);

	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	DIFFUSE_LIGHT += rim_color * rim * rim_strength * ATTENUATION * (1.0 / PI);
}
