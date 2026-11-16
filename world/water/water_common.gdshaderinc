// Shared shading for the lake and river shaders. The optics are the FFT ocean's (water_optics): Schlick
// Fresnel, a GGX sun glint whose roughness comes from the slopes a pixel can't resolve, a planar
// reflection blurred by the same slopes, blur through murky water, and Snell's window from below.
// Each shader computes its own surface (waves or flow), normal and slope variance, then calls:
//   water_shade(...)  in fragment(): refraction, per-channel absorption, caustics, reflection, foam
//   water_light(...)  in light():    sun glint and light scattered through the water
// Requires render_mode: blend_mix, depth_draw_always, cull_disabled (back faces are the surface seen
// from below).

#include "res://world/water/water_optics.gdshaderinc"
#include "res://world/water/water_reflection.gdshaderinc"

uniform vec3 absorption = vec3(0.45, 0.075, 0.05);      // per metre, per channel: red dies first
uniform vec3 scatter_color : source_color = vec3(0.02, 0.16, 0.18);
uniform vec3 foam_color : source_color = vec3(0.92, 0.94, 0.94);
uniform vec3 sss_color : source_color = vec3(0.1, 0.55, 0.45);
uniform vec3 deep_color : source_color = vec3(0.006, 0.035, 0.04); // seen from below, beyond Snell's window
uniform float refraction_strength = 0.04;
uniform float refraction_full_distance = 8.0;           // metres; the screen offset shrinks beyond this
uniform float reflection_distortion = 0.03;
uniform float reflection_blur = 1.0;                    // 1 = blur by the real unresolved slopes
uniform float murk_blur = 2.0;                          // screen mip levels of blur through deep water
uniform float caustic_strength = 2.2;
uniform float caustic_scale = 0.35;
uniform float caustic_fade = 0.6;                       // per metre of depth
uniform float shore_foam_width = 0.6;
uniform float shore_foam_strength = 0.9;
uniform float crest_foam_strength = 0.8;
// 1 = break foam up with the built-in drifting noise; 0 = the caller supplies foam that is already textured.
uniform float foam_breakup = 1.0;
uniform float base_slope_variance = 0.0004;             // capillary ripples below the detail normals
uniform float sun_specular_strength = 1.0;              // 1 is physical
uniform float sss_crest_strength = 3.2;                 // light through thin crests, per metre of crest
uniform float sss_view_strength = 0.25;                 // soft glow in the water towards the viewer
uniform float sky_reflection = 0.354;                   // engine sky reflection without planar (0.354: F0 = 0.02)

uniform sampler2D foam_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D caustic_texture : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

struct WaterResult {
	vec3 albedo;
	vec3 emission;
	float roughness;
	float specular;
	float foam;
	// What is left for light scattered inside the water after the reflection took its share.
	float transmitted;
	// 1 when the surface is seen from above; light() only lights the top.
	float front;
};

// Bright, sharp light lines on the bottom: two drifting layers of cellular-edge noise.
float water_caustics(vec2 p, float t) {
	vec2 q = p * caustic_scale;
	float a = texture(caustic_texture, q + vec2(t * 0.031, t * 0.017)).r;
	float b = texture(caustic_texture, q * 1.31 + vec2(-t * 0.022, t * 0.029) + 0.5).r;
	return pow(min(a, b), 2.0) * 4.0;
}

// The camera-facing surface and what the shader knows about it.
struct WaterSurface {
	vec3 n_world;      // final normal, pointing up
	vec3 n_view;       // the same in view space
	vec3 world;        // surface position
	vec3 vertex_view;  // VERTEX
	vec2 slope_variance; // slopes the pixel can't resolve, per axis
	float crest_foam;  // 0..1 from the wave shape
	vec2 foam_motion;  // how the built-in foam drifts (m/s)
	bool from_below;   // !FRONT_FACING: the camera is under the surface
};

// screen: (SCREEN_UV, FRAGCOORD.xy); proj: (PROJECTION_MATRIX[0][0], [1][1]).
WaterResult water_shade(WaterSurface s, vec2 screen_uv, vec2 frag_coord, vec2 proj, mat4 inv_proj, mat4 inv_view,
		vec3 cam_pos, float t) {
	WaterResult r;
	vec3 v = normalize(cam_pos - s.world);
	float dist = length(cam_pos - s.world);
	float roughness = water_roughness(s.slope_variance);
	r.roughness = roughness;
	r.foam = 0.0;
	r.specular = 0.0;
	r.albedo = vec3(0.0);
	if (s.from_below) {
		vec3 n_down = -s.n_world;
		vec3 above = textureLod(screen_tex, screen_uv - s.n_view.xy * refraction_strength, 0.0).rgb;
		r.emission = water_seen_from_below(n_down, v, above, deep_color, absorption, dist);
		r.transmitted = 0.0;
		r.front = 0.0;
		return r;
	}
	r.front = 1.0;
	float ndv = clamp(dot(s.n_world, v), 0.0, 1.0);
	// Rough water reflects less sharply at grazing angles (masking of wave backs), as on the ocean.
	float fresnel = water_schlick(ndv) * mix(1.0, 0.75, roughness);

	// Ground straight behind this pixel (for shore foam) and behind the refracted ray (for colour).
	vec3 g_view = water_view_from_depth(screen_uv, texture(depth_tex, screen_uv).r, inv_proj);
	float thickness = max(s.vertex_view.z - g_view.z, 0.0);
	// A refracted ray bends by an angle, so its screen offset shrinks with distance; a constant offset lands
	// on nearby objects at range and the fallback below then draws their silhouette into the water.
	// The offset also fades out at the screen edges so it never samples outside the screen.
	float distance_scale = min(1.0, refraction_full_distance / max(-s.vertex_view.z, 0.001));
	vec2 to_edge = min(screen_uv, vec2(1.0) - screen_uv);
	float edge_fade = smoothstep(0.0, 2.0 * refraction_strength, min(to_edge.x, to_edge.y));
	vec2 ruv = screen_uv + s.n_view.xy * refraction_strength * clamp(thickness, 0.0, 1.0) * distance_scale * edge_fade;
	vec3 rg_view = water_view_from_depth(ruv, texture(depth_tex, ruv).r, inv_proj);
	if (rg_view.z > s.vertex_view.z) { // refracted sample lands on something in front of the water
		ruv = screen_uv;
		rg_view = g_view;
	}
	vec3 g_world = (inv_view * vec4(rg_view, 1.0)).xyz;
	vec3 straight_world = (inv_view * vec4(g_view, 1.0)).xyz;
	float path = max(length(rg_view) - length(s.vertex_view), 0.0);
	float depth_below = max(s.world.y - g_world.y, 0.0);
	float shore_depth = max(s.world.y - straight_world.y, 0.0);

	vec3 transmittance = exp(-absorption * path);
	float murk = 1.0 - dot(transmittance, vec3(1.0 / 3.0));
	float murk_lod = murk * murk_blur;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// Web / Compatibility: no blur through murky water (the screen copy may have no mip levels there).
	murk_lod = 0.0;
#endif
	vec3 bottom = textureLod(screen_tex, ruv, murk_lod).rgb;
	float caustic = water_caustics(g_world.xz, t) * exp(-depth_below * caustic_fade) * smoothstep(0.0, 0.25, depth_below);
	bottom *= 1.0 + caustic * caustic_strength;

	// Moving foam bands that hug the shoreline, broken up by the foam texture.
	vec2 fuv = s.world.xz * 0.35 - s.foam_motion * t;
	float foam_tex = texture(foam_texture, fuv).r * texture(foam_texture, fuv * 0.37 + 0.3).r * 1.6;
	float band = 0.5 + 0.5 * sin(shore_depth / shore_foam_width * 9.0 - t * 1.7);
	float shore = 1.0 - smoothstep(0.0, shore_foam_width, shore_depth);
	float foam = shore * mix(0.6, 1.0, band) * shore_foam_strength;
	foam += s.crest_foam * crest_foam_strength;
	foam = clamp(foam * mix(1.0, smoothstep(0.25, 0.75, foam_tex + foam * 0.35), foam_breakup), 0.0, 1.0);

	// Thin water at the very edge fades its reflection so the shore has no hard seam.
	float edge = smoothstep(0.0, 0.12, path);
	vec3 reflection = vec3(0.0);
	bool planar = water_reflection_enabled;
	if (planar) {
		float slope_sigma = sqrt(0.5 * (s.slope_variance.x + s.slope_variance.y)) * reflection_blur;
		vec2 spread = water_reflection_spread(slope_sigma, ndv, proj);
		reflection = water_reflection_sample(screen_uv, s.n_view.xy * reflection_distortion, spread, frag_coord);
	}
	float f = fresnel * edge;
	r.emission = (bottom * transmittance * (1.0 - f) + reflection * f) * (1.0 - foam);
	r.albedo = mix(scatter_color * murk * (1.0 - f), foam_color, foam);
	r.roughness = mix(roughness, 0.85, foam);
	r.specular = planar ? 0.0 : sky_reflection * edge * (1.0 - foam);
	r.foam = foam;
	r.transmitted = 1.0 - f;
	return r;
}

// Call from light() with the WaterResult values passed through varyings.
// crest: metres above the rest level, for light shining through thin crests.
void water_light(vec3 n, vec3 v, vec3 l, vec3 light_color, float attenuation, float roughness, float crest,
		float foam_amount, float transmitted, float front, inout vec3 diffuse_light, inout vec3 specular_light) {
	if (front < 0.5) {
		return;
	}
	float ndl = clamp(dot(n, l), 0.0, 1.0);
	diffuse_light += ndl * attenuation * light_color / PI;
	float glint = water_ggx_specular(n, v, l, roughness) * sun_specular_strength;
	specular_light += glint * attenuation * light_color * (1.0 - foam_amount);
	float scatter = water_scatter(n, v, l, crest, sss_crest_strength, sss_view_strength);
	specular_light += scatter * sss_color * light_color * attenuation * transmitted * (1.0 - foam_amount);
}
