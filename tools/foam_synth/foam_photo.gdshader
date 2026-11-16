// Foam from a photo, pass 1: brightness to height, with the lighting flattened and the seams blended so
// the result tiles. The input is a square crop; `lowpass` is the same crop shrunk to a few pixels.
shader_type canvas_item;

uniform sampler2D photo : filter_linear, repeat_enable;
uniform sampler2D lowpass : filter_linear, repeat_enable;
uniform float mean_luma = 0.5;
uniform vec2 levels = vec2(0.2, 0.9);   // luma that becomes height 0 and 1
uniform float flatten = 0.7;            // how much of the large-scale lighting to remove
uniform float seam_width = 0.22;        // share of the tile over which the seams are blended

float luma(vec2 uv) {
	float l = dot(texture(photo, uv).rgb, vec3(0.2126, 0.7152, 0.0722));
	float broad = dot(texture(lowpass, uv).rgb, vec3(0.2126, 0.7152, 0.0722));
	return l - (broad - mean_luma) * flatten;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), u.x), u.y);
}

float height_at(vec2 uv) {
	return smoothstep(levels.x, levels.y, luma(uv));
}

// Cross-fade that keeps the average and the contrast: a plain mix flattens the overlap into a greyer band.
float blend(float a, float b, float t, float mean_h) {
	return mean_h + ((a - mean_h) * (1.0 - t) + (b - mean_h) * t) / sqrt((1.0 - t) * (1.0 - t) + t * t);
}

// Weight of the half-shifted copy along one axis: 1 at the tile's border (where the copy wraps
// seamlessly), 0 in the middle (where the copy has its own seam), with a ragged edge.
float shift_weight(float x, float jitter) {
	float border = min(x, 1.0 - x);
	return 1.0 - smoothstep(0.0, seam_width, border + jitter * seam_width * 0.6);
}

// Seamless along x only.
float seamless_x(vec2 uv, float mean_h) {
	float a = height_at(uv);
	float b = height_at(vec2(fract(uv.x + 0.5), uv.y));
	return blend(a, b, shift_weight(uv.x, vnoise(uv * 24.0) - 0.5), mean_h);
}

void fragment() {
	// First seamless along x, then that result along y (shifting along y keeps it seamless along x).
	float mean_h = smoothstep(levels.x, levels.y, mean_luma);
	float a = seamless_x(UV, mean_h);
	float b = seamless_x(vec2(UV.x, fract(UV.y + 0.5)), mean_h);
	float h = blend(a, b, shift_weight(UV.y, vnoise(UV * 24.0 + 7.0) - 0.5), mean_h);
	COLOR = vec4(vec3(clamp(h, 0.0, 1.0)), 1.0);
}
