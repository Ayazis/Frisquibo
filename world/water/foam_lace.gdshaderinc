// Foam that ages into lace, shared by the sea (breakers, ocean_shore_foam) and the beach (foam the
// swash leaves on the sand, terrain_ground). Fresh foam is a nearly closed sheet; as it ages, holes open
// and grow until only threads are left, and then those go too. The pattern is foam_surface's, with the
// foam's age turned into its fill.

#include "res://world/water/foam_surface.gdshaderinc"

// Holes open quickly at first, then the threads thin slowly: fill falls with age^LACE_OPENING.
const float LACE_OPENING = 0.5;
// The last threads fade out over the end of the foam's life.
const float LACE_FADE_START = 0.75;
// Average cover of old lace, for distant foam that no longer shows the pattern.
const float LACE_FAR_COVER = 0.15;
// Metres the pattern is moved per wave, so each breaker leaves its own lace.
const float LACE_WAVE_SHIFT = 53.0;
// How unevenly lace wears (scales the fill with the caller's broad `breakup` noise).
const vec2 LACE_BREAKUP = vec2(0.6, 1.4);

// Per-wave offset of the pattern (0..1 in each axis).
vec2 water_lace_offset(float seed) {
	float a = fract(sin(seed * 12.9898) * 43758.5453);
	float b = fract(sin(seed * 78.233) * 12543.123);
	return vec2(a, b);
}

// The lace at `p` (metres on the water or the ground), `age` 0 fresh to 1 gone, as a full FoamSurface.
// `breakup` 0..1 from a broad noise: lace wears unevenly. `detail`: foam_detail() of the distance.
FoamSurface water_lace_surface(vec2 p, float age, float seed, float breakup, float detail) {
	float fill = (1.0 - pow(clamp(age, 0.0, 1.0), LACE_OPENING)) * mix(LACE_BREAKUP.x, LACE_BREAKUP.y, breakup);
	FoamSurface f = foam_surface(p + water_lace_offset(seed) * LACE_WAVE_SHIFT, fill, detail, vec2(0.0));
	float fade = 1.0 - smoothstep(LACE_FADE_START, 1.0, age);
	f.cover *= fade;
	f.sub *= fade;
	f.normal *= fade;
	return f;
}

// Lace cover only, up close.
float water_lace(vec2 p, float age, float seed, float breakup) {
	if (age >= 1.0) {
		return 0.0;
	}
	return water_lace_surface(p, age, seed, breakup, 1.0).cover;
}

// What the lace averages to from far away.
float water_lace_far(float age) {
	return mix(1.0, LACE_FAR_COVER, pow(clamp(age, 0.0, 1.0), LACE_OPENING)) * (1.0 - smoothstep(LACE_FADE_START, 1.0, age));
}
