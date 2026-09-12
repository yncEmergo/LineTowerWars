shader_type canvas_item;

// Dims the whole screen except a soft circle around one point, so the tutorial
// can say "this one" about something in the world rather than in words.
//
// A CANVAS shader over the finished frame rather than anything touching the
// world, which is what keeps it out of the simulation entirely: nothing is
// tinted, nothing is re-rendered, and a lesson that dims the lane changes not
// one thing about what is in it.
//
// The circle is in SCREEN space and is handed down every frame by
// TutorialSpotlight, which projects a world point through the camera. Doing the
// projection in GDScript rather than here is deliberate: the thing being lit is
// a creep that walks, and the code that knows which creep is not a shader.

// Middle of the lit circle, in 0..1 screen coordinates.
uniform vec2 focus = vec2(0.5, 0.5);
// Radius of the fully lit part, and of the fade around it, as a share of screen
// height. Height rather than width so a circle is a circle whatever the aspect.
uniform float radius : hint_range(0.0, 2.0) = 0.12;
uniform float feather : hint_range(0.0, 2.0) = 0.10;
// How dark everything outside gets. 1 is black.
uniform float strength : hint_range(0.0, 1.0) = 0.72;
uniform vec4 dim_color : source_color = vec4(0.02, 0.024, 0.035, 1.0);
// Screen width divided by height, so the circle is not an ellipse.
uniform float aspect = 1.777;

void fragment() {
	vec2 offset = UV - focus;
	offset.x *= aspect;
	float distance_to_focus = length(offset);
	// 0 inside the lit circle, 1 once the feather has run out.
	float shade = smoothstep(radius, radius + max(feather, 0.001), distance_to_focus);
	COLOR = vec4(dim_color.rgb, shade * strength);
}
