shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, world_vertex_coords;
// Flowing river driven by a baked RiverFlowField (river_flow_field.gd), the same data gameplay uses:
//  - flow map RG: surface current, parting around rocks and slowing in their wakes
//  - B: turbulence, where foam gathers (bow waves, wakes, sheared water along the banks)
//  - A: surface height: bow waves in front of rocks, wake troughs and V-shaped standing waves behind
// Detail normals and foam are advected along the local current with the two-phase flow-map method
// (two layers cross-faded half a cycle apart, so the pattern never visibly resets).
// Refraction, absorption, caustics and reflection come from water_common.

#include "res://world/water/water_common.gdshaderinc"

uniform sampler2D flow_map : filter_linear, repeat_disable;
uniform vec4 flow_rect = vec4(-45.0, -20.0, 90.0, 40.0);  // origin x, origin z, size x, size z
uniform float max_speed = 2.5;
uniform float cycle = 1.4;
uniform float detail_scale = 0.22;
uniform float detail_strength = 0.18;
uniform float turbulent_detail = 0.9;      // extra normal strength in turbulent water
uniform float height_normal_step = 0.2;    // metres between height samples for the slope
uniform float foam_scale = 0.45;
uniform float foam_amount = 1.15;
uniform float foam_softness = 0.22;
uniform float streak_stretch = 4.0;        // foam elongated along the current
uniform float chop_amplitude = 0.035;      // small breaking ripples in turbulent water

uniform sampler2D normal_map_a : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map_b : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 v_world;
varying float v_turbulence;
varying float v_foam;

vec4 flow_sample(vec2 p) {
	vec2 uv = (p - flow_rect.xy) / flow_rect.zw;
	return textureLod(flow_map, uv, 0.0);
}

vec2 detail_normal(vec2 uv) {
	vec3 a = texture(normal_map_a, uv).xyz * 2.0 - 1.0;
	vec3 b = texture(normal_map_b, uv * 2.3 + 0.37).xyz * 2.0 - 1.0;
	return a.xy + b.xy * 0.6;
}

// Foam texture stretched along the current direction `dir`.
float streak(vec2 p, vec2 dir) {
	vec2 q = vec2(dot(p, dir) / streak_stretch, dot(p, vec2(-dir.y, dir.x)));
	return texture(foam_texture, q * foam_scale).r * 0.6 + texture(foam_texture, q * foam_scale * 2.3 + 0.31).r * 0.4;
}

void vertex() {
	vec4 f = flow_sample(VERTEX.xz);
	float ripple = sin(VERTEX.x * 2.1 + VERTEX.z * 1.3 - TIME * 4.0) * sin(VERTEX.z * 2.7 - VERTEX.x * 0.9 + TIME * 3.1);
	VERTEX.y += f.a + ripple * chop_amplitude * f.b;
	v_world = VERTEX;
	v_turbulence = f.b;
}

void fragment() {
	vec2 p = v_world.xz;
	vec4 f = flow_sample(p);
	vec2 flow = f.rg;
	float speed = length(flow);
	vec2 dir = speed > 0.001 ? flow / speed : vec2(1.0, 0.0);

	// Two-phase advection: each layer drifts with the local current for one cycle, then fades out while
	// the other (half a cycle apart) is at full strength.
	float t0 = fract(TIME / cycle);
	float t1 = fract(TIME / cycle + 0.5);
	float w = abs(t0 - 0.5) * 2.0;
	vec2 p0 = p - flow * t0 * cycle;
	vec2 p1 = p - flow * t1 * cycle + vec2(0.41, 0.73);

	float turbulence = f.b;
	vec2 detail = mix(detail_normal(p0 * detail_scale), detail_normal(p1 * detail_scale), w);
	detail *= detail_strength * (0.4 + speed / max_speed * 0.6 + turbulence * turbulent_detail);
	float dist = length(CAMERA_POSITION_WORLD - v_world);
	detail *= mix(1.0, 0.35, smoothstep(15.0, 120.0, dist));

	// Slope of the baked surface: bow waves and standing waves catch the light.
	float e = height_normal_step;
	float dhdx = (flow_sample(p + vec2(e, 0.0)).a - flow_sample(p - vec2(e, 0.0)).a) / (2.0 * e);
	float dhdz = (flow_sample(p + vec2(0.0, e)).a - flow_sample(p - vec2(0.0, e)).a) / (2.0 * e);
	vec3 n_world = normalize(vec3(-dhdx + detail.x, 1.0, -dhdz + detail.y));
	vec3 n_view = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// Foam rides the current and gathers where the field is turbulent.
	float foam_tex = mix(streak(p0, dir), streak(p1, dir), w);
	float coverage = clamp(pow(turbulence, 1.3) * foam_amount, 0.0, 1.0);
	float foam = smoothstep(1.0 - coverage, 1.0 - coverage + foam_softness, foam_tex);

	WaterResult r = water_shade(n_world, n_view, v_world, VERTEX, SCREEN_UV, INV_PROJECTION_MATRIX,
			INV_VIEW_MATRIX, CAMERA_POSITION_WORLD, TIME, foam, vec2(0.0));
	NORMAL = n_view;
	ALBEDO = r.albedo;
	EMISSION = r.emission;
	ROUGHNESS = r.roughness;
	SPECULAR = r.specular;
	v_foam = r.foam;
}

void light() {
	water_light(NORMAL, VIEW, LIGHT, LIGHT_COLOR, ATTENUATION, v_turbulence * 0.5, v_foam, DIFFUSE_LIGHT, SPECULAR_LIGHT);
}
