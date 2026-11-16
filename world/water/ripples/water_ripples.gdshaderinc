// Interaction ripples (WaterRipples): waves and foam that floating and moving objects make, simulated on
// a camera-centred grid. Every water shader adds them to its surface with water_ripples().

global uniform sampler2D water_ripple_map : filter_linear;
global uniform vec4 water_ripple_rect;          // origin x, origin z, size x, size z
global uniform bool water_ripples_enabled;

// Share of the area at each edge where the ripples fade out, so the border never shows.
const float WATER_RIPPLE_EDGE = 0.1;

// (dh/dx, dh/dz, height, foam) of the ripples at world `p`; zero outside the simulated area.
vec4 water_ripples(vec2 p) {
	if (!water_ripples_enabled || water_ripple_rect.z <= 0.0) {
		return vec4(0.0);
	}
	vec2 uv = (p - water_ripple_rect.xy) / water_ripple_rect.zw;
	float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
	if (edge <= 0.0) {
		return vec4(0.0);
	}
	vec2 texel = 1.0 / vec2(textureSize(water_ripple_map, 0));
	vec3 c = textureLod(water_ripple_map, uv, 0.0).rgb;
	float hx = textureLod(water_ripple_map, uv + vec2(texel.x, 0.0), 0.0).r - textureLod(water_ripple_map, uv - vec2(texel.x, 0.0), 0.0).r;
	float hz = textureLod(water_ripple_map, uv + vec2(0.0, texel.y), 0.0).r - textureLod(water_ripple_map, uv - vec2(0.0, texel.y), 0.0).r;
	vec2 slope = vec2(hx, hz) / (2.0 * texel * water_ripple_rect.zw);
	return vec4(slope, c.r, c.b) * smoothstep(0.0, WATER_RIPPLE_EDGE, edge);
}
