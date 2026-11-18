// Clear air over a round earth: Rayleigh scattering, haze (Mie) and ozone, single scattering plus an
// even share for the light scattered more than once. A per-pixel copy of AtmosphereModel
// (atmosphere_model.gd): keep the constants and the maths the same (atmosphere_test.gd compares them).
// Units: metres.

const float EARTH_RADIUS = 6360000.0;
const float ATMOSPHERE_RADIUS = 6460000.0;
const vec3 RAYLEIGH = vec3(5.802e-6, 13.558e-6, 33.1e-6);
const float RAYLEIGH_HEIGHT = 8000.0;
const float MIE_SCATTERING = 3.996e-6;
const float MIE_EXTINCTION = 4.44e-6;
const float MIE_HEIGHT = 1200.0;
const float MIE_ANISOTROPY = 0.8;
const vec3 OZONE = vec3(0.650e-6, 1.881e-6, 0.085e-6) * 1.875;
const float MULTIPLE_SCATTERING = 1.5;
const float EARTH_SHADOW_SOFTNESS = 1000.0;

// How much of a light's disc the earth leaves uncovered from `altitude`, looking at `cos_zenith`.
float atmo_visibility(float altitude, float cos_zenith) {
	if (cos_zenith >= 0.0) {
		return 1.0;
	}
	float tangent = (EARTH_RADIUS + altitude) * sqrt(max(1.0 - cos_zenith * cos_zenith, 0.0));
	return smoothstep(-EARTH_SHADOW_SOFTNESS, EARTH_SHADOW_SOFTNESS, tangent - EARTH_RADIUS);
}

// Air along a ray from `altitude` to space in metres of sea-level air: the Chapman function (Schüler).
float atmo_column(float altitude, float cos_zenith, float scale_height) {
	float x = (EARTH_RADIUS + altitude) / scale_height;
	float h = altitude / scale_height;
	float c = sqrt(0.5 * PI * x);
	if (cos_zenith >= 0.0) {
		return scale_height * c / (c * cos_zenith + 1.0) * exp(-h);
	}
	float x0 = max(sqrt(max(1.0 - cos_zenith * cos_zenith, 0.0)) * x, EARTH_RADIUS / scale_height);
	float c0 = sqrt(0.5 * PI * x0);
	return scale_height * (2.0 * c0 * exp(EARTH_RADIUS / scale_height - x0) - c / (1.0 - c * cos_zenith) * exp(-h));
}

// Share of light (per colour) from a body at `cos_zenith` that reaches `altitude`.
vec3 atmo_transmittance(float altitude, float cos_zenith, float turbidity) {
	float visible = atmo_visibility(altitude, cos_zenith);
	if (visible <= 0.0) {
		return vec3(0.0);
	}
	float rayleigh_column = atmo_column(altitude, cos_zenith, RAYLEIGH_HEIGHT);
	float mie_column = atmo_column(altitude, cos_zenith, MIE_HEIGHT);
	return exp(-((RAYLEIGH + OZONE) * rayleigh_column + MIE_EXTINCTION * turbidity * mie_column)) * visible;
}

float atmo_rayleigh_phase(float mu) {
	return 3.0 / (16.0 * PI) * (1.0 + mu * mu);
}

float atmo_mie_phase(float mu) {
	float g = MIE_ANISOTROPY;
	float g2 = g * g;
	return 3.0 / (8.0 * PI) * (1.0 - g2) * (1.0 + mu * mu) / ((2.0 + g2) * pow(1.0 + g2 - 2.0 * g * mu, 1.5));
}

float atmo_ray_sphere_far(vec3 origin, vec3 direction, float radius) {
	float b = dot(origin, direction);
	float c = dot(origin, origin) - radius * radius;
	return -b + sqrt(max(b * b - c, 0.0));
}

// Light scattered towards the eye by the air along `view`, from one light along `light` with
// irradiance `irradiance` above the atmosphere, given the rayleigh and mie sums of the march.
vec3 atmo_scattered(vec3 view, vec3 light, vec3 irradiance, vec3 rayleigh_sum, vec3 mie_sum, float turbidity) {
	float mu = dot(view, light);
	vec3 rayleigh_light = RAYLEIGH * rayleigh_sum;
	vec3 mie_light = mie_sum * MIE_SCATTERING * turbidity;
	vec3 single = rayleigh_light * atmo_rayleigh_phase(mu) + mie_light * atmo_mie_phase(mu);
	vec3 multiple = (rayleigh_light + mie_light) * MULTIPLE_SCATTERING / (4.0 * PI);
	return (single + multiple) * irradiance;
}

// Radiance of the clear sky along `view` (looking along the horizon below it), lit by the sun and,
// when `moon_light` is not black, the moon. `steps` samples, crowded near the observer.
vec3 atmo_radiance(vec3 view, float altitude, vec3 sun, vec3 sun_light, vec3 moon, vec3 moon_light,
		float turbidity, int steps) {
	vec3 d = normalize(vec3(view.x, max(view.y, 0.0), view.z));
	vec3 origin = vec3(0.0, EARTH_RADIUS + altitude, 0.0);
	float len = atmo_ray_sphere_far(origin, d, ATMOSPHERE_RADIUS);
	bool moonlit = max(moon_light.r, max(moon_light.g, moon_light.b)) > 0.0;
	float rayleigh_view = 0.0;
	float mie_view = 0.0;
	vec3 sun_rayleigh = vec3(0.0);
	vec3 sun_mie = vec3(0.0);
	vec3 moon_rayleigh = vec3(0.0);
	vec3 moon_mie = vec3(0.0);
	float previous = 0.0;
	for (int i = 0; i < steps; i++) {
		float f = (float(i) + 1.0) / float(steps);
		float t = len * f * f;
		float ds = t - previous;
		vec3 p = origin + d * (previous + 0.5 * ds);
		previous = t;
		float r = length(p);
		float height = r - EARTH_RADIUS;
		float rayleigh_density = exp(-height / RAYLEIGH_HEIGHT);
		float mie_density = exp(-height / MIE_HEIGHT);
		float rayleigh_here = rayleigh_view + 0.5 * rayleigh_density * ds;
		float mie_here = mie_view + 0.5 * mie_density * ds;
		float cos_sun = dot(p, sun) / r;
		float sun_visible = atmo_visibility(height, cos_sun);
		if (sun_visible > 0.0) {
			vec3 through = exp(-((RAYLEIGH + OZONE) * (rayleigh_here + atmo_column(height, cos_sun, RAYLEIGH_HEIGHT))
					+ MIE_EXTINCTION * turbidity * (mie_here + atmo_column(height, cos_sun, MIE_HEIGHT)))) * sun_visible;
			sun_rayleigh += through * rayleigh_density * ds;
			sun_mie += through * mie_density * ds;
		}
		if (moonlit) {
			float cos_moon = dot(p, moon) / r;
			float moon_visible = atmo_visibility(height, cos_moon);
			if (moon_visible > 0.0) {
				vec3 through = exp(-((RAYLEIGH + OZONE) * (rayleigh_here + atmo_column(height, cos_moon, RAYLEIGH_HEIGHT))
						+ MIE_EXTINCTION * turbidity * (mie_here + atmo_column(height, cos_moon, MIE_HEIGHT)))) * moon_visible;
				moon_rayleigh += through * rayleigh_density * ds;
				moon_mie += through * mie_density * ds;
			}
		}
		rayleigh_view += rayleigh_density * ds;
		mie_view += mie_density * ds;
	}
	vec3 color = atmo_scattered(d, sun, sun_light, sun_rayleigh, sun_mie, turbidity);
	if (moonlit) {
		color += atmo_scattered(d, moon, moon_light, moon_rayleigh, moon_mie, turbidity);
	}
	return color;
}
