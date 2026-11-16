// Gusts ("cat's paws"): wind is never even, so patches of water are rougher and others glassier, and the
// patches drift downwind. Water shaders scale their smallest ripples by water_gusts(); it averages 1.

// Two layers of the gust texture, the second smaller and faster, so patches change shape as they drift.
const float WATER_GUST_SECOND_SCALE = 2.3;
const float WATER_GUST_SECOND_SPEED = 1.4;
// Gust patterns travel at about this share of the wind speed.
const float WATER_GUST_DRIFT_SHARE = 0.6;

// Multiplier on small-ripple energy at `p`: between 1 - strength and 1 + strength.
// air: wind direction * m/s; size: metres across a patch; t: time in seconds.
// (Parameter names avoid the shaders' uniform names, which they may not shadow.)
float water_gusts(sampler2D field, vec2 p, vec2 air, float size, float strength, float t) {
	vec2 drift = air * WATER_GUST_DRIFT_SHARE * t;
	float a = texture(field, (p - drift) / size).r;
	float b = texture(field, (p - drift * WATER_GUST_SECOND_SPEED) / (size / WATER_GUST_SECOND_SCALE) + 0.37).r;
	// The noise sits around 0.5; stretch it so patches have clear edges.
	float g = smoothstep(0.3, 0.7, a * 0.65 + b * 0.35);
	return 1.0 + strength * (2.0 * g - 1.0);
}
