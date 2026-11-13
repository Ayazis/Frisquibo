shader_type spatial;
// Procedural triplanar masonry: staggered blocks, mortar, per-block tint, grime and damp base.

uniform vec3 stone_color : source_color = vec3(0.56, 0.53, 0.48);
uniform vec3 mortar_color : source_color = vec3(0.25, 0.24, 0.21);
uniform vec2 brick_size = vec2(0.9, 0.45);
uniform float variation = 0.35;

varying vec3 wp;
varying vec3 wn;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// rgb = colour, a = 1 on stone, 0 in mortar
vec4 blocks(vec2 uv) {
	vec2 b = uv / brick_size;
	float row = floor(b.y);
	b.x += mod(row, 2.0) * 0.5 + hash(vec2(row, 3.0)) * 0.3;
	vec2 id = floor(b);
	vec2 f = fract(b);
	vec2 edge = min(f, 1.0 - f) * brick_size;
	float m = smoothstep(0.012, 0.045, min(edge.x, edge.y) + (vnoise(uv * 11.0) - 0.5) * 0.02);
	float h = hash(id);
	vec3 c = stone_color * (1.0 - variation * 0.5 + variation * h);
	c = mix(c, c * vec3(1.05, 0.98, 0.9), hash(id + 7.0)); // warm/cool stones
	c *= 0.82 + 0.3 * vnoise(uv * 7.0) + 0.08 * vnoise(uv * 23.0);
	return vec4(mix(mortar_color, c, m), m);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 w = pow(abs(wn), vec3(6.0));
	w /= (w.x + w.y + w.z);
	vec4 b = blocks(wp.zy) * w.x + blocks(wp.xz) * w.y + blocks(wp.xy) * w.z;
	float grime = vnoise(wp.xz * 0.25 + vec2(wp.y * 0.4));
	vec3 col = b.rgb * mix(0.72, 1.0, grime);
	col *= mix(0.65, 1.0, smoothstep(0.0, 1.8, wp.y)); // damp, dark base
	col = mix(col, col * vec3(0.8, 0.95, 0.7), smoothstep(0.55, 0.9, vnoise(wp.xy * 0.6 + wp.zy * 0.6)) * 0.5); // moss
	ALBEDO = col;
	ROUGHNESS = mix(1.0, 0.82, b.a);
	AO = mix(0.5, 1.0, b.a);
}
