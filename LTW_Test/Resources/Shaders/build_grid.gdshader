// Grid overlay for the buildable zone.
//
// Simplified from "The Best Darn Grid Shader (Yet)" by Ben Golus:
// https://godotshaders.com/shader/the-best-darn-grid-shader-yet-for-godot/
//
// Line width is derived from screen-space UV derivatives, so lines stay the
// same visual thickness at any camera distance or angle, never alias, and
// never disappear when minified. Only one line thickness is used, since the
// player never sees internal half cells.

shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

// How many cells the quad is divided into. Set from GameConfig at runtime.
uniform vec2 cell_count = vec2(8.0, 30.0);
// Line thickness as a fraction of one cell.
uniform float line_width : hint_range(0.001, 0.5, 0.001) = 0.04;
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 0.35);


float pristine_grid(vec2 uv, float width) {
	vec2 ddx = dFdx(uv);
	vec2 ddy = dFdy(uv);
	vec2 uv_deriv = vec2(length(vec2(ddx.x, ddy.x)), length(vec2(ddx.y, ddy.y)));

	vec2 target_width = vec2(width);
	// Never let a line render thinner than one pixel, or it starts to shimmer.
	vec2 draw_width = clamp(target_width, uv_deriv, vec2(0.5));
	vec2 line_aa = uv_deriv * 1.5;

	vec2 grid_uv = 1.0 - abs(fract(uv) * 2.0 - 1.0);
	vec2 grid = smoothstep(draw_width + line_aa, draw_width - line_aa, grid_uv);

	// Compensate for the widening above, then fade towards a flat average
	// once cells get too small to resolve.
	grid *= clamp(target_width / draw_width, 0.0, 1.0);
	grid = mix(grid, target_width, clamp(uv_deriv * 2.0 - 1.0, 0.0, 1.0));

	return mix(grid.x, 1.0, grid.y);
}


void fragment() {
	float grid = pristine_grid(UV * cell_count, line_width);
	ALBEDO = line_color.rgb;
	ALPHA = grid * line_color.a;
}
