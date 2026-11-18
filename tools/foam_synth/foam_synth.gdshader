// Foam texture generator, pass 1: a seamless foam height field (0..1) of one kind, built from packed
// bubbles of mixed sizes inside a large-scale mask. Rendered once into a texture by foam_synth.gd.
// Kinds: 0 surf sheet (dense, low-contrast holes stretched along x), 1 streaks (thin threads along x),
// 2 spatter (clusters and lone specks), 3 old lace (thin warped network), 4 churn (fresh, lumpy white water).
shader_type canvas_item;

uniform int kind = 0;
uniform float seed = 1.0;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031 + seed * 0.0173);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973) + seed * 0.0213);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// Value noise that repeats every `period` cells, so the texture tiles.
float vnoise(vec2 uv, vec2 period) {
	vec2 p = uv * period;
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(mod(i, period));
	float b = hash21(mod(i + vec2(1.0, 0.0), period));
	float c = hash21(mod(i + vec2(0.0, 1.0), period));
	float d = hash21(mod(i + vec2(1.0, 1.0), period));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 uv, vec2 period, int octaves) {
	float sum = 0.0;
	float amp = 0.5;
	float norm = 0.0;
	for (int o = 0; o < octaves; o++) {
		sum += vnoise(uv + float(o) * 0.37, period) * amp;
		norm += amp;
		period *= 2.0;
		amp *= 0.5;
	}
	return sum / norm;
}

// Packed bubbles: one jittered disc per cell (if it exists), radius in cell units, as dome heights.
float bubbles(vec2 uv, float cells, vec2 radius, float density, float salt) {
	vec2 p = uv * cells;
	vec2 i = floor(p);
	float h = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = i + vec2(float(x), float(y));
			vec2 cw = mod(c, vec2(cells)) + salt;
			if (hash21(cw + 3.3) > density) {
				continue;
			}
			vec2 centre = c + 0.15 + 0.7 * hash22(cw);
			float r = mix(radius.x, radius.y, hash21(cw + 7.1));
			float d = length(p - centre) / r;
			h = max(h, sqrt(max(1.0 - d * d, 0.0)));
		}
	}
	return h;
}

// Distance to the nearest edge of a seamless cellular pattern (F2 - F1), cells per axis `period`.
float cell_edge(vec2 uv, vec2 period) {
	vec2 p = uv * period;
	vec2 i = floor(p);
	float f1 = 9.0;
	float f2 = 9.0;
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			vec2 c = i + vec2(float(x), float(y));
			vec2 centre = c + hash22(mod(c, period) + 11.0);
			float d = length(p - centre);
			if (d < f1) {
				f2 = f1;
				f1 = d;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return f2 - f1;
}

// Foam body: three sizes of packed bubbles; `size` > 1 makes them bigger (older or fresher foam).
float foam_body(vec2 uv, float size, float density) {
	float big = bubbles(uv, 60.0 / size, vec2(0.35, 0.75), density, 0.0);
	float mid = bubbles(uv, 150.0 / size, vec2(0.35, 0.8), density, 17.0);
	float small = bubbles(uv, 380.0 / size, vec2(0.3, 0.8), density, 41.0);
	return max(max(big * 0.95, mid * 0.8), small * 0.65);
}

void fragment() {
	vec2 uv = UV;
	vec2 warp = vec2(fbm(uv, vec2(3.0), 3), fbm(uv + 0.5, vec2(3.0), 3)) - 0.5;
	float h = 0.0;
	if (kind == 0) {
		// Surf sheet: holes long along x, shallow (bubbly water shows through), many sizes.
		float n = fbm(uv + warp * 0.08, vec2(3.0, 10.0), 5);
		float hole = smoothstep(0.56, 0.66, n);
		float body = foam_body(uv, 1.0, 0.95);
		h = mix(0.45 + 0.55 * body, 0.12 + 0.25 * foam_body(uv + 0.31, 0.6, 0.35), hole);
	} else if (kind == 1) {
		// Streaks: ridged noise drawn out along x into threads, at two sizes.
		float a = fbm(uv + warp * 0.05, vec2(2.0, 22.0), 4);
		float b = fbm(uv + warp * 0.03 + 0.21, vec2(3.0, 48.0), 3);
		float threads = max(pow(1.0 - abs(2.0 * a - 1.0), 7.0), 0.7 * pow(1.0 - abs(2.0 * b - 1.0), 10.0));
		float patches = smoothstep(0.35, 0.65, fbm(uv, vec2(4.0, 6.0), 3));
		h = threads * mix(0.4, 1.0, patches) * (0.5 + 0.5 * foam_body(uv, 0.5, 0.9));
	} else if (kind == 2) {
		// Spatter: clusters of small bubbles and lone specks on open water.
		float clusters = smoothstep(0.58, 0.75, fbm(uv + warp * 0.1, vec2(6.0), 5));
		float cluster_body = foam_body(uv, 0.5, 0.85) * clusters;
		float specks = bubbles(uv, 220.0, vec2(0.15, 0.4), 0.18, 63.0) * 0.8;
		h = max(cluster_body, specks * smoothstep(0.35, 0.6, fbm(uv, vec2(8.0), 3)));
	} else if (kind == 3) {
		// Old lace: a strongly warped network at two sizes, threads of varying width that break off.
		vec2 w2 = vec2(fbm(uv * 1.0 + 0.13, vec2(7.0), 4), fbm(uv + 0.71, vec2(7.0), 4)) - 0.5;
		float e = cell_edge(uv + warp * 0.3 + w2 * 0.08, vec2(4.0, 8.0));
		float fine = cell_edge(uv + warp * 0.2 + w2 * 0.05 + 0.4, vec2(11.0, 20.0)) + 0.12;
		float edge = min(e, fine);
		float width = mix(0.015, 0.11, fbm(uv + 0.29, vec2(9.0), 3));
		float thread = 1.0 - smoothstep(width * 0.5, width, edge);
		float broken = smoothstep(0.3, 0.5, fbm(uv + 0.83, vec2(12.0), 3));
		h = thread * broken * (0.45 + 0.55 * foam_body(uv, 0.7, 0.9));
	} else {
		// Churn: fresh white water, nearly closed, lumpy, big bubbles.
		float lumps = fbm(uv + warp * 0.2, vec2(5.0), 5);
		float body = foam_body(uv, 1.6, 1.0);
		h = (0.55 + 0.3 * lumps) * (0.7 + 0.3 * body) + 0.15 * smoothstep(0.6, 0.8, lumps);
	}
	COLOR = vec4(vec3(clamp(h, 0.0, 1.0)), 1.0);
}
