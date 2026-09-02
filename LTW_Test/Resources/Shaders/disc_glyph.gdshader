// The coloured heart of a technology disc: the top of its three layers, and
// the only one that differs between two discs.
//
// A PLAIN CIRCLE, and that is the rule rather than a placeholder waiting to be
// improved. Ten elements, ten colours, one shape. An earlier cut gave each
// element the side count its towers are built on - a four sided Ice, a five
// sided Earth - and it was dropped on review: a disc is the one thing in the
// game whose whole job is to be read at a glance in somebody's peripheral
// vision while they are looking at a creep wave, and asking the eye to count
// sides at that size is asking for something it will not do. Colour it can do
// instantly. So colour carries the element alone.
//
// SIZE IS NOT IN THIS SHADER. The tier is how big the circle is, and it is the
// MESH that is sized rather than a radius uniform here - which is what lets an
// upgrade grow the coloured part while the plate under it stays put. See
// disc_models.py and Disc._apply_visual_height.
//
// So there is one material per ELEMENT and not one per element and tier: every
// tier of Fire is the same orange circle at three sizes, which is exactly what
// an upgrade should look like.

shader_type spatial;
render_mode cull_disabled, depth_draw_never;

group_uniforms Glyph;
// The element's own lit colour, and the brighter tone its edge lights up in.
// Both come straight off style.ELEMENTS, so a Fire disc and a Fire tower
// cannot disagree about what Fire looks like.
uniform vec3 glyph_color : source_color = vec3(0.5, 0.5, 0.5);
uniform vec3 edge_color : source_color = vec3(0.9, 0.9, 0.9);
// How far out the circle reaches within its own quad. Left at 1 in practice:
// the quad IS the circle and the tier sizes the quad, so this is only here for
// trimming the soft border in without resizing the mesh.
uniform float radius : hint_range(0.1, 1.0, 0.01) = 0.94;
uniform float edge_softness : hint_range(0.001, 0.3, 0.001) = 0.05;
// Width of the lit rim around the circle, as a share of its own radius. A
// share rather than a fixed band so it grows with the tier instead of
// swallowing the smallest one whole.
uniform float rim_width : hint_range(0.0, 0.6, 0.01) = 0.22;
// How brightly it gives off its own light.
//
// LOW, and that is measured rather than chosen. Emission ADDS to albedo, so a
// figure near 1 pushes a saturated hue past white in its strongest channel and
// every element comes out the same pale yellow - which is exactly what the
// first cut of this roster did, and it cost the ten hues the whole reason they
// were chosen against each other.
uniform float emission_strength : hint_range(0.0, 4.0, 0.05) = 0.45;
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 0.95;


void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);

	float fill = 1.0 - smoothstep(radius - edge_softness, radius + edge_softness, r);
	// Measured inwards from the circle's own edge, so the rim is a proportion
	// of the glyph rather than a fixed band.
	float rim = smoothstep(radius - rim_width * radius, radius, r) * fill;

	vec3 color = mix(glyph_color, edge_color, rim);

	ALBEDO = color;
	EMISSION = color * fill * emission_strength;
	ALPHA = fill * opacity;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
