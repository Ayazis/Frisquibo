#[compute]
#version 450
// Initial wave spectrum h0(k) for one cascade: JONSWAP energy, TMA finite-depth correction,
// Donelan-Banner directional spreading and Gaussian random amplitudes. Each cascade keeps only its own
// band of wavenumbers, so the cascades add up to one continuous spectrum without double-counted waves.
// Runs only when the sea state changes.

#define N 256u
#define PI 3.14159265358979
#define G 9.81

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
	float swell;
	float spread;
	float short_wave_cutoff;
	float k_min;
	float k_max;
	uint cascade;
	uint seed;
} p;

uint pcg(uint v) {
	uint state = v * 747796405u + 2891336453u;
	uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
	return (word >> 22u) ^ word;
}

vec2 gaussian_pair(uint seed) {
	uint a = pcg(seed);
	uint b = pcg(a ^ 0x9E3779B9u);
	float u1 = (float(a) + 0.5) / 4294967296.0;
	float u2 = (float(b) + 0.5) / 4294967296.0;
	return sqrt(-2.0 * log(u1)) * vec2(cos(2.0 * PI * u2), sin(2.0 * PI * u2));
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
	// Swell: long-travelled waves are far more aligned with the wind than a young wind sea.
	beta *= 1.0 + p.swell * 4.0;
	float s = 1.0 / cosh(beta * theta);
	float directional = beta / (2.0 * tanh(beta * PI)) * s * s;
	return mix(directional, 1.0 / (2.0 * PI), p.spread);
}

vec2 amplitude(vec2 k, uint seed) {
	float kl = length(k);
	if (kl < 1e-6 || kl < p.k_min || kl >= p.k_max) {
		return vec2(0.0);
	}
	float wp = 22.0 * pow(G * G / (p.wind_speed * p.fetch_m), 1.0 / 3.0);
	float w = dispersion(kl);
	float theta = atan(k.y, k.x) - p.wind_angle;
	theta = mod(theta + PI, 2.0 * PI) - PI;
	float s_omega = jonswap(w, wp) * tma(w) * donelan_banner(theta, w, wp);
	// S(omega, theta) to a wavenumber spectrum S(k): times d(omega)/dk, divided by k.
	float s_k = s_omega * dispersion_derivative(kl) / kl;
	s_k *= exp(-kl * kl * p.short_wave_cutoff * p.short_wave_cutoff);
	float dk = 2.0 * PI / p.tile_length;
	return gaussian_pair(seed) * sqrt(s_k) * dk * 0.70710678;
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
