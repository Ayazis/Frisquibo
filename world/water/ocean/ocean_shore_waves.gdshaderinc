// Waves near the coast (see ShoreWaves, the CPU twin, for the model; keep the two in step). Inside the
// zone a share of the open sea's energy turns into waves whose crests follow the ShoreField's lines of
// equal travel time: refracted to meet the beach, growing as the water shallows until the depth limit
// breaks them, leaning forward as they steepen. Breaking crests carry white water on their front face
// and leave a band of foam behind that fades. Timing and size are the swash's, wave for wave.
// Needs from the ocean shader: seabed_rect, wave_amplitude, breaker_ratio, and swash.gdshaderinc.

// ShoreField.image: travel time to the waterline (s), its gradient x and z (s/m), validity.
uniform sampler2D shore_field : filter_linear, repeat_disable, hint_default_transparent;
// ShoreField.origins: the waterline point (world x, z) each wave is heading for, and the refraction
// coefficient Kr.
uniform sampler2D shore_origin : filter_linear, repeat_disable, hint_default_black;
uniform float shore_wave_depth = 8.0;
uniform float shore_wave_share = 0.7;
uniform float shore_lee_share = 0.3;
// Unit direction the open sea's main waves travel in.
uniform vec2 shore_wave_direction = vec2(1.0, 0.0);

// Same as ShoreField.MIN_DEPTH and ShoreField.MAX_DEPTH.
const float SHORE_MIN_DEPTH = 0.05;
const float SHORE_MAX_DEPTH = 12.0;
// Same as ShoreWaves: FRONT_SHARE_MIN, SKEW_START, LEAN, LEE_FROM, LEE_TO.
const float SHORE_FRONT_SHARE_MIN = 0.18;
const float SHORE_SKEW_START = 0.3;
const float SHORE_LEAN = 0.9;
const float SHORE_LEE_FROM = -0.3;
const float SHORE_LEE_TO = 0.7;
// Same as ShoreWaves: BREAK_ONSET, ROLLER_REACH, ROLLER_HEIGHT.
const float SHORE_BREAK_ONSET = 0.85;
const float SHORE_ROLLER_REACH = 0.4;
const float SHORE_ROLLER_HEIGHT = 0.12;
// The roller's white water reaches this share of a period past the crest, onto the back of the wave.
const float SHORE_ROLLER_BACK = 0.04;
// The foam a breaker leaves behind ages into lace and is gone after this share of a period.
const float SHORE_LACE_LIFE = 0.9;

struct ShoreWave {
	vec3 offset;      // displacement of the water resting here
	vec2 slope;       // height gradient over the rest position
	vec2 stretch;     // d(sway)/dx, d(sway)/dz: added to the jacobian, as the FFT's horizontal displacement
	float weight;     // how much of the shore waves is present (0 offshore)
	// White water (ocean_shore_foam.gdshaderinc reads these):
	float roller;     // the roller on the breaking front: 1 at the crest, 0 where it ends down the face
	float roller_wave; // number of the crest the roller belongs to (a different pattern per wave)
	vec2 crest_frame; // metres from that crest along the travel direction (negative ahead) and along it
	float lace;       // how much foam the last breaker left here, before ageing
	float lace_age;   // 0 when its crest has just passed, 1 when the lace is gone
	float lace_wave;  // number of the crest that left it
	// Where in its wave this water is (ocean_breakers.gdshaderinc reads these):
	float u;          // share of a period since the last crest passed
	float front;      // share of a period the front of the wave takes
	vec2 towards;     // unit direction of travel, towards the shore
	float wavelength; // metres between crests here
	float gain;       // open-sea crest height this coast gets, before shoaling and the per-wave size
	vec2 end;         // the waterline point the wave is heading for
};

float shore_zone() {
	return min(shore_wave_depth, SHORE_MAX_DEPTH);
}

// 0 offshore, 1 well inside the zone. Same as ShoreWaves.weight().
float shore_weight(float depth) {
	if (seabed_rect.z <= 0.0 || depth <= 0.0 || depth >= shore_zone()) {
		return 0.0;
	}
	return 1.0 - smoothstep(0.5 * shore_zone(), shore_zone(), depth);
}

// Amplitude share the FFT waves keep. Same as ShoreWaves.open_sea_share().
float shore_open_sea_share(float depth) {
	return sqrt(1.0 - shore_wave_share * shore_weight(depth));
}

float shore_wave_size(vec2 p, float wave) {
	return mix(SWASH_SMALLEST, 1.0, swash_noise(p / SWASH_ALONGSHORE + wave * SWASH_WAVE_STEP));
}

// Water resting at `p`, still water `depth` deep. Same as ShoreWaves.displacement(), plus the
// derivatives and the foam the CPU doesn't need.
ShoreWave shore_wave(vec2 p, float depth) {
	ShoreWave w;
	w.offset = vec3(0.0);
	w.slope = vec2(0.0);
	w.stretch = vec2(0.0);
	w.weight = shore_weight(depth);
	w.roller = 0.0;
	w.roller_wave = 0.0;
	w.crest_frame = vec2(0.0);
	w.lace = 0.0;
	w.lace_age = 1.0;
	w.lace_wave = 0.0;
	w.u = 0.0;
	w.front = 0.5;
	w.towards = vec2(1.0, 0.0);
	w.wavelength = 1.0;
	w.gain = 0.0;
	w.end = p;
	if (w.weight <= 0.0) {
		return w;
	}
	vec2 uv = (p - seabed_rect.xy) / seabed_rect.zw;
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		w.weight = 0.0;
		return w;
	}
	vec4 field = textureLod(shore_field, uv, 0.0);
	float slowness = length(field.yz);
	if (field.a < 0.5 || slowness <= 0.0) {
		w.weight = 0.0;
		return w;
	}
	vec2 towards_shore = -field.yz / slowness;
	// What varies along the coast is drawn at the waterline point this wave is heading for: the swash's
	// draw there, unchanged along the wave's way in.
	vec3 ray = textureLod(shore_origin, uv, 0.0).xyz;
	vec2 end = ray.xy;
	float cycle = max(water_swash_period, 0.1);
	float phase = (water_wave_time + field.x) / cycle + swash_noise(end / SWASH_ALONGSHORE) * SWASH_PHASE_SPREAD;
	float wave = floor(phase);
	float u = phase - wave;
	float size = mix(shore_wave_size(end, wave), shore_wave_size(end, wave + 1.0), smoothstep(0.0, 1.0, u));
	float lee = mix(shore_lee_share, 1.0, smoothstep(SHORE_LEE_FROM, SHORE_LEE_TO, dot(towards_shore, shore_wave_direction)));
	// Refraction gathers the energy on headlands and spreads it in bays (ray.z: Kr); shoaling grows it.
	float free_crest = wave_amplitude * sqrt(shore_wave_share) * lee * size * ray.z
			* pow(shore_zone() / max(depth, SHORE_MIN_DEPTH), 0.25);
	float limit = breaker_ratio * depth;
	float crest = min(free_crest, limit) * w.weight;
	float ratio = free_crest / max(limit, 1e-4);
	float skew = smoothstep(SHORE_SKEW_START, 1.0, ratio);
	float breaking = smoothstep(SHORE_BREAK_ONSET, 1.0, ratio);
	float front = mix(0.5, SHORE_FRONT_SHARE_MIN, skew);
	float back = 1.0 - front;

	// The cycle (ShoreWaves.shape) and its derivative by u: height, sway.
	vec2 shape;
	vec2 shape_du;
	// The roller's bulge (ShoreWaves.roller_bump) and its derivative by u.
	float bump = 0.0;
	float bump_du = 0.0;
	// Where on the face, from the crest (1) down to where the roller ends (0); share of a period from
	// the crest (negative ahead of it).
	float on_face = 0.0;
	float from_crest;
	if (u < back) {
		float x = u / back;
		shape = vec2(cos(PI * x), sin(PI * x));
		shape_du = vec2(-sin(PI * x), cos(PI * x)) * PI / back;
		from_crest = u;
		on_face = 1.0 - smoothstep(0.0, SHORE_ROLLER_BACK, u);
	} else {
		float y = (u - back) / front;
		shape = vec2(-cos(PI * y), -sin(PI * y));
		shape_du = vec2(sin(PI * y), -cos(PI * y)) * PI / front;
		from_crest = u - 1.0;
		float t = (y - (1.0 - SHORE_ROLLER_REACH)) / SHORE_ROLLER_REACH;
		if (t > 0.0) {
			bump = 16.0 * t * t * (1.0 - t) * (1.0 - t);
			bump_du = 32.0 * t * (1.0 - t) * (1.0 - 2.0 * t) / (SHORE_ROLLER_REACH * front);
			on_face = t;
		}
	}
	float sway = crest * SHORE_LEAN * skew;
	float lift = shape.x + SHORE_ROLLER_HEIGHT * breaking * bump;
	w.offset = vec3(towards_shore.x * sway * shape.y, crest * lift, towards_shore.y * sway * shape.y);
	// The phase rises along the travel time's gradient: grad u = grad T / period.
	vec2 grad_u = field.yz / cycle;
	w.slope = crest * (shape_du.x + SHORE_ROLLER_HEIGHT * breaking * bump_du) * grad_u;
	w.stretch = towards_shore * towards_shore * sway * shape_du.y * dot(grad_u, towards_shore);

	float white = breaking * w.weight;
	w.roller = white * on_face;
	// The crest at u = 0 is wave number `wave`; the face ahead of it (u -> 1) already belongs to the next.
	w.roller_wave = u < back ? wave : wave + 1.0;
	// Local wavelength: the period over the slowness.
	w.crest_frame = vec2(from_crest * cycle / slowness, dot(p, vec2(-towards_shore.y, towards_shore.x)));
	w.lace = white;
	w.lace_age = clamp(u / SHORE_LACE_LIFE, 0.0, 1.0);
	w.lace_wave = wave;
	w.u = u;
	w.front = front;
	w.towards = towards_shore;
	w.wavelength = cycle / slowness;
	w.gain = wave_amplitude * sqrt(shore_wave_share) * lee * ray.z;
	w.end = end;
	return w;
}
