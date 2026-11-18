// Planar reflection lookup shared by every water shader (sea, lake, river). PlanarReflection renders the
// mirrored scene into `water_reflection`; this blurs it by the slopes a pixel can't resolve.
//
// Why the blur is an upright ellipse: tilting the normal by an angle d towards or away from the viewer
// turns the reflected ray by 2d, but tilting it sideways only by 2d * cos(view angle). At grazing angles
// rough water therefore smears reflections into vertical streaks, as on a real sea or a windy lake.

global uniform sampler2D water_reflection : filter_linear;
global uniform bool water_reflection_enabled;
// The second mirror plane (PlanarReflection slot 1): water above the sea, such as a pond.
global uniform sampler2D water_reflection_2 : filter_linear;
global uniform bool water_reflection_2_enabled;
// Taps of the blur, from the quality tier (PlanarReflection.blur_samples). 1 = a single sharp sample.
global uniform int water_reflection_blur_samples;

const float WATER_GOLDEN_ANGLE = 2.39996323;
// The kernel reaches this many standard deviations of the slope spread.
const float WATER_REFLECTION_KERNEL_SIGMAS = 2.0;
// Upper limit of the blur radius, as a fraction of the screen, so storm seas don't sample half the image.
const float WATER_REFLECTION_MAX_BLUR = 0.12;
// Below this radius (a fraction of the screen) one sample looks the same.
const float WATER_REFLECTION_MIN_BLUR = 0.0005;
// Keeps samples off the border texels of the reflection image.
const float WATER_REFLECTION_UV_MARGIN = 0.001;
// Samples stay this far (a fraction of the screen) on the water's side of the horizon.
const float WATER_REFLECTION_HORIZON_MARGIN = 0.002;

// Interleaved gradient noise (Jimenez 2014): rotates the tap pattern per pixel so few taps don't band.
float water_reflection_noise(vec2 pixel) {
	return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}

// Screen-space radius of the blur, per axis. slope_sigma: rms slope per axis that the pixel doesn't
// resolve; ndv: cosine between the view ray and the normal; proj: (PROJECTION_MATRIX[0][0], [1][1]).
vec2 water_reflection_spread(float slope_sigma, float ndv, vec2 proj) {
	// Ray angle to NDC is proj, NDC to UV is a half.
	vec2 angle = 2.0 * slope_sigma * vec2(clamp(ndv, 0.0, 1.0), 1.0);
	return min(angle * proj * 0.5 * WATER_REFLECTION_KERNEL_SIGMAS, vec2(WATER_REFLECTION_MAX_BLUR));
}

// True when mirror `slot` (0: the sea's plane, 1: the second plane; -1: none) is being rendered.
bool water_reflection_available(int slot) {
	return slot == 0 ? water_reflection_enabled : (slot == 1 && water_reflection_2_enabled);
}

// Where the horizon crosses the screen above (or below) this pixel, and on which side of it the water
// is: (screen UV y of the horizon, +1 or -1; 0 when looking straight down). vertex: the pixel's
// view-space position. A wave that tilts the mirror image across the horizon line would otherwise
// sample what the mirror camera sees under the plane: the lower half of the sky, a bright seam.
vec2 water_reflection_horizon(vec3 vertex, vec2 screen_uv, mat4 view, mat4 inv_view, mat4 proj) {
	vec3 dir = (inv_view * vec4(vertex, 0.0)).xyz;
	if (dot(dir.xz, dir.xz) < 1e-8) {
		return vec2(0.0);
	}
	vec4 clip = proj * vec4((view * vec4(dir.x, 0.0, dir.z, 0.0)).xyz, 0.0);
	if (clip.w <= 1e-6) {
		return vec2(0.0);
	}
	float y = clip.y / clip.w * 0.5 + 0.5;
	return vec2(y, screen_uv.y >= y ? 1.0 : -1.0);
}

vec3 water_reflection_tap(int slot, vec2 uv, vec2 horizon) {
	if (horizon.y != 0.0) {
		// The mirror image is sampled upside down: screen y = 1 - uv.y.
		float screen_y = 1.0 - uv.y;
		float limit = horizon.x + horizon.y * WATER_REFLECTION_HORIZON_MARGIN;
		screen_y = horizon.y > 0.0 ? max(screen_y, limit) : min(screen_y, limit);
		uv.y = 1.0 - screen_y;
	}
	vec2 inside = clamp(uv, vec2(WATER_REFLECTION_UV_MARGIN), vec2(1.0 - WATER_REFLECTION_UV_MARGIN));
	return slot == 1 ? texture(water_reflection_2, inside).rgb : texture(water_reflection, inside).rgb;
}

// Mirrored world of mirror `slot` seen at screen_uv, shifted by `offset` (the resolved waves) and
// blurred by `spread`, never crossing the `horizon` (water_reflection_horizon).
vec3 water_reflection_sample(int slot, vec2 screen_uv, vec2 offset, vec2 spread, vec2 frag_coord, vec2 horizon) {
	vec2 base = vec2(screen_uv.x, 1.0 - screen_uv.y) + offset;
	int taps = water_reflection_blur_samples;
	if (taps <= 1 || max(spread.x, spread.y) < WATER_REFLECTION_MIN_BLUR) {
		return water_reflection_tap(slot, base, horizon);
	}
	// Vogel disk: evenly spread taps over the ellipse, weighted to a Gaussian of the slope distribution.
	float rotation = water_reflection_noise(frag_coord) * TAU;
	vec3 sum = vec3(0.0);
	float weight_sum = 0.0;
	for (int i = 0; i < taps; i++) {
		float r = sqrt((float(i) + 0.5) / float(taps));
		float a = float(i) * WATER_GOLDEN_ANGLE + rotation;
		vec2 disk = vec2(cos(a), sin(a)) * r;
		float sigmas = r * WATER_REFLECTION_KERNEL_SIGMAS;
		float w = exp(-0.5 * sigmas * sigmas);
		sum += water_reflection_tap(slot, base + disk * spread, horizon) * w;
		weight_sum += w;
	}
	return sum / weight_sum;
}
