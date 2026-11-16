// Foam texture generator, pass 3: packs height into the game's layout. R, G = normal x, y (OpenGL:
// green towards the image's top), B = height.
shader_type canvas_item;

uniform sampler2D height_map : filter_linear, repeat_enable;
uniform float texture_size = 2048.0;
uniform float relief = 6.0;        // slope scale: height units per texture width, times this

void fragment() {
	vec2 px = vec2(1.0 / texture_size);
	float l = texture(height_map, UV - vec2(px.x, 0.0)).r;
	float r = texture(height_map, UV + vec2(px.x, 0.0)).r;
	float u = texture(height_map, UV - vec2(0.0, px.y)).r;
	float d = texture(height_map, UV + vec2(0.0, px.y)).r;
	vec2 slope = vec2(r - l, d - u) * 0.5 * texture_size / 256.0 * relief;
	vec3 n = normalize(vec3(-slope.x, slope.y, 1.0));
	COLOR = vec4(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, texture(height_map, UV).r, 1.0);
}
