// The curl of plunging breakers: the GPU twin of BreakerProfile (keep the two in step). See there for
// the model: a folded sheet in each crest's frame, its lip on a ballistic path, the type of breaker from
// the surf similarity number. Here also the ribbons (OceanBreakers): strips of the ocean surface laid
// along the breaking crests near the camera, fine across the crest where the curl needs it. A ribbon is
// the ocean's own material on another mesh: its vertices find their rest position on the wave rays
// (ShoreRays), then go through the ocean's vertex stage like any other water. Where a crest curls, the
// ribbon draws the curl and the ocean surface leaves a hole for it; they overlap a little at the edges.
// Needs from the ocean shader: the shore waves include, seabed_depth(), ocean_still_depth(),
// breaker_ratio, sea_level.

// How hard waves plunge: 1 is physical, 0 turns curls off (they all spill).
uniform float curl_strength = 1.0;
// Curls are drawn within this many metres of the camera (the ribbons' reach, from the quality tier);
// further out the shore waves spill. 0: no curls.
uniform float breaker_reach = 0.0;
// ShoreRays.image: world (x, z) and the field's travel time per ray (row) and step (column).
uniform sampler2D shore_rays : filter_linear, repeat_disable;
uniform vec2 shore_rays_size = vec2(1.0);  // columns, rows
uniform float shore_rays_step = 0.4;       // ShoreRays.TIME_STEP
// Crest numbers the ribbons cover now (OceanBreakers.covered): the ocean surface leaves holes for these
// crests' curls only.
uniform vec2 breaker_waves = vec2(1.0, 0.0);

// Per ribbon (OceanBreakers sets them; the ocean surface itself keeps the zeros):
// first row, first row of its waterline, rows of that waterline (0: not a ribbon), 1 if the line is closed.
instance uniform vec4 breaker_ribbon = vec4(0.0);
// The wave number of the crest it follows, and how many of its rows are in use.
instance uniform vec2 breaker_span = vec2(0.0);

// Same as BreakerProfile.
const float BREAKER_SPILL_START = 0.3;
const float BREAKER_SPILL_END = 0.6;
const float BREAKER_SURGE_START = 2.0;
const float BREAKER_SURGE_END = 3.3;
const float BREAKER_MIN_SLOPE = 0.005;
const float BREAKER_DEPTH_EXPONENT = 0.8;
const float BREAKER_LIP_REACH = 0.55;
const float BREAKER_MAX_REACH_SHARE = 0.8;
const float BREAKER_LIP_GROW = 0.25;
const float BREAKER_COLLAPSE_START = 1.3;
const float BREAKER_COLLAPSE_END = 2.4;
const float BREAKER_ROOT_THICKNESS = 0.45;
const float BREAKER_TIP_THICKNESS = 0.08;
const float BREAKER_FACE_BASE = 0.3;
const float BREAKER_BACK_WALL = 0.35;
const float BREAKER_HANDLE = 0.4;
const float BREAKER_SPLASH_HEIGHT = 0.8;
const float BREAKER_SPLASH_WIDTH = 0.35;
const vec4 BREAKER_SPLASH = vec4(0.9, 1.1, 1.25, 1.9);
const float BREAKER_END_BLEND = 0.85;
const float BREAKER_NORMAL_STEP = 0.004;
const float BREAKER_GRAVITY = 9.81;
// Parts of the sheet (BreakerProfile.Part).
const float BREAKER_PART_TIP = 1.0;
const float BREAKER_PART_CEILING = 2.0;
const float BREAKER_PART_BACK_WALL = 3.0;
const float BREAKER_PART_TROUGH = 4.0;
// Metres either side of the crest the seabed slope is measured over.
const float BREAKER_SLOPE_STEP = 2.0;
// A breaker's stage and plunge are averaged along its crest, over BREAKER_PEEL_TAPS points this many
// metres apart (weights rising to the middle: 1 2 3 4 3 2 1), so the lip peels along a long stretch of
// crest instead of jumping ahead where the wave's height, size or depth changes within a few metres
// (same as BreakerProfile.PEEL_STEP and PEEL_TAPS).
const float BREAKER_PEEL_STEP = 3.0;
const int BREAKER_PEEL_TAPS = 7;
// Same as BreakerProfile.PEEL_BEFORE and PEEL_SHORE.
const float BREAKER_PEEL_BEFORE = -1.0;
const float BREAKER_PEEL_SHORE = 0.3;
// Curls fade out between this share of the reach and the reach.
const float BREAKER_REACH_FADE = 0.75;
// Ribbon window around its crest, in periods: ahead of it (to beyond the trough) and behind it.
const float BREAKER_WINDOW_FRONT = 0.32;
const float BREAKER_WINDOW_BACK = 0.04;
// The ribbon draws where the curl is at least RIBBON_FROM; the ocean surface where it is at most
// SURFACE_UNTIL. In between both draw the same water.
const float BREAKER_RIBBON_FROM = 0.01;
const float BREAKER_SURFACE_UNTIL = 0.05;

struct Breaker {
	float curl;       // how far the water here is carried onto the curl (0: plain surface)
	float phi;        // share of the way from the crest to the trough ahead
	float stage;      // time since the crest broke, in lip flight times (negative: not yet)
	float crest;      // crest height above still water (m)
	float distance;   // metres from the crest to the trough ahead
	vec2 crest_rest;  // where the crest's water rests (world x, z)
	vec2 towards;     // direction of travel
};

struct BreakerSheet {
	vec2 position;    // crest frame: metres towards the shore, metres above still water
	vec2 normal;      // crest frame, out of the water
	float part;       // part + share along it (BreakerProfile.Part)
};

bool breaker_is_ribbon() {
	return breaker_ribbon.z > 0.5;
}

// Whether this pixel is drawn by the surface it belongs to: a ribbon draws where the curl is strong
// enough, the ocean surface everywhere else, except under the curls the ribbons cover.
bool breaker_drawn_here(Breaker b, float crest_number) {
	if (breaker_is_ribbon()) {
		return b.curl >= BREAKER_RIBBON_FROM;
	}
	bool covered = crest_number >= breaker_waves.x - 0.5 && crest_number <= breaker_waves.y + 0.5;
	return b.curl <= BREAKER_SURFACE_UNTIL || !covered;
}

float breaker_plunge_share(float xi) {
	return smoothstep(BREAKER_SPILL_START, BREAKER_SPILL_END, xi)
			* (1.0 - smoothstep(BREAKER_SURGE_START, BREAKER_SURGE_END, xi)) * curl_strength;
}

float breaker_splash(float stage) {
	return smoothstep(BREAKER_SPLASH.x, BREAKER_SPLASH.y, stage) * (1.0 - smoothstep(BREAKER_SPLASH.z, BREAKER_SPLASH.w, stage));
}

// Seabed slope at `p` along the direction of travel (rising towards the shore).
float breaker_seabed_slope(vec2 p, vec2 towards) {
	return (seabed_depth(p - towards * BREAKER_SLOPE_STEP) - seabed_depth(p + towards * BREAKER_SLOPE_STEP))
			/ (2.0 * BREAKER_SLOPE_STEP);
}

// Stage and plunge share of the breaker of crest number `wave` whose crest water rests at `crest`,
// travelling `towards`, for averaging along the crest: (stage, plunge share, weight). Both change
// smoothly: before breaking the stage is negative, from the same formula (BreakerProfile.peel_stage()),
// and the weight fades out over the last BREAKER_PEEL_SHORE metres of water (ShoreBreakers._stage_plunge()).
vec3 breaker_stage_plunge(vec2 crest, vec2 towards, float wave) {
	float depth = ocean_still_depth(crest);
	float weight = shore_weight(depth) * smoothstep(0.0, BREAKER_PEEL_SHORE, depth);
	vec2 uv = (crest - seabed_rect.xy) / seabed_rect.zw;
	if (weight <= 0.0 || any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		return vec3(BREAKER_PEEL_BEFORE, 0.0, 0.0);
	}
	// Refraction and the per-wave size at the crest, as the CPU twin reads them.
	vec3 ray = textureLod(shore_origin, uv, 0.0).xyz;
	float lee = mix(shore_lee_share, 1.0, smoothstep(SHORE_LEE_FROM, SHORE_LEE_TO, dot(towards, shore_wave_direction)));
	float gain = wave_amplitude * sqrt(shore_wave_share) * lee * ray.z;
	float free_crest = gain * shore_wave_size(ray.xy, wave) * pow(shore_zone() / max(depth, SHORE_MIN_DEPTH), 0.25);
	float ratio = free_crest / max(breaker_ratio * depth, 1e-4);
	float slope = max(breaker_seabed_slope(crest, towards), BREAKER_MIN_SLOPE);
	float break_depth = depth * pow(max(ratio, 1e-3), BREAKER_DEPTH_EXPONENT);
	float height = max(2.0 * breaker_ratio * break_depth, 1e-3);
	float run = (break_depth - depth) / slope;
	float flight = sqrt(2.0 * height / BREAKER_GRAVITY);
	float stage = max(run / (sqrt(BREAKER_GRAVITY * max(break_depth, 1e-3)) * flight), BREAKER_PEEL_BEFORE);
	float period = max(water_swash_period, 0.1);
	float deep_wavelength = BREAKER_GRAVITY * period * period / TAU;
	float xi = slope / sqrt(height / deep_wavelength);
	return vec3(stage, breaker_plunge_share(xi), weight);
}

// The breaker the water resting at `p` belongs to (BreakerProfile.stage(), fold(), plunge_share()).
Breaker breaker_at(vec2 p, ShoreWave w, float camera_distance) {
	Breaker b;
	b.curl = 0.0;
	b.phi = 0.0;
	b.stage = -1.0;
	b.crest = 0.0;
	b.distance = 1.0;
	b.crest_rest = p;
	b.towards = w.towards;
	float back = 1.0 - w.front;
	if (breaker_reach <= 0.0 || curl_strength <= 0.0 || w.weight <= 0.0 || w.u < back) {
		return b;
	}
	// Ahead of a crest, between it and the trough: the front of crest number roller_wave.
	b.phi = (1.0 - w.u) / w.front;
	b.distance = w.front * w.wavelength;
	b.crest_rest = p - w.towards * b.phi * b.distance;
	float depth = ocean_still_depth(b.crest_rest);
	float weight = shore_weight(depth);
	if (weight <= 0.0) {
		return b;
	}
	vec2 uv = (b.crest_rest - seabed_rect.xy) / seabed_rect.zw;
	vec3 ray = textureLod(shore_origin, clamp(uv, vec2(0.0), vec2(1.0)), 0.0).xyz;
	float lee = mix(shore_lee_share, 1.0, smoothstep(SHORE_LEE_FROM, SHORE_LEE_TO, dot(w.towards, shore_wave_direction)));
	float free_crest = wave_amplitude * sqrt(shore_wave_share) * lee * ray.z * shore_wave_size(ray.xy, w.roller_wave)
			* pow(shore_zone() / max(depth, SHORE_MIN_DEPTH), 0.25);
	b.crest = min(free_crest, breaker_ratio * depth) * weight;
	// Stage and plunge, averaged along the crest.
	vec2 along = vec2(-w.towards.y, w.towards.x);
	float stage = 0.0;
	float plunge = 0.0;
	float total = 0.0;
	for (int k = 0; k < BREAKER_PEEL_TAPS; k++) {
		float offset = float(k - BREAKER_PEEL_TAPS / 2);
		float tap_weight = float(BREAKER_PEEL_TAPS / 2 + 1) - abs(offset);
		vec3 tap = breaker_stage_plunge(b.crest_rest + along * offset * BREAKER_PEEL_STEP, w.towards, w.roller_wave);
		tap_weight *= tap.z;
		stage += tap.x * tap_weight;
		plunge += tap.y * tap_weight;
		total += tap_weight;
	}
	if (total <= 0.0) {
		return b;
	}
	b.stage = stage / total;
	float fold = plunge / total * smoothstep(0.0, BREAKER_LIP_GROW, b.stage)
			* (1.0 - smoothstep(BREAKER_COLLAPSE_START, BREAKER_COLLAPSE_END, b.stage));
	float reach_fade = 1.0 - smoothstep(BREAKER_REACH_FADE * breaker_reach, breaker_reach, camera_distance);
	b.curl = fold * weight * reach_fade * (1.0 - smoothstep(BREAKER_END_BLEND, 1.0, b.phi));
	return b;
}

vec2 breaker_bezier(vec2 p0, vec2 p1, vec2 p2, vec2 p3, float t) {
	float s = 1.0 - t;
	return p0 * (s * s * s) + p1 * (3.0 * s * s * t) + p2 * (3.0 * s * t * t) + p3 * (t * t * t);
}

float breaker_bezier_length(vec2 p0, vec2 p1, vec2 p2, vec2 p3) {
	return 0.5 * (distance(p0, p3) + distance(p0, p1) + distance(p1, p2) + distance(p2, p3));
}

// Control point of the parabola that leaves `root` level and reaches `end` along `heading`: where the
// two tangents meet, half way along when they hardly do (BreakerProfile._Shape._corner()).
vec2 breaker_corner(vec2 root, vec2 end, vec2 heading) {
	vec2 midway = vec2((root.x + end.x) * 0.5, root.y);
	if (heading.y > -1e-3) {
		return midway;
	}
	vec2 meet = end + heading * ((root.y - end.y) / heading.y);
	return meet.x >= root.x && meet.x <= end.x ? meet : midway;
}

// The sheet's five curves (control points) and their lengths, for a breaker at `stage` with its crest
// `crest` metres high and the trough `trough_distance` metres ahead (BreakerProfile.curve()).
void breaker_sheet_curves(float stage, float crest, float trough_distance, out vec2 c[20], out float lengths[5]) {
	float flight = clamp(stage, 0.0, 1.0);
	float height = 2.0 * crest;
	float reach = min(BREAKER_LIP_REACH * height, BREAKER_MAX_REACH_SHARE * trough_distance);
	vec2 top = vec2(0.0, crest);
	vec2 tip = vec2(reach * flight, crest - height * flight * flight);
	vec2 heading = vec2(reach, -2.0 * height * flight);
	heading = dot(heading, heading) < 1e-12 ? vec2(1.0, 0.0) : normalize(heading);
	vec2 inward = vec2(heading.y, -heading.x);
	vec2 tip_inside = tip + inward * BREAKER_TIP_THICKNESS * crest;
	vec2 ceiling = vec2(0.0, crest - BREAKER_ROOT_THICKNESS * crest * sqrt(flight));
	vec2 base = vec2(BREAKER_FACE_BASE * reach * flight, -crest);
	vec2 trough = vec2(trough_distance, -crest);
	// The lip's outside follows the tip's ballistic path (a parabola, one cubic exactly); its underside a
	// parabola from the root of the lip to the inside of the tip.
	vec2 thrown = vec2(tip.x * 0.5, crest);
	vec2 under = breaker_corner(ceiling, tip_inside, heading);
	float wall = BREAKER_BACK_WALL * crest * flight;
	float wall_handle = BREAKER_HANDLE * distance(ceiling, base);
	float run_handle = BREAKER_HANDLE * distance(base, trough);
	c[0] = top; c[1] = mix(top, thrown, 2.0 / 3.0); c[2] = mix(tip, thrown, 2.0 / 3.0); c[3] = tip;
	c[4] = tip; c[5] = mix(tip, tip_inside, 1.0 / 3.0); c[6] = mix(tip, tip_inside, 2.0 / 3.0); c[7] = tip_inside;
	c[8] = tip_inside; c[9] = mix(tip_inside, under, 2.0 / 3.0); c[10] = mix(ceiling, under, 2.0 / 3.0); c[11] = ceiling;
	c[12] = ceiling; c[13] = ceiling - vec2(wall + wall_handle, 0.0); c[14] = base - vec2(wall_handle, 0.0); c[15] = base;
	c[16] = base; c[17] = base + vec2(run_handle, 0.0); c[18] = trough - vec2(run_handle, 0.0); c[19] = trough;
	for (int k = 0; k < 5; k++) {
		lengths[k] = breaker_bezier_length(c[4 * k], c[4 * k + 1], c[4 * k + 2], c[4 * k + 3]);
	}
}

// Metres of sheet from the crest to the trough ahead (the flat water there spans trough_distance).
float breaker_sheet_length(float stage, float crest, float trough_distance) {
	vec2 c[20];
	float lengths[5];
	breaker_sheet_curves(stage, crest, trough_distance, c, lengths);
	return lengths[0] + lengths[1] + lengths[2] + lengths[3] + lengths[4];
}

// Where water resting at `rest` lies along the folded sheet, as a rest-like position: along the crest as
// it rests, towards the shore by metres of sheet instead of metres of flat water. Ripples and foam looked
// up here keep their size on the curl, where the rest position would draw a narrow band of them out over
// the whole lip.
vec2 breaker_surface_position(vec2 rest, Breaker b) {
	if (b.curl <= 0.0) {
		return rest;
	}
	float sheet = breaker_sheet_length(b.stage, b.crest, b.distance);
	return mix(rest, b.crest_rest + b.towards * b.phi * sheet, b.curl);
}

// The sheet at `phi` (BreakerProfile.curve() and normal()).
BreakerSheet breaker_sheet(float phi, float stage, float crest, float trough_distance) {
	float height = 2.0 * crest;
	float reach = min(BREAKER_LIP_REACH * height, BREAKER_MAX_REACH_SHARE * trough_distance);
	vec2 c[20];
	float lengths[5];
	breaker_sheet_curves(stage, crest, trough_distance, c, lengths);
	float total = lengths[0] + lengths[1] + lengths[2] + lengths[3] + lengths[4];
	float splash_height = BREAKER_SPLASH_HEIGHT * crest * breaker_splash(stage);
	float splash_width = max(BREAKER_SPLASH_WIDTH * height, 1e-3);
	// At phi, and either side of it for the tangent.
	vec2 at[3];
	float part = 0.0;
	for (int n = 0; n < 3; n++) {
		float along = clamp(phi + float(n - 1) * BREAKER_NORMAL_STEP, 0.0, 1.0) * total;
		at[n] = c[0];
		for (int k = 0; k < 5; k++) {
			if (along <= lengths[k] || k == 4) {
				float t = clamp(along / max(lengths[k], 1e-9), 0.0, 1.0);
				vec2 q = breaker_bezier(c[4 * k], c[4 * k + 1], c[4 * k + 2], c[4 * k + 3], t);
				if (k == 4) {
					float off = (q.x - reach) / splash_width;
					q.y += splash_height * exp(-off * off);
				}
				at[n] = q;
				if (n == 1) {
					part = float(k) + min(t, 0.999);
				}
				break;
			}
			along -= lengths[k];
		}
	}
	BreakerSheet sheet;
	sheet.position = at[1];
	vec2 tangent = at[2] - at[0];
	sheet.normal = dot(tangent, tangent) < 1e-12 ? vec2(0.0, 1.0) : normalize(vec2(-tangent.y, tangent.x));
	sheet.part = part;
	return sheet;
}

// World position on the wave rays of ribbon vertex `grid` (x: row in the ribbon, z: 0..1 across it).
vec2 breaker_ribbon_rest(vec3 grid) {
	float line_start = breaker_ribbon.y;
	float line_rows = breaker_ribbon.z;
	float local = breaker_ribbon.x - line_start + min(grid.x, breaker_span.y - 1.0);
	local = breaker_ribbon.w > 0.5 ? mod(local, line_rows) : clamp(local, 0.0, line_rows - 1.0);
	float v = (line_start + floor(local) + 0.5) / shore_rays_size.y;
	vec3 shore_end = textureLod(shore_rays, vec2(0.5 / shore_rays_size.x, v), 0.0).xyz;
	// The crest of wave n is where (t + T) / period + timing = n (ocean_shore_waves).
	float period = max(water_swash_period, 0.1);
	float timing = swash_noise(shore_end.xy / SWASH_ALONGSHORE) * SWASH_PHASE_SPREAD;
	float crest_time = (breaker_span.x - timing) * period - water_wave_time;
	float time = crest_time + mix(-BREAKER_WINDOW_FRONT, BREAKER_WINDOW_BACK, grid.z) * period;
	// Column of that travel time, then one step that takes up the ray's clock drift (ShoreRays.column()).
	float last = shore_rays_size.x - 1.0;
	float column = clamp((time - shore_end.z) / shore_rays_step, 0.0, last);
	float there = textureLod(shore_rays, vec2((column + 0.5) / shore_rays_size.x, v), 0.0).z;
	if (there >= 0.0) {
		column = clamp(column + (time - there) / shore_rays_step, 0.0, last);
	}
	return textureLod(shore_rays, vec2((column + 0.5) / shore_rays_size.x, v), 0.0).xy;
}
