#[compute]
#version 450
// Initial wave spectrum h0(k) for one cascade: JONSWAP energy, TMA finite-depth correction,
// Donelan-Banner directional spreading and random phases. Each cascade keeps only its own
// band of wavenumbers, so the cascades add up to one continuous spectrum without double-counted waves.
// A separate swell (waves from a distant storm, with their own height, period and direction) is added
// to the longest cascade.
// Runs only when the sea state changes.

#define N 256u
#define PI 3.14159265358979
#define G 9.81
// Swell is a narrow band of periods: this fraction of its wavenumber, as a standard deviation.
#define SWELL_BANDWIDTH 0.07
// The swell is never narrower than this many spectrum texels, so the grid samples its energy fully.
#define MIN_SWELL_TEXELS 0.7

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(std430, set = 0, binding = 0) restrict writeonly buffer Spectrum {
	vec4 h0[]; // per cascade N*N: (h0(k), conj(h0(-k)))
};

layout(push_constant, std430) uniform Params {
	float tile_length;
	float wind_speed;
	float wind_angle;
	float fetch_m;
	float depth;
	float wind_spread; // OceanSpectrum.wind_spread: width of the spreading relative to Donelan-Banner
	float short_wave_cutoff;
	float k_min;
	float k_max;
	uint cascade;
	uint seed;
	float peak_scale; // OceanSpectrum.wavelength_scale: multiplies the peak wavelength
	float swell_height;     // significant height in metres; 0 = no swell
	float swell_wavenumber; // rad/m at the sea's depth
	float swell_angle;
	float swell_spread;     // directional standard deviation in radians
	float pad0;
	float pad1;
	float pad2;
	float pad3;
} p;

uint pcg(uint v) {
	uint state = v * 747796405u + 2891336453u;
	uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
	return (word >> 22u) ^ word;
}

// A wave with a random phase and a fixed share of the energy. Random amplitudes as well (a Gaussian
// pair) are right for an endless sea, but a tile holds few long waves: with their heights left to
// chance the sea came out up to 40% too high or too low for its wind, depending on the seed.
// Many such waves still add up to a Gaussian sea surface.
vec2 random_phase(uint seed) {
	float u = (float(pcg(seed)) + 0.5) / 4294967296.0;
	return sqrt(2.0) * vec2(cos(2.0 * PI * u), sin(2.0 * PI * u));
}

float dispersion(float k) {
	return sqrt(G * k * tanh(min(k * p.depth, 20.0)));
}

float dispersion_derivative(float k) {
	float kh = min(k * p.depth, 20.0);
	float th = tanh(kh);
	float sech = 1.0 / cosh(kh);
	return G * (th + kh * sech * sech) / (2.0 * sqrt(G * k * th));
}

float jonswap(float w, float wp) {
	float alpha = 0.076 * pow(p.wind_speed * p.wind_speed / (p.fetch_m * G), 0.22);
	float sigma = w <= wp ? 0.07 : 0.09;
	float r = exp(-(w - wp) * (w - wp) / (2.0 * sigma * sigma * wp * wp));
	return alpha * G * G / pow(w, 5.0) * exp(-1.25 * pow(wp / w, 4.0)) * pow(3.3, r);
}

// Kitaigorodskii depth attenuation (the TMA spectrum): long waves lose energy in shallow water.
float tma(float w) {
	float wh = w * sqrt(p.depth / G);
	if (wh <= 1.0) {
		return 0.5 * wh * wh;
	}
	if (wh < 2.0) {
		return 1.0 - 0.5 * (2.0 - wh) * (2.0 - wh);
	}
	return 1.0;
}

float donelan_banner(float theta, float w, float wp) {
	float ratio = w / wp;
	float beta;
	if (ratio < 0.95) {
		beta = 2.61 * pow(ratio, 1.3);
	} else if (ratio < 1.6) {
		beta = 2.28 * pow(ratio, -1.3);
	} else {
		beta = pow(10.0, -0.4 + 0.8393 * exp(-0.567 * log(ratio * ratio)));
	}
	// A wider spread is a smaller beta; as beta goes to 0 the spreading becomes uniform by itself.
	// The normalisation keeps the integral over all directions at 1, so the height doesn't change.
	beta /= p.wind_spread;
	float s = 1.0 / cosh(beta * theta);
	return beta / (2.0 * tanh(beta * PI)) * s * s;
}

// Energy density S(k) of the local wind sea.
float wind_sea(vec2 k, float kl) {
	if (kl < p.k_min || kl >= p.k_max) {
		return 0.0;
	}
	// Peak frequency; a wave length scale s moves it to w / sqrt(s) (deep water: length ~ 1 / w^2).
	float wp = 22.0 * pow(G * G / (p.wind_speed * p.fetch_m), 1.0 / 3.0) / sqrt(p.peak_scale);
	float w = dispersion(kl);
	float theta = atan(k.y, k.x) - p.wind_angle;
	theta = mod(theta + PI, 2.0 * PI) - PI;
	float s_omega = jonswap(w, wp) * tma(w) * donelan_banner(theta, w, wp);
	// S(omega, theta) to a wavenumber spectrum S(k): times d(omega)/dk, divided by k.
	// JONSWAP energy grows with wp^-4, so a longer peak would also make the waves taller (by s).
	// Divide that out: horizontal size changes only the length; height_scale owns the height.
	s_omega /= p.peak_scale * p.peak_scale;
	float s_k = s_omega * dispersion_derivative(kl) / kl;
	return s_k * exp(-kl * kl * p.short_wave_cutoff * p.short_wave_cutoff);
}

// Energy density S(k) of the swell: a Gaussian around its wave vector holding the variance
// (height / 4)^2, which is what a significant wave height means. Lives in the longest cascade only.
float swell_sea(vec2 k) {
	if (p.cascade != 0u || p.swell_height <= 0.0) {
		return 0.0;
	}
	float min_width = MIN_SWELL_TEXELS * 2.0 * PI / p.tile_length;
	float along_width = max(SWELL_BANDWIDTH * p.swell_wavenumber, min_width);
	float across_width = max(p.swell_spread * p.swell_wavenumber, min_width);
	vec2 dir = vec2(cos(p.swell_angle), sin(p.swell_angle));
	float along = (dot(k, dir) - p.swell_wavenumber) / along_width;
	float across = dot(k, vec2(-dir.y, dir.x)) / across_width;
	float variance = p.swell_height * p.swell_height / 16.0;
	return variance / (2.0 * PI * along_width * across_width) * exp(-0.5 * (along * along + across * across));
}

vec2 amplitude(vec2 k, uint seed) {
	float kl = length(k);
	if (kl < 1e-6) {
		return vec2(0.0);
	}
	float s_k = wind_sea(k, kl) + swell_sea(k);
	float dk = 2.0 * PI / p.tile_length;
	// A wave of amplitude a carries variance a^2 / 2 = S(k) dk^2 and shows up as |h| = a / 2 at both
	// k and -k, so |h0|^2 = S(k) dk^2 / 2. random_phase() has length sqrt(2): hence the 0.5.
	return random_phase(seed) * sqrt(s_k) * dk * 0.5;
}

void main() {
	uvec2 id = gl_GlobalInvocationID.xy;
	float dk = 2.0 * PI / p.tile_length;
	vec2 k = (vec2(id) - float(N / 2u)) * dk;
	uint cascade_base = p.cascade * N * N;
	uint salt = p.seed * 0x9E3779B9u + cascade_base;
	uvec2 mirrored = (uvec2(N) - id) % N;
	vec2 h = amplitude(k, pcg(id.y * N + id.x + salt));
	vec2 hm = amplitude(-k, pcg(mirrored.y * N + mirrored.x + salt));
	h0[cascade_base + id.y * N + id.x] = vec4(h, hm.x, -hm.y);
}
