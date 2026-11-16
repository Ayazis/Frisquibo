shader_type spatial;
render_mode blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, shadows_disabled,
		ambient_light_disabled, fog_disabled;
// What the camera sees while its lens is under water (UnderwaterView draws this on a full-screen quad).
// It is the first transparent pass (render_priority below the water's), so the screen copy holds the
// opaque scene; the water surface, which shades itself from below, draws on top of it afterwards.
//  - per-channel absorption and in-scatter over the distance to each pixel, darker with depth
//  - the scene blurs with distance (forward scattering)
//  - a waterline where the wavy surface crosses the lens, with a dark meniscus
//  - light shafts: the sun refracted through the surface, focused by the waves, scattering towards
//    the camera (ray-marched in light(), which has the sun's direction and colour)

#include "res://world/water/water_optics.gdshaderinc"

const int MAX_CASCADES = 4;
// Distance at which fog and shafts stop: everything beyond is fully in-scattered for any real water.
const float MAX_DISTANCE = 400.0;
// Shafts are not drawn for light this close to horizontal inside the water.
const float MIN_LIGHT_DOWN = 0.05;

uniform vec3 absorption = vec3(0.42, 0.07, 0.045);         // per metre, per channel: red dies first
uniform vec3 deep_color : source_color = vec3(0.004, 0.03, 0.04); // radiance of deep water, looking sideways
uniform float blur_per_metre = 0.06;                       // screen mip levels of blur per metre of water
uniform float max_blur = 5.0;
uniform float meniscus_width = 0.012;                      // metres either side of the waterline on the lens
uniform float meniscus_darkening = 0.55;

group_uniforms shafts;
uniform int shaft_steps = 16;                              // from the quality tier; 0 = no shafts
uniform float shaft_distance = 60.0;
uniform vec3 scattering = vec3(0.02, 0.03, 0.03);          // per metre: share of light scattered out of the beam
uniform float shaft_anisotropy = 0.8;                      // Henyey-Greenstein g; sea water scatters forward
uniform float shaft_strength = 1.0;
uniform float shaft_scale = 0.08;                          // pattern size of the focused light at the surface
uniform float shaft_contrast = 0.85;
uniform float shaft_sharpness = 3.0;
uniform sampler2D caustic_texture : hint_default_white, filter_linear_mipmap, repeat_enable;

group_uniforms surface;
// The water surface over the lens: rest level and, for the FFT ocean, the summed cascade displacement
// scaled by wave_scale (its shore damping at the camera). Lakes leave cascade_count at 0.
uniform float surface_level = 0.0;
uniform float wave_scale = 1.0;
uniform sampler2DArray displacement_maps : filter_linear, repeat_enable;
uniform float tile_lengths[4];
uniform int cascade_count = 0;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec3 v_start;
varying vec3 v_dir;
varying float v_dist;

// Henyey-Greenstein phase function, per steradian.
float phase_hg(float cos_theta, float g) {
	float d = 1.0 + g * g - 2.0 * g * cos_theta;
	return (1.0 - g * g) / (4.0 * PI * d * sqrt(d));
}

float surface_height(vec2 p) {
	float h = 0.0;
	for (int i = 0; i < MAX_CASCADES; i++) {
		if (i >= cascade_count) {
			break;
		}
		h += textureLod(displacement_maps, vec3(p / tile_lengths[i], float(i)), 0.0).y;
	}
	return surface_level + h * wave_scale;
}

// Interleaved gradient noise: offsets the ray-march steps per pixel so few steps don't band.
float step_noise(vec2 pixel) {
	return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}

void vertex() {
	// The quad (2 x 2) covers the screen whatever the camera does.
	POSITION = vec4(VERTEX.xy, 0.5, 1.0);
}

void fragment() {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	float near_raw = 0.0;
#else
	float near_raw = 1.0; // reversed Z: 1 is the near plane
#endif
	vec3 near_view = water_view_from_depth(SCREEN_UV, near_raw, INV_PROJECTION_MATRIX);
	vec3 scene_view = water_view_from_depth(SCREEN_UV, texture(depth_tex, SCREEN_UV).r, INV_PROJECTION_MATRIX);
	vec3 near_world = (INV_VIEW_MATRIX * vec4(near_view, 1.0)).xyz;
	vec3 dir = normalize((INV_VIEW_MATRIX * vec4(scene_view, 0.0)).xyz);
	float dist = min(length(scene_view) - length(near_view), MAX_DISTANCE);

	// Which part of the lens is under water: the surface over this pixel's point on the near plane.
	float below = surface_height(near_world.xz) - near_world.y;
	float lens_wet = smoothstep(-meniscus_width, meniscus_width, below);
	float meniscus = 1.0 - smoothstep(0.0, 2.0 * meniscus_width, abs(below));

	float lod = clamp(dist * blur_per_metre, 0.0, max_blur);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	lod = 0.0; // Web / Compatibility: the screen copy may have no mip levels.
#endif
	vec3 scene = textureLod(screen_tex, SCREEN_UV, lod).rgb;
	// Less daylight reaches deeper water: darken the in-scatter by the depth halfway along the ray.
	vec3 end = near_world + dir * dist;
	float mid_depth = max(surface_level - 0.5 * (near_world.y + end.y), 0.0);
	vec3 ambient = deep_color * exp(-absorption * mid_depth);
	vec3 transmittance = exp(-absorption * dist);
	vec3 seen = scene * transmittance + ambient * (1.0 - transmittance);

	EMISSION = seen * (1.0 - meniscus * meniscus_darkening);
	ALBEDO = vec3(0.0);
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	ALPHA = lens_wet;
	v_start = near_world;
	v_dir = dir;
	v_dist = dist;
}

void light() {
	if (LIGHT_IS_DIRECTIONAL && shaft_steps > 0) {
		vec3 to_light = normalize((INV_VIEW_MATRIX * vec4(LIGHT, 0.0)).xyz);
		// Direction sunlight travels in once it has crossed a flat surface.
		vec3 down = refract(-to_light, vec3(0.0, 1.0, 0.0), 1.0 / WATER_IOR);
		if (down.y < -MIN_LIGHT_DOWN) {
			float len = min(v_dist, shaft_distance);
			float dt = len / float(shaft_steps);
			float jitter = step_noise(FRAGCOORD.xy);
			vec3 sum = vec3(0.0);
			for (int i = 0; i < shaft_steps; i++) {
				float t = (float(i) + jitter) * dt;
				vec3 p = v_start + v_dir * t;
				float depth = surface_level - p.y;
				if (depth <= 0.0) {
					continue;
				}
				// Follow the sunbeam back up to the surface, where the waves focus it into a pattern.
				float beam = depth / -down.y;
				vec2 at_surface = (p - down * beam).xz;
				float pattern = texture(caustic_texture, at_surface * shaft_scale + vec2(TIME * 0.011, TIME * 0.007)).r;
				float focus = mix(1.0, pow(pattern, shaft_sharpness) * (shaft_sharpness + 1.0), shaft_contrast);
				sum += focus * exp(-absorption * (beam + t)) * dt;
			}
			float phase = phase_hg(dot(down, -v_dir), shaft_anisotropy);
			SPECULAR_LIGHT += sum * scattering * phase * LIGHT_COLOR * shaft_strength;
		}
	}
}
