// Foam texture generator, pass 2: smears the height along a wavy flow (mostly along x), as wind and
// currents draw foam out into fibres. Line-integral convolution over a repeating texture.
shader_type canvas_item;

uniform sampler2D source : filter_linear, repeat_enable;
uniform float amount = 0.0;        // 0 = untouched, 1 = fully smeared
uniform float length_px = 40.0;    // streak half-length in pixels
uniform float texture_size = 2048.0;
const int STEPS = 24;

vec2 flow(vec2 uv) {
	float a = sin(uv.y * 6.2832 * 3.0 + sin(uv.x * 6.2832 * 2.0) * 1.5) * 0.25;
	return vec2(cos(a), sin(a));
}

void fragment() {
	float src = texture(source, UV).r;
	if (amount <= 0.0) {
		COLOR = vec4(vec3(src), 1.0);
	} else {
		float step_uv = length_px / texture_size / float(STEPS);
		float sum = src;
		float peak = src;
		float weight = 1.0;
		for (int dir = -1; dir <= 1; dir += 2) {
			vec2 p = UV;
			for (int i = 1; i <= STEPS; i++) {
				p += flow(p) * step_uv * float(dir);
				float wgt = 1.0 - float(i) / float(STEPS + 1);
				float s = texture(source, p).r;
				sum += s * wgt;
				peak = max(peak, s * wgt);
				weight += wgt;
			}
		}
		float smeared = mix(sum / weight * 1.8, peak, 0.35);
		COLOR = vec4(vec3(clamp(mix(src, smeared, amount), 0.0, 1.0)), 1.0);
	}
}
