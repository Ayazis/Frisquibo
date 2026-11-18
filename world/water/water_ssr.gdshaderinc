// Screen-space reflections for every water surface (sea, lake, river). The planar mirror is one flat
// plane at the rest level: on big waves a nearby boat reflects from the wrong height, and sloping water
// (a river) has no mirror at all, only the sky. Here the ray reflected off the real, displaced surface is
// marched against the depth buffer and picks up whatever it hits on screen. It can only find what the
// screen shows, so it fades out at the screen edges, with distance and for rays turning back towards
// the camera; the mirror (or the sky) fills in there.
// Needs from the including shader: screen_tex (hint_screen_texture, mipmapped), depth_tex, and the
// water_optics and water_reflection includes.

// Ray-march steps from the quality tier (OceanQuality.reflection_march_steps); 0 turns it off.
global uniform int water_ssr_steps;

// Metres a reflected ray is followed.
const float WATER_SSR_MAX_DISTANCE = 60.0;
// How far behind a surface in the depth buffer the ray may be and still count as hitting it: a little,
// plus more with distance, where the steps grow and objects look thinner than they are.
const float WATER_SSR_THICKNESS = 0.5;
const float WATER_SSR_THICKNESS_PER_METRE = 0.03;
// Bisection steps that pin down a hit between the last two samples.
const int WATER_SSR_REFINE_STEPS = 5;
// Hits fade out within this share of the screen from its edges...
const float WATER_SSR_EDGE_FADE = 0.06;
// ...from this share of the ray's reach to its end...
const float WATER_SSR_DISTANCE_FADE = 0.7;
// ...and as the ray turns back towards the camera (view-space z of its direction), where what it would
// hit is mostly off screen.
const float WATER_SSR_TOWARD_CAMERA_FADE = 0.4;
// Sine of the lowest angle a reflected ray may take above the horizon. A wave tilted far enough sends
// the ray down into the next wave, which mostly mirrors the sky near the horizon in turn.
const float WATER_SSR_MIN_ELEVATION = 0.02;

// The view-space ray for a reflection leaving the surface in world direction `reflected`, kept above
// the horizon.
vec3 water_ssr_direction(vec3 reflected, mat4 view) {
	vec3 r = normalize(reflected);
	r.y = max(r.y, WATER_SSR_MIN_ELEVATION);
	return normalize((view * vec4(normalize(r), 0.0)).xyz);
}

vec2 water_ssr_project(vec3 p, mat4 proj) {
	vec4 clip = proj * vec4(p, 1.0);
	return clip.xy / clip.w * 0.5 + 0.5;
}

// Depth of the scene minus depth of `p` along the view axis: positive when `p` lies behind the
// surface the screen shows at its pixel.
float water_ssr_behind(vec3 p, mat4 proj, mat4 inv_proj) {
	vec2 uv = water_ssr_project(p, proj);
	vec3 scene = water_view_from_depth(uv, textureLod(depth_tex, uv, 0.0).r, inv_proj);
	return scene.z - p.z;
}

// Colour the reflected ray from view-space `origin` along `dir` hits (rgb), and how much to trust it
// (a: 0 nothing found). blur_lod: screen mip level for rough water.
vec4 water_ssr(vec3 origin, vec3 dir, mat4 proj, mat4 inv_proj, vec2 frag_coord, float blur_lod) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// Web / Compatibility: no reflection march; the sky (or the mirror) alone.
	return vec4(0.0);
#else
	int steps = water_ssr_steps;
	if (steps <= 0) {
		return vec4(0.0);
	}
	// Steps grow with the square of the distance: fine near the water, long reach far out. The
	// per-pixel jitter turns the banding of few steps into noise.
	float jitter = water_reflection_noise(frag_coord);
	float previous = 0.0;
	for (int i = 0; i < steps; i++) {
		float share = (float(i) + jitter) / float(steps);
		float t = WATER_SSR_MAX_DISTANCE * share * share;
		vec3 p = origin + dir * t;
		if (p.z >= 0.0) {
			break;
		}
		vec2 uv = water_ssr_project(p, proj);
		if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) {
			break;
		}
		float behind = water_ssr_behind(p, proj, inv_proj);
		if (behind > 0.0 && behind < WATER_SSR_THICKNESS + t * WATER_SSR_THICKNESS_PER_METRE) {
			float near_t = previous;
			float far_t = t;
			for (int k = 0; k < WATER_SSR_REFINE_STEPS; k++) {
				float mid = 0.5 * (near_t + far_t);
				if (water_ssr_behind(origin + dir * mid, proj, inv_proj) > 0.0) {
					far_t = mid;
				} else {
					near_t = mid;
				}
			}
			vec2 hit = water_ssr_project(origin + dir * far_t, proj);
			vec2 to_edge = min(hit, vec2(1.0) - hit);
			float trust = smoothstep(0.0, WATER_SSR_EDGE_FADE, min(to_edge.x, to_edge.y))
					* (1.0 - smoothstep(WATER_SSR_DISTANCE_FADE * WATER_SSR_MAX_DISTANCE, WATER_SSR_MAX_DISTANCE, far_t))
					* (1.0 - smoothstep(0.0, WATER_SSR_TOWARD_CAMERA_FADE, dir.z));
			return vec4(textureLod(screen_tex, hit, blur_lod).rgb, trust);
		}
		previous = t;
	}
	return vec4(0.0);
#endif
}

// Screen mip level that blurs a hit as much as the mirror blurs for this `spread`
// (water_reflection_spread, a fraction of the screen).
float water_ssr_blur_lod(vec2 spread, vec2 viewport_size) {
	return log2(max(max(spread.x * viewport_size.x, spread.y * viewport_size.y), 1.0));
}
