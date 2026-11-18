// White water of the breaking shore waves (ocean_shore_waves): the roller on the breaking front and the
// lace each breaker leaves behind. Both are patterns on the water surface, lit like the rest of the
// foam (relief, bubble glow), not particles.
// Needs from the ocean shader: foam_texture, and the shore waves and foam_lace includes.
// Both use the shared foam surface (foam_surface.gdshaderinc): thresholding a noise directly drew contour
// lines that looked like marble.

// How fast the roller's foam tumbles down the face (m/s, relative to the crest it rides).
const float SHORE_ROLLER_TUMBLE = 0.6;
// Average cover of the roller seen from far away.
const float SHORE_ROLLER_FAR_COVER = 0.8;
// Metres per tile of the broad noise that makes lace wear unevenly.
const float SHORE_LACE_BREAKUP_TILE = 23.0;

// (foam pattern up close, average cover from far away), both 0..1. `detail`: foam_detail() of the distance.
// `shade`: the foam's brightness (FoamSurface.shade).
vec2 ocean_shore_foam(ShoreWave w, vec2 rest, float time, float detail, out float shade) {
	vec2 roller = vec2(0.0, 1.0);
	vec2 lace = vec2(0.0, 1.0);
	float far = 0.0;
	if (w.roller > 0.0) {
		// The pattern rides the crest (it travels with the wave) and slides down its face. The foam surface
		// stretches its x, so x runs along the crest, as foam is drawn out along a breaker.
		vec2 q = vec2(w.crest_frame.y, w.crest_frame.x - time * SHORE_ROLLER_TUMBLE)
				+ water_lace_offset(w.roller_wave) * LACE_WAVE_SHIFT;
		FoamSurface fs = foam_surface(q, w.roller, detail, vec2(0.0));
		roller = vec2(fs.cover, fs.shade);
		far = w.roller * SHORE_ROLLER_FAR_COVER;
	}
	if (w.lace > 0.0) {
		float breakup = texture(foam_texture, rest / SHORE_LACE_BREAKUP_TILE + water_lace_offset(w.lace_wave)).r;
		lace = water_lace_shaded(rest, w.lace_age, w.lace_wave, breakup);
		lace.x *= w.lace;
		far = max(far, water_lace_far(w.lace_age) * w.lace);
	}
	shade = water_foam_shade(roller, lace, vec2(0.0, 1.0));
	return vec2(max(roller.x, lace.x), far);
}
