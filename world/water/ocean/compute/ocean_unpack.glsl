#[compute]
#version 450
// Turns the transformed signals into the textures the surface shader samples, per cascade layer:
//   displacement: (Dx, Dy, Dz, jacobian)
//   slope:        (dDy/dx, dDy/dz, dDx/dx, dDz/dz)
//   moments:      (slope_x^2, slope_z^2, foam, 0), squared slopes so mip levels keep slope variance (LEAN)
// Foam is injected where the surface folds (jacobian below a threshold) and decays over time.

#define N 256u

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(std430, set = 0, binding = 0) restrict readonly buffer Signals {
	vec4 signals[];
};
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image2D displacement_map;
layout(set = 0, binding = 2, rgba16f) uniform restrict writeonly image2D slope_map;
layout(set = 0, binding = 3, rgba16f) uniform restrict image2D moment_map;

layout(push_constant, std430) uniform Params {
	float height_scale;
	float choppiness;
	float foam_threshold;
	float foam_gain;
	float foam_decay;
	float cascade;
	float pad1;
	float pad2;
} p;

void main() {
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	uint texel = uint(p.cascade) * N * N + uint(id.y) * N + uint(id.x);
	// The spectrum is centred on k = 0, which multiplies the inverse transform by (-1)^(x+y).
	float sign_flip = ((id.x + id.y) & 1) == 1 ? -1.0 : 1.0;
	vec4 a = signals[texel * 2u] * sign_flip;
	vec4 b = signals[texel * 2u + 1u] * sign_flip;

	float s = p.height_scale;
	float chop = p.choppiness * s;
	vec3 displacement = vec3(a.x * chop, a.z * s, a.y * chop);
	vec2 slope = vec2(a.w, b.x) * s;
	float jxx = b.y * chop;
	float jzz = b.z * chop;
	float jxz = b.w * chop;
	float jacobian = (1.0 + jxx) * (1.0 + jzz) - jxz * jxz;

	float previous = imageLoad(moment_map, id).z;
	float injected = clamp((p.foam_threshold - jacobian) * p.foam_gain, 0.0, 1.0);
	float foam = max(previous * p.foam_decay, injected);

	imageStore(displacement_map, id, vec4(displacement, jacobian));
	imageStore(slope_map, id, vec4(slope, jxx, jzz));
	imageStore(moment_map, id, vec4(slope * slope, foam, 0.0));
}
