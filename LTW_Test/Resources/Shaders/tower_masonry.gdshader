// Dressed stone: the material the Basic tower roster climbs INTO.
//
// A Basic tower starts as timber and turns to masonry as it is upgraded (see
// game_rules.md under Presentation), so this and tower_timber.gdshader are one
// pair and share their whole structure - the same three tone uniforms, the
// same wrapped lambert, the same rim light. Only the pattern differs.
//
// It replaces the metal trim ring that used to carry a Basic tower's tier. A
// ring reads instantly, which is exactly why it was a bad thing to spend a
// ladder on: put one on every tower and the ring is what a player sees first
// on all of them. What a tier is read off now is the tower's own material,
// which is the fix the ELEMENTAL roster already made for the same problem.
//
// WHY THE PATTERN IS IN LOCAL SPACE, which is the one real decision in here
// and was got WRONG first time round.
//
// It was authored in WORLD space, for two real benefits: stone courses ran
// continuously through a tower's separate meshes instead of restarting at each
// join, and two towers side by side got different block phases for free,
// without a per-instance uniform that gl_compatibility does not have.
//
// Both of those are worth less than the thing they cost. A world-projected
// pattern is nailed to the GROUND, not to the model - so anything that moves
// slides through it. The saw was the obvious case, spinning inside a stationary
// grain like a disc behind a dirty window, but it was wrong on every aiming
// turret, every recoiling barrel and the Stomper's falling weight too.
//
// So the pattern is projected in the mesh's OWN space and rides it. What is
// given up is continuity across parts, which turns out to be nearly free: the
// two halves of a shaft are DIFFERENT MATERIALS anyway - that is the whole
// point of them - so there was never a course to carry across the join.
//
// WORLD HEIGHT IS STILL PASSED, for one thing only: the damp at the foot of a
// tower is a fact about the GROUND, and every tower in a maze should weather to
// the same line whatever height its own meshes are authored at.
//
// RUNNING BOND: each course is offset by a hashed fraction of a block, so the
// vertical joints never line up between neighbouring courses. Stacked joints
// are the single thing that makes a stone wall read as a printed texture.
//
// TUNING BELONGS IN THE MATERIAL. Every uniform is a knob on the
// Resources/Materials/Towers/*_masonry*.tres files, which the generator
// writes; the values here are only what a fresh material starts from.

shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

group_uniforms Colors;
// The face of an average block.
uniform vec3 stone_color : source_color = vec3(0.60, 0.59, 0.56);
// What the mortar, the shaded sides and the weathered base fall towards.
uniform vec3 stone_dark_color : source_color = vec3(0.34, 0.33, 0.31);
// The brightest a lucky block gets. Blocks are scattered between the dark tone
// and this, which is where nearly all of the life in a stone wall comes from.
uniform vec3 stone_light_color : source_color = vec3(0.74, 0.73, 0.69);

group_uniforms Blocks;
// Height of one course, in world units. A player cell is 1.0, so 0.11 gives
// roughly nine courses per cell of height.
uniform float course_height : hint_range(0.02, 1.0, 0.005) = 0.11;
// Length of one block along the face, in world units.
uniform float block_length : hint_range(0.05, 2.0, 0.005) = 0.19;
// Width of the mortar joint as a share of a course. Wider reads as rougher,
// older work; narrower reads as dressed ashlar.
uniform float joint_width : hint_range(0.0, 0.4, 0.005) = 0.055;
// How dark the mortar goes against the block face.
uniform float joint_strength : hint_range(0.0, 1.0, 0.01) = 0.7;
// How far apart the lightest and darkest blocks are. 0 is one flat colour.
uniform float block_variation : hint_range(0.0, 1.0, 0.01) = 0.55;
// How much a block's face is chipped and mottled within itself.
uniform float block_grain : hint_range(0.0, 1.0, 0.01) = 0.22;

group_uniforms Weathering;
// World height below which the stone darkens towards the dark tone, as if
// damp. 0 turns it off. This is what stops a tall tower reading as one flat
// slab from the ground to its parapet.
uniform float damp_height : hint_range(0.0, 3.0, 0.01) = 0.34;
uniform float damp_strength : hint_range(0.0, 1.0, 0.01) = 0.42;

group_uniforms Shading;
// How far down-facing surfaces darken, which is what keeps a faceted solid
// legible when the only light comes from more or less overhead.
uniform float ambient_wrap : hint_range(0.0, 1.0, 0.01) = 0.40;
// The outline. Strength 0 turns it off entirely.
uniform vec3 rim_color : source_color = vec3(0.92, 0.92, 0.88);
uniform float rim_strength : hint_range(0.0, 3.0, 0.05) = 0.55;
uniform float rim_power : hint_range(0.5, 8.0, 0.1) = 2.6;

group_uniforms Surface;
uniform float roughness_value : hint_range(0.0, 1.0, 0.01) = 0.86;
// Kept at zero on purpose. Under gl_compatibility, with no reflection probes
// and no sky, a metallic surface takes almost all its colour from reflections
// it does not have and renders BLACK. Stone wants none of it anyway.
uniform float metallic_value : hint_range(0.0, 1.0, 0.01) = 0.0;

// The mesh's own space, which is what the pattern is drawn in.
varying vec3 local_pos;
varying vec3 local_normal;
// World height, for the damp at the foot of a tower and nothing else.
varying float ground_height;


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

	// Which way this face looks, and therefore which world axis runs ALONG it.
	// A wall facing x is coursed along z and the other way about; a face
	// pointing up or down is paving rather than walling and is coursed on x.
	float u = mix(local_pos.x, local_pos.z, step(a.z, a.x));
	float v = local_pos.y;
	if (a.y > max(a.x, a.z)) {
		u = local_pos.x;
		v = local_pos.z;
	}

	// The course this fragment is in, and how far up that course it sits.
	float course = floor(v / course_height);
	float course_f = fract(v / course_height);

	// RUNNING BOND. Each course slides along by a hashed fraction of a block,
	// so vertical joints never stack - which is the one thing that makes a
	// stone wall read as a printed pattern rather than as masonry.
	float bond = hash21(vec2(course, 7.3)) * block_length;
	float block = floor((u + bond) / block_length);
	float block_f = fract((u + bond) / block_length);

	// Distance to the nearest joint on each axis, as 0 at the joint and 1 in
	// the middle of a block face. The vertical joint's width is converted into
	// block lengths so a joint is the same real thickness both ways round.
	float to_course = 1.0 - abs(course_f - 0.5) * 2.0;
	float to_block = 1.0 - abs(block_f - 0.5) * 2.0;
	float across = joint_width * course_height / max(0.0001, block_length);
	float joint = 1.0 - min(smoothstep(0.0, joint_width, to_course),
		smoothstep(0.0, across, to_block));

	// This block's own value, so no two neighbours are quite the same stone.
	float pick = hash21(vec2(block, course));
	vec3 scattered = mix(stone_dark_color, stone_light_color, pick);
	vec3 color = mix(stone_color, scattered, block_variation);

	// Chipping and mottle WITHIN one block, keyed off the block's own pick so
	// it cannot swim across a joint into its neighbour.
	float grain = hash21(floor(vec2(u, v) * 37.0) + pick * 13.0);
	color = mix(color, stone_dark_color, grain * block_grain * 0.5);

	color = mix(color, stone_dark_color, joint * joint_strength);

	// Damp at the foot of the tower. Absolute world height, so every tower in
	// a maze weathers to the same line and it reads as the ground doing it
	// rather than as a property of one model.
	if (damp_height > 0.0) {
		float damp = 1.0 - smoothstep(0.0, damp_height, ground_height);
		color = mix(color, stone_dark_color, damp * damp_strength);
	}

	// Down-facing surfaces towards the dark tone, so the shape survives a
	// mostly overhead light.
	float up = n.y * 0.5 + 0.5;
	color = mix(color, mix(stone_dark_color, color, up), ambient_wrap);

	ALBEDO = color;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	SPECULAR = 0.25;
}


void light() {
	// Wrapped lambert rather than the plain one, so the side of a tower facing
	// away from the sun is shaded rather than black. A top down game shows a
	// lot of those sides at once.
	float lambert = clamp(dot(NORMAL, LIGHT) * 0.5 + 0.5, 0.0, 1.0);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * lambert * (1.0 / PI);

	// The outline, added in the light pass so it is lit-space bright rather
	// than a flat wash over the albedo. This is the top down readability line.
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	DIFFUSE_LIGHT += rim_color * rim * rim_strength * ATTENUATION * (1.0 / PI);
}
