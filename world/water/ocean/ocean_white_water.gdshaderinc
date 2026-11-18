// Tumbling white water on crests that are breaking now (ocean.gdshader). A breaking crest is not a
// smooth line: its top collapses into a churning, lumpy mass of foam and air. Where the simulation
// marks a crest as breaking (the short-lived white water in the moment maps), the surface is raised
// by separate lumps of noise that tumble over time, so the crest's outline turns ragged and torn.
// The lumps are a share (white_water_height) of the breaking wave's own height, so a small breaking
// wavelet gets small lumps and a storm crest big ones.

// Share of the breaking wave's height (OceanSpectrum.white_water_height, set by Ocean). 0: none.
uniform float white_water_height = 0.0;

const int WHITE_WATER_OCTAVES = 4;
// Metres across the largest lumps, and how much smaller and weaker each next octave is.
const float WHITE_WATER_LUMP_SIZE = 5.0;
const float WHITE_WATER_LACUNARITY = 2.1;
const float WHITE_WATER_GAIN = 0.55;
// Noise periods per second the mass churns through.
const float WHITE_WATER_CHURN = 0.7;
// Noise values that become lumps: below the first is flat, above the second is a full lump. Leaving
// most of the noise flat keeps the lumps apart, which tears the outline.
const vec2 WHITE_WATER_LUMP_RANGE = vec2(0.4, 0.66);
// An octave fades out when its lumps are smaller than this many vertex spacings (or pixels), so
// distant white water doesn't shimmer.
const float WHITE_WATER_MIN_FEATURE = 2.0;
// Steepest tilt the lumps give the surface normal (rise over run): foam-covered lumps are rounded,
// and steeper normals would turn their sides away from the light.
const float WHITE_WATER_MAX_SLOPE = 0.8;
// Breaking water spills forward: metres moved downwind per metre of lump.
const float WHITE_WATER_SPILL = 0.35;

float white_water_hash(vec3 c) {
	uvec3 q = uvec3(ivec3(c) + ivec3(1 << 20));
	uint h = q.x * 0x8da6b343u ^ q.y * 0xd8163841u ^ q.z * 0xcb1ab31fu;
	h ^= h >> 16u;
	h *= 0x7feb352du;
	h ^= h >> 15u;
	h *= 0x846ca68bu;
	h ^= h >> 16u;
	return float(h) / 4294967295.0;
}

// Value noise in (x, y, time) with its derivative along x and y: (value 0..1, d/dx, d/dy).
vec3 white_water_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = x - i;
	vec3 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	vec3 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);
	float a = white_water_hash(i);
	float b = white_water_hash(i + vec3(1.0, 0.0, 0.0));
	float c = white_water_hash(i + vec3(0.0, 1.0, 0.0));
	float d = white_water_hash(i + vec3(1.0, 1.0, 0.0));
	float e = white_water_hash(i + vec3(0.0, 0.0, 1.0));
	float g = white_water_hash(i + vec3(1.0, 0.0, 1.0));
	float h = white_water_hash(i + vec3(0.0, 1.0, 1.0));
	float k = white_water_hash(i + vec3(1.0, 1.0, 1.0));
	float k1 = b - a;
	float k2 = c - a;
	float k3 = e - a;
	float k4 = a - b - c + d;
	float k5 = a - c - e + h;
	float k6 = a - b - e + g;
	float k7 = -a + b + c - d + e - g - h + k;
	float value = a + k1 * u.x + k2 * u.y + k3 * u.z + k4 * u.x * u.y + k5 * u.y * u.z + k6 * u.z * u.x
			+ k7 * u.x * u.y * u.z;
	float dx = du.x * (k1 + k4 * u.y + k6 * u.z + k7 * u.y * u.z);
	float dy = du.y * (k2 + k4 * u.x + k5 * u.z + k7 * u.x * u.z);
	return vec3(value, dx, dy);
}

// Lump shape at rest position `p` (metres) and `time`: (height 0..1, d/dx, d/dz per metre).
// `resolution` is the size of a vertex spacing or pixel there, in metres.
vec3 white_water_lumps(vec2 p, float resolution, float time) {
	vec3 sum = vec3(0.0);
	float total = 0.0;
	float size = WHITE_WATER_LUMP_SIZE;
	float amplitude = 1.0;
	for (int o = 0; o < WHITE_WATER_OCTAVES; o++) {
		float shown = smoothstep(WHITE_WATER_MIN_FEATURE, 2.0 * WHITE_WATER_MIN_FEATURE, size / max(resolution, 1e-4));
		// Each octave gets its own offset so the octaves never line up.
		vec3 n = white_water_noise(vec3(p / size + float(o) * 17.31, time * WHITE_WATER_CHURN + float(o) * 5.17));
		// Unresolved octaves fall back to their mean, so the overall height doesn't jump.
		sum += vec3(mix(0.5, n.x, shown), n.yz * shown / size) * amplitude;
		total += amplitude;
		size /= WHITE_WATER_LACUNARITY;
		amplitude *= WHITE_WATER_GAIN;
	}
	sum /= total;
	float lump = smoothstep(WHITE_WATER_LUMP_RANGE.x, WHITE_WATER_LUMP_RANGE.y, sum.x);
	float t = clamp((sum.x - WHITE_WATER_LUMP_RANGE.x) / (WHITE_WATER_LUMP_RANGE.y - WHITE_WATER_LUMP_RANGE.x), 0.0, 1.0);
	float slope = 6.0 * t * (1.0 - t) / (WHITE_WATER_LUMP_RANGE.y - WHITE_WATER_LUMP_RANGE.x);
	return vec3(lump, sum.yz * slope);
}

// Tilt of the surface (d/dx, d/dz) from lumps `height` metres tall, limited to WHITE_WATER_MAX_SLOPE.
vec2 white_water_slope(vec2 p, float resolution, float time, float height) {
	vec2 slope = white_water_lumps(p, resolution, time).yz * height;
	float steepness = length(slope);
	return steepness > WHITE_WATER_MAX_SLOPE ? slope * (WHITE_WATER_MAX_SLOPE / steepness) : slope;
}
