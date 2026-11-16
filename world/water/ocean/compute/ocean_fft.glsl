#[compute]
#version 450
// Inverse FFT of four packed complex signals along one line (a row or a column) per workgroup.
// Radix-2 Stockham in shared memory, so the result comes out in natural order without bit reversal.

#define N 256u
#define HALF_N 128u
#define PI 3.14159265358979

layout(local_size_x = 128, local_size_y = 1, local_size_z = 1) in;

layout(std430, set = 0, binding = 0) restrict buffer Signals {
	vec4 signals[];
};

layout(push_constant, std430) uniform Params {
	uint vertical;
	uint pad0;
	uint pad1;
	uint pad2;
} p;

shared vec4 pingpong[2][N * 2u];

vec2 cmul(vec2 a, vec2 b) {
	return vec2(a.x * b.x - a.y * b.y, a.x * b.y + a.y * b.x);
}

uint address(uint line, uint i) {
	return p.vertical != 0u ? i * N + line : line * N + i;
}

void main() {
	uint line = gl_WorkGroupID.x;
	uint base = gl_WorkGroupID.y * N * N;
	uint j = gl_LocalInvocationID.x;

	for (uint e = j; e < N; e += HALF_N) {
		uint a = (base + address(line, e)) * 2u;
		pingpong[0][e * 2u] = signals[a];
		pingpong[0][e * 2u + 1u] = signals[a + 1u];
	}
	memoryBarrierShared();
	barrier();

	uint src = 0u;
	for (uint ns = 1u; ns < N; ns <<= 1u) {
		uint r = j % ns;
		float angle = PI * float(r) / float(ns); // positive angle: inverse transform
		vec2 w = vec2(cos(angle), sin(angle));
		vec4 a0 = pingpong[src][j * 2u];
		vec4 a1 = pingpong[src][j * 2u + 1u];
		vec4 b0 = pingpong[src][(j + HALF_N) * 2u];
		vec4 b1 = pingpong[src][(j + HALF_N) * 2u + 1u];
		b0 = vec4(cmul(b0.xy, w), cmul(b0.zw, w));
		b1 = vec4(cmul(b1.xy, w), cmul(b1.zw, w));
		uint out_index = (j / ns) * ns * 2u + r;
		uint dst = 1u - src;
		pingpong[dst][out_index * 2u] = a0 + b0;
		pingpong[dst][out_index * 2u + 1u] = a1 + b1;
		pingpong[dst][(out_index + ns) * 2u] = a0 - b0;
		pingpong[dst][(out_index + ns) * 2u + 1u] = a1 - b1;
		src = dst;
		memoryBarrierShared();
		barrier();
	}

	for (uint e = j; e < N; e += HALF_N) {
		uint a = (base + address(line, e)) * 2u;
		signals[a] = pingpong[src][e * 2u];
		signals[a + 1u] = pingpong[src][e * 2u + 1u];
	}
}
