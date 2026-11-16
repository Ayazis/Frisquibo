// Optics every water surface shares (sea, lake, river): pure functions, no uniforms, so each shader keeps
// its own tunables. The FFT ocean is the reference; lake and river reach these through water_common.

const float WATER_F0 = 0.02;
const float WATER_IOR = 1.333;
// Smoothest GGX roughness used, so the sun stays a small, finite highlight on a dead calm surface.
const float WATER_MIN_ROUGHNESS = 0.03;

float water_schlick(float cos_theta) {
	return WATER_F0 + (1.0 - WATER_F0) * pow(1.0 - clamp(cos_theta, 0.0, 1.0), 5.0);
}

// Mean Fresnel reflectance over the slopes a pixel can't resolve (Bruneton, Neyret & Holzschuch 2010,
// their fit to the integral over a Gaussian slope distribution, with shadowing and masking). cos_v:
// cosine between the view and the resolved normal; sigma_v: rms unresolved slope along the view
// direction. Rough water seen at a low angle reflects less than one mirror facet would: some facets
// face away, others hide behind the wave backs. Smooth water gets Schlick's mirror value back.
float water_mean_fresnel(float cos_v, float sigma_v) {
	float s = max(sigma_v, 0.0);
	float grazing = pow(1.0 - clamp(cos_v, 0.0, 1.0), 5.0 * exp(-2.69 * s)) / (1.0 + 22.7 * pow(s, 1.5));
	return WATER_F0 + (1.0 - WATER_F0) * grazing;
}

// Rms unresolved slope along the horizontal direction of `v` (towards the viewer), from the slope
// variance per world axis (x, z).
float water_view_slope_sigma(vec3 v, vec2 slope_variance) {
	vec2 h = v.xz;
	float len2 = dot(h, h);
	if (len2 < 1e-8) {
		return sqrt(0.5 * (slope_variance.x + slope_variance.y));
	}
	return sqrt(max(dot(h * h / len2, slope_variance), 0.0));
}

vec3 water_view_from_depth(vec2 uv, float raw, mat4 inv_proj) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec4 v = inv_proj * vec4(vec3(uv, raw) * 2.0 - 1.0, 1.0);
#else
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, raw, 1.0);
#endif
	return v.xyz / v.w;
}

// Slope variance (per axis) to GGX roughness: alpha ~ Beckmann m, m^2 = sigma_x^2 + sigma_z^2, and Godot's
// roughness is sqrt(alpha).
float water_roughness(vec2 slope_variance) {
	return clamp(pow(max(slope_variance.x + slope_variance.y, 0.0), 0.25), WATER_MIN_ROUGHNESS, 1.0);
}

// Sun glint: GGX distribution with height-correlated Smith visibility and Schlick Fresnel, times N.L.
float water_ggx_specular(vec3 n, vec3 v, vec3 l, float roughness) {
	float ndl = clamp(dot(n, l), 0.0, 1.0);
	float ndv = clamp(dot(n, v), 1e-4, 1.0);
	vec3 h = normalize(v + l);
	float ndh = clamp(dot(n, h), 0.0, 1.0);
	float a = roughness * roughness;
	float a2 = a * a;
	float dd = ndh * ndh * (a2 - 1.0) + 1.0;
	float distribution = a2 / (PI * dd * dd);
	float vis = 0.5 / (ndl * sqrt(ndv * ndv * (1.0 - a2) + a2) + ndv * sqrt(ndl * ndl * (1.0 - a2) + a2) + 1e-5);
	return distribution * vis * water_schlick(dot(v, h)) * ndl;
}

// Light scattered inside the water (Atlas, GDC 2019): bright through thin crests facing away from the sun
// (crest_strength, scaled by how high the point is on its wave), plus a soft term towards the viewer.
float water_scatter(vec3 n, vec3 v, vec3 l, float crest, float crest_strength, float view_strength) {
	float ndv = clamp(dot(n, v), 0.0, 1.0);
	float through = crest_strength * max(crest, 0.0) * pow(clamp(dot(l, -v), 0.0, 1.0), 4.0) * pow(0.5 - 0.5 * dot(l, n), 3.0);
	return (through + view_strength * ndv * ndv) / PI;
}

// The surface seen from below: inside Snell's window the world above shows through, outside it the
// surface mirrors the water itself (total internal reflection). n points down towards the viewer.
// Parameter names differ from the shaders' uniforms, which they may not shadow.
vec3 water_seen_from_below(vec3 n, vec3 v, vec3 above, vec3 deep, vec3 absorb, float dist) {
	float cos_i = clamp(dot(n, v), 0.0, 1.0);
	float sin_t2 = WATER_IOR * WATER_IOR * (1.0 - cos_i * cos_i);
	float reflected = sin_t2 >= 1.0 ? 1.0 : water_schlick(sqrt(1.0 - sin_t2));
	vec3 fog = exp(-absorb * dist);
	return mix(above, deep, reflected) * fog + deep * (1.0 - fog);
}

// Godot's F0 is 0.16 * specular^2; this gives water's 0.02 for the engine's own sky reflection.
const float WATER_ENGINE_SPECULAR = 0.354;
// Share of the slope change across a pixel that becomes roughness (Kaplanyan et al. 2016 use a box
// filter of half a pixel each way) and the most roughness it may add.
const float WATER_FOOTPRINT_KERNEL = 0.25;
const float WATER_FOOTPRINT_MAX_VARIANCE = 0.18;

// Geometric specular anti-aliasing: slopes that change within one pixel can't be drawn as a normal, so
// they become roughness. Only valid in fragment(), where derivatives exist.
vec2 water_footprint_variance(vec2 slope_x, vec2 slope_y) {
	vec2 v = WATER_FOOTPRINT_KERNEL * (slope_x * slope_x + slope_y * slope_y);
	return min(v, vec2(WATER_FOOTPRINT_MAX_VARIANCE));
}

// Toksvig: a mipmapped normal map averages bumpy normals into a shorter vector. How much shorter tells
// the slope variance that was averaged away. `n` is the unpacked normal (xyz in -1..1, not normalised).
float water_toksvig_variance(vec3 n) {
	float len = clamp(length(n), 1e-3, 1.0);
	return (1.0 - len) / len;
}
