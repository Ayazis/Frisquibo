// The sun's and the moon's discs and the stars. Needs sky_atmosphere.gdshaderinc first.

uniform mat3 star_rotation = mat3(1.0);          // equatorial to world: columns are the equatorial axes
uniform float night = 0.0;                       // 0 by day, 1 when the stars are out
uniform vec3 moon_disc_light = vec3(0.0);        // the moon's disc radiance before the air

const float SUN_ANGULAR_RADIUS = 0.004654;      // 0.2667 degrees
const float MOON_ANGULAR_RADIUS = 0.00452;
// The sun's disc is far brighter than anything else; capped so its glow stays a glow.
const float SUN_DISC_RADIANCE = 80.0;
const float LIMB_DARKENING = 0.6;
// Stars: cells per radian of sky, the share of cells with a star, size within its cell, brightness.
const float STAR_CELLS = 220.0;
const float STAR_SHARE = 0.12;
const float STAR_SIZE = 0.09;
const float STAR_RADIANCE = 0.08;
const float STAR_BRIGHTNESS_SPREAD = 12.0;

vec3 night_hash3(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

// Disc coordinate of `view` around `centre`: 0 at the centre, 1 at the edge of a disc of `radius`.
// Uses the cross product, which stays precise for tiny angles where acos does not.
float disc_radius(vec3 view, vec3 centre, float radius) {
	if (dot(view, centre) <= 0.0) {
		return 2.0;
	}
	return length(cross(view, centre)) / sin(radius);
}

vec3 sun_disc(vec3 view, vec3 sun, float sun_light, float altitude, float turbidity) {
	float r = disc_radius(view, sun, SUN_ANGULAR_RADIUS);
	if (r >= 1.0) {
		return vec3(0.0);
	}
	float edge = 1.0 - smoothstep(1.0 - fwidth(r) * 1.5, 1.0, r);
	float limb = 1.0 - LIMB_DARKENING * (1.0 - sqrt(max(1.0 - r * r, 0.0)));
	return SUN_DISC_RADIANCE * sun_light * limb * edge * atmo_transmittance(altitude, view.y, turbidity);
}

// The moon's disc, lit from the sun's side, with darker seas from the cloud noise.
vec3 moon_disc(vec3 view, vec3 moon, vec3 sun, float altitude, float turbidity, sampler3D maria) {
	float r = disc_radius(view, moon, MOON_ANGULAR_RADIUS);
	if (r >= 1.0) {
		return vec3(0.0);
	}
	vec3 side = normalize(cross(moon, abs(moon.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	vec3 up = cross(side, moon);
	vec2 disc = vec2(dot(view - moon, side), dot(view - moon, up)) / sin(MOON_ANGULAR_RADIUS);
	vec3 normal = side * disc.x + up * disc.y - moon * sqrt(max(1.0 - dot(disc, disc), 0.0));
	float lit = smoothstep(-0.05, 0.1, dot(normal, sun));
	float seas = mix(0.55, 1.0, smoothstep(0.35, 0.65, texture(maria, vec3(disc * 0.35 + 0.5, 0.5)).r));
	float edge = 1.0 - smoothstep(1.0 - fwidth(r) * 1.5, 1.0, r);
	return moon_disc_light * lit * seas * edge * atmo_transmittance(altitude, view.y, turbidity);
}

// Stars: one per cell at most, with a random place, brightness and colour; they twinkle near the horizon.
vec3 star_field(vec3 view, float altitude, float turbidity, float time) {
	vec3 celestial = transpose(star_rotation) * view;
	vec3 p = celestial * STAR_CELLS;
	vec3 cell = floor(p);
	vec3 h = night_hash3(cell);
	if (h.x > STAR_SHARE) {
		return vec3(0.0);
	}
	vec3 centre = cell + 0.25 + 0.5 * night_hash3(cell + 17.0);
	float d = length(p - centre);
	float glow = exp(-d * d / (STAR_SIZE * STAR_SIZE));
	float brightness = pow(h.y, STAR_BRIGHTNESS_SPREAD) * 6.0 + 0.08 * h.z;
	vec3 color = mix(vec3(1.0, 0.75, 0.55), vec3(0.7, 0.82, 1.0), h.z);
	float twinkle = 1.0 - 0.5 * (1.0 - view.y) * (0.5 + 0.5 * sin(time * (3.0 + 5.0 * h.z) + h.y * 40.0));
	return color * glow * brightness * twinkle * STAR_RADIANCE * atmo_transmittance(altitude, view.y, turbidity);
}
