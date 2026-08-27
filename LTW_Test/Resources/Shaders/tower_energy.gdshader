// The lit part of a tower: its crystal, its vents, its charge rings.
//
// One shader for every tower in the game, and the whole tier ladder is a
// single uniform. A Lesser Archer and an Ultimate Watch Tower are the same
// material with `tier` set differently: the accent gets brighter, its pulse
// gets faster and deeper, and from the upper tiers a band of light climbs the
// piece. That is the point - "how strong is this tower" has to be readable
// from a top down camera at a glance, and colour intensity survives that
// distance where added geometry does not.
//
// UNSHADED on purpose. This is emitted light, not a lit surface, so it must
// not dim when a tower stands in shadow, and the project renders with
// gl_compatibility where there is no dependable bloom to lean on. Everything
// here therefore has to read from the albedo alone.
//
// Per-instance uniforms do NOT exist under gl_compatibility, which is why tier
// is a plain uniform and there is one material per line and tier rather than
// one material with an override per tower. Same reason the foundation shader
// gives its preview ghost a duplicated material.
//
// TUNING BELONGS IN THE MATERIAL. Every uniform below is a knob on the
// Resources/Materials/Towers/energy_*.tres files; the values here are only
// what a fresh material starts from.

shader_type spatial;
render_mode unshaded, cull_back;

group_uniforms Color;
// The accent's own colour, which is the LINE's identity: cyan for Archer,
// ember for Cutter, violet for Sentry.
uniform vec3 glow_color : source_color = vec3(0.37, 0.88, 1.0);
// What it falls back to at the bottom of a pulse. Kept as its own colour
// rather than a multiply, so a dim accent can shift hue as it cools.
uniform vec3 dim_color : source_color = vec3(0.10, 0.22, 0.30);

group_uniforms Tier;
// Where this tower sits on the six step price ladder, 0 for a 10 gold tower
// and 1 for a 25,000 gold one. Everything below scales off it, so ONE number
// moves the whole look up a tier.
uniform float tier : hint_range(0.0, 1.0, 0.01) = 0.0;
// Brightness at the bottom and the top of the ladder. The top goes above 1 so
// the ultimate tiers clip white at their peak, which is what makes them read
// as overloaded rather than merely brighter.
uniform float min_brightness : hint_range(0.0, 4.0, 0.05) = 0.55;
uniform float max_brightness : hint_range(0.0, 4.0, 0.05) = 2.30;

group_uniforms Pulse;
// Pulses per second at the bottom and the top of the ladder.
uniform float min_pulse_speed : hint_range(0.0, 12.0, 0.05) = 0.55;
uniform float max_pulse_speed : hint_range(0.0, 12.0, 0.05) = 2.60;
// How much of the brightness the pulse swings, 0 for a steady light.
uniform float pulse_depth : hint_range(0.0, 1.0, 0.01) = 0.35;

group_uniforms Surge;
// A band of light climbing the piece, which only appears in the upper half of
// the ladder - it is the "this one is overcharged" tell.
uniform float surge_tier_start : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform float surge_speed : hint_range(0.0, 6.0, 0.05) = 0.9;
uniform float surge_width : hint_range(0.01, 1.0, 0.01) = 0.22;
uniform float surge_strength : hint_range(0.0, 3.0, 0.05) = 0.9;
// Height the band travels over, in the model's own space. Roughly the height
// of the piece it is painted on.
uniform float surge_height : hint_range(0.05, 8.0, 0.05) = 1.0;

group_uniforms Facets;
// Lightens faces pointing up and darkens faces pointing away, so a flat
// coloured solid still reads as faceted with no light touching it. Without
// this an unshaded crystal is a silhouette rather than a shape.
uniform float facet_strength : hint_range(0.0, 1.0, 0.01) = 0.30;

// Height of this fragment within the model, for the climbing band.
varying float local_height;
// Normal in world space, for the facet shading.
varying vec3 world_normal;


void vertex() {
	local_height = VERTEX.y;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}


void fragment() {
	// One pulse, its rate and its depth both climbing with the tier. sin is
	// remapped to 0..1 first so the accent never dips below dim_color.
	float speed = mix(min_pulse_speed, max_pulse_speed, tier);
	float pulse = sin(TIME * speed * 6.2831853) * 0.5 + 0.5;
	float lit = mix(1.0 - pulse_depth, 1.0, pulse);

	float brightness = mix(min_brightness, max_brightness, tier) * lit;
	vec3 color = mix(dim_color, glow_color, clamp(brightness, 0.0, 1.0));
	// Past full the colour keeps climbing rather than clamping, which is what
	// pushes the top tiers towards white.
	color *= max(1.0, brightness);

	// The climbing band, fading in over the top half of the ladder. fract
	// gives it a hard restart at the bottom, which reads as a charge cycling
	// rather than as a light sliding about.
	float surge_mix = smoothstep(surge_tier_start, 1.0, tier);
	if (surge_mix > 0.0) {
		float travel = fract(TIME * surge_speed);
		float at = clamp(local_height / surge_height, 0.0, 1.0);
		float band = 1.0 - smoothstep(0.0, surge_width, abs(at - travel));
		color += glow_color * band * surge_strength * surge_mix;
	}

	// Cheap fake shading so the solid keeps its facets with no light on it.
	float facing = world_normal.y * 0.5 + 0.5;
	color *= mix(1.0, 0.55 + facing * 0.75, facet_strength);

	ALBEDO = color;
}
