shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, world_vertex_coords;
// Open water (sea, lake, moat): Gerstner waves with sharp crests and crest foam, two scrolling detail
// normal maps, and the shared optics from water_common (refraction, absorption, caustics, reflection, foam).

#include "res://world/water/water_common.gdshaderinc"

uniform float wave_amplitude = 0.12;
uniform float wave_length = 9.0;
uniform float wave_steepness = 0.55;     // 0 = round sine waves, 1 = sharpest crests before looping
uniform float wave_time = -1.0; // Ocean fallback synchronizes this with CPU buoyancy.
uniform float wave_speed = 1.0;
uniform vec2 wind_direction = vec2(1.0, 0.35);
uniform float wave_spread = 0.6;         // radians of direction spread between wave trains
uniform int wave_count = 6;
uniform float detail_strength = 0.35;
uniform float detail_scale = 0.12;
uniform float detail_speed = 0.35;
uniform float crest_foam_threshold = 0.55;

uniform sampler2D normal_map_a : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map_b : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 v_world;
varying vec3 v_wave_normal;
varying float v_crest;
varying float v_crest_foam;
varying float v_foam;

const int MAX_WAVES = 8;

void vertex() {
	vec2 p = VERTEX.xz;
	vec3 disp = vec3(0.0);
	vec3 n = vec3(0.0, 1.0, 0.0);
	float jxx = 1.0, jzz = 1.0, jxz = 0.0;
	float base_angle = atan(wind_direction.y, wind_direction.x);
	int count = min(wave_count, MAX_WAVES);
	for (int i = 0; i < MAX_WAVES; i++) {
		if (i >= count) break;
		float fi = float(i);
		float angle = base_angle + wave_spread * sin(fi * 2.4 + 0.7);
		vec2 d = vec2(cos(angle), sin(angle));
		float len = wave_length * pow(0.72, fi);
		float k = TAU / len;
		float a = wave_amplitude * pow(0.66, fi);
		float c = sqrt(9.81 / k) * wave_speed;
		float q = wave_steepness / (k * a * float(count));
		float f = k * (dot(d, p) - c * (wave_time >= 0.0 ? wave_time : TIME)) + fi * 1.7;
		float cf = cos(f);
		float sf = sin(f);
		disp.xz += q * a * d * cf;
		disp.y += a * sf;
		float wa = k * a;
		n.xz -= d * wa * cf;
		n.y -= q * wa * sf;
		jxx -= q * wa * d.x * d.x * sf;
		jzz -= q * wa * d.y * d.y * sf;
		jxz -= q * wa * d.x * d.y * sf;
	}
	VERTEX += disp;
	v_world = VERTEX;
	v_wave_normal = normalize(n);
	NORMAL = v_wave_normal;
	v_crest = clamp(disp.y / max(wave_amplitude, 0.0001) * 0.5 + 0.5, 0.0, 1.0);
	float jacobian = jxx * jzz - jxz * jxz;
	v_crest_foam = smoothstep(crest_foam_threshold, crest_foam_threshold - 0.35, jacobian);
}

void fragment() {
	vec2 wind = normalize(wind_direction);
	vec2 uv = v_world.xz * detail_scale;
	vec3 na = texture(normal_map_a, uv + wind * TIME * detail_speed * 0.1).xyz * 2.0 - 1.0;
	vec3 nb = texture(normal_map_b, uv * 1.9 - vec2(-wind.y, wind.x) * TIME * detail_speed * 0.13).xyz * 2.0 - 1.0;
	vec2 detail = (na.xy + nb.xy) * detail_strength;
	// Detail fades out in the distance where it would only shimmer.
	float dist = length(CAMERA_POSITION_WORLD - v_world);
	detail *= mix(1.0, 0.25, smoothstep(15.0, 160.0, dist));
	vec3 n_world = normalize(v_wave_normal + vec3(detail.x, 0.0, detail.y));
	vec3 n_view = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	WaterResult r = water_shade(n_world, n_view, v_world, VERTEX, SCREEN_UV, INV_PROJECTION_MATRIX,
			INV_VIEW_MATRIX, CAMERA_POSITION_WORLD, TIME, v_crest_foam, wind * 0.15);
	NORMAL = n_view;
	ALBEDO = r.albedo;
	EMISSION = r.emission;
	ROUGHNESS = r.roughness;
	SPECULAR = r.specular;
	v_foam = r.foam;
}

void light() {
	water_light(NORMAL, VIEW, LIGHT, LIGHT_COLOR, ATTENUATION, v_crest, v_foam, DIFFUSE_LIGHT, SPECULAR_LIGHT);
}
