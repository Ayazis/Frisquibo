// Foam that ages into lace, shared by the sea (breakers, ocean_shore_foam) and the beach (foam the
// swash leaves on the sand, terrain_ground). Fresh foam is a solid sheet. As it ages, bubbles burst
// from the inside of each cell outwards, so holes open and grow until only a network of thin threads is
// left, and then those go too. The cells are the edges of cellular noise (F2 - F1, WaterTextures.lace)
// at two sizes: lace, never scattered spots.

// Set by Ocean (WaterTextures.lace()).
global uniform sampler2D water_foam_lace : filter_linear_mipmap_anisotropic, repeat_enable;

// Metres per tile of the lace texture: about 15 cells across, so cells of about a quarter metre...
const float LACE_TILE = 4.0;
// ...with a finer net of smaller cells inside them, kept thinner by a lift on its edge distance.
const float LACE_FINE_SCALE = 2.3;
const float LACE_FINE_LIFT = 0.12;
// Width of the threads (in the texture's 0..1 edge distance) when fresh (all covered) and when old.
const float LACE_SOLID = 1.0;
const float LACE_THREAD = 0.04;
// Holes open quickly at first, then the threads thin slowly: width follows age^LACE_OPENING.
const float LACE_OPENING = 0.5;
const float LACE_SOFTNESS = 0.03;
// The last threads fade out over the end of the foam's life.
const float LACE_FADE_START = 0.75;
// Average cover of old lace, for distant foam that no longer shows the pattern.
const float LACE_FAR_COVER = 0.15;

// Per-wave offset of the pattern, so each breaker leaves its own lace.
vec2 water_lace_offset(float seed) {
	float a = fract(sin(seed * 12.9898) * 43758.5453);
	float b = fract(sin(seed * 78.233) * 12543.123);
	return vec2(a, b);
}

// Lace cover at `p` (metres on the water or the ground), `age` 0 fresh to 1 gone. `breakup` 0..1 from
// a broad noise: lace wears unevenly, thinner in some patches than in others.
float water_lace(vec2 p, float age, float seed, float breakup) {
	if (age >= 1.0) {
		return 0.0;
	}
	vec2 q = p / LACE_TILE + water_lace_offset(seed);
	float edge = min(texture(water_foam_lace, q).r,
			texture(water_foam_lace, q * LACE_FINE_SCALE + vec2(0.37, 0.61)).r + LACE_FINE_LIFT);
	float width = mix(LACE_SOLID, LACE_THREAD, pow(clamp(age, 0.0, 1.0), LACE_OPENING)) * mix(0.6, 1.4, breakup);
	return (1.0 - smoothstep(width, width + LACE_SOFTNESS, edge)) * (1.0 - smoothstep(LACE_FADE_START, 1.0, age));
}

// What the lace averages to from far away.
float water_lace_far(float age) {
	return mix(1.0, LACE_FAR_COVER, pow(clamp(age, 0.0, 1.0), LACE_OPENING)) * (1.0 - smoothstep(LACE_FADE_START, 1.0, age));
}
