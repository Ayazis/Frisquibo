// Volumetric cumulus in a layer over the round earth, ray-marched with a short march towards the light
// per sample, plus a thin sheet of cirrus far above. Needs sky_atmosphere.gdshaderinc first.

uniform sampler3D cloud_shape_noise : filter_linear_mipmap, repeat_enable;
uniform sampler3D cloud_detail_noise : filter_linear_mipmap, repeat_enable;
uniform float cloud_coverage = 0.3;
uniform float cloud_density = 1.0;
uniform float cloud_bottom = 1500.0;
uniform float cloud_top = 3500.0;
uniform vec2 cloud_offset = vec2(0.0);           // metres the wind has carried the clouds
uniform vec3 cloud_light_direction = vec3(0.0, 1.0, 0.0);
uniform vec3 cloud_light = vec3(1.0);            // irradiance of the sun (or moon) at cloud height
uniform vec3 cloud_ambient = vec3(0.05);         // mean radiance of the sky around the clouds
uniform float cloud_flash = 0.0;                 // lightning lighting the clouds from inside
uniform float cirrus_amount = 0.2;
uniform vec2 cirrus_offset = vec2(0.0);
uniform vec3 cirrus_light = vec3(1.0);
uniform int cloud_steps = 48;
uniform int radiance_cloud_steps = 16;
uniform int cloud_light_steps = 5;
uniform bool cloud_detail = true;

// Sizes of the noise patterns: big shapes, the coverage map, and the eroded edges (metres per repeat).
const float SHAPE_SIZE = 9000.0;
const float SHAPE_HEIGHT_SIZE = 4500.0;
const float COVERAGE_SIZE = 45000.0;
const float DETAIL_SIZE = 1400.0;
// How much the coverage map varies the cover around its mean, and how deep the detail eats into edges.
const float COVERAGE_VARIATION = 0.6;
const float DETAIL_EROSION = 0.45;
// Cloud material at density 1: extinction per metre (cumulus: 0.02 to 0.1).
const float CLOUD_EXTINCTION = 0.025;
// The march stops this far into the layer and ignores clouds farther away than CLOUD_DISTANCE.
const float MAX_MARCH = 30000.0;
const float CLOUD_DISTANCE = 90000.0;
// Distant clouds sink into the haze: half their contrast is gone at this distance on a clean day.
const float CLOUD_HAZE_DISTANCE = 40000.0;
// Light march towards the sun: its length, the forward and backward lobes of the scattering and the
// powder darkening of thin edges seen away from the light.
const float LIGHT_MARCH = 1600.0;
const float FORWARD_LOBE = 0.65;
const float BACKWARD_LOBE = -0.2;
const float BACKWARD_SHARE = 0.25;
// A thick cloud scatters light many times and sends back far more than one scattering would: its sunlit
// side is about as bright as a white wall. Scales the octaves below up to that.
const float CLOUD_SCATTER_GAIN = 2.5;
const float POWDER_DEPTH = 120.0;
const float POWDER_STRENGTH = 0.7;
// Cloud bottoms see only the ground and the sea, not the sky: their ambient light is this much darker.
const float AMBIENT_BOTTOM = 0.35;
const vec3 FLASH_COLOR = vec3(0.75, 0.8, 1.0);
// Cirrus: height, size of its streaks along and across the wind, and opacity.
const float CIRRUS_ALTITUDE = 8000.0;
const vec2 CIRRUS_SIZE = vec2(60000.0, 14000.0);
const float CIRRUS_DETAIL_SIZE = 5000.0;
const float CIRRUS_OPACITY = 0.6;

float cloud_hg(float mu, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (4.0 * PI * pow(1.0 + g2 - 2.0 * g * mu, 1.5));
}

// Two-lobed phase: bright silver linings towards the light, some light back towards it. `eccentricity`
// (1 for single scattering) flattens both lobes for light scattered several times.
float cloud_phase(float mu, float eccentricity) {
	return mix(cloud_hg(mu, FORWARD_LOBE * eccentricity), cloud_hg(mu, BACKWARD_LOBE * eccentricity), BACKWARD_SHARE);
}

// Height within the cumulus layer: 0 at its base, 1 at its top.
float cloud_height_fraction(vec3 planet_position) {
	return (length(planet_position) - EARTH_RADIUS - cloud_bottom) / max(cloud_top - cloud_bottom, 1.0);
}

// Cloud density at a point (planet coordinates: y up from the earth's centre, xz over the ground).
float cloud_density_at(vec3 p, float height, bool detailed) {
	if (height <= 0.0 || height >= 1.0) {
		return 0.0;
	}
	vec2 ground = p.xz + cloud_offset;
	float local_cover = texture(cloud_shape_noise, vec3(ground / COVERAGE_SIZE, 0.37)).r;
	float cover = clamp(cloud_coverage + (local_cover - 0.5) * COVERAGE_VARIATION * (1.0 - cloud_coverage), 0.0, 1.0);
	// Rounded bases; tops rise higher where the cover is heavy.
	float profile = smoothstep(0.0, 0.12, height) * (1.0 - smoothstep(0.3 + 0.55 * cover, 1.0, height));
	float altitude = height * (cloud_top - cloud_bottom);
	float shape = texture(cloud_shape_noise, vec3(ground.x / SHAPE_SIZE, altitude / SHAPE_HEIGHT_SIZE, ground.y / SHAPE_SIZE)).r;
	float d = clamp((shape * profile - (1.0 - cover)) / max(cover, 0.05), 0.0, 1.0);
	if (d <= 0.0) {
		return 0.0;
	}
	if (detailed) {
		// Billows eat into the edges, more at the base than at the cauliflower tops.
		vec3 q = vec3(ground.x, altitude, ground.y) / DETAIL_SIZE;
		float erosion = (1.0 - texture(cloud_detail_noise, q).r) * DETAIL_EROSION * mix(1.0, 0.6, height);
		d = clamp((d - erosion) / max(1.0 - erosion, 0.05), 0.0, 1.0);
	}
	return d * cloud_density;
}

// Optical depth from `p` towards the light through the layer, in `steps` growing steps.
float cloud_light_depth(vec3 p, int steps) {
	float depth = 0.0;
	float previous = 0.0;
	for (int j = 0; j < steps; j++) {
		float f = (float(j) + 1.0) / float(steps);
		float t = LIGHT_MARCH * f * f;
		vec3 s = p + cloud_light_direction * (0.5 * (previous + t));
		float h = cloud_height_fraction(s);
		if (h >= 1.0) {
			break;
		}
		depth += cloud_density_at(s, h, false) * (t - previous);
		previous = t;
	}
	return depth * CLOUD_EXTINCTION;
}

// Light the cloud at a sample scatters towards the eye: the direct light, with a cheap stand-in for
// multiple scattering (three octaves of ever weaker extinction and wider phase, Wrenninge 2013), the
// ambient sky and lightning.
vec3 cloud_in_scatter(float light_depth, float sigma, float mu, float height) {
	float direct = 0.0;
	float weight = 1.0;
	float spread = 1.0;
	for (int k = 0; k < 3; k++) {
		direct += weight * cloud_phase(mu, spread) * exp(-light_depth * spread);
		weight *= 0.5;
		spread *= 0.5;
	}
	direct *= CLOUD_SCATTER_GAIN;
	float powder = mix(1.0, 1.0 - exp(-sigma * POWDER_DEPTH), POWDER_STRENGTH * (0.5 - 0.5 * mu));
	vec3 ambient = cloud_ambient * mix(AMBIENT_BOTTOM, 1.0, height);
	return cloud_light * direct * powder + ambient + FLASH_COLOR * cloud_flash * (1.0 - height * 0.5);
}

// The cumulus seen along `view` in front of `sky`: rgb is the light they send, a the sky that shows
// through. `jitter` (0..1) staggers the first sample per pixel.
vec4 cloud_layer(vec3 view, float altitude, vec3 sky, int steps, float jitter, float turbidity) {
	if (steps <= 0 || cloud_coverage <= 0.0 || view.y <= 0.0) {
		return vec4(0.0, 0.0, 0.0, 1.0);
	}
	vec3 origin = vec3(0.0, EARTH_RADIUS + altitude, 0.0);
	float enter = atmo_ray_sphere_far(origin, view, EARTH_RADIUS + cloud_bottom);
	if (enter > CLOUD_DISTANCE) {
		return vec4(0.0, 0.0, 0.0, 1.0);
	}
	float leave = min(atmo_ray_sphere_far(origin, view, EARTH_RADIUS + cloud_top), enter + MAX_MARCH);
	float ds = (leave - enter) / float(steps);
	float mu = dot(view, cloud_light_direction);
	float transmittance = 1.0;
	vec3 light = vec3(0.0);
	float distance_sum = 0.0;
	float weight_sum = 0.0;
	for (int i = 0; i < steps; i++) {
		float t = enter + (float(i) + jitter) * ds;
		vec3 p = origin + view * t;
		float h = cloud_height_fraction(p);
		float density = cloud_density_at(p, h, cloud_detail);
		if (density > 0.0) {
			float sigma = density * CLOUD_EXTINCTION;
			float absorbed = 1.0 - exp(-sigma * ds);
			vec3 scatter = cloud_in_scatter(cloud_light_depth(p, cloud_light_steps), sigma, mu, h);
			light += transmittance * scatter * absorbed;
			distance_sum += transmittance * absorbed * t;
			weight_sum += transmittance * absorbed;
			transmittance *= 1.0 - absorbed;
			if (transmittance < 0.01) {
				break;
			}
		}
	}
	// Haze between the eye and the cloud: distant clouds fade into the sky behind them.
	float mean_distance = weight_sum > 0.0 ? distance_sum / weight_sum : enter;
	float haze = 1.0 - exp(-mean_distance * turbidity / CLOUD_HAZE_DISTANCE);
	haze = max(haze, smoothstep(0.6 * CLOUD_DISTANCE, CLOUD_DISTANCE, enter));
	light = mix(light, sky * (1.0 - transmittance), haze);
	return vec4(light, transmittance);
}

// Thin cirrus streaks along the wind, far above the cumulus.
vec4 cirrus_layer(vec3 view, float altitude, vec3 sky, float turbidity) {
	if (cirrus_amount <= 0.0 || view.y <= 0.0) {
		return vec4(0.0, 0.0, 0.0, 1.0);
	}
	vec3 origin = vec3(0.0, EARTH_RADIUS + altitude, 0.0);
	float t = atmo_ray_sphere_far(origin, view, EARTH_RADIUS + CIRRUS_ALTITUDE);
	vec2 ground = (origin + view * t).xz + cirrus_offset;
	float streaks = texture(cloud_shape_noise, vec3(ground / CIRRUS_SIZE, 0.71)).r;
	float detail = texture(cloud_detail_noise, vec3(ground / CIRRUS_DETAIL_SIZE, 0.29)).r;
	float cover = smoothstep(1.0 - cirrus_amount * 0.6, 1.0, streaks * mix(0.75, 1.15, detail)) * CIRRUS_OPACITY;
	float mu = dot(view, cloud_light_direction);
	vec3 lit = cirrus_light * cloud_hg(mu, FORWARD_LOBE) * 0.8 + cloud_ambient;
	float haze = 1.0 - exp(-t * turbidity / (2.0 * CLOUD_HAZE_DISTANCE));
	return vec4(mix(lit, sky, haze) * cover, 1.0 - cover);
}
