// Caustics from the simulated waves: each wave crest is a weak lens. Sunlight entering a tilted surface
// bends by (1 - 1/n) of the tilt, so light that crossed the surface at x reaches the seabed d metres
// below at x + d (1 - 1/n) grad h. Where that map squeezes area together (under crests) the light is
// brighter by 1 / |det(I + d (1 - 1/n) H)|, H the curvature (Hessian) of the surface. Blue bends a little
// more than red, so the brightest lines get coloured fringes.
// Requires the including shader to declare: slope_maps (sampler2DArray, slopes in .xy), tile_lengths,
// cascade_count, map_size and MAX_CASCADES. The sun is taken as overhead.

// Refractive index of sea water for red, green and blue light.
const vec3 OCEAN_CAUSTIC_IOR = vec3(1.331, 1.333, 1.338);
// The sun's disk is half a degree wide, so deeper caustics are blurred over depth * this.
const float OCEAN_SUN_ANGULAR_SIZE = 0.0093;
// Brightest a caustic gets; real focus lines are limited the same way by the sun's size.
const float OCEAN_CAUSTIC_MAX = 12.0;

// Brightness of sunlight on the seabed `depth` metres below the surface at `p`, per colour (1 = flat
// water). waves: share of the simulated waves present there (shore damping).
vec3 ocean_caustics(vec2 p, float depth, float waves) {
	if (depth <= 0.0 || waves <= 0.0) {
		return vec3(1.0);
	}
	float blur = depth * OCEAN_SUN_ANGULAR_SIZE;
	vec2 dsx = vec2(0.0); // d(slope)/dx
	vec2 dsz = vec2(0.0); // d(slope)/dz
	for (int i = 0; i < MAX_CASCADES; i++) {
		if (i >= cascade_count) {
			break;
		}
		float tile = tile_lengths[i];
		float texel = tile / map_size;
		// Average over the sun-disk blur: pick the mip whose texels are that wide.
		float lod = log2(max(blur / texel, 1.0));
		float step_m = texel * exp2(lod);
		vec3 uv = vec3(p / tile, float(i));
		vec3 ex = vec3(step_m / tile, 0.0, 0.0);
		vec3 ez = vec3(0.0, step_m / tile, 0.0);
		dsx += (textureLod(slope_maps, uv + ex, lod).xy - textureLod(slope_maps, uv - ex, lod).xy) / (2.0 * step_m);
		dsz += (textureLod(slope_maps, uv + ez, lod).xy - textureLod(slope_maps, uv - ez, lod).xy) / (2.0 * step_m);
	}
	dsx *= waves;
	dsz *= waves;
	// H = [[hxx, hxz], [hzx, hzz]]; det(I + k H) = 1 + k tr(H) + k^2 det(H).
	float trace = dsx.x + dsz.y;
	float det = dsx.x * dsz.y - dsx.y * dsz.x;
	vec3 k = depth * (1.0 - 1.0 / OCEAN_CAUSTIC_IOR);
	vec3 j = 1.0 + k * trace + k * k * det;
	return min(1.0 / max(abs(j), vec3(1.0 / OCEAN_CAUSTIC_MAX)), vec3(OCEAN_CAUSTIC_MAX));
}
