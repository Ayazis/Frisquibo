// White water of the breaking shore waves (ocean_shore_waves): the roller on the breaking front and the
// lace each breaker leaves behind. Both are patterns on the water surface, lit like the rest of the
// foam (relief, bubble glow), not particles.
// Needs from the ocean shader: foam_texture, and the shore waves and foam_lace includes.

// Metres per tile of the foam pattern in the roller, and how fast it tumbles down the face (m/s,
// relative to the crest it rides).
const float SHORE_ROLLER_TILE = 2.5;
const float SHORE_ROLLER_TUMBLE = 0.6;
// The roller's lower edge is ragged: how soft the pattern's threshold is.
const float SHORE_ROLLER_SOFTNESS = 0.15;
// Average cover of the roller seen from far away.
const float SHORE_ROLLER_FAR_COVER = 0.8;
// Metres per tile of the broad noise that makes lace wear unevenly.
const float SHORE_LACE_BREAKUP_TILE = 23.0;

// (foam pattern up close, average cover from far away), both 0..1.
vec2 ocean_shore_foam(ShoreWave w, vec2 rest, float time) {
	float near = 0.0;
	float far = 0.0;
	if (w.roller > 0.0) {
		// The pattern rides the crest (it travels with the wave) and slides down its face.
		vec2 q = vec2(w.crest_frame.x - time * SHORE_ROLLER_TUMBLE, w.crest_frame.y) / SHORE_ROLLER_TILE
				+ water_lace_offset(w.roller_wave);
		float pattern = texture(foam_texture, q).r * 0.6 + texture(foam_texture, q * 2.3 + vec2(0.41, 0.17)).r * 0.4;
		near = smoothstep(1.0 - w.roller, 1.0 - w.roller + SHORE_ROLLER_SOFTNESS, pattern);
		far = w.roller * SHORE_ROLLER_FAR_COVER;
	}
	if (w.lace > 0.0) {
		float breakup = texture(foam_texture, rest / SHORE_LACE_BREAKUP_TILE + water_lace_offset(w.lace_wave)).r;
		near = max(near, water_lace(rest, w.lace_age, w.lace_wave, breakup) * w.lace);
		far = max(far, water_lace_far(w.lace_age) * w.lace);
	}
	return vec2(near, far);
}
