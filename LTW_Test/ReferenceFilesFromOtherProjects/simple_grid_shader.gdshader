//https://godotshaders.com/shader/the-best-darn-grid-shader-yet-for-godot/
shader_type spatial;

render_mode unshaded,diffuse_burley,specular_disabled;
uniform float scale_0 : hint_range(1, 1024, 1);
uniform float scale_1 : hint_range(1, 1024, 1);
uniform float scale_factor : hint_range(0.01, 5, 0.01);
uniform vec2 offset;

uniform float line_scale_0 : hint_range(0.001, 1, 0.001);
uniform float line_scale_1 : hint_range(0.001, 1, 0.001);

uniform float quad_width : hint_range(0.001, 100, 0.001);
uniform float quad_height : hint_range(0.001, 100, 0.001);

uniform vec4 color_0 : source_color;
uniform vec4 color_1 : source_color;


float pristineGrid( vec2 uv, vec2 lineWidth)
{
    vec2 ddx = dFdx(uv);
    vec2 ddy = dFdy(uv);

    vec2 uvDeriv = vec2(length(vec2(ddx.x, ddy.x)), length(vec2(ddx.y, ddy.y)));
    bvec2 invertLine = bvec2(lineWidth.x > 0.5, lineWidth.y > 0.5);

    vec2 targetWidth = vec2(
      invertLine.x ? 1.0 - lineWidth.x : lineWidth.x,
      invertLine.y ? 1.0 - lineWidth.y : lineWidth.y
      );

    vec2 drawWidth = clamp(targetWidth, uvDeriv, vec2(0.5));
    vec2 lineAA = uvDeriv * 1.5;
    float aspectRatio = quad_height / quad_width;
	vec2 uvAspect = uv;
	uvAspect.x *= quad_width;
	uvAspect.y *= quad_height;
	uvAspect += offset;
	vec2 gridUV = abs(fract(uvAspect) * 2.0 - 1.0);

	//gridUV.x *= aspectRatio;

    gridUV.x = invertLine.x ? gridUV.x : 1.0 - gridUV.x;
    gridUV.y = invertLine.y ? gridUV.y : 1.0 - gridUV.y;

    vec2 grid2 = smoothstep(drawWidth + lineAA, drawWidth - lineAA, gridUV);

    grid2 *= clamp(targetWidth / drawWidth, 0.0, 1.0);
    grid2 = mix(grid2, targetWidth, clamp(uvDeriv * 2.0 - 1.0, 0.0, 1.0));
    grid2.x = invertLine.x ? 1.0 - grid2.x : grid2.x;
    grid2.y = invertLine.y ? 1.0 - grid2.y : grid2.y;
    return mix(grid2.x, 1.0, grid2.y);
}

void vertex()
{
	//UV = VERTEX.xz;
}

void fragment()
{
	vec4 grid_0 = vec4(pristineGrid(UV * float(scale_0 * scale_factor), vec2(line_scale_0)));
	vec4 grid_1 = vec4(pristineGrid(UV * float(scale_1 * scale_factor), vec2(line_scale_1)));

	vec4 grid_3 = mix(grid_1 * color_1.rgba, grid_0 * color_0.rgba, grid_0);
	//if (grid_3 == vec3(0,0,0)){
	//	discard;
	//}
	ALPHA = grid_3.a; //length(grid_3);

	ALBEDO =  grid_3.rgb;
}