shader_type sky;
// The sky of the time of day: physically based air (sky_atmosphere), cirrus and volumetric cumulus
// (sky_clouds), the sun's and moon's discs and the stars (sky_night). The Atmosphere node sets every
// uniform each frame from the time of day, the weather and the quality tier.
// The air and clouds are drawn at half resolution; the full-resolution pass adds the sharp discs and
// stars, dimmed by the clouds in front of them. The radiance map (ambient light, reflections) gets the
// air and clouds with fewer samples and no discs: the sun and moon lights stand in for those.
render_mode use_half_res_pass;

#include "res://world/time_of_day/sky_atmosphere.gdshaderinc"
#include "res://world/time_of_day/sky_clouds.gdshaderinc"
#include "res://world/time_of_day/sky_night.gdshaderinc"

uniform vec3 sun_direction = vec3(0.0, 1.0, 0.0);
uniform float sun_irradiance = 1.75;             // above the atmosphere, in light units
uniform vec3 moon_direction = vec3(0.0, -1.0, 0.0);
uniform vec3 moon_sky_light = vec3(0.0);         // the moon's irradiance above the atmosphere, tinted
uniform float turbidity = 1.5;
uniform float observer_altitude = 2.0;
uniform vec3 night_sky = vec3(0.0004, 0.0006, 0.0012); // starlight and airglow
uniform int atmosphere_steps = 16;
uniform int radiance_atmosphere_steps = 8;
// Off where the renderer has no half-resolution sky pass (Compatibility, web): the full pass then
// draws everything itself.
uniform bool use_half_res = true;
uniform float sky_time = 0.0;                    // seconds, for the twinkling of the stars
uniform vec3 sea_albedo = vec3(0.01, 0.03, 0.035);        // linear

// Below the horizon the sky shows the far sea, past the end of the water mesh: it clears of haze this
// fast as the view tips down.
const float SEA_HAZE = 40.0;
const float WATER_F0 = 0.02;

// Interleaved gradient noise: staggers the cloud samples per pixel, so steps show as fine grain, not bands.
float sky_jitter(vec2 frag) {
	return fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715))));
}

vec3 clear_sky(vec3 view, int steps) {
	return atmo_radiance(view, observer_altitude, sun_direction, vec3(sun_irradiance), moon_direction,
			moon_sky_light, turbidity, steps) + night_sky;
}

// The far sea: the sky mirrored at its Fresnel, grey under heavy cloud, over the water's own body.
vec3 far_sea(vec3 view, int steps) {
	float depth = -view.y;
	vec3 reflected = clear_sky(vec3(view.x, depth, view.z), steps);
	reflected = mix(reflected, cloud_ambient, cloud_coverage * cloud_coverage);
	float fresnel = WATER_F0 + (1.0 - WATER_F0) * pow(1.0 - depth, 5.0);
	vec3 lit = cloud_ambient + cloud_light * max(cloud_light_direction.y, 0.0) / PI;
	vec3 sea = reflected * fresnel + sea_albedo * lit * (1.0 - fresnel);
	return mix(sea, reflected, exp(-depth * SEA_HAZE));
}

// Air, cirrus and cumulus along `view`: rgb, and in a the share of the sky beyond (sun, moon, stars)
// that shows through.
vec4 sky_and_clouds(vec3 view, int air_steps, int cloud_march, float jitter) {
	if (view.y < 0.0) {
		return vec4(far_sea(view, air_steps), 0.0);
	}
	vec3 air = clear_sky(view, air_steps);
	vec4 cirrus = cirrus_layer(view, observer_altitude, air, turbidity);
	vec3 color = air * cirrus.a + cirrus.rgb;
	vec4 cumulus = cloud_layer(view, observer_altitude, color, cloud_march, jitter, turbidity);
	return vec4(color * cumulus.a + cumulus.rgb, cirrus.a * cumulus.a);
}

void sky() {
	if (AT_CUBEMAP_PASS) {
		COLOR = sky_and_clouds(EYEDIR, radiance_atmosphere_steps, radiance_cloud_steps, 0.5).rgb;
	} else if (AT_HALF_RES_PASS) {
		vec4 s = sky_and_clouds(EYEDIR, atmosphere_steps, cloud_steps, sky_jitter(FRAGCOORD.xy));
		COLOR = s.rgb;
		ALPHA = s.a;
	} else {
		vec4 s = use_half_res ? HALF_RES_COLOR : sky_and_clouds(EYEDIR, atmosphere_steps, cloud_steps,
				sky_jitter(FRAGCOORD.xy));
		vec3 color = s.rgb;
		if (EYEDIR.y > 0.0 && s.a > 0.0) {
			vec3 beyond = sun_disc(EYEDIR, sun_direction, sun_irradiance, observer_altitude, turbidity);
			beyond += moon_disc(EYEDIR, moon_direction, sun_direction, observer_altitude, turbidity, cloud_shape_noise);
			if (night > 0.0) {
				beyond += star_field(EYEDIR, observer_altitude, turbidity, sky_time) * night;
			}
			color += beyond * s.a;
		}
		COLOR = color;
	}
}
