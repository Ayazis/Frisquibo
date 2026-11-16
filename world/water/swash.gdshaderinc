// The swash on a beach: each wave runs up the sand and slides back down. Shared by the ocean surface,
// which rises to the swash edge near the waterline, and the ground (damp sand, the glossy film the
// backwash leaves), so the two always agree. Ocean publishes the run-up and period (ShoreRunup).

// R2% run-up above still water (m; 0 = no waves) and the dominant wave period (s).
global uniform float water_swash_runup;
global uniform float water_swash_period;

// Share of a swash cycle spent running up; the rest is the slower backwash.
const float SWASH_UPRUSH_SHARE = 0.3;
// Waves vary: each reaches between this share of the run-up and all of it.
const float SWASH_SMALLEST = 0.45;
// Metres along the shore over which neighbouring stretches of beach are hit at different times.
const float SWASH_ALONGSHORE = 25.0;
// How many wave periods the timing differs between stretches of beach.
const float SWASH_PHASE_SPREAD = 1.5;
// Offset between the noise of successive waves, so each reaches its own height.
const float SWASH_WAVE_STEP = 7.31;

float swash_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float swash_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(swash_hash(i), swash_hash(i + vec2(1.0, 0.0)), u.x),
			mix(swash_hash(i + vec2(0.0, 1.0)), swash_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// At world `p` and time `t`: (height of the swash edge now, highest point this wave reaches), both in
// metres above still water. The edge is 0 between waves, so a new wave starts without a jump.
vec2 water_swash(vec2 p, float t) {
	float runup = max(water_swash_runup, 0.0);
	if (runup <= 0.0) {
		return vec2(0.0);
	}
	float phase = t / max(water_swash_period, 0.1) + swash_noise(p / SWASH_ALONGSHORE) * SWASH_PHASE_SPREAD;
	float cycle = fract(phase);
	float reach = runup * mix(SWASH_SMALLEST, 1.0, swash_noise(p / SWASH_ALONGSHORE + floor(phase) * SWASH_WAVE_STEP));
	float rush = cycle < SWASH_UPRUSH_SHARE ? smoothstep(0.0, SWASH_UPRUSH_SHARE, cycle)
			: 1.0 - smoothstep(SWASH_UPRUSH_SHARE, 1.0, cycle);
	return vec2(reach * rush, reach);
}
