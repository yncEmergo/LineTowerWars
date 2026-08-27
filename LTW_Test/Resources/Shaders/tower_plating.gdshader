// The solid part of a tower: its plinth, its shaft, its housing, its barrel.
//
// One shader and THREE materials for every tower body in the game, one per
// line - steel for Archer, rust for Cutter, obsidian for Sentry. Nothing here
// knows about tiers. A tower's tier is carried by its TRIM METAL, which is
// separate geometry with its own material, the way an artist would build it
// rather than as a band painted on by a shader.
//
// It exists because a flat StandardMaterial3D loses a top down tower. Seen
// from above, a faceted solid of one colour is a blob: every facet points away
// from the camera and the only thing separating the tower from the ground is
// its shadow. Two cheap tricks fix that and they are both here:
//
//   PANEL LINES   dark seams at fixed heights in the model's own space, so a
//                 shaft reads as stacked segments rather than as one pole
//   RIM LIGHT     a bright edge wherever the surface turns away from the
//                 camera, which from above is exactly the tower's outline.
//                 This is the line that lifts it off the ground
//
// Lit, unlike the energy accents: this is a surface, so it belongs in the same
// light as everything else on the field.
//
// TUNING BELONGS IN THE MATERIAL. Every uniform is a knob on the
// Resources/Materials/Towers/*_plate.tres files; the values here are only what
// a fresh material starts from.

shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

group_uniforms Colors;
// The bulk of the surface.
uniform vec3 plate_color : source_color = vec3(0.29, 0.36, 0.45);
// Streaked into it, and what down-facing surfaces fall towards.
uniform vec3 plate_dark_color : source_color = vec3(0.15, 0.20, 0.27);

group_uniforms Panels;
// Panel seams per unit of height, in the model's own space.
uniform float panel_frequency : hint_range(0.0, 40.0, 0.5) = 7.0;
uniform float panel_width : hint_range(0.0, 0.5, 0.005) = 0.06;
uniform float panel_strength : hint_range(0.0, 1.0, 0.01) = 0.35;

group_uniforms Shading;
// How far down-facing surfaces darken, which is what keeps a faceted solid
// legible when the only light comes from more or less overhead.
uniform float ambient_wrap : hint_range(0.0, 1.0, 0.01) = 0.40;
// The outline. Strength 0 turns it off entirely.
uniform vec3 rim_color : source_color = vec3(0.72, 0.84, 0.98);
uniform float rim_strength : hint_range(0.0, 3.0, 0.05) = 0.60;
uniform float rim_power : hint_range(0.5, 8.0, 0.1) = 2.6;

group_uniforms Surface;
uniform float roughness_value : hint_range(0.0, 1.0, 0.01) = 0.62;
uniform float metallic_value : hint_range(0.0, 1.0, 0.01) = 0.15;

varying float local_height;


void vertex() {
	local_height = VERTEX.y;
}


void fragment() {
	// fract of the height gives evenly stacked segments; the distance to the
	// nearest seam between them is the panel line.
	float seam = abs(fract(local_height * panel_frequency) - 0.5) * 2.0;
	float panel = 1.0 - smoothstep(1.0 - panel_width * 2.0, 1.0, seam);

	vec3 color = mix(plate_color, plate_dark_color, panel * panel_strength);

	// Down-facing surfaces towards the dark tone, so the shape survives a
	// mostly overhead light.
	float up = NORMAL.y * 0.5 + 0.5;
	color = mix(color, mix(plate_dark_color, color, up), ambient_wrap);

	ALBEDO = color;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	SPECULAR = 0.4;
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
