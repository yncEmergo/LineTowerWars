// Worldspace health bar drawn as a single quad.
//
// One quad rather than a green one layered over a red one: two overlapping
// transparent quads sort by camera distance, so which of them won depended on
// where the unit stood. Splitting the colour inside the fragment shader removes
// the ordering question entirely.

shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled;

// Filled proportion, 0 to 1.
uniform float ratio : hint_range(0.0, 1.0) = 1.0;
uniform vec4 fill_color : source_color = vec4(0.24, 0.80, 0.28, 1.0);
uniform vec4 missing_color : source_color = vec4(0.65, 0.13, 0.13, 1.0);


void vertex() {
	// Billboard: keep the quad's position but take the camera's orientation,
	// so the bar faces the player at any pitch.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
}


void fragment() {
	// UV.x runs 0 at the left edge to 1 at the right, so the split is the
	// ratio itself and the bar always empties rightwards.
	vec4 color = UV.x <= ratio ? fill_color : missing_color;
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
