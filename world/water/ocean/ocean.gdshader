shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, world_vertex_coords;
// Surface of the FFT ocean (see ocean_simulation.gd). Per pixel:
//  - normals from the summed slopes of all cascades, sharpened by the horizontal-displacement jacobian
//  - LEAN mapping: slope variance from the mip chain becomes GGX roughness, so distant waves turn into a
//    wide, glittering sun path instead of aliasing
//  - planar (desktop) or sky reflection with Fresnel; refraction with per-channel absorption and caustics
//  - subsurface light through thin crests (the Atlas model), persistent whitecaps and shoreline surf
//  - seen from below: Snell's window and total internal reflection

const int MAX_CASCADES = 4;
const float WATER_F0 = 0.02;
const float WATER_IOR = 1.333;

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
uniform sampler2D foam_texture : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

group_uniforms caustics;
uniform float caustic_strength = 2.4;
uniform float caustic_scale = 0.3;
uniform float caustic_fade = 0.35;                         // per metre of depth
uniform sampler2D caustic_texture : hint_default_black, filter_linear_mipmap, repeat_enable;

group_uniforms shore;
// Seabed height map baked by Ocean.set_seabed(); rect = (origin x, origin z, size x, size z), size 0 = none.
uniform sampler2D seabed_height : filter_linear, repeat_disable, hint_default_black;
uniform vec4 seabed_rect = vec4(0.0);
// Depth-limited waves: crests can't exceed breaker_ratio * depth (waves break at H = 0.78 d, crest = H / 2).
// wave_amplitude is the typical crest height of the open sea, measured by Ocean from the simulation.
uniform float breaker_ratio = 0.39;
uniform float wave_amplitude = 1.0;
uniform float min_shore_wave = 0.12;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

global uniform sampler2D water_reflection : filter_linear;
global uniform bool water_reflection_enabled;

varying vec2 v_rest;
varying vec3 v_world;
varying float v_crest;
varying float v_damping;
varying float v_seabed_depth;
varying float v_front;
varying float v_foam;
varying float v_fresnel_scale;

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

// Fraction of the open-sea wave that survives at this water depth. Ripples remain right up to the beach.
float shore_damping(float depth) {
	float limited = breaker_ratio * max(depth, 0.0) / max(wave_amplitude, 0.01);
	return clamp(max(limited, min_shore_wave * smoothstep(0.0, 0.5, depth)), 0.0, 1.0);
}

vec3 view_from_depth(vec2 uv, float raw, mat4 inv_proj) {
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, raw, 1.0);
	return v.xyz / v.w;
}

float schlick(float cos_theta) {
	return WATER_F0 + (1.0 - WATER_F0) * pow(1.0 - clamp(cos_theta, 0.0, 1.0), 5.0);
}

void vertex() {
	vec2 p = VERTEX.xz;
	float dist = length(p - CAMERA_POSITION_WORLD.xz);
	float spacing = max(dist, 1.0) * mesh_angular_step;
	v_seabed_depth = seabed_depth(p);
	v_damping = shore_damping(v_seabed_depth);
	vec3 d = vec3(0.0);
	for (int i = 0; i < MAX_CASCADES; i++) {
		if (i >= cascade_count) {
			break;
		}
		float tile = tile_lengths[i];
		// Pick the mip whose texels match the vertex spacing: waves the mesh can't carry average out.
		float lod = log2(max(spacing * map_size / tile, 1.0));
		d += textureLod(displacement_maps, vec3(p / tile, float(i)), lod).xyz;
	}
	d *= v_damping;
	VERTEX += d;
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
	jac *= v_damping;
	variance *= v_damping * v_damping;
	vec2 eff = slope / max(vec2(1.0) + jac, vec2(0.25));
	vec3 n_world = normalize(vec3(-eff.x, 1.0, -eff.y));
	if (!FRONT_FACING) {
		n_world = -n_world;
	}
	vec3 n_view = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	// GGX alpha ~ Beckmann m, m^2 = sigma_x^2 + sigma_z^2; Godot roughness is sqrt(alpha).
	float roughness = clamp(pow(variance.x + variance.y, 0.25), 0.03, 1.0);

	vec3 v = normalize(CAMERA_POSITION_WORLD - v_world);
	float dist = length(CAMERA_POSITION_WORLD - v_world);
	float ndv = dot(n_world, v);
	float fresnel = schlick(ndv);
	// Rough, distant water reflects less sharply at grazing angles (masking of wave backs).
	fresnel *= mix(1.0, 0.75, roughness);

	// --- What lies under the surface ------------------------------------------------------------------
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec3 straight_view = view_from_depth(SCREEN_UV, raw, INV_PROJECTION_MATRIX);
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
	vec3 bottom_view = view_from_depth(ruv, texture(depth_tex, ruv).r, INV_PROJECTION_MATRIX);
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
	vec2 cp = bottom_world.xz * caustic_scale + eff * 0.6;
	float ca = texture(caustic_texture, cp + vec2(TIME * 0.031, TIME * 0.017)).r;
	float cb = texture(caustic_texture, cp * 1.31 + vec2(-TIME * 0.022, TIME * 0.029) + 0.5).r;
	float caustic = pow(min(ca, cb), 2.0) * 4.0 * exp(-bottom_depth * caustic_fade) * smoothstep(0.0, 0.3, bottom_depth);
	bottom *= 1.0 + caustic * caustic_strength;
	vec3 refracted = bottom * transmittance;

	// --- Foam: whitecaps from the simulation, surf on shallow ground, a line where water meets land -----
	vec2 fuv = v_rest * foam_scale;
	float tex = texture(foam_texture, fuv).r * 0.65 + texture(foam_texture, fuv * 2.71 + vec2(0.37, 0.11)).r * 0.35;
	float whitecap = clamp(foam_cover * whitecap_strength, 0.0, 1.0);
	float surf = (1.0 - smoothstep(0.0, surf_depth, v_seabed_depth)) * smoothstep(-0.05, 0.25, v_crest);
	float shore_line = 1.0 - smoothstep(0.0, shore_foam_width, contact);
	float cover = clamp(max(whitecap, max(surf * 0.85, shore_line * 0.9)), 0.0, 1.0);
	float foam_near = smoothstep(1.0 - cover, 1.0 - cover + foam_softness, tex);
	float foam = mix(foam_near, cover * 0.6, smoothstep(foam_far_distance * 0.3, foam_far_distance, dist));
	// Fade foam and reflection where the water is only millimetres thick, so the shore has no seam.
	float edge = smoothstep(0.0, 0.08, path);
	foam *= smoothstep(0.0, 0.03, path);

	// --- Reflection ------------------------------------------------------------------------------------
	vec3 reflection = vec3(0.0);
	bool planar = water_reflection_enabled && FRONT_FACING;
	if (planar) {
		vec2 puv = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y) + n_view.xy * reflection_distortion;
		reflection = texture(water_reflection, clamp(puv, vec2(0.001), vec2(0.999))).rgb;
	}

	float f = fresnel * edge;
	if (FRONT_FACING) {
		EMISSION = (refracted * (1.0 - f) + reflection * f) * (1.0 - foam);
		ALBEDO = mix(scatter_color * murk * (1.0 - f), foam_color, foam);
		// Godot's F0 is 0.16 * specular^2; 0.354 gives water's 0.02. Only used for sky reflection.
		SPECULAR = planar ? 0.0 : 0.354 * edge * (1.0 - foam);
	} else {
		// Below the surface: inside Snell's window we see the world above, outside it the water mirrors itself.
		float cos_i = clamp(dot(n_world, v), 0.0, 1.0);
		float sin_t2 = WATER_IOR * WATER_IOR * (1.0 - cos_i * cos_i);
		float under_f = sin_t2 >= 1.0 ? 1.0 : schlick(sqrt(1.0 - sin_t2));
		vec3 above = textureLod(screen_tex, SCREEN_UV + n_view.xy * refraction_strength, 0.0).rgb;
		vec3 fog = exp(-absorption * dist);
		EMISSION = mix(above, deep_color, under_f) * fog + deep_color * (1.0 - fog);
		ALBEDO = vec3(0.0);
		SPECULAR = 0.0;
	}
	ROUGHNESS = mix(roughness, 0.7, foam);
	NORMAL = n_view;
	v_front = FRONT_FACING ? 1.0 : 0.0;
	v_foam = foam;
	v_fresnel_scale = 1.0 - f;
}

void light() {
	if (v_front > 0.5) {
	vec3 n = NORMAL;
	vec3 l = LIGHT;
	vec3 v = VIEW;
	float ndl = clamp(dot(n, l), 0.0, 1.0);
	float ndv = clamp(dot(n, v), 1e-4, 1.0);
	DIFFUSE_LIGHT += ndl * ATTENUATION * LIGHT_COLOR / PI;

	// Sun glint: GGX with the LEAN roughness, height-correlated Smith visibility.
	vec3 h = normalize(v + l);
	float ndh = clamp(dot(n, h), 0.0, 1.0);
	float a = ROUGHNESS * ROUGHNESS;
	float a2 = a * a;
	float dd = ndh * ndh * (a2 - 1.0) + 1.0;
	float distribution = a2 / (PI * dd * dd);
	float vis = 0.5 / (ndl * sqrt(ndv * ndv * (1.0 - a2) + a2) + ndv * sqrt(ndl * ndl * (1.0 - a2) + a2) + 1e-5);
	float fres = schlick(dot(v, h));
	SPECULAR_LIGHT += distribution * vis * fres * ndl * ATTENUATION * LIGHT_COLOR * sun_specular_strength * (1.0 - v_foam);

	// Light scattered inside the water (Atlas, GDC 2019): bright through thin crests facing away from the
	// sun, plus a soft term towards the viewer.
	float crest = max(v_crest, 0.0);
	float k1 = sss_crest_strength * crest * pow(clamp(dot(l, -v), 0.0, 1.0), 4.0) * pow(0.5 - 0.5 * dot(l, n), 3.0);
	float k2 = sss_view_strength * pow(ndv, 2.0);
	vec3 scatter = (k1 + k2) * sss_color * LIGHT_COLOR * ATTENUATION / PI;
	SPECULAR_LIGHT += scatter * v_fresnel_scale * (1.0 - v_foam);
}
}
