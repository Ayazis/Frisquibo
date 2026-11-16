// Prototype: foam patterns side by side. Coverage falls from full on the left (x = -ramp/2) to none on
// the right, so one image shows how each pattern wears away.
// variant 0: the current cellular lace (foam_lace.gdshaderinc), a hard white mask.
// variant 1: flow streaks: ridged noise stretched along the flow and meandered by a broad warp, at three
//            sizes, eroded by coverage like a height map, shaded by thickness.
// variant 2: veins: a network of large cellular threads stretched along the crests (x), mildly warped,
//            frayed, with specks; a blurred copy below the surface tinted with bubble turquoise; the
//            fill amount runs from thin open-sea threads (low coverage) to a nearly closed sheet.
shader_type spatial;

// variant 6: the game's own foam (foam_surface.gdshaderinc) at a constant fill, to judge repetition.
#include "res://world/water/foam_surface.gdshaderinc"
uniform float fixed_fill = 0.5;

uniform int variant = 1;
uniform sampler2D lace_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D foam_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 water_color : source_color = vec3(0.015, 0.07, 0.07);
uniform vec3 foam_color : source_color = vec3(0.86, 0.9, 0.9);
uniform float ramp_width = 40.0;
uniform vec2 flow_dir = vec2(0.0, 1.0);

// variant 3: the vein network as the large structure, a scanned foam material (ambientCG Foam00x, CC0)
//            for the detail: its height decides where the foam wears through, at two tile sizes.
// variant 4: all three scans blended: smooth fluffy Foam001 where foam is dense, lacy Foam002 where it is
//            sparse, Foam003 between, varied across the sea by broad noise; each at its own size and angle.
uniform sampler2D tex_height : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_height_1 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_normal_1 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_height_2 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_normal_2 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_height_3 : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_normal_3 : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tex_tile = 2.5;
// variant 5: one packed texture (R, G normal, B height), scan or generated, under the vein network.
uniform sampler2D tex_packed : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 bubble_color : source_color = vec3(0.05, 0.26, 0.26);

varying vec3 w;

void vertex() {
	vec3 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = 0.35 * sin(p.z * 0.45) + 0.12 * sin(p.x * 0.31 + p.z * 0.22);
	VERTEX.y += h;
	NORMAL = normalize(vec3(-0.12 * 0.31 * cos(p.x * 0.31 + p.z * 0.22), 1.0,
			-(0.35 * 0.45 * cos(p.z * 0.45) + 0.12 * 0.22 * cos(p.x * 0.31 + p.z * 0.22))));
	w = p;
}

float lace(vec2 p, float age) {
	vec2 q = p / 4.0;
	float edge = min(texture(lace_tex, q).r, texture(lace_tex, q * 2.3 + vec2(0.37, 0.61)).r + 0.12);
	float width = mix(1.0, 0.04, pow(clamp(age, 0.0, 1.0), 0.5));
	return (1.0 - smoothstep(width, width + 0.03, edge)) * (1.0 - smoothstep(0.75, 1.0, age));
}

float streak_height(vec2 p) {
	vec2 d = normalize(flow_dir);
	vec2 n = vec2(-d.y, d.x);
	vec2 warp = vec2(texture(foam_tex, p / 23.0).r, texture(foam_tex, p / 23.0 + vec2(0.5, 0.27)).r) - 0.5;
	vec2 pw = p + warp * 7.0;
	vec2 s = vec2(dot(pw, n), dot(pw, d));
	float big = texture(foam_tex, vec2(s.x / 7.0, s.y / 20.0)).r;
	float mid = texture(foam_tex, vec2(s.x / 1.8, s.y / 4.5) + vec2(0.31, 0.11)).r;
	float fine = texture(foam_tex, vec2(s.x / 0.5, s.y / 1.0) + vec2(0.67, 0.43)).r;
	float patches = texture(foam_tex, p / 41.0 + vec2(0.13, 0.71)).r;
	return big * 0.4 + mid * 0.3 + fine * 0.15 + patches * 0.15;
}

// Edge distance of the vein network at p (0 on a thread), with a mip bias for the blurred copy.
float vein_edge(vec2 p, float bias, float lift, float fray) {
	vec2 warp = vec2(texture(foam_tex, p / 31.0).r, texture(foam_tex, p / 31.0 + vec2(0.5, 0.27)).r) - 0.5;
	vec2 wob = vec2(texture(foam_tex, p / 1.3).r, texture(foam_tex, p / 1.3 + vec2(0.21, 0.63)).r) - 0.5;
	vec2 q = p + warp * 2.5 + wob * 0.12;
	q.x /= 4.0;
	float e1 = texture(lace_tex, q / 22.0, bias).r;
	float e2 = texture(lace_tex, q / 7.0 + vec2(0.37, 0.71), bias).r + lift;
	float e = min(e1, e2);
	return e + (texture(foam_tex, p / 0.7, bias).r - 0.5) * fray;
}

void veins(vec2 p, float fill, vec3 view_world, out float cover, out float thick, out float sub, out float speck) {
	float width = mix(0.07, 0.85, fill);
	float lift = mix(0.45, 0.15, fill);
	float fray = mix(0.04, 0.12, fill);
	float e = vein_edge(p, 0.0, lift, fray);
	cover = 1.0 - smoothstep(width * 0.55, width, e);
	thick = smoothstep(0.0, 1.0, 1.0 - e / width);
	vec2 shift = -view_world.xz / max(abs(view_world.y), 0.25) * 0.15;
	float es = vein_edge(p + shift, 3.0, lift, fray);
	sub = 1.0 - smoothstep(width * 0.8, width * 1.7 + 0.1, es);
	float near_thread = 1.0 - smoothstep(width, width + 0.25, e);
	speck = smoothstep(0.75, 0.85, texture(lace_tex, p / 1.1 + vec2(0.17, 0.53)).r) * near_thread;
}

vec2 scan_uv(vec2 p, float tile, float angle, vec2 offset) {
	vec2 q = vec2(p.x / 1.6, p.y);
	float c = cos(angle);
	float s = sin(angle);
	return mat2(vec2(c, s), vec2(-s, c)) * q / tile + offset;
}

// Blended height (x) and tangent-space normal (yzw) of the three scans at p.
vec4 scans(vec2 p, float fill) {
	vec2 u1 = scan_uv(p, 3.1, 0.3, vec2(0.11, 0.42));
	vec2 u2 = scan_uv(p, 1.9, -0.5, vec2(0.67, 0.23));
	vec2 u3 = scan_uv(p, 2.5, 1.1, vec2(0.38, 0.81));
	// Preference by density: 001 dense, 003 middle, 002 sparse; broad noise moves the boundaries around.
	float n1 = texture(foam_tex, p / 29.0 + vec2(0.2, 0.7)).r;
	float n2 = texture(foam_tex, p / 13.0 + vec2(0.6, 0.1)).r;
	float d = clamp(fill + (n1 - 0.5) * 0.7, 0.0, 1.0);
	vec3 wgt = vec3(smoothstep(0.45, 0.85, d), 1.0 - smoothstep(0.15, 0.55, d), 0.0);
	wgt.z = max(1.0 - wgt.x - wgt.y, 0.0) + (n2 - 0.5) * 0.6;
	wgt = max(wgt, vec3(0.0));
	wgt /= max(wgt.x + wgt.y + wgt.z, 1e-3);
	float h = texture(tex_height_1, u1).r * wgt.x + texture(tex_height_2, u2).r * wgt.y + texture(tex_height_3, u3).r * wgt.z;
	vec3 nrm = (texture(tex_normal_1, u1).xyz * 2.0 - 1.0) * wgt.x + (texture(tex_normal_2, u2).xyz * 2.0 - 1.0) * wgt.y
			+ (texture(tex_normal_3, u3).xyz * 2.0 - 1.0) * wgt.z;
	return vec4(h, normalize(nrm));
}

void fragment() {
	float coverage = clamp(0.5 - w.x / ramp_width, 0.0, 1.0);
	float cover;
	float thick;
	if (variant == 0) {
		cover = lace(w.xz, 1.0 - coverage) * step(0.001, coverage);
		thick = cover;
	} else if (variant == 2) {
		vec3 view_world = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		float present = smoothstep(0.0, 0.08, coverage);
		float sub;
		float speck;
		veins(w.xz, coverage, view_world, cover, thick, sub, speck);
		cover = max(cover, speck * 0.7) * present;
		sub *= present;
		float cavity2 = mix(0.78, 1.0, texture(lace_tex, w.xz / 0.3).r);
		vec3 base = mix(water_color, bubble_color, sub * mix(0.35, 0.9, coverage));
		vec3 foam_albedo2 = mix(mix(bubble_color, foam_color, 0.55), foam_color, thick) * cavity2;
		ALBEDO = mix(base, foam_albedo2, cover);
		ROUGHNESS = mix(0.06, 0.8, cover);
		SPECULAR = 0.5;
		float hgt = thick * cover * 0.02;
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		vec3 r1 = cross(dpdy, NORMAL);
		vec3 r2 = cross(NORMAL, dpdx);
		float det = dot(dpdx, r1);
		vec3 grad = sign(det) * (dFdx(hgt) * r1 + dFdy(hgt) * r2);
		NORMAL = normalize(abs(det) * NORMAL - grad);
	} else if (variant == 6) {
		float dist6 = length(VERTEX);
		FoamSurface fs = foam_surface(w.xz, fixed_fill, foam_detail(dist6), vec2(0.0));
		cover = fs.cover;
		thick = fs.thick;
		vec3 base = mix(water_color, bubble_color, fs.sub * 0.3);
		ALBEDO = mix(base, mix(mix(bubble_color, foam_color, 0.5), foam_color, thick), cover);
		ROUGHNESS = mix(0.06, 0.8, cover);
		SPECULAR = 0.5;
	} else if (variant == 5) {
		vec3 view_world = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		float present = smoothstep(0.0, 0.08, coverage);
		float vcover;
		float vthick;
		float sub;
		float speck;
		veins(w.xz, coverage, view_world, vcover, vthick, sub, speck);
		vec2 u = scan_uv(w.xz, tex_tile, 0.3, vec2(0.11, 0.42));
		vec4 t = texture(tex_packed, u);
		float detail = 1.0 - smoothstep(12.0, 45.0, length(VERTEX));
		float h = mix(0.5, t.b, detail);
		float macro = mix(vthick, 1.0, coverage * coverage);
		float hh = macro * 0.45 + h * 0.55;
		float th = mix(0.72, 0.32, coverage);
		float aa = mix(0.12, 0.03, detail);
		cover = smoothstep(th - aa, th + aa, hh) * present;
		thick = smoothstep(th, th + 0.3, hh);
		sub *= present;
		vec3 base = mix(water_color, bubble_color, sub * mix(0.2, 0.5, coverage));
		ALBEDO = mix(base, mix(mix(bubble_color, foam_color, 0.5), foam_color, thick), cover);
		ROUGHNESS = mix(0.06, 0.8, cover);
		SPECULAR = 0.5;
		vec2 n = (t.rg * 2.0 - 1.0) * vec2(1.0, -1.0);
		NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), normalize(vec3(n.x, -n.y, 1.0)) * 0.5 + 0.5, cover * detail);
	} else if (variant == 4) {
		vec3 view_world = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		float present = smoothstep(0.0, 0.08, coverage);
		float vcover;
		float vthick;
		float sub;
		float speck;
		veins(w.xz, coverage, view_world, vcover, vthick, sub, speck);
		vec4 sc = scans(w.xz, coverage);
		// Far away the fine detail averages out instead of fizzing: pull it towards its mean.
		float dist = length(VERTEX);
		float detail = 1.0 - smoothstep(12.0, 45.0, dist);
		float h = mix(0.5, sc.x, detail);
		float macro = mix(vthick, 1.0, coverage * coverage);
		float hh = macro * 0.45 + h * 0.55;
		float t = mix(0.72, 0.32, coverage);
		float aa = max(fwidth(hh) * 1.5, 0.03);
		cover = smoothstep(t - aa, t + aa, hh) * present;
		thick = smoothstep(t, t + 0.3, hh);
		sub *= present;
		vec3 base = mix(water_color, bubble_color, sub * mix(0.35, 0.95, coverage));
		vec3 thin_foam = mix(bubble_color, foam_color, 0.5);
		ALBEDO = mix(base, mix(thin_foam, foam_color, thick), cover);
		ROUGHNESS = mix(0.06, 0.8, cover);
		SPECULAR = 0.5;
		NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), sc.yzw * 0.5 + 0.5, cover * detail);
	} else if (variant == 3) {
		vec3 view_world = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		float present = smoothstep(0.0, 0.08, coverage);
		float vcover;
		float vthick;
		float sub;
		float speck;
		veins(w.xz, coverage, view_world, vcover, vthick, sub, speck);
		vec2 ua = vec2(w.x / 1.6, w.z) / tex_tile;
		vec2 ub = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * vec2(w.x / 1.6, w.z) / (tex_tile * 2.37) + vec2(0.31, 0.57);
		float blend = smoothstep(0.35, 0.65, texture(foam_tex, w.xz / 17.0).r);
		float ha = texture(tex_height, ua).r;
		float hb = texture(tex_height, ub).r;
		float h = mix(ha, hb, blend);
		// Large structure from the veins, detail from the scan: erode the sum like a height map.
		float macro = mix(vthick, 1.0, coverage * coverage);
		float hh = macro * 0.55 + h * 0.45;
		float t = mix(0.75, 0.2, coverage);
		cover = smoothstep(t - 0.03, t + 0.05, hh) * present;
		thick = smoothstep(t, t + 0.35, hh);
		sub *= present;
		vec3 scan = mix(texture(tex_albedo, ua).rgb, texture(tex_albedo, ub).rgb, blend);
		vec3 base = mix(water_color, bubble_color, sub * mix(0.35, 0.9, coverage));
		vec3 thin_foam = mix(bubble_color, foam_color, 0.55);
		vec3 foam_albedo3 = mix(thin_foam, foam_color, thick) * mix(0.7, 1.0, dot(scan, vec3(0.333)));
		ALBEDO = mix(base, foam_albedo3, cover);
		ROUGHNESS = mix(0.06, 0.8, cover);
		SPECULAR = 0.5;
		vec3 na = texture(tex_normal, ua).xyz * 2.0 - 1.0;
		vec3 nb = texture(tex_normal, ub).xyz * 2.0 - 1.0;
		vec3 nt = normalize(mix(na, nb, blend));
		NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), nt * 0.5 + 0.5, cover);
	} else {
		float h = streak_height(w.xz);
		float t = 1.0 - coverage;
		cover = smoothstep(t - 0.05, t + 0.05, h) * step(0.001, coverage);
		thick = smoothstep(t, t + 0.4, h);
	}
	if (variant < 2) {
		float cavity = mix(0.72, 1.0, texture(lace_tex, w.xz / 0.3).r);
		vec3 thin = water_color + foam_color * 0.4;
		vec3 foam_albedo = variant == 0 ? foam_color : mix(thin, foam_color, thick) * cavity;
		ALBEDO = mix(water_color, foam_albedo, cover);
		ROUGHNESS = mix(0.06, 0.75, cover);
		SPECULAR = 0.5;
	}
}
