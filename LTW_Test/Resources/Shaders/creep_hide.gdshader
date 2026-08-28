// The solid part of a creep: its hide, its bone, its bark, its wet mud.
//
// One shader and THREE materials per creep - base, deep and pale - the same
// three depths every tower body already uses. What is different is what the
// surface is PRETENDING to be, and that is the whole reason this is not
// tower_plating.gdshader with different numbers:
//
//   BANDING     rings ACROSS the body rather than seams stacked up a shaft.
//               On a limb they read as segments, on a flank as ribs, on a
//               shell as plating - and they are a soft sine rather than a hard
//               seam, because a creature has no panel gaps
//   SHEEN       a broad wrapped highlight towards the light, which is what
//               makes wool, chitin and wet mud read as a surface rather than
//               as painted cardboard. A tower does not want this: flat plate
//               is exactly what a tower is
//   NO METAL    hide is never metallic. A creep's hard parts - claws, horns,
//               plates, weapons - are separate geometry with the carapace
//               material on them, which is where all the metal in the roster
//               lives. See style.CREEP_CARAPACE_RAMP
//
// It keeps tower_plating's RIM LIGHT unchanged and for the same reason: from
// above, a faceted solid of one colour is a blob, and the rim is the line that
// lifts it off the ground. It is the single most important thing in either
// shader.
//
// OPAQUE, and that is a family rule rather than an oversight. The FLYING
// creeps are drawn with creep_vapour.gdshader instead, which is the
// translucent one - see style.py under CREEPS for why the material is one of
// the things that says which family a creep is in.
//
// TUNING BELONGS IN THE MATERIAL. Every uniform is a knob on the
// Resources/Materials/Creeps/*_hide.tres files, written by Tools/ModelGen.

shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

group_uniforms Colors;
// The bulk of the surface.
uniform vec3 hide_color : source_color = vec3(0.52, 0.48, 0.40);
// Banded into it, and what down-facing surfaces fall towards.
uniform vec3 hide_dark_color : source_color = vec3(0.30, 0.28, 0.22);

group_uniforms Banding;
// Bands per unit of length, in the model's own space. Rings around a limb.
uniform float band_frequency : hint_range(0.0, 40.0, 0.5) = 9.0;
uniform float band_strength : hint_range(0.0, 1.0, 0.01) = 0.30;
// Which local axis the bands run along. Y for a body or an upright limb, and
// the model's own author is the only one who knows - a creep laid along Z is
// a tail, and its bands should still ring it.
uniform vec3 band_axis = vec3(0.0, 1.0, 0.0);

group_uniforms Shading;
// How far down-facing surfaces darken, which is what keeps a faceted solid
// legible when the only light comes from more or less overhead. Higher than a
// tower's, because a creature is round and needs the falloff to say so.
uniform float ambient_wrap : hint_range(0.0, 1.0, 0.01) = 0.55;
// The broad soft highlight. Strength 0 turns it off, which is what dry cloth
// and wool want.
uniform float sheen_strength : hint_range(0.0, 2.0, 0.05) = 0.35;
// The outline. Strength 0 turns it off entirely.
uniform vec3 rim_color : source_color = vec3(0.96, 0.94, 0.88);
uniform float rim_strength : hint_range(0.0, 3.0, 0.05) = 0.70;
uniform float rim_power : hint_range(0.5, 8.0, 0.1) = 2.4;

group_uniforms Surface;
uniform float roughness_value : hint_range(0.0, 1.0, 0.01) = 0.82;

varying float band_position;


void vertex() {
	band_position = dot(VERTEX, normalize(band_axis));
}


void fragment() {
	// A sine rather than the plating shader's seam: the bands should swell and
	// fade the way ribs under skin do, not cut the surface into panels.
	float band = sin(band_position * band_frequency * 6.2831853) * 0.5 + 0.5;
	vec3 color = mix(hide_color, hide_dark_color, band * band_strength);

	// Down-facing surfaces towards the dark tone, so the shape survives a
	// mostly overhead light.
	float up = NORMAL.y * 0.5 + 0.5;
	color = mix(color, mix(hide_dark_color, color, up), ambient_wrap);

	ALBEDO = color;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
	SPECULAR = 0.25;
}


void light() {
	// Wrapped lambert rather than the plain one, so the side of a creep facing
	// away from the sun is shaded rather than black. A top down game shows a
	// lot of those sides at once.
	float lambert = clamp(dot(NORMAL, LIGHT) * 0.5 + 0.5, 0.0, 1.0);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * lambert * (1.0 / PI);

	// The sheen. A very wide, very weak specular lobe, added as diffuse so it
	// survives the compatibility renderer rather than being a hot dot.
	float sheen = pow(clamp(dot(NORMAL, normalize(LIGHT + VIEW)), 0.0, 1.0), 3.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * sheen * sheen_strength * ATTENUATION * (1.0 / PI);

	// The outline, added in the light pass so it is lit-space bright rather
	// than a flat wash over the albedo. This is the top down readability line.
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	DIFFUSE_LIGHT += rim_color * rim * rim_strength * ATTENUATION * (1.0 / PI);
}
