#[compute]
#version 450
// Advances the spectrum to time t and builds the eight real fields we need (displacement xyz, height
// slopes and horizontal-displacement derivatives), packed two per complex number into four signals so
// one inverse FFT gives all of them. Frequencies are snapped to a repeat period so time can wrap
// without a visible jump and without float precision loss in long sessions.

#define N 256u
#define PI 3.14159265358979
#define G 9.81

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(std430, set = 0, binding = 0) restrict readonly buffer Spectrum {
	vec4 h0[];
};

layout(std430, set = 0, binding = 1) restrict writeonly buffer Signals {
	vec4 signals[]; // per cascade N*N*2
};

layout(push_constant, std430) uniform Params {
	vec4 tile_lengths;
	float time;
	float depth;
	float repeat_period;
	float pad;
} p;

vec2 cmul(vec2 a, vec2 b) {
	return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

void main() {
	uvec3 id = gl_GlobalInvocationID;
	uint cascade = id.z;
	float tile = p.tile_lengths[cascade];
	vec2 k = (vec2(id.xy) - float(N / 2u)) * (2.0 * PI / tile);
	float kl = length(k);
	uint texel = cascade * N * N + id.y * N + id.x;

	float w = sqrt(G * kl * tanh(min(kl * p.depth, 20.0)));
	float w0 = 2.0 * PI / p.repeat_period;
	w = floor(w / w0) * w0;
	vec2 e = vec2(cos(w * p.time), sin(w * p.time));
	vec4 s = h0[texel];
	vec2 h = cmul(s.xy, e) + cmul(s.zw, vec2(e.x, -e.y));
	vec2 ih = vec2(-h.y, h.x);
	vec2 dir = kl > 1e-6 ? k / kl : vec2(0.0);

	// Horizontal displacement D = i * k/|k| * h pulls points towards the crests (sharp, choppy waves).
	vec2 c0 = dir.x * ih - dir.y * h;                   // Dx + i Dz
	vec2 c1 = h - k.x * h;                              // Dy + i dDy/dx
	vec2 c2 = (k.y - k.x * dir.x) * ih;                 // dDy/dz + i dDx/dx
	vec2 c3 = -(k.y * dir.y) * h - (k.x * dir.y) * ih;  // dDz/dz + i dDx/dz

	signals[texel * 2u] = vec4(c0, c1);
	signals[texel * 2u + 1u] = vec4(c2, c3);
}
