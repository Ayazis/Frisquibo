shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, world_vertex_coords;
// Open water (sea, lake, moat): Gerstner waves with sharp crests and crest foam, two scrolling detail
// normal maps, and the shared optics from water_common (refraction, absorption, caustics, rough
// reflection, foam, Snell's window from below).

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
varying float v_transmitted;
varying float v_front;

const int MAX_WAVES = 8;
// Detail normals fade from full strength at DETAIL_FADE_START to DETAIL_FAR_SHARE of it at DETAIL_FADE_END (m).
const float DETAIL_FADE_START = 15.0;
const float DETAIL_FADE_END = 160.0;
const float DETAIL_FAR_SHARE = 0.25;

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
	VERTEX.y += water_ripples(VERTEX.xz).z;
	v_world = VERTEX;
	v_wave_normal = normalize(n);
	NORMAL = v_wave_normal;
	v_crest = max(disp.y, 0.0);
	float jacobian = jxx * jzz - jxz * jxz;
	v_crest_foam = smoothstep(crest_foam_threshold, crest_foam_threshold - 0.35, jacobian);
}

void fragment() {
	vec2 wind = normalize(wind_direction);
	vec2 uv = v_world.xz * detail_scale;
	vec3 na = texture(normal_map_a, uv + wind * TIME * detail_speed * 0.1).xyz * 2.0 - 1.0;
	vec3 nb = texture(normal_map_b, uv * 1.9 - vec2(-wind.y, wind.x) * TIME * detail_speed * 0.13).xyz * 2.0 - 1.0;
	// Detail fades out in the distance where it would only shimmer; what it loses becomes roughness.
	float dist = length(CAMERA_POSITION_WORLD - v_world);
	float fade = mix(1.0, DETAIL_FAR_SHARE, smoothstep(DETAIL_FADE_START, DETAIL_FADE_END, dist));
	// Gusts: the detail ripples carry more energy in some patches than in others.
	float gust = water_gusts(gust_texture, v_world.xz, wind * gust_wind, gust_size, gust_strength, TIME);
	float strength = detail_strength * sqrt(gust);
	vec2 detail = (na.xy + nb.xy) * strength * fade;
	// Rings, wakes and splashes from objects in the water (WaterRipples): their slope tilts the normal.
	vec4 ripple = water_ripples(v_world.xz);
	detail -= ripple.xy;
	vec3 n_world = normalize(v_wave_normal + vec3(detail.x, 0.0, detail.y));
	bool from_below = !FRONT_FACING;
	vec3 n_view = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// Slopes this pixel can't show: those that change within it, the detail its mip levels averaged away
	// (Toksvig) and the detail faded out with distance. They widen the glint and blur the reflection.
	vec2 slope = n_world.xz / max(n_world.y, 0.05);
	float resolved = dot(na.xy, na.xy) + dot(nb.xy, nb.xy);
	float hidden = water_toksvig_variance(na) + water_toksvig_variance(nb);
	float lost = strength * strength * ((1.0 - fade * fade) * resolved + hidden);
	vec2 variance = vec2(base_slope_variance * gust + 0.5 * lost) + water_footprint_variance(dFdx(slope), dFdy(slope));

	WaterSurface surface = WaterSurface(n_world, n_view, v_world, VERTEX, variance, max(v_crest_foam, ripple.w), wind * 0.15, from_below);
	WaterResult r = water_shade(surface, SCREEN_UV, FRAGCOORD.xy, vec2(PROJECTION_MATRIX[0][0], PROJECTION_MATRIX[1][1]),
			INV_PROJECTION_MATRIX, INV_VIEW_MATRIX, CAMERA_POSITION_WORLD, TIME);
	NORMAL = from_below ? -n_view : n_view;
	ALBEDO = r.albedo;
	EMISSION = r.emission;
	ROUGHNESS = r.roughness;
	SPECULAR = r.specular;
	v_foam = r.foam;
	v_transmitted = r.transmitted;
	v_front = r.front;
}

void light() {
	water_light(NORMAL, VIEW, LIGHT, LIGHT_COLOR, ATTENUATION, ROUGHNESS, v_crest, v_foam, v_transmitted, v_front,
			DIFFUSE_LIGHT, SPECULAR_LIGHT);
}
