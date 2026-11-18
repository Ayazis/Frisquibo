#[compute]
#version 450
// Turns the transformed signals into the textures the surface shader samples, per cascade layer:
//   displacement: (Dx, Dy, Dz, jacobian)
//   slope:        (dDy/dx, dDy/dz, dDx/dx, dDz/dz)
//   moments:      (slope_x^2, slope_z^2, foam, white water), squared slopes so mip levels keep slope
//                 variance (LEAN)
// Foam is injected where the surface folds (jacobian below a threshold) and decays over time. White
// water is the same injection with a short life: it marks crests that are breaking right now.
//
// Crest lean: surface waves are not symmetric. Each point is pushed along their travel by crest_lean
// times its height: crests forward, troughs back. That squeezes the face in front of a crest and
// stretches the one behind it by crest_lean times the wave's slope, so steep surface waves get a steep
// front and a gentle back while gentle swell (slope ~0.03) barely changes, at every wave length.
// The push's derivatives go into the jacobian terms; where it would compress the surface past
// LEAN_MIN_JACOBIAN it is scaled back, so the lean never folds the surface.

#define N 256u
// The lean may compress the surface down to this jacobian, never further (and never below the
// jacobian the wave already had).
#define LEAN_MIN_JACOBIAN 0.3

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(std430, set = 0, binding = 0) restrict readonly buffer Signals {
	vec4 signals[];
};
layout(set = 0, binding = 1, rgba16f) uniform restrict writeonly image2D displacement_map;
layout(set = 0, binding = 2, rgba16f) uniform restrict writeonly image2D slope_map;
layout(set = 0, binding = 3, rgba16f) uniform restrict image2D moment_map;

layout(push_constant, std430) uniform Params {
	float pad_scale;
	float choppiness;
	float foam_threshold;
	float foam_gain;
	float foam_decay;
	float cascade;
	float crest_lean;        // push along the waves' travel per metre of height
	float white_water_decay; // per frame, as foam_decay
	vec2 lean_direction;     // unit vector along the surface waves' travel
	float pad0;
	float pad1;
} p;

void main() {
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	uint texel = uint(p.cascade) * N * N + uint(id.y) * N + uint(id.x);
	// The spectrum is centred on k = 0, which multiplies the inverse transform by (-1)^(x+y).
	float sign_flip = ((id.x + id.y) & 1) == 1 ? -1.0 : 1.0;
	vec4 a = signals[texel * 2u] * sign_flip;
	vec4 b = signals[texel * 2u + 1u] * sign_flip;

	float chop = p.choppiness;
	vec3 displacement = vec3(a.x * chop, a.z, a.y * chop);
	vec2 slope = vec2(a.w, b.x);
	float jxx = b.y * chop;
	float jzz = b.z * chop;
	float jxz = b.w * chop;
	float jacobian = (1.0 + jxx) * (1.0 + jzz) - jxz * jxz;

	// Lean = lean_direction * crest_lean * height; its derivatives follow from the slope.
	vec2 lean = p.lean_direction * p.crest_lean;
	float lxx = lean.x * slope.x;
	float lxz = lean.x * slope.y;
	float lzx = lean.y * slope.x;
	float lzz = lean.y * slope.y;
	float leaned = (1.0 + jxx + lxx) * (1.0 + jzz + lzz) - (jxz + lxz) * (jxz + lzx);
	// Share of the lean this texel can take without compressing past the limit (secant estimate; the
	// surface shader's fold limit catches what is left).
	float floor_jacobian = min(jacobian, LEAN_MIN_JACOBIAN);
	float share = 1.0;
	if (leaned < floor_jacobian) {
		share = clamp((jacobian - floor_jacobian) / max(jacobian - leaned, 1e-4), 0.0, 1.0);
	}
	vec3 leaned_displacement = displacement + vec3(lean.x, 0.0, lean.y) * displacement.y * share;
	float ljxx = jxx + lxx * share;
	float ljzz = jzz + lzz * share;
	float leaned_jacobian = (1.0 + ljxx) * (1.0 + ljzz) - (jxz + lxz * share) * (jxz + lzx * share);

	vec4 previous = imageLoad(moment_map, id);
	// Foam follows the waves' own compression, so the lean doesn't change how much of the sea is white.
	float injected = clamp((p.foam_threshold - jacobian) * p.foam_gain, 0.0, 1.0);
	float foam = max(previous.z * p.foam_decay, injected);
	float white_water = max(previous.w * p.white_water_decay, injected);

	imageStore(displacement_map, id, vec4(leaned_displacement, leaned_jacobian));
	imageStore(slope_map, id, vec4(slope, ljxx, ljzz));
	imageStore(moment_map, id, vec4(slope * slope, foam, white_water));
}
