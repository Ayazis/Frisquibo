// The swash on a beach: each wave runs up the sand and slides back down. Shared by the ocean surface,
// which rises to the swash edge near the waterline, and the ground (damp sand, the glossy film the
// backwash leaves), so the two always agree. Ocean publishes the run-up and period (ShoreRunup).

// R2% run-up above still water (m; 0 = no waves) and the dominant wave period (s).
global uniform float water_swash_runup;
global uniform float water_swash_period;
// The ocean's wave clock (s), published by Ocean each frame. The swash, the shore waves
// (ocean_shore_waves) and Ocean.height_at all run on it, so they agree with each other and with the CPU.
global uniform float water_wave_time;

// Share of a swash cycle spent running up; the rest is the slower backwash.
const float SWASH_UPRUSH_SHARE = 0.3;
// Waves vary: each reaches between this share of the run-up and all of it.
const float SWASH_SMALLEST = 0.45;
// Metres along the shore over which neighbouring stretches of beach are hit at different times.
const float SWASH_ALONGSHORE = 25.0;
// How many wave periods the timing differs between stretches of beach. The shore waves share this
// timing, so it also sets how far their crests turn away from parallel to the beach.
const float SWASH_PHASE_SPREAD = 0.5;
// Offset between the noise of successive waves, so each reaches its own height.
const float SWASH_WAVE_STEP = 7.31;

// Keeps lattice coordinates positive before they become unsigned integers.
const int SWASH_HASH_OFFSET = 1048576;

// Integer hash of a lattice point (Quilez), in 0..1. Integer arithmetic gives the same value on every GPU
// and in ShoreWaves.hash() on the CPU, so floating objects ride the same waves the screen shows.
float swash_hash(vec2 p) {
	uvec2 q = uvec2(ivec2(p) + ivec2(SWASH_HASH_OFFSET));
	q *= uvec2(1597334677u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334677u;
	return float(n) / 4294967295.0;
}

float swash_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(swash_hash(i), swash_hash(i + vec2(1.0, 0.0)), u.x),
			mix(swash_hash(i + vec2(0.0, 1.0)), swash_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// At world `p` and time `t`: (height of the swash edge now, highest point this wave reaches, share of
// the swash cycle gone by, number of the wave). Heights in metres above still water. The edge is 0
// between waves, so a new wave starts without a jump.
vec4 water_swash_state(vec2 p, float t) {
	float runup = max(water_swash_runup, 0.0);
	if (runup <= 0.0) {
		return vec4(0.0);
	}
	float phase = t / max(water_swash_period, 0.1) + swash_noise(p / SWASH_ALONGSHORE) * SWASH_PHASE_SPREAD;
	float cycle = fract(phase);
	float reach = runup * mix(SWASH_SMALLEST, 1.0, swash_noise(p / SWASH_ALONGSHORE + floor(phase) * SWASH_WAVE_STEP));
	float rush = cycle < SWASH_UPRUSH_SHARE ? smoothstep(0.0, SWASH_UPRUSH_SHARE, cycle)
			: 1.0 - smoothstep(SWASH_UPRUSH_SHARE, 1.0, cycle);
	return vec4(reach * rush, reach, cycle, floor(phase));
}

// (height of the swash edge now, highest point this wave reaches): see water_swash_state.
vec2 water_swash(vec2 p, float t) {
	return water_swash_state(p, t).xy;
}
