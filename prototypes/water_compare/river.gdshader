shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, world_vertex_coords;
// Flowing river: detail normal maps advected along the channel with the two-phase flow-map trick
// (cross-faded so the pattern never visibly resets), faster mid-channel than at the banks, foam streaks,
// plus the shared optics from water_common (refraction, absorption, caustics, reflection, shore foam).

#include "res://world/water/water_common.gdshaderinc"

uniform float flow_speed = 1.6;
uniform float meander_amplitude = 4.0;
uniform float meander_frequency = 0.08;
uniform float channel_half_width = 7.5;
uniform float cycle = 1.6;
uniform float detail_scale = 0.16;
uniform float detail_strength = 0.45;
uniform float streak_strength = 0.6;

uniform sampler2D normal_map_a : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map_b : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 v_world;
varying float v_speed;
varying float v_foam;

// Flow velocity in world XZ: along the meander, fastest in the middle of the channel.
vec2 flow_at(vec2 p) {
	float centre = sin(p.x * meander_frequency) * meander_amplitude;
	vec2 dir = normalize(vec2(1.0, cos(p.x * meander_frequency) * meander_amplitude * meander_frequency));
	float across = clamp(abs(p.y - centre) / channel_half_width, 0.0, 1.0);
	return dir * flow_speed * (1.0 - across * across);
}

void vertex() {
	vec2 f = flow_at(VERTEX.xz);
	v_speed = length(f) / flow_speed;
	// Small standing ripples where the current is fast.
	VERTEX.y += sin(VERTEX.x * 1.3 + VERTEX.z * 0.4 - TIME * 3.0) * 0.012 * v_speed;
	v_world = VERTEX;
}

vec2 detail_normal(vec2 uv) {
	vec3 a = texture(normal_map_a, uv).xyz * 2.0 - 1.0;
	vec3 b = texture(normal_map_b, uv * 2.3 + 0.37).xyz * 2.0 - 1.0;
	return a.xy + b.xy * 0.6;
}

void fragment() {
	vec2 p = v_world.xz;
	vec2 flow = flow_at(p);
	float t0 = fract(TIME / cycle);
	float t1 = fract(TIME / cycle + 0.5);
	float w = abs(t0 - 0.5) * 2.0;
	vec2 uv = p * detail_scale;
	vec2 uv0 = uv - flow * detail_scale * t0 * cycle;
	vec2 uv1 = uv - flow * detail_scale * t1 * cycle + vec2(0.41, 0.73);
	vec2 detail = mix(detail_normal(uv0), detail_normal(uv1), w) * detail_strength * (0.5 + v_speed);
	float dist = length(CAMERA_POSITION_WORLD - v_world);
	detail *= mix(1.0, 0.3, smoothstep(12.0, 120.0, dist));
	vec3 n_world = normalize(vec3(detail.x, 1.0, detail.y));
	vec3 n_view = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// Foam streaks stretched along the current: sample the foam texture squashed across the flow.
	vec2 dir = normalize(flow + vec2(0.0001));
	mat2 to_flow = mat2(vec2(dir.x, -dir.y), vec2(dir.y, dir.x));
	vec2 s0 = (to_flow * (p - flow * t0 * cycle)) * vec2(0.08, 0.5);
	vec2 s1 = (to_flow * (p - flow * t1 * cycle)) * vec2(0.08, 0.5) + 0.5;
	float streak = mix(texture(foam_texture, s0).r, texture(foam_texture, s1).r, w);
	float streak_foam = smoothstep(0.62, 0.9, streak) * v_speed * streak_strength;

	WaterResult r = water_shade(n_world, n_view, v_world, VERTEX, SCREEN_UV, INV_PROJECTION_MATRIX,
			INV_VIEW_MATRIX, CAMERA_POSITION_WORLD, TIME, streak_foam, flow);
	NORMAL = n_view;
	ALBEDO = r.albedo;
	EMISSION = r.emission;
	ROUGHNESS = r.roughness;
	SPECULAR = r.specular;
	v_foam = r.foam;
}

void light() {
	water_light(NORMAL, VIEW, LIGHT, LIGHT_COLOR, ATTENUATION, v_speed * 0.4, v_foam, DIFFUSE_LIGHT, SPECULAR_LIGHT);
}
