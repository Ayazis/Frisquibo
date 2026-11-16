shader_type canvas_item;
render_mode unshaded, blend_disabled;
// One step of the interaction ripples (WaterRipples): the 2D wave equation on a camera-centred grid,
// with disturbances pushed in and foam that decays. State texture: R height now, G height one step
// before, B foam (0..1). Two viewports take turns, each reading the other's last state.

const int MAX_SOURCES = 16;

uniform sampler2D previous : filter_nearest, repeat_disable;
uniform bool reset = true;                     // the first frame: start from still water
uniform vec2 texel = vec2(0.00390625);           // 1 / resolution
uniform vec2 shift = vec2(0.0);                // texels the area moved since the previous step
uniform float courant2 = 0.02;                 // (wave speed * dt / texel size)^2, below 0.5 to stay stable
uniform float damping = 0.99;                  // kept share of the wave per step
uniform float foam_decay = 0.99;               // kept share of the foam per step
uniform float edge_absorb = 0.1;               // share of the area at each edge where waves die out
uniform int source_count = 0;
uniform vec4 sources[MAX_SOURCES];             // centre (uv), radius (uv), push down in metres
uniform float source_foam[MAX_SOURCES];        // foam the source leaves, 0..1
// Gaussian footprint of a source: exp(-SOURCE_FALLOFF * (distance / radius)^2).
const float SOURCE_FALLOFF = 4.0;

vec3 state(vec2 uv) {
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
		return vec3(0.0);
	}
	return texture(previous, uv).rgb;
}

void fragment() {
	vec2 uv = UV + shift * texel;
	vec3 c = state(uv);
	float neighbours = state(uv + vec2(texel.x, 0.0)).r + state(uv - vec2(texel.x, 0.0)).r
			+ state(uv + vec2(0.0, texel.y)).r + state(uv - vec2(0.0, texel.y)).r;
	float next = (2.0 * c.r - c.g + courant2 * (neighbours - 4.0 * c.r)) * damping;
	float foam = c.b * foam_decay;
	for (int i = 0; i < MAX_SOURCES; i++) {
		if (i >= source_count) {
			break;
		}
		vec2 d = (UV - sources[i].xy) / max(sources[i].z, 1e-5);
		float g = exp(-SOURCE_FALLOFF * dot(d, d));
		next -= sources[i].w * g;
		foam = max(foam, source_foam[i] * g);
	}
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	next *= smoothstep(0.0, edge_absorb, edge);
	COLOR = reset ? vec4(0.0, 0.0, 0.0, 1.0) : vec4(next, c.r, foam, 1.0);
}
