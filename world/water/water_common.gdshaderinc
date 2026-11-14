// Shared optics for all our water shaders (sea, lake, river).
// Each shader computes its own surface (waves or flow) and normal, then calls:
//   water_shade(...)  in fragment(): refraction, per-channel absorption, caustics, reflection, foam
//   water_light(...)  in light():    sun glint and light shining through backlit wave crests
// Requires render_mode: blend_mix, depth_draw_always (or opaque-depth aware), and an emission-friendly setup.

uniform vec3 absorption = vec3(0.45, 0.075, 0.05);      // per metre, per channel: red dies first
uniform vec3 scatter_color : source_color = vec3(0.02, 0.16, 0.18);
uniform vec3 foam_color : source_color = vec3(0.92, 0.94, 0.94);
uniform vec3 sss_color : source_color = vec3(0.1, 0.55, 0.45);
uniform float refraction_strength = 0.04;
uniform float reflection_distortion = 0.03;
uniform float caustic_strength = 2.2;
uniform float caustic_scale = 0.35;
uniform float caustic_fade = 0.6;                       // per metre of depth
uniform float shore_foam_width = 0.6;
uniform float shore_foam_strength = 0.9;
uniform float crest_foam_strength = 0.8;
uniform float glint_power = 900.0;
uniform float glint_strength = 6.0;
uniform float sss_strength = 1.4;
uniform float sky_reflection = 0.5;                     // engine sky reflection when no planar reflection

uniform sampler2D foam_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D caustic_texture : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

global uniform sampler2D water_reflection : filter_linear;
global uniform bool water_reflection_enabled;

struct WaterResult {
	vec3 albedo;
	vec3 emission;
	float roughness;
	float specular;
	float foam;
};

vec3 water_view_from_depth(vec2 uv, float raw, mat4 inv_proj) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec4 v = inv_proj * vec4(vec3(uv, raw) * 2.0 - 1.0, 1.0);
#else
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, raw, 1.0);
#endif
	return v.xyz / v.w;
}

// Bright, sharp light lines on the bottom: two drifting layers of cellular-edge noise.
float water_caustics(vec2 p, float t) {
	vec2 q = p * caustic_scale;
	float a = texture(caustic_texture, q + vec2(t * 0.031, t * 0.017)).r;
	float b = texture(caustic_texture, q * 1.31 + vec2(-t * 0.022, t * 0.029) + 0.5).r;
	return pow(min(a, b), 2.0) * 4.0;
}

// n_world: final surface normal; surf_world: surface position; vertex_view: VERTEX (view space);
// n_view: final normal in view space; crest_foam: 0..1 from the wave shape; foam_motion: how foam drifts (m/s).
WaterResult water_shade(vec3 n_world, vec3 n_view, vec3 surf_world, vec3 vertex_view, vec2 screen_uv,
		mat4 inv_proj, mat4 inv_view, vec3 cam_pos, float t, float crest_foam, vec2 foam_motion) {
	WaterResult r;
	vec3 v = normalize(cam_pos - surf_world);
	float ndv = clamp(dot(n_world, v), 0.0, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);

	// Ground straight behind this pixel (for shore foam) and behind the refracted ray (for colour).
	vec3 g_view = water_view_from_depth(screen_uv, texture(depth_tex, screen_uv).r, inv_proj);
	float thickness = max(vertex_view.z - g_view.z, 0.0);
	vec2 ruv = screen_uv + n_view.xy * refraction_strength * clamp(thickness, 0.0, 1.0);
	vec3 rg_view = water_view_from_depth(ruv, texture(depth_tex, ruv).r, inv_proj);
	if (rg_view.z > vertex_view.z) { // refracted sample lands on something in front of the water
		ruv = screen_uv;
		rg_view = g_view;
	}
	vec3 g_world = (inv_view * vec4(rg_view, 1.0)).xyz;
	vec3 straight_world = (inv_view * vec4(g_view, 1.0)).xyz;
	float path = max(length(rg_view) - length(vertex_view), 0.0);
	float depth_below = max(surf_world.y - g_world.y, 0.0);
	float shore_depth = max(surf_world.y - straight_world.y, 0.0);

	vec3 bottom = textureLod(screen_tex, ruv, 0.0).rgb;
	float caustic = water_caustics(g_world.xz, t) * exp(-depth_below * caustic_fade) * smoothstep(0.0, 0.25, depth_below);
	bottom *= 1.0 + caustic * caustic_strength;
	vec3 transmittance = exp(-absorption * path);
	float murk = 1.0 - dot(transmittance, vec3(0.333));

	// Moving foam bands that hug the shoreline, broken up by the foam texture.
	vec2 fuv = surf_world.xz * 0.35 - foam_motion * t;
	float foam_tex = texture(foam_texture, fuv).r * texture(foam_texture, fuv * 0.37 + 0.3).r * 1.6;
	float band = 0.5 + 0.5 * sin(shore_depth / shore_foam_width * 9.0 - t * 1.7);
	float shore = 1.0 - smoothstep(0.0, shore_foam_width, shore_depth);
	float foam = shore * mix(0.6, 1.0, band) * shore_foam_strength;
	foam += crest_foam * crest_foam_strength;
	foam = clamp(foam * smoothstep(0.25, 0.75, foam_tex + foam * 0.35), 0.0, 1.0);

	// Thin water at the very edge fades its reflection so the shore has no hard seam.
	float edge = smoothstep(0.0, 0.12, path);
	vec3 reflection = vec3(0.0);
	bool planar = water_reflection_enabled;
	if (planar) {
		vec2 puv = vec2(screen_uv.x, 1.0 - screen_uv.y) + n_view.xy * reflection_distortion;
		reflection = texture(water_reflection, clamp(puv, vec2(0.001), vec2(0.999))).rgb;
	}
	float f = fresnel * edge;
	r.emission = bottom * transmittance * (1.0 - f) * (1.0 - foam) + reflection * f * (1.0 - foam);
	r.albedo = mix(scatter_color * murk * (1.0 - f), foam_color, foam);
	r.roughness = mix(0.02, 0.85, foam);
	r.specular = planar ? 0.0 : sky_reflection * edge * (1.0 - foam);
	r.foam = foam;
	return r;
}

// Call from light(). crest: 0..1 how high the point is on a wave (for light shining through crests).
void water_light(vec3 n, vec3 v, vec3 l, vec3 light_color, float attenuation, float crest, float foam_amount,
		inout vec3 diffuse_light, inout vec3 specular_light) {
	float ndl = clamp(dot(n, l), 0.0, 1.0);
	diffuse_light += ndl * attenuation * light_color / PI;
	vec3 h = normalize(v + l);
	float ndv = clamp(dot(n, v), 0.0, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
	float glint = pow(clamp(dot(n, h), 0.0, 1.0), glint_power) * glint_strength * (glint_power + 8.0) / (8.0 * PI);
	specular_light += glint * fresnel * ndl * attenuation * light_color * (1.0 - foam_amount);
	float back = pow(clamp(dot(v, -l), 0.0, 1.0), 4.0);
	specular_light += sss_color * back * crest * sss_strength * attenuation * light_color;
}
