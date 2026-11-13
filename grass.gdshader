shader_type spatial;
render_mode cull_disabled, world_vertex_coords, diffuse_burley, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.03, 0.10, 0.02);
uniform vec3 tip_color : source_color = vec3(0.42, 0.68, 0.14);
uniform vec3 dry_color : source_color = vec3(0.78, 0.66, 0.30);
uniform vec2 wind_dir = vec2(1.0, 0.4);
uniform float wind_strength = 0.35;
uniform float wind_speed = 1.0;
uniform vec4 pushers[16];
uniform int pusher_count = 0;

varying float v_h;
varying vec2 v_custom;
varying float v_gust;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	float bh = length(MODEL_MATRIX[1].xyz);
	float h = UV.y;
	vec2 wd = normalize(wind_dir);

	// Rolling gusts: noise scrolling with the wind
	vec2 p = root.xz * 0.08 - wd * TIME * wind_speed * 1.2;
	float gust = vnoise(p) * 0.7 + vnoise(p * 2.7) * 0.3;
	gust = smoothstep(0.25, 0.9, gust);
	float flutter = sin(TIME * 5.0 * wind_speed + root.x * 1.3 + root.z * 0.7 + INSTANCE_CUSTOM.r * 6.28);

	vec2 bend = wd * (gust * 1.6 + 0.25) * wind_strength;
	bend += vec2(-wd.y, wd.x) * flutter * 0.12 * (0.3 + wind_strength);

	// Physics objects push the grass away
	for (int i = 0; i < pusher_count; i++) {
		vec4 ps = pushers[i];
		vec2 d = root.xz - ps.xz;
		float dist = length(d);
		float r = ps.w * 1.7;
		float f = clamp(1.0 - dist / r, 0.0, 1.0);
		f *= clamp(1.0 - (abs(root.y - ps.y) - ps.w) / 1.2, 0.0, 1.0);
		f = f * f * (3.0 - 2.0 * f);
		bend += normalize(d + vec2(0.0001)) * f * 3.0;
	}

	vec2 off = bend * h * h * bh;
	float len = length(off);
	float maxl = bh * 0.95;
	if (len > maxl) { off *= maxl / len; len = maxl; }
	VERTEX.xz += off;
	VERTEX.y -= h * bh * (1.0 - sqrt(max(1.0 - (len / bh) * (len / bh), 0.0)));

	// Rounded normals so the flat blade shades like a curved leaf
	vec3 side = normalize(MODEL_MATRIX[0].xyz);
	NORMAL = normalize(NORMAL + side * (UV.x - 0.5) * 1.4 + vec3(0.0, 0.5, 0.0));

	v_h = h;
	v_custom = INSTANCE_CUSTOM.rg;
	v_gust = gust;
}

void fragment() {
	vec3 col = mix(base_color, tip_color, smoothstep(0.0, 1.0, v_h));
	col = mix(col, dry_color * mix(0.5, 1.0, v_h), v_custom.g * 0.75);
	col *= 0.8 + v_custom.r * 0.4;
	col += vec3(0.05, 0.06, 0.02) * v_gust * v_h; // silver sheen of gusts
	ALBEDO = col;
	ROUGHNESS = 0.5;
	SPECULAR = 0.4;
	AO = mix(0.15, 1.0, v_h);
	AO_LIGHT_AFFECT = 0.7;
	BACKLIGHT = col * 1.4 * v_h; // light shining through the blades
}
