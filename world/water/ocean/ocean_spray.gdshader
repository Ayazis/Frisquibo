shader_type particles;
// Spray torn off breaking crests by strong wind (OceanSpray). Each particle looks for a crest that is
// breaking now (the simulation's short-lived white water) at a few random points near the camera when
// it (re)starts; it only lives if it finds one and the wind is strong enough. Two kinds:
//  - droplets leave the crest with part of the wind's speed and some lift, are dragged towards the
//    wind speed and fall back, and die when they reach the sea;
//  - spindrift: wisps of fine mist that the wind tears off the crest and carries downwind, growing and
//    thinning out as they go. From a distance these make the white veils streaming off storm crests.

const int MAX_CASCADES = 4;
const float GRAVITY = 9.81;
// Random points a particle tries before giving up: spray only comes from the few crests breaking now.
const int LAUNCH_TRIES = 8;

uniform sampler2DArray displacement_maps : filter_linear, repeat_enable;
uniform sampler2DArray moment_maps : filter_linear, repeat_enable;
uniform float tile_lengths[4];
uniform int cascade_count = 4;
uniform float sea_level = 0.0;
uniform vec2 wind = vec2(8.0, 3.0);                    // direction * m/s
uniform vec2 area_centre = vec2(0.0);
uniform float area_size = 200.0;                       // metres per side, around the camera
// Spray starts at spray_wind_start (about Beaufort 6) and is at its fullest from spray_wind_full.
uniform float spray_wind_start = 11.0;
uniform float spray_wind_full = 25.0;
// Multiplies the chance that a breaking crest throws spray (OceanSpectrum.spray_amount).
uniform float spray_amount = 1.0;
uniform vec2 breaking_range = vec2(0.3, 0.9);          // white water from "just breaking" to "fully broken"
uniform float foam_falloff = 0.6;                      // as foam_cascade_falloff in ocean.gdshader
uniform vec2 launch_wind_share = vec2(0.3, 0.7);       // share of the wind speed a droplet leaves with
uniform vec2 launch_lift = vec2(0.8, 3.0);             // upward speed at launch (m/s) in spray_wind_full
uniform float air_drag = 1.5;                          // 1/s: how fast droplets take on the wind's speed
uniform vec2 droplet_size = vec2(0.04, 0.16);          // metres
// Spindrift: share of the particles, size at launch (metres), how many times it grows over its life,
// how many times wider than tall a wisp is (the wind smears it out), its opacity, how much of gravity
// the fine mist still feels, and how fast it takes on the wind's speed (1/s).
uniform float mist_share = 0.6;
uniform vec2 mist_size = vec2(0.4, 1.6);
uniform float mist_growth = 4.0;
uniform float mist_stretch = 2.5;
uniform float mist_opacity = 0.2;
uniform float mist_fall = 0.1;
uniform float mist_drag = 3.0;

uint hash(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return x;
}

float rand(inout uint state) {
	state = hash(state);
	return float(state) / 4294967295.0;
}

// Displacement (xyz) and how much it is breaking now (w) at rest position p.
vec4 crest_at(vec2 p) {
	vec3 d = vec3(0.0);
	float breaking = 0.0;
	float weight = 1.0;
	for (int i = 0; i < MAX_CASCADES; i++) {
		if (i >= cascade_count) {
			break;
		}
		vec3 uv = vec3(p / tile_lengths[i], float(i));
		d += textureLod(displacement_maps, uv, 0.0).xyz;
		breaking += textureLod(moment_maps, uv, 0.0).w * weight;
		weight *= foam_falloff;
	}
	return vec4(d, breaking);
}

void start() {
	uint state = hash(NUMBER ^ hash(RANDOM_SEED));
	float speed = length(wind);
	float windy = smoothstep(spray_wind_start, spray_wind_full, speed);
	vec2 p = area_centre;
	vec4 crest = vec4(0.0);
	bool found = false;
	for (int t = 0; t < LAUNCH_TRIES; t++) {
		p = area_centre + (vec2(rand(state), rand(state)) - 0.5) * area_size;
		crest = crest_at(p);
		float chance = clamp(windy * smoothstep(breaking_range.x, breaking_range.y, crest.w) * spray_amount, 0.0, 1.0);
		if (rand(state) < chance) {
			found = true;
			break;
		}
	}
	ACTIVE = found;
	vec2 dir = speed > 0.0 ? wind / speed : vec2(1.0, 0.0);
	bool mist = rand(state) < mist_share;
	float size = mist ? mix(mist_size.x, mist_size.y, rand(state)) : mix(droplet_size.x, droplet_size.y, rand(state));
	TRANSFORM = mat4(vec4(size, 0.0, 0.0, 0.0), vec4(0.0, size, 0.0, 0.0), vec4(0.0, 0.0, size, 0.0),
			vec4(p.x + crest.x, sea_level + crest.y, p.y + crest.z, 1.0));
	float share = mix(launch_wind_share.x, launch_wind_share.y, rand(state));
	// Stronger wind throws spray higher.
	float lift = mix(launch_lift.x, launch_lift.y, rand(state)) * max(speed / spray_wind_full, 1.0);
	VELOCITY = vec3(dir.x, 0.0, dir.y) * speed * share + vec3(0.0, lift, 0.0);
	COLOR = vec4(1.0, 1.0, 1.0, mist ? 0.0 : 1.0);
	// y: age, z: size at launch, w: 1 for spindrift.
	CUSTOM = vec4(0.0, 0.0, size, mist ? 1.0 : 0.0);
}

void process() {
	CUSTOM.y += DELTA;
	bool mist = CUSTOM.w > 0.5;
	vec3 air = vec3(wind.x, 0.0, wind.y);
	VELOCITY += (air - VELOCITY) * min((mist ? mist_drag : air_drag) * DELTA, 1.0);
	VELOCITY.y -= GRAVITY * (mist ? mist_fall : 1.0) * DELTA;
	// The engine moves the particle by VELOCITY after process().
	float age = CUSTOM.y / max(LIFETIME, 0.001);
	if (mist) {
		float size = CUSTOM.z * (1.0 + mist_growth * age);
		// Billboards keep the scale of each axis: x is the wisp's width on screen.
		TRANSFORM[0].xyz = vec3(size * mist_stretch, 0.0, 0.0);
		TRANSFORM[1].xyz = vec3(0.0, size, 0.0);
		TRANSFORM[2].xyz = vec3(0.0, 0.0, size);
		COLOR.a = mist_opacity * smoothstep(0.0, 0.08, age) * (1.0 - smoothstep(0.3, 1.0, age));
	} else {
		COLOR.a = 1.0 - smoothstep(0.6, 1.0, age);
	}
	if (TRANSFORM[3].y < sea_level - 0.5 && VELOCITY.y < 0.0) {
		ACTIVE = false;
	}
}
