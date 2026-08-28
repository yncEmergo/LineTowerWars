// What a FLYING creep is made of. The one translucent surface in the game.
//
// It exists because the flying family needs a tell that survives a top down
// camera, and altitude does not: from above, a Shade hanging at cruising
// height and a Shade standing on the floor are the same picture. So flying is
// said three ways at once and this shader is one of them - the creep is
// VAPOUR, it has NO LEGS, and it hangs over a shadow disc pinned to the ground
// beneath it. See style.py under CREEPS.
//
// FRESNEL OPACITY is the whole trick. A ghost drawn at a flat 50% alpha reads
// as a solid model somebody forgot to finish; a ghost that is nearly clear
// where it faces you and nearly solid at its edges reads as a hollow shell of
// smoke. Same geometry, and the difference is one dot product.
//
// It is UNLIT, unlike creep_hide.gdshader, because vapour has no surface to
// catch the sun on - and because an unlit body is the second half of what
// separates a flyer from the pale robed creeps that walk.
//
// Deliberately a SEPARATE file from creep_hide rather than an `alpha` uniform
// on it. A blend_mix material is sorted per object and writes no depth,
// whether or not its alpha happens to be 1 - so a single shader would have put
// every walking creep in the transparent pass to buy translucency for one of
// them.

shader_type spatial;
render_mode cull_back, blend_mix, depth_draw_never, unshaded, shadows_disabled;

group_uniforms Colors;
// The bulk of the vapour.
uniform vec3 vapour_color : source_color = vec3(0.62, 0.66, 0.74);
// What the parts facing the camera fall towards as they thin out.
uniform vec3 vapour_deep_color : source_color = vec3(0.40, 0.44, 0.52);
// The lit edge. A ghost is brightest exactly where it is most solid.
uniform vec3 rim_color : source_color = vec3(0.90, 0.95, 1.00);

group_uniforms Opacity;
// How visible the parts facing straight at the camera are.
uniform float face_alpha : hint_range(0.0, 1.0, 0.01) = 0.22;
// How visible the silhouette is. This is what the player actually sees.
uniform float edge_alpha : hint_range(0.0, 1.0, 0.01) = 0.92;
// How sharply one becomes the other. Higher keeps the body clear and lights
// only a thin rind.
uniform float edge_power : hint_range(0.5, 8.0, 0.1) = 2.2;
// Scales the whole thing, so a wisp can be authored fainter than the body it
// trails from without needing its own colours.
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 1.0;

group_uniforms Banding;
// Bands per unit of length, in the model's own space, drifting UPWARDS over
// time - the one piece of motion in here, and it is what stops a hovering
// ghost reading as a frozen prop. Set strength to 0 for a still one.
uniform float band_frequency : hint_range(0.0, 40.0, 0.5) = 6.0;
uniform float band_strength : hint_range(0.0, 1.0, 0.01) = 0.25;
uniform float band_drift : hint_range(-2.0, 2.0, 0.05) = 0.35;

varying float band_position;


void vertex() {
	band_position = VERTEX.y;
}


void fragment() {
	float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), edge_power);

	float band = sin((band_position - TIME * band_drift)
		* band_frequency * 6.2831853) * 0.5 + 0.5;
	vec3 body = mix(vapour_deep_color, vapour_color, band * band_strength + 0.5);

	ALBEDO = mix(body, rim_color, edge);
	ALPHA = mix(face_alpha, edge_alpha, edge) * opacity;
}
