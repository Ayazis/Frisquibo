// Sea foam on a surface: a network of large veins for the big shapes, foam photos and scans for the
// detail (world/water/foam_scans/SOURCE.txt), three per foam density, picked across the sea by broad noise. One `fill` value runs from thin open-sea threads (low) to a nearly
// closed surf-zone sheet (high). The result is a thickness, not an on/off mask: thin foam lets the water
// through, and a blurred copy of the pattern just under the surface stands for the bubbles below the foam.
// Shared by the open-sea foam (ocean), the lace breakers leave (foam_lace) and foam on the beach.

// Set by Ocean (WaterTextures): cellular edge distance, a ridged noise, and the packed foam textures
// (R, G: normal x, y in OpenGL convention; B: height).
global uniform sampler2D water_foam_lace : filter_linear_mipmap_anisotropic, repeat_enable;
global uniform sampler2D water_foam_noise : filter_linear_mipmap_anisotropic, repeat_enable;
global uniform sampler2D water_foam_dense_a : filter_linear_mipmap_anisotropic, repeat_enable;
global uniform sampler2D water_foam_dense_b : filter_linear_mipmap_anisotropic, repeat_enable;
global uniform sampler2D water_foam_dense_c : filter_linear_mipmap_anisotropic, repeat_enable;
global uniform sampler2D water_foam_middle_a : filter_linear_mipmap_anisotropic, repeat_enable;
global uniform sampler2D water_foam_middle_b : filter_linear_mipmap_anisotropic, repeat_enable;
global uniform sampler2D water_foam_middle_c : filter_linear_mipmap_anisotropic, repeat_enable;
global uniform sampler2D water_foam_sparse_a : filter_linear_mipmap_anisotropic, repeat_enable;
global uniform sampler2D water_foam_sparse_b : filter_linear_mipmap_anisotropic, repeat_enable;
global uniform sampler2D water_foam_sparse_c : filter_linear_mipmap_anisotropic, repeat_enable;
global uniform sampler2D water_foam_specks : filter_linear_mipmap_anisotropic, repeat_enable;

// Veins: metres per tile of the two cell sizes (about 15 cells per tile), and how much longer the cells
// are along x than across.
const float FOAM_VEIN_TILE = 22.0;
const float FOAM_VEIN_FINE_TILE = 7.0;
const float FOAM_VEIN_STRETCH = 4.0;
// A broad warp bends the cells out of their grid; a small wobble makes the threads waver.
const float FOAM_WARP_TILE = 31.0;
const float FOAM_WARP = 2.5;
const float FOAM_WOBBLE_TILE = 1.3;
const float FOAM_WOBBLE = 0.12;
// Fraying of the thread edges (in edge distance), at this many metres per tile.
const float FOAM_FRAY_TILE = 0.7;
const vec2 FOAM_FRAY = vec2(0.04, 0.12);
// Thread width (edge distance) from sparse to dense, and the lift that keeps the fine cells thinner.
const vec2 FOAM_VEIN_WIDTH = vec2(0.07, 0.85);
const vec2 FOAM_FINE_LIFT = vec2(0.45, 0.15);
// Foam textures: metres per tile of the dense, middle and sparse ones, and their angles, so their tiling
// never lines up. All are squeezed along x like the veins.
const float FOAM_SCAN_STRETCH = 1.6;
const vec3 FOAM_SCAN_TILE = vec3(3.5, 2.8, 2.2);
const vec3 FOAM_SCAN_ANGLE = vec3(0.3, 1.1, -0.5);
// Which of a density's three textures where: broad noise (metres per tile) split at these values, with
// a soft change-over of this width.
const float FOAM_VARIANT_TILE = 41.0;
const vec2 FOAM_VARIANT_SPLIT = vec2(0.45, 0.62);
const float FOAM_VARIANT_BLEND = 0.06;
// The second and third variant are drawn at these sizes and turned by these angles relative to the first.
const vec2 FOAM_VARIANT_SCALE = vec2(1.13, 0.89);
const vec2 FOAM_VARIANT_TURN = vec2(0.9, -0.7);
// Lone specks of foam where it is sparse: metres per tile, height threshold, and how white they are.
const float FOAM_SPECK_TILE = 1.2;
const vec2 FOAM_SPECK_LEVEL = vec2(0.55, 0.85);
const vec2 FOAM_SPECK_FILL = vec2(0.1, 0.6);
const float FOAM_SPECK_COVER = 0.6;
// Which density where: dense textures above, sparse below these fill values; broad noise moves the
// boundaries (FOAM_MIX_TILE metres, by FOAM_MIX_SPREAD) and sprinkles the middle ones in everywhere.
const vec2 FOAM_DENSE_RANGE = vec2(0.45, 0.85);
const vec2 FOAM_SPARSE_RANGE = vec2(0.15, 0.55);
const float FOAM_MIX_TILE = 29.0;
const float FOAM_MIX_SPREAD = 0.7;
const float FOAM_SPRINKLE_TILE = 13.0;
const float FOAM_SPRINKLE = 0.6;
// The large shapes come from the same textures drawn this many times bigger (hex-tiled, so they never
// repeat on a grid), with this share of the vein network mixed in; they stay visible to the horizon,
// where the fine detail has faded out.
const float FOAM_LARGE_SCALE = 5.0;
const float FOAM_LARGE_VEIN_SHARE = 0.3;
// The textures' heights average about FOAM_HEX_MEAN; the large shapes are re-centred on 0.5 (like the
// vein network) and given this much contrast, so the amount of foam stays what `fill` asks for.
const float FOAM_LARGE_CONTRAST = 1.6;
// Large shapes and fine detail: their shares in the eroded height...
const float FOAM_MACRO_SHARE = 0.4;
// ...and the height where foam wears through, from sparse to dense.
const vec2 FOAM_THRESHOLD = vec2(0.72, 0.32);
// Edge softness up close and far away, and the height range over which foam thickens to full white.
const vec2 FOAM_SOFTNESS = vec2(0.03, 0.12);
const float FOAM_THICKENING = 0.3;
// The bubble layer under the foam: blurred (mip bias) and wider than the foam itself.
const float FOAM_SUB_BLUR = 3.0;
const vec2 FOAM_SUB_WIDTH = vec2(0.8, 1.7);
const float FOAM_SUB_MARGIN = 0.1;
// Below this fill there is no foam at all.
const float FOAM_PRESENT = 0.08;

struct FoamSurface {
	float cover;   // 0..1 how much of the pixel is foam
	float thick;   // 0..1 thin and see-through to thick and white
	float sub;     // 0..1 bubbles just under the surface (blurred, wider)
	vec3 normal;   // world-space bend of the foam's relief (add to the surface normal)
};

float foam_noise(vec2 p) {
	return texture(water_foam_noise, p).r;
}

// Edge distance of the vein network at p (0 on a thread).
float foam_vein_edge(vec2 p, float bias, float lift, float fray) {
	vec2 warp = vec2(foam_noise(p / FOAM_WARP_TILE), foam_noise(p / FOAM_WARP_TILE + vec2(0.5, 0.27))) - 0.5;
	vec2 wob = vec2(foam_noise(p / FOAM_WOBBLE_TILE), foam_noise(p / FOAM_WOBBLE_TILE + vec2(0.21, 0.63))) - 0.5;
	vec2 q = p + warp * FOAM_WARP + wob * FOAM_WOBBLE;
	q.x /= FOAM_VEIN_STRETCH;
	float coarse = texture(water_foam_lace, q / FOAM_VEIN_TILE, bias).r;
	float fine = texture(water_foam_lace, q / FOAM_VEIN_FINE_TILE + vec2(0.37, 0.71), bias).r + lift;
	return min(coarse, fine) + (texture(water_foam_noise, p / FOAM_FRAY_TILE, bias).r - 0.5) * fray;
}

// Hex-tiling (stochastic texturing): the plane is cut into hexagonal cells, each samples the texture at
// a random offset and a small random turn, and neighbouring cells blend. No regular grid is left, so
// nothing distinctive in a texture comes back at a fixed spacing. Cells per texture tile...
const float FOAM_HEX_DENSITY = 1.3;
// ...how far each cell may turn (radians; small, so foam stretched along the crests stays so)...
const float FOAM_HEX_TURN = 0.4;
// ...how sharply cells hand over (higher: less blending, less washed-out detail)...
const float FOAM_HEX_SHARPNESS = 4.0;
// ...and the typical height the blend keeps the contrast around.
const float FOAM_HEX_MEAN = 0.4;
// Skews the plane so a square grid of cells becomes a triangular one (Heitz & Neyret 2018).
const mat2 FOAM_HEX_SKEW = mat2(vec2(1.0, 0.0), vec2(-0.57735027, 1.15470054));
const float FOAM_HEX_SCALE = 3.46410162;  // 2 sqrt(3): one cell per unit

vec2 foam_hex_hash(vec2 cell) {
	return fract(sin(vec2(dot(cell, vec2(127.1, 311.7)), dot(cell, vec2(269.5, 183.3)))) * 43758.5453);
}

// One cell's sample: packed texel and the cell's turn.
vec4 foam_hex_sample(sampler2D scan, vec2 uv, vec2 dx, vec2 dy, vec2 cell, out float turn) {
	vec2 h = foam_hex_hash(cell);
	turn = (h.x - 0.5) * 2.0 * FOAM_HEX_TURN;
	float c = cos(turn);
	float s = sin(turn);
	mat2 r = mat2(vec2(c, s), vec2(-s, c));
	return textureGrad(scan, r * uv + h, r * dx, r * dy);
}

// Height (x) and the normal's slope (yz) in the uv frame, hex-tiled.
vec3 foam_hex(sampler2D scan, vec2 uv) {
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	vec2 skewed = FOAM_HEX_SKEW * (uv * FOAM_HEX_DENSITY * FOAM_HEX_SCALE);
	vec2 base = floor(skewed);
	vec3 t = vec3(fract(skewed), 0.0);
	t.z = 1.0 - t.x - t.y;
	vec3 w;
	vec2 v1;
	vec2 v2;
	vec2 v3;
	if (t.z > 0.0) {
		w = vec3(t.z, t.y, t.x);
		v1 = base;
		v2 = base + vec2(0.0, 1.0);
		v3 = base + vec2(1.0, 0.0);
	} else {
		w = vec3(-t.z, 1.0 - t.y, 1.0 - t.x);
		v1 = base + vec2(1.0, 1.0);
		v2 = base + vec2(1.0, 0.0);
		v3 = base + vec2(0.0, 1.0);
	}
	w = pow(max(w, vec3(0.0)), vec3(FOAM_HEX_SHARPNESS));
	w /= max(w.x + w.y + w.z, 1e-5);
	float r1;
	float r2;
	float r3;
	vec4 s1 = foam_hex_sample(scan, uv, dx, dy, v1, r1);
	vec4 s2 = foam_hex_sample(scan, uv, dx, dy, v2, r2);
	vec4 s3 = foam_hex_sample(scan, uv, dx, dy, v3, r3);
	// Heights blend around their typical value, scaled back up so the overlap keeps its contrast.
	float h = FOAM_HEX_MEAN + (w.x * (s1.b - FOAM_HEX_MEAN) + w.y * (s2.b - FOAM_HEX_MEAN) + w.z * (s3.b - FOAM_HEX_MEAN))
			/ sqrt(dot(w, w));
	// Normals: OpenGL green points to the image's top, v grows to its bottom; turn each back by its cell's turn.
	vec2 n = vec2(0.0);
	vec2 n1 = (s1.rg * 2.0 - 1.0) * vec2(1.0, -1.0);
	vec2 n2 = (s2.rg * 2.0 - 1.0) * vec2(1.0, -1.0);
	vec2 n3 = (s3.rg * 2.0 - 1.0) * vec2(1.0, -1.0);
	n += w.x * vec2(cos(r1) * n1.x + sin(r1) * n1.y, -sin(r1) * n1.x + cos(r1) * n1.y);
	n += w.y * vec2(cos(r2) * n2.x + sin(r2) * n2.y, -sin(r2) * n2.x + cos(r2) * n2.y);
	n += w.z * vec2(cos(r3) * n3.x + sin(r3) * n3.y, -sin(r3) * n3.x + cos(r3) * n3.y);
	return vec3(clamp(h, 0.0, 1.0), n);
}

// One texture at p: height (x) and world-space normal bend (yz -> x, z).
vec3 foam_scan(sampler2D scan, vec2 p, float tile, float angle, vec2 offset) {
	float c = cos(angle);
	float s = sin(angle);
	vec2 q = vec2(p.x / FOAM_SCAN_STRETCH, p.y);
	vec3 t = foam_hex(scan, vec2(c * q.x - s * q.y, s * q.x + c * q.y) / tile + offset);
	// Turn the normal's slope back from the texture's rotated frame into the world's.
	return vec3(t.x, c * t.y + s * t.z, -s * t.y + c * t.z);
}

// One density's texture at p: its three variants picked by broad noise `pick`, blended where they meet.
vec3 foam_role(sampler2D a, sampler2D b, sampler2D c, vec2 p, float tile, float angle, float pick) {
	float wa = 1.0 - smoothstep(FOAM_VARIANT_SPLIT.x - FOAM_VARIANT_BLEND, FOAM_VARIANT_SPLIT.x + FOAM_VARIANT_BLEND, pick);
	float wc = smoothstep(FOAM_VARIANT_SPLIT.y - FOAM_VARIANT_BLEND, FOAM_VARIANT_SPLIT.y + FOAM_VARIANT_BLEND, pick);
	float wb = max(1.0 - wa - wc, 0.0);
	vec3 r = vec3(0.0);
	if (wa > 0.0) {
		r += foam_scan(a, p, tile, angle, vec2(0.11, 0.42)) * wa;
	}
	if (wb > 0.0) {
		r += foam_scan(b, p, tile * FOAM_VARIANT_SCALE.x, angle + FOAM_VARIANT_TURN.x, vec2(0.67, 0.23)) * wb;
	}
	if (wc > 0.0) {
		r += foam_scan(c, p, tile * FOAM_VARIANT_SCALE.y, angle + FOAM_VARIANT_TURN.y, vec2(0.38, 0.81)) * wc;
	}
	return r;
}

// All three densities' textures at p, weighted by w (dense, middle, sparse), drawn `scale` times bigger.
vec3 foam_textures(vec2 p, vec3 w, float scale) {
	vec3 scan = vec3(0.0);
	if (w.x > 0.0) {
		float pick = foam_noise(p / FOAM_VARIANT_TILE + vec2(0.13, 0.57));
		scan += foam_role(water_foam_dense_a, water_foam_dense_b, water_foam_dense_c, p, FOAM_SCAN_TILE.x * scale, FOAM_SCAN_ANGLE.x, pick) * w.x;
	}
	if (w.y > 0.0) {
		float pick = foam_noise(p / FOAM_VARIANT_TILE + vec2(0.71, 0.09));
		scan += foam_role(water_foam_middle_a, water_foam_middle_b, water_foam_middle_c, p, FOAM_SCAN_TILE.y * scale, FOAM_SCAN_ANGLE.y, pick) * w.y;
	}
	if (w.z > 0.0) {
		float pick = foam_noise(p / FOAM_VARIANT_TILE + vec2(0.37, 0.83));
		scan += foam_role(water_foam_sparse_a, water_foam_sparse_b, water_foam_sparse_c, p, FOAM_SCAN_TILE.z * scale, FOAM_SCAN_ANGLE.z, pick) * w.z;
	}
	return scan;
}

// `fill` 0..1 (none, sparse threads .. dense sheet); `detail` 1 up close, 0 far away (fine detail
// averaged out); `sub_shift` metres the bubble layer is seen displaced by refraction.
FoamSurface foam_surface(vec2 p, float fill, float detail, vec2 sub_shift) {
	FoamSurface f;
	f.cover = 0.0;
	f.thick = 0.0;
	f.sub = 0.0;
	f.normal = vec3(0.0);
	if (fill <= 0.0) {
		return f;
	}
	fill = min(fill, 1.0);
	float present = smoothstep(0.0, FOAM_PRESENT, fill);
	float width = mix(FOAM_VEIN_WIDTH.x, FOAM_VEIN_WIDTH.y, fill);
	float lift = mix(FOAM_FINE_LIFT.x, FOAM_FINE_LIFT.y, fill);
	// Fraying is fine detail too: far away it only draws contour lines.
	float fray = mix(FOAM_FRAY.x, FOAM_FRAY.y, fill) * detail;
	float edge = foam_vein_edge(p, 0.0, lift, fray);
	float vein = smoothstep(0.0, 1.0, 1.0 - edge / width);

	float d = clamp(fill + (foam_noise(p / FOAM_MIX_TILE + vec2(0.2, 0.7)) - 0.5) * FOAM_MIX_SPREAD, 0.0, 1.0);
	vec3 w = vec3(smoothstep(FOAM_DENSE_RANGE.x, FOAM_DENSE_RANGE.y, d), 0.0,
			1.0 - smoothstep(FOAM_SPARSE_RANGE.x, FOAM_SPARSE_RANGE.y, d));
	w.y = max(1.0 - w.x - w.z, 0.0) + (foam_noise(p / FOAM_SPRINKLE_TILE + vec2(0.6, 0.1)) - 0.5) * FOAM_SPRINKLE;
	w = max(w, vec3(0.0));
	w /= max(w.x + w.y + w.z, 1e-3);
	vec3 scan = detail > 0.0 ? foam_textures(p, w, 1.0) : vec3(0.5, 0.0, 0.0);
	vec3 large = foam_textures(p, w, FOAM_LARGE_SCALE);
	float h = mix(0.5, scan.x, detail);
	float shapes = mix(0.5 + (large.x - FOAM_HEX_MEAN) * FOAM_LARGE_CONTRAST, vein, FOAM_LARGE_VEIN_SHARE);
	float macro = mix(shapes, 1.0, fill * fill);
	float eroded = macro * FOAM_MACRO_SHARE + h * (1.0 - FOAM_MACRO_SHARE);
	float threshold = mix(FOAM_THRESHOLD.x, FOAM_THRESHOLD.y, fill);
	float soft = mix(FOAM_SOFTNESS.y, FOAM_SOFTNESS.x, detail);
	f.cover = smoothstep(threshold - soft, threshold + soft, eroded) * present;
	float speck = smoothstep(FOAM_SPECK_LEVEL.x, FOAM_SPECK_LEVEL.y, texture(water_foam_specks, p / FOAM_SPECK_TILE).b)
			* (1.0 - smoothstep(FOAM_SPECK_FILL.x, FOAM_SPECK_FILL.y, fill)) * present * detail;
	f.cover = max(f.cover, speck * FOAM_SPECK_COVER);
	f.thick = smoothstep(threshold, threshold + FOAM_THICKENING, eroded);
	float sub_edge = foam_vein_edge(p + sub_shift, FOAM_SUB_BLUR, lift, fray);
	f.sub = (1.0 - smoothstep(width * FOAM_SUB_WIDTH.x, width * FOAM_SUB_WIDTH.y + FOAM_SUB_MARGIN, sub_edge)) * present;
	f.normal = (vec3(scan.y, 0.0, scan.z) * detail + vec3(large.y, 0.0, large.z) / FOAM_LARGE_SCALE) * f.cover;
	return f;
}

// How much fine detail to keep at `dist` metres from the camera.
const vec2 FOAM_DETAIL_FADE = vec2(12.0, 45.0);
float foam_detail(float dist) {
	return 1.0 - smoothstep(FOAM_DETAIL_FADE.x, FOAM_DETAIL_FADE.y, dist);
}
