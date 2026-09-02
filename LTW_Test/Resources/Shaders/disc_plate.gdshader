// The round mechanism plate of a technology disc: the middle of its three
// layers, and the one that says "disc" rather than "tower".
//
// A disc is drawn in three flat layers, and each answers one question:
//
//   the FOUNDATION is the shared square patch every tower stands on,
//   Scenes/Units/Models/tower_foundation.tscn, unchanged and not this file.
//   It says a BUILDING is here and claims this square
//   the PLATE, this file, is a round worked disc set into that square. It says
//   the building is a DISC. Identical on all thirty-one of them
//   the GLYPH is a coloured circle in the middle, disc_glyph.gdshader. It says
//   WHICH ELEMENT by its colour and WHICH TIER by its size
//
// Round on a square is the whole trick. The foundation and the plate are the
// same stone, so neither can be told from the other by colour - which is
// deliberate, because colour belongs to the elements (see style.py). What
// separates them is that one is a square patch of ground and the other is a
// made, machined circle sitting on it, and that reads instantly from directly
// overhead at any zoom.
//
// ONE MATERIAL for the whole roster, unlike the glyph. Nothing about this
// layer varies with element or tier, and it must not be allowed to: a plate
// that changed with either would be a second thing competing to say what the
// glyph already says.
//
// Everything is procedural - there is no texture anywhere in the project. The
// stone TONE is sampled in world space so two neighbouring discs never show
// the same blotches; the rings and spokes are sampled in UV space so they stay
// centred on the disc's own cell whatever its world position.
//
// Draw order: the foundation is at render_priority -1 like every tower's, this
// sits above it, and the build grid is above both so its lines stay readable
// across a disc.

shader_type spatial;
render_mode cull_disabled, depth_draw_never;

group_uniforms Plate;
// Lit stone tone, the bulk of the plate.
uniform vec3 plate_color : source_color = vec3(0.58, 0.57, 0.54);
// Weathered tone the blotch noise mixes towards.
uniform vec3 plate_dark_color : source_color = vec3(0.41, 0.40, 0.38);
// Lines cut into the plate: the concentric rings and the radial spokes.
uniform vec3 groove_color : source_color = vec3(0.22, 0.21, 0.20);
// Darker band around the plate's own edge, so it reads as a made object set
// INTO the foundation rather than as a stain lying on top of it.
uniform vec3 edge_color : source_color = vec3(0.28, 0.27, 0.25);
// Half extent of the plate, as a fraction of the quad's own half size.
//
// Deliberately smaller than the foundation under it: the square has to show
// around the circle at every corner, or the two layers read as one lump and
// the whole point of putting a round thing on a square one is lost.
uniform float radius : hint_range(0.1, 1.0, 0.01) = 0.52;
uniform float edge_softness : hint_range(0.001, 0.5, 0.001) = 0.02;
// Width of that darker band, measured inwards from the border.
uniform float edge_width : hint_range(0.0, 0.5, 0.01) = 0.07;
// Frequency of the large tone variation, in cells.
uniform float blotch_scale : hint_range(0.5, 40.0, 0.5) = 3.5;

group_uniforms Grooves;
// How many concentric rings are cut into the plate.
uniform float ring_count : hint_range(0.0, 12.0, 1.0) = 3.0;
uniform float ring_width : hint_range(0.0, 0.2, 0.002) = 0.022;
// How many spokes run out from the centre. 0 for none.
uniform float spoke_count : hint_range(0.0, 24.0, 1.0) = 8.0;
uniform float spoke_width : hint_range(0.0, 0.5, 0.005) = 0.045;
uniform float groove_strength : hint_range(0.0, 1.0, 0.01) = 0.6;

group_uniforms Surface;
uniform float opacity : hint_range(0.0, 1.0, 0.01) = 0.85;

varying vec2 world_pos;


float hash1(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}


float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 t = f * f * (3.0 - 2.0 * f);
	float a = hash1(cell);
	float b = hash1(cell + vec2(1.0, 0.0));
	float c = hash1(cell + vec2(0.0, 1.0));
	float d = hash1(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, t.x), mix(c, d, t.x), t.y);
}


/// Four octaves, normalised back to 0..1 so a smoothstep over it can be
/// reasoned about rather than guessed at. The same one the tower foundation
/// uses, deliberately: the two are different SHAPES made of the same stone, so
/// a maze reads as one floor.
float fbm(vec2 p) {
	float sum = 0.0;
	float amplitude = 0.5;
	float total = 0.0;
	for (int i = 0; i < 4; i++) {
		sum += value_noise(p) * amplitude;
		total += amplitude;
		p *= 2.03;
		amplitude *= 0.5;
	}
	return sum / total;
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}


void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);

	// A TRUE circle, with none of the noise the tower foundation is allowed to
	// chew into its border. That patch is poured concrete and may crumble; this
	// is a machined plate and its outline is the thing telling a player it was
	// made rather than spilled.
	float mask = 1.0 - smoothstep(radius - edge_softness, radius + edge_softness, r);

	float blotch = fbm(world_pos * blotch_scale);
	vec3 color = mix(plate_dark_color, plate_color, smoothstep(0.25, 0.75, blotch));

	// Rings, evenly spaced out to the plate's own border so a disc reads as one
	// object however its radius is tuned.
	float rings = 0.0;
	if (ring_count > 0.5) {
		float spacing = radius / (ring_count + 1.0);
		float phase = abs(fract(r / spacing) - 0.5) * spacing;
		rings = 1.0 - smoothstep(0.0, ring_width, phase);
	}

	// Spokes, faded out towards the centre so they meet at a hub rather than
	// collapsing into a smudge.
	float spokes = 0.0;
	if (spoke_count > 0.5) {
		float segment = 6.28318530718 / spoke_count;
		float angle = atan(p.y, p.x);
		float across = abs(mod(angle + segment * 0.5, segment) - segment * 0.5) * r;
		spokes = (1.0 - smoothstep(0.0, spoke_width * 0.5, across))
			* smoothstep(0.0, radius * 0.30, r);
	}
	color = mix(color, groove_color, max(rings, spokes) * groove_strength);

	color = mix(color, edge_color,
		smoothstep(radius - edge_width, radius, r) * 0.9);

	ALBEDO = color;
	ALPHA = mask * opacity;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
