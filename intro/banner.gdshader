shader_type spatial;
render_mode cull_disabled;
// Hanging cloth: pinned at the top (UV.y = 0), waves in the wind. Optional heraldic emblem + swallowtail.

uniform vec3 cloth_color : source_color = vec3(0.55, 0.06, 0.08);
uniform vec3 trim_color : source_color = vec3(0.92, 0.72, 0.22);
uniform bool emblem = true;
uniform float wave = 0.15;
uniform float speed = 3.0;
uniform float phase = 0.0;

varying float fold;

void vertex() {
	float t = UV.y;
	float s = sin(TIME * speed + UV.y * 5.0 + UV.x * 2.5 + phase);
	VERTEX.z += s * wave * t;
	VERTEX.x += sin(TIME * speed * 0.7 + UV.y * 3.0 + phase) * wave * 0.25 * t;
	fold = s * t;
}

void fragment() {
	vec2 uv = UV;
	vec3 c = cloth_color;
	if (emblem) {
		if (uv.y > 1.0 - (0.5 - abs(uv.x - 0.5)) * 0.35) discard; // swallowtail
		float border = step(min(uv.x, 1.0 - uv.x), 0.06) + step(uv.y, 0.04);
		vec2 p = (uv - vec2(0.5, 0.4)) * vec2(1.0, 2.0);
		float ring = 1.0 - smoothstep(0.03, 0.05, abs(length(p) - 0.3));
		float cross_h = step(abs(p.y), 0.05) * step(abs(p.x), 0.22);
		float cross_v = step(abs(p.x), 0.05) * step(abs(p.y), 0.22);
		float e = clamp(border + ring + cross_h + cross_v, 0.0, 1.0);
		c = mix(c, trim_color, e);
	}
	c *= 0.8 + 0.25 * fold;
	ALBEDO = c;
	ROUGHNESS = 0.95;
	BACKLIGHT = c * 0.4;
}
