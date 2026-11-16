shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, world_vertex_coords;
// Surface of the FFT ocean (see ocean_simulation.gd). Per pixel:
//  - normals from the summed slopes of all cascades, sharpened by the horizontal-displacement jacobian
//  - LEAN mapping: slope variance from the mip chain becomes GGX roughness, so distant waves turn into a
//    wide, glittering sun path instead of aliasing
//  - planar (desktop) or sky reflection with Fresnel, the planar one blurred by the same slope variance;
//    refraction with per-channel absorption, light lost on its way down to the seabed, and caustics
//    focused by the simulated waves (ocean_caustics)
//  - subsurface light through thin crests (the Atlas model), persistent whitecaps and shoreline surf
//  - interaction ripples, wakes and splash foam from objects in the water (WaterRipples)
//  - seen from below: Snell's window and total internal reflection

const int MAX_CASCADES = 4;
const int MAX_LOCAL_RULES = 8; // must match OceanLocalRules.MAX_RULES

uniform sampler2DArray displacement_maps : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray slope_maps : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray moment_maps : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_lengths[4];
uniform int cascade_count = 4;
uniform float map_size = 256.0;
// Angular step of the surface mesh, to estimate vertex spacing for anti-aliased displacement.
uniform float mesh_angular_step = 0.0123;
uniform float sea_level = 0.0;

group_uniforms optics;
uniform vec3 absorption = vec3(0.42, 0.07, 0.045);         // per metre, per channel: red dies first
uniform vec3 scatter_color : source_color = vec3(0.012, 0.095, 0.11);
uniform vec3 sss_color : source_color = vec3(0.06, 0.42, 0.36);
uniform vec3 deep_color : source_color = vec3(0.004, 0.03, 0.04); // seen from below, beyond Snell's window
uniform float sss_crest_strength = 3.2;
uniform float sss_view_strength = 0.35;
uniform float refraction_strength = 0.06;
uniform float refraction_full_distance = 8.0;                // metres; the offset shrinks beyond this
uniform float reflection_distortion = 0.035;
uniform float reflection_blur = 1.0;                       // 1 = blur by the real unresolved slopes
uniform float base_slope_variance = 0.0006;                // capillary ripples below the smallest cascade
uniform float sun_specular_strength = 1.0;
uniform float murk_blur = 3.0;                             // screen mip levels of blur through deep water

group_uniforms foam;
uniform vec3 foam_color : source_color = vec3(0.86, 0.9, 0.9);
uniform float foam_scale = 0.22;
uniform float foam_softness = 0.18;
uniform float whitecap_strength = 1.0;
uniform float foam_cascade_falloff = 0.6;                  // smaller cascades make thinner, shorter-lived foam
uniform float shore_foam_width = 0.9;
uniform float surf_depth = 1.6;
uniform float foam_far_distance = 250.0;
uniform float foam_streaks = 0.35;                         // cover of wind-blown streaks in a full gale
uniform float streak_length = 24.0;                        // streaks are this many times longer than wide
// Wind over the sea (direction * m/s), set by Ocean from the sea state.
uniform vec2 wind = vec2(8.16, 3.8);
uniform sampler2D foam_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

// Foam starts to blow into streaks along the wind at Beaufort 7 and covers the sea with them at 10.
const float STREAK_WIND_START = 13.0;
const float STREAK_WIND_FULL = 28.0;
// Streaks are thinner than whitecaps: a softer white, and a coarser pattern than the bubbles.
const float STREAK_OPACITY = 0.55;
const float STREAK_PATTERN_SCALE = 0.35;
// Streaks gather in bands and patches: a much larger stretched pattern decides where they lie.
const float STREAK_PATCH_SCALE = 0.06;
const vec2 STREAK_PATCH_RANGE = vec2(0.45, 0.75);
const float STREAK_FAR_COVER = 0.35;
group_uniforms caustics;
uniform float caustic_strength = 1.0;                      // 1 = the light the waves really focus
uniform float caustic_fade = 0.1;                          // per metre of depth, on top of the sun-disk blur
// Light on the seabed has crossed the water once already, on its way down. 1 = physical, 0 = none.
uniform float seabed_light_loss = 1.0;

group_uniforms shore;
// Seabed height map baked by Ocean.set_seabed(); rect = (origin x, origin z, size x, size z), size 0 = none.
uniform sampler2D seabed_height : filter_linear, repeat_disable, hint_default_black;
uniform vec4 seabed_rect = vec4(0.0);
// Depth-limited waves: crests can't exceed breaker_ratio * depth (waves break at H = 0.78 d, crest = H / 2).
// wave_amplitude is the typical crest height of the open sea, measured by Ocean from the simulation.
uniform float breaker_ratio = 0.39;
uniform float wave_amplitude = 1.0;
uniform float min_shore_wave = 0.12;
// Wave set-up: breaking waves pile water up towards the beach. Extra level at the waterline, as a
// fraction of wave_amplitude, fading out to zero where breaking starts (depth = amplitude / breaker_ratio).
uniform float wave_setup = 0.3;

group_uniforms folding;
// Strong choppiness pulls crests sideways past their neighbours and the surface folds through itself.
// Horizontal displacement is scaled down where the surface would compress below this jacobian.
uniform float min_jacobian = 0.12;
// Set by Ocean each frame: back faces are only "seen from below" when the camera is under water.
uniform bool camera_underwater = false;

group_uniforms rules;
// Local OceanRules (see OceanLocalRules): per rule a depth range (min, max, softness min, softness max)
// and an effect (output: 0 foam / 1 wave size / 2 water level, operation: 0 add / 1 multiply / 2 set,
// amount, weight of its global conditions).
uniform int local_rule_count = 0;
uniform vec4 local_rule_depth[MAX_LOCAL_RULES];
uniform vec4 local_rule_effect[MAX_LOCAL_RULES];

#include "res://world/water/ocean/ocean_caustics.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

#include "res://world/water/water_optics.gdshaderinc"
#include "res://world/water/water_reflection.gdshaderinc"
#include "res://world/water/ripples/water_ripples.gdshaderinc"

varying vec2 v_rest;
varying vec3 v_world;
varying float v_crest;
varying float v_damping;
varying float v_seabed_depth;
varying float v_front;
varying float v_foam;
varying float v_fresnel_scale;
varying float v_rule_foam;
varying float v_fold;

float seabed_depth(vec2 p) {
	if (seabed_rect.z <= 0.0) {
		return 1e4;
	}
	vec2 uv = (p - seabed_rect.xy) / seabed_rect.zw;
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		return 1e4;
	}
	return sea_level - textureLod(seabed_height, uv, 0.0).r;
}

// Same as OceanLocalRules._soft_step().
float soft_step(float edge, float softness, float x) {
	if (softness <= 0.0) {
		return x > edge ? 1.0 : 0.0;
	}
	return smoothstep(edge - softness * 0.5, edge + softness * 0.5, x);
}

// (foam, wave size, water level) from the local rules at water depth `depth`. Same as OceanLocalRules.evaluate().
vec3 local_rules(float depth) {
	vec3 result = vec3(0.0, 1.0, 0.0);
	for (int i = 0; i < MAX_LOCAL_RULES; i++) {
		if (i >= local_rule_count) {
			break;
		}
		vec4 r = local_rule_depth[i];
		vec4 e = local_rule_effect[i];
		float w = e.w * soft_step(r.x, r.z, depth) * (1.0 - soft_step(r.y, r.w, depth));
		int axis = int(e.x + 0.5);
		float current = axis == 0 ? result.x : (axis == 1 ? result.y : result.z);
		int op = int(e.y + 0.5);
		current = op == 0 ? current + e.z * w : (op == 1 ? current * mix(1.0, e.z, w) : mix(current, e.z, w));
		if (axis == 0) {
			result.x = current;
		} else if (axis == 1) {
			result.y = current;
		} else {
			result.z = current;
		}
	}
	result.y = max(result.y, 0.0);
	return result;
}

// Same as Ocean._setup_lift(): extra water at the beach from breaking waves.
float setup_lift(float depth) {
	if (depth > 1e3) {
		return 0.0;
	}
	float zone = wave_amplitude / max(breaker_ratio, 0.01);
	return wave_setup * wave_amplitude * (1.0 - smoothstep(0.0, zone, depth));
}

// Fraction of the open-sea wave that survives at this water depth. Ripples remain right up to the beach.
float shore_damping(float depth) {
	float limited = breaker_ratio * max(depth, 0.0) / max(wave_amplitude, 0.01);
	return clamp(max(limited, min_shore_wave * smoothstep(0.0, 0.5, depth)), 0.0, 1.0);
}

// Scale on horizontal displacement that keeps the jacobian (1 + dDx/dx)(1 + dDz/dz) from folding.
float fold_limit(vec2 jac) {
	float k = 1.0;
	float limit = min_jacobian - 1.0;
	if (jac.x < limit) {
		k = min(k, limit / jac.x);
	}
	if (jac.y < limit) {
		k = min(k, limit / jac.y);
	}
	return clamp(k, 0.0, 1.0);
}

void vertex() {
	vec2 p = VERTEX.xz;
	float dist = length(p - CAMERA_POSITION_WORLD.xz);
	float spacing = max(dist, 1.0) * mesh_angular_step;
	float depth = seabed_depth(p);
	vec3 rules = local_rules(depth);
	// Set-up and rule water rise the surface and deepen the water the waves see; low land floods.
	float lift = setup_lift(depth) + rules.z;
	v_seabed_depth = depth + lift;
	v_damping = shore_damping(v_seabed_depth) * rules.y;
	v_rule_foam = rules.x;
	vec3 d = vec3(0.0);
	vec2 jac = vec2(0.0);
	for (int i = 0; i < MAX_CASCADES; i++) {
		if (i >= cascade_count) {
			break;
		}
		float tile = tile_lengths[i];
		// Pick the mip whose texels match the vertex spacing: waves the mesh can't carry average out.
		float lod = log2(max(spacing * map_size / tile, 1.0));
		vec3 uv = vec3(p / tile, float(i));
		d += textureLod(displacement_maps, uv, lod).xyz;
		jac += textureLod(slope_maps, uv, lod).zw;
	}
	v_fold = fold_limit(jac * v_damping);
	d.xz *= v_damping * v_fold;
	d.y *= v_damping;
	VERTEX += d;
	VERTEX.y += lift + water_ripples(VERTEX.xz).z;
	v_rest = p;
	v_world = VERTEX;
	v_crest = d.y;
}

void fragment() {
	// --- Surface shape from the simulation -----------------------------------------------------------
	vec2 slope = vec2(0.0);
	vec2 jac = vec2(0.0);
	vec2 variance = vec2(base_slope_variance);
	float foam_cover = 0.0;
	float foam_weight = 1.0;
	for (int i = 0; i < MAX_CASCADES; i++) {
		if (i >= cascade_count) {
			break;
		}
		vec3 uv = vec3(v_rest / tile_lengths[i], float(i));
		vec4 s = texture(slope_maps, uv);
		vec4 m = texture(moment_maps, uv);
		slope += s.xy;
		jac += s.zw;
		variance += max(m.xy - s.xy * s.xy, vec2(0.0));
		foam_cover += m.z * foam_weight;
		foam_weight *= foam_cascade_falloff;
	}
	slope *= v_damping;
	jac *= v_damping * v_fold;
	variance *= v_damping * v_damping;
	// Rings, wakes and splashes from objects in the water (WaterRipples).
	vec4 ripple = water_ripples(v_world.xz);
	slope += ripple.xy;
	vec2 eff = slope / max(vec2(1.0) + jac, vec2(0.25));
	vec3 n_world = normalize(vec3(-eff.x, 1.0, -eff.y));
	// From above, a back face is the far side of a steep or folded crest: draw it as the top surface.
	bool from_below = !FRONT_FACING && camera_underwater;
	if (from_below) {
		n_world = -n_world;
	}
	vec3 n_view = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	float roughness = water_roughness(variance);

	vec3 v = normalize(CAMERA_POSITION_WORLD - v_world);
	float dist = length(CAMERA_POSITION_WORLD - v_world);
	float ndv = dot(n_world, v);
	float fresnel = water_schlick(ndv);
	// Rough, distant water reflects less sharply at grazing angles (masking of wave backs).
	fresnel *= mix(1.0, 0.75, roughness);

	// --- What lies under the surface ------------------------------------------------------------------
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec3 straight_view = water_view_from_depth(SCREEN_UV, raw, INV_PROJECTION_MATRIX);
	float thickness = max(VERTEX.z - straight_view.z, 0.0);
	// Fade the offset out at the screen edges, where it would sample outside the screen.
	vec2 to_edge = min(SCREEN_UV, vec2(1.0) - SCREEN_UV);
	// The fade is twice the largest offset, so the offset is always smaller than the distance to the edge.
	float edge_fade = smoothstep(0.0, 2.0 * refraction_strength, min(to_edge.x, to_edge.y));
	// A refracted ray bends by a fixed angle, so its screen offset shrinks with distance. A constant screen
	// offset reaches far across the world at range and lands on nearer geometry (hard fallback blotches).
	float distance_scale = min(1.0, refraction_full_distance / max(-VERTEX.z, 0.001));
	vec2 ruv = SCREEN_UV + n_view.xy * refraction_strength * clamp(thickness * 0.5, 0.0, 1.0) * edge_fade * distance_scale;
	ruv = clamp(ruv, vec2(0.0), vec2(1.0));
	vec3 bottom_view = water_view_from_depth(ruv, texture(depth_tex, ruv).r, INV_PROJECTION_MATRIX);
	if (bottom_view.z > VERTEX.z) {
		// The refracted sample hit something in front of the water: fall back to straight through.
		ruv = SCREEN_UV;
		bottom_view = straight_view;
	}
	vec3 bottom_world = (INV_VIEW_MATRIX * vec4(bottom_view, 1.0)).xyz;
	vec3 straight_world = (INV_VIEW_MATRIX * vec4(straight_view, 1.0)).xyz;
	float path = max(length(bottom_view) - length(VERTEX), 0.0);
	// Water between the surface and whatever is straight behind it along the view ray: thin only right at
	// the waterline, also against vertical objects (a vertical column would foam a whole submerged side).
	float contact = max(length(straight_view) - length(VERTEX), 0.0);
	vec3 transmittance = exp(-absorption * path);
	float murk = 1.0 - dot(transmittance, vec3(1.0 / 3.0));

	vec3 bottom = textureLod(screen_tex, ruv, murk * murk_blur).rgb;
	float bottom_depth = max(v_world.y - bottom_world.y, 0.0);
	float caustic_weight = caustic_strength * exp(-bottom_depth * caustic_fade) * smoothstep(0.0, 0.3, bottom_depth);
	vec3 caustic = ocean_caustics(bottom_world.xz, bottom_depth, v_damping);
	vec3 downwelling = mix(vec3(1.0), exp(-absorption * bottom_depth), seabed_light_loss);
	bottom *= mix(vec3(1.0), caustic, caustic_weight) * downwelling;
	vec3 refracted = bottom * transmittance;

	// --- Foam: whitecaps from the simulation, surf on shallow ground, a line where water meets land -----
	vec2 fuv = v_rest * foam_scale;
	float tex = texture(foam_texture, fuv).r * 0.65 + texture(foam_texture, fuv * 2.71 + vec2(0.37, 0.11)).r * 0.35;
	float whitecap = clamp(foam_cover * whitecap_strength, 0.0, 1.0);
	// Surf only where the depth limit is actually cutting a wave down (it is breaking), on its crest.
	float breaking = smoothstep(0.0, 0.6, 1.0 - v_damping) * (1.0 - smoothstep(0.0, surf_depth, v_seabed_depth) * 0.5);
	float surf = breaking * smoothstep(0.02, 0.3, v_crest);
	float shore_line = 1.0 - smoothstep(0.0, shore_foam_width, contact);
	float cover = clamp(max(max(whitecap, ripple.w), max(surf * 0.85, shore_line * 0.9)) + v_rule_foam, 0.0, 1.0);
	float foam_near = smoothstep(1.0 - cover, 1.0 - cover + foam_softness, tex);
	// Wind-blown streaks: the foam pattern stretched along the wind, growing with the wind.
	float wind_speed = length(wind);
	vec2 wind_dir = wind_speed > 0.0 ? wind / wind_speed : vec2(1.0, 0.0);
	vec2 along_wind = vec2(dot(v_rest, wind_dir) / streak_length, dot(v_rest, vec2(-wind_dir.y, wind_dir.x)));
	float streak_cover = foam_streaks * smoothstep(STREAK_WIND_START, STREAK_WIND_FULL, wind_speed);
	float streak_tex = texture(foam_texture, along_wind * foam_scale * STREAK_PATTERN_SCALE).r;
	float streak_patch = texture(foam_texture, along_wind * foam_scale * STREAK_PATCH_SCALE + vec2(0.61, 0.23)).r;
	float streak = smoothstep(1.0 - streak_cover, 1.0 - streak_cover + foam_softness, streak_tex) * STREAK_OPACITY
			* smoothstep(STREAK_PATCH_RANGE.x, STREAK_PATCH_RANGE.y, streak_patch);
	foam_near = max(foam_near, streak);
	float foam = mix(foam_near, max(cover * 0.6, streak_cover * STREAK_FAR_COVER), smoothstep(foam_far_distance * 0.3, foam_far_distance, dist));
	// Fade foam and reflection where the water is only millimetres thick, so the shore has no seam.
	float edge = smoothstep(0.0, 0.08, path);
	foam *= smoothstep(0.0, 0.03, path);

	// --- Reflection ------------------------------------------------------------------------------------
	vec3 reflection = vec3(0.0);
	bool planar = water_reflection_enabled && !from_below;
	if (planar) {
		// Slopes the pixel resolves shift the mirror image; the ones it averages away (LEAN variance) blur it.
		float slope_sigma = sqrt(0.5 * (variance.x + variance.y)) * reflection_blur;
		vec2 spread = water_reflection_spread(slope_sigma, ndv, vec2(PROJECTION_MATRIX[0][0], PROJECTION_MATRIX[1][1]));
		reflection = water_reflection_sample(SCREEN_UV, n_view.xy * reflection_distortion, spread, FRAGCOORD.xy);
	}

	float f = fresnel * edge;
	if (!from_below) {
		EMISSION = (refracted * (1.0 - f) + reflection * f) * (1.0 - foam);
		ALBEDO = mix(scatter_color * murk * (1.0 - f), foam_color, foam);
		// Only used for the engine's sky reflection, when there is no planar one.
		SPECULAR = planar ? 0.0 : WATER_ENGINE_SPECULAR * edge * (1.0 - foam);
	} else {
		vec3 above = textureLod(screen_tex, SCREEN_UV + n_view.xy * refraction_strength, 0.0).rgb;
		EMISSION = water_seen_from_below(n_world, v, above, deep_color, absorption, dist);
		ALBEDO = vec3(0.0);
		SPECULAR = 0.0;
	}
	ROUGHNESS = mix(roughness, 0.7, foam);
	NORMAL = n_view;
	v_front = from_below ? 0.0 : 1.0;
	v_foam = foam;
	v_fresnel_scale = 1.0 - f;
}

void light() {
	if (v_front > 0.5) {
		float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
		DIFFUSE_LIGHT += ndl * ATTENUATION * LIGHT_COLOR / PI;
		// Sun glint with the LEAN roughness; light through thin crests (Atlas).
		float glint = water_ggx_specular(NORMAL, VIEW, LIGHT, ROUGHNESS) * sun_specular_strength;
		SPECULAR_LIGHT += glint * ATTENUATION * LIGHT_COLOR * (1.0 - v_foam);
		float scatter = water_scatter(NORMAL, VIEW, LIGHT, v_crest, sss_crest_strength, sss_view_strength);
		SPECULAR_LIGHT += scatter * sss_color * LIGHT_COLOR * ATTENUATION * v_fresnel_scale * (1.0 - v_foam);
	}
}
