// Worked iron: the Cutter line's own material, and the blade on every tower
// in it.
//
// The third of the three Basic surfaces, with tower_timber and tower_masonry.
// The Cutter line skips timber entirely - it is machinery standing on a stone
// footing rather than carpentry - so this carries its whole body where the
// other two lines only use it for a blade, a band or a barrel hoop.
//
// THE HARD PART IS THAT METAL CANNOT BE MADE OF METAL HERE. Under
// gl_compatibility, with no reflection probes and no sky, a surface with
// METALLIC near 1 takes almost all of its colour from reflections that do not
// exist and renders BLACK - a trap already paid for once on the creep
// carapace. So the metal read is faked out of three things that cost nothing
// and need no environment:
//
//   BRUSHED STREAKS  fine lines along the part, which is the signal that says
//                    "this was machined" rather than "this was quarried"
//   A SHEEN BAND     one broad bright band that slides around the part with
//                    the surface angle, standing in for the horizon
//                    reflection a real metal would have
//   A HARD RIM       a tight, bright edge. Metal's giveaway is that its
//                    silhouette is brighter than its middle, and a narrow
//                    high rim_power says that where a wide soft one says
//                    "dusty stone"
//
// `polish` is the one knob the tier ladder turns: at 0 it is rough dark cast
// iron, at 1 it is bright worked steel. That is the Cutter line's whole tier
// tell, doing the job the timber-to-stone ramp does on the other two lines.

// The pattern is projected in the mesh's OWN space so it rides the model.
// tower_masonry.gdshader has the long version of why, and it matters: it was
// authored in world space first, and everything that moved slid through it.
// World height is still passed for the damp at the foot, which is a fact about
// the ground rather than about the model.

shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

group_uniforms Colors;
// The body of the metal.
uniform vec3 iron_color : source_color = vec3(0.42, 0.43, 0.46);
// Pitting, the shaded sides, and the bottom of every streak.
uniform vec3 iron_dark_color : source_color = vec3(0.19, 0.20, 0.23);
// The top of a streak and the colour of the sheen band.
uniform vec3 iron_light_color : source_color = vec3(0.72, 0.75, 0.80);

group_uniforms Finish;
// Rough cast iron at 0, worked steel at 1. Raises the sheen, tightens the
// streaks and lifts the whole surface towards the light tone. THE TIER KNOB.
uniform float polish : hint_range(0.0, 1.0, 0.01) = 0.35;
// Brushed lines per world unit along the part.
uniform float streak_frequency : hint_range(0.0, 300.0, 1.0) = 90.0;
uniform float streak_strength : hint_range(0.0, 1.0, 0.01) = 0.28;
// Casting pits and corrosion. Falls away as `polish` rises, so a Lesser tower
// is visibly rougher metal than an Ultimate rather than merely darker.
uniform float pitting : hint_range(0.0, 1.0, 0.01) = 0.35;

group_uniforms Sheen;
// How bright the band gets, and how broad it is. A narrow band reads as a
// polished cylinder; a broad one reads as brushed plate.
uniform float sheen_strength : hint_range(0.0, 2.0, 0.01) = 0.55;
uniform float sheen_width : hint_range(0.05, 4.0, 0.05) = 1.4;

group_uniforms Shading;
uniform float ambient_wrap : hint_range(0.0, 1.0, 0.01) = 0.34;
uniform vec3 rim_color : source_color = vec3(0.92, 0.96, 1.00);
uniform float rim_strength : hint_range(0.0, 3.0, 0.05) = 0.45;
// TIGHTER than the stone and timber shaders use, on purpose. A narrow bright
// edge is what separates metal from everything else at a glance.
uniform float rim_power : hint_range(0.5, 8.0, 0.1) = 4.2;

group_uniforms Surface;
uniform float roughness_value : hint_range(0.0, 1.0, 0.01) = 0.42;
// Deliberately well below 1 whatever the finish is. See the note at the top.
uniform float metallic_value : hint_range(0.0, 1.0, 0.01) = 0.35;

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

	// Streaks run the long way of the part: up a housing or a post, and
	// across a plate that is lying flat.
	float across = mix(local_pos.x, local_pos.z, step(a.z, a.x));
	float along = local_pos.y;
	if (a.y > max(a.x, a.z)) {
		across = local_pos.x;
		along = local_pos.z;
	}

	// A LIGHT TOUCH. Polishing lifts the whole surface towards the light
	// tone, and at 0.45 an Ultimate's blade came out nearly white - the
	// polish, the sheen band and the rim all pulling the same way at once
	// on a model that is mostly facets pointing away from the camera.
	vec3 base = mix(iron_color, iron_light_color, polish * 0.2);

	// BRUSHED STREAKS. Hashed rather than a sine, so they are irregular the
	// way a ground finish is; a clean wave reads as ribbing, not as brushing.
	float lane = floor(across * streak_frequency * mix(0.6, 1.6, polish));
	float streak = hash21(vec2(lane, floor(along * 3.0)));
	vec3 color = mix(base, mix(iron_dark_color, iron_light_color, streak),
		streak_strength);

	// CASTING PITS, and they go away as the metal is worked.
	float pits = hash21(floor(vec2(across, along) * 60.0));
	float rough = pitting * (1.0 - polish);
	color = mix(color, iron_dark_color, step(0.82, pits) * rough);

	// THE SHEEN BAND. Keyed off how far the surface leans from vertical, so it
	// slides around a drum and sits as one broad stripe on a flat plate -
	// which is what the missing horizon reflection would have done.
	float lean = 1.0 - abs(n.y);
	float band = exp(-pow((lean - 0.55) * sheen_width * 4.0, 2.0));
	color += iron_light_color * band * sheen_strength * mix(0.35, 1.0, polish);

	float up = n.y * 0.5 + 0.5;
	color = mix(color, mix(iron_dark_color, color, up), ambient_wrap);

	ALBEDO = clamp(color, vec3(0.0), vec3(1.0));
	ROUGHNESS = mix(roughness_value, roughness_value * 0.35, polish);
	METALLIC = metallic_value;
	SPECULAR = mix(0.45, 0.85, polish);
}


void light() {
	float lambert = clamp(dot(NORMAL, LIGHT) * 0.5 + 0.5, 0.0, 1.0);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * lambert * (1.0 / PI);

	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	DIFFUSE_LIGHT += rim_color * rim * rim_strength * mix(0.6, 1.0, polish)
		* ATTENUATION * (1.0 / PI);
}
