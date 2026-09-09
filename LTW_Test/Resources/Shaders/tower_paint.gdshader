// Painted board and dyed cloth: the small coloured detail that says which
// LINE a Basic tower belongs to and how far up its ladder it has climbed.
//
// The Basic roster carries no colour of its own - stone, timber and iron -
// because the ten ELEMENTS each own a hue and can only read as elements if the
// towers a player has been looking at since the first minute are not competing
// for the same signal. This is the deliberate, tiny exception: a shield board,
// a painted lintel, a pennant. See game_rules.md under Presentation.
//
// WHAT KEEPS IT FROM READING AS AN ELEMENT is not the hue, which is a battle
// this shader would lose - the ten elements between them cover very nearly the
// whole wheel. It is that AN ELEMENT IS LIT AND PAINT IS NOT. Every elemental
// accent goes through tower_energy.gdshader, which emits, pulses and surges;
// this is a matte surface sitting in the same light as the stone next to it,
// and it never moves. A deep blue pennant and an Ice tower's accent can share
// a hue and still never be confused, because one of them glows.
//
// So the two rules this file exists to keep are: NO EMISSION, EVER, and keep
// the saturation short of what the energy shader reaches. Both are enforced
// here rather than left to whoever writes the next material.

shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

group_uniforms Colors;
// The paint. Muted on purpose - see the note above.
uniform vec3 paint_color : source_color = vec3(0.34, 0.36, 0.52);
// Where it fades in the folds, in the weave and along a worn edge.
uniform vec3 paint_dark_color : source_color = vec3(0.18, 0.19, 0.29);

group_uniforms Cloth;
// Threads per world unit. High enough to read as fabric close up and to
// average out into a flat colour at match distance, which is what it should
// do - this is a detail, not a pattern.
uniform float weave_frequency : hint_range(0.0, 400.0, 1.0) = 150.0;
uniform float weave_strength : hint_range(0.0, 1.0, 0.01) = 0.18;
// How much the colour is scrubbed off the edges of the piece, which is what
// stops a flat quad reading as a decal.
uniform float wear_strength : hint_range(0.0, 1.0, 0.01) = 0.30;

group_uniforms Shading;
uniform float ambient_wrap : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform vec3 rim_color : source_color = vec3(1.00, 0.98, 0.92);
uniform float rim_strength : hint_range(0.0, 3.0, 0.05) = 0.45;
uniform float rim_power : hint_range(0.5, 8.0, 0.1) = 2.4;

group_uniforms Surface;
uniform float roughness_value : hint_range(0.0, 1.0, 0.01) = 0.92;


void fragment() {
	// LOCAL space, not world. A pennant is a small object that turns and bobs;
	// projected from the world its weave would slide across the cloth as it
	// moved, which is exactly the crawl the other three shaders use world
	// space to avoid on things that never move at all.
	vec2 uv = UV * weave_frequency;
	float warp = abs(fract(uv.x) - 0.5) * 2.0;
	float weft = abs(fract(uv.y) - 0.5) * 2.0;
	float weave = max(warp, weft);

	vec3 color = mix(paint_color, paint_dark_color, weave * weave_strength);

	// Worn at the edges of the piece, where a real flag frays and a real
	// painted board loses its paint first.
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	color = mix(paint_dark_color, color, smoothstep(0.0, 0.12, edge)
		* wear_strength + (1.0 - wear_strength));

	float up = NORMAL.y * 0.5 + 0.5;
	color = mix(color, mix(paint_dark_color, color, up), ambient_wrap);

	ALBEDO = color;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
	SPECULAR = 0.15;
}


void light() {
	float lambert = clamp(dot(NORMAL, LIGHT) * 0.5 + 0.5, 0.0, 1.0);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * lambert * (1.0 / PI);

	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	DIFFUSE_LIGHT += rim_color * rim * rim_strength * ATTENUATION * (1.0 / PI);
}
