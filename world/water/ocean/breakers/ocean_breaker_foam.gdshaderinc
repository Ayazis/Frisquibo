// White water of a plunging breaker (ocean_breakers), as foam on the water's surface like all the other
// foam: never as puffs. The lip turns white from its tip as it flies and air gets into it, the water it
// lands on bursts into fresh foam where it splashes up, and after the plunge the whole curl foams over
// on its way to becoming a bore (whose roller and lace ocean_shore_foam draws).
// Needs: foam_lace, ocean_breakers.

// The lip aerates from its tip, starting at this stage and fully white at the plunge...
const float BREAKER_AERATION_START = 0.3;
// ...over this share of the lip back from the tip (in sheet parts).
const float BREAKER_AERATION_REACH = 0.6;
// After the plunge the curl foams over between these stages.
const vec2 BREAKER_FOAM_OVER = vec2(1.0, 1.6);
// Fresh foam is lace at this age: nearly solid, with a few holes.
const float BREAKER_FRESH_FOAM = 0.12;

// (foam pattern up close, average cover from far away). `lip`: the lip share at this pixel (ocean
// shader); curl, part and stage: the breaker's (v_curl, v_curl_part, v_curl_stage); wave: the number of
// its crest, so each breaker has its own pattern that stays put while it breaks.
vec2 ocean_breaker_foam(vec2 rest, float lip, float curl, float part, float stage, float wave) {
	if (curl <= 0.0) {
		return vec2(0.0);
	}
	float near_tip = smoothstep(BREAKER_PART_TIP - BREAKER_AERATION_REACH, BREAKER_PART_TIP, part);
	float aerated = lip * near_tip * smoothstep(BREAKER_AERATION_START, 1.0, stage);
	float on_trough = smoothstep(BREAKER_PART_TROUGH - 0.3, BREAKER_PART_TROUGH, part);
	float burst = curl * on_trough * breaker_splash(stage);
	float over = curl * smoothstep(BREAKER_FOAM_OVER.x, BREAKER_FOAM_OVER.y, stage);
	float amount = clamp(max(max(aerated, burst), over), 0.0, 1.0);
	float fresh = water_lace(rest, BREAKER_FRESH_FOAM, wave, 0.5);
	return vec2(fresh * amount, amount);
}
