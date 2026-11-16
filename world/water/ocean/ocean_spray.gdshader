shader_type particles;
// Spray torn off breaking crests by strong wind (OceanSpray). Each particle picks a random point near the
// camera when it (re)starts; it only lives if a whitecap is breaking there now and the wind is strong
// enough. It leaves the crest with part of the wind's speed and some lift, is dragged towards the wind
// speed and falls back, and dies when it reaches the sea.

const int MAX_CASCADES = 4;
const float GRAVITY = 9.81;

uniform sampler2DArray displacement_maps : filter_linear, repeat_enable;
uniform sampler2DArray moment_maps : filter_linear, repeat_enable;
uniform float tile_lengths[4];
uniform int cascade_count = 4;
uniform float sea_level = 0.0;
uniform vec2 wind = vec2(8.0, 3.0);                    // direction * m/s
uniform vec2 area_centre = vec2(0.0);
uniform float area_size = 120.0;                       // metres per side, around the camera
// Spray starts at spray_wind_start (about Beaufort 6) and is at its fullest from spray_wind_full.
uniform float spray_wind_start = 11.0;
uniform float spray_wind_full = 25.0;
uniform float breaking_foam = 0.75;                    // foam this fresh means the crest is breaking now
uniform float foam_falloff = 0.6;                      // as foam_cascade_falloff in ocean.gdshader
uniform vec2 launch_wind_share = vec2(0.3, 0.7);       // share of the wind speed a droplet leaves with
uniform vec2 launch_lift = vec2(0.8, 3.0);             // upward speed at launch (m/s)
uniform float air_drag = 1.5;                          // 1/s: how fast droplets take on the wind's speed
uniform vec2 droplet_size = vec2(0.04, 0.16);          // metres

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

void start() {
	uint state = hash(NUMBER ^ hash(RANDOM_SEED));
	vec2 p = area_centre + (vec2(rand(state), rand(state)) - 0.5) * area_size;
	vec3 d = vec3(0.0);
	float foam = 0.0;
	float weight = 1.0;
	for (int i = 0; i < MAX_CASCADES; i++) {
		if (i >= cascade_count) {
			break;
		}
		vec3 uv = vec3(p / tile_lengths[i], float(i));
		d += textureLod(displacement_maps, uv, 0.0).xyz;
		foam += textureLod(moment_maps, uv, 0.0).z * weight;
		weight *= foam_falloff;
	}
	float speed = length(wind);
	float chance = smoothstep(spray_wind_start, spray_wind_full, speed) * smoothstep(breaking_foam, 1.0, foam);
	ACTIVE = rand(state) < chance;
	vec2 dir = speed > 0.0 ? wind / speed : vec2(1.0, 0.0);
	float size = mix(droplet_size.x, droplet_size.y, rand(state));
	TRANSFORM = mat4(vec4(size, 0.0, 0.0, 0.0), vec4(0.0, size, 0.0, 0.0), vec4(0.0, 0.0, size, 0.0),
			vec4(p.x + d.x, sea_level + d.y, p.y + d.z, 1.0));
	float share = mix(launch_wind_share.x, launch_wind_share.y, rand(state));
	VELOCITY = vec3(dir.x, 0.0, dir.y) * speed * share + vec3(0.0, mix(launch_lift.x, launch_lift.y, rand(state)), 0.0);
	COLOR = vec4(1.0);
	CUSTOM = vec4(0.0);
}

void process() {
	CUSTOM.y += DELTA;
	vec3 air = vec3(wind.x, 0.0, wind.y);
	VELOCITY += (air - VELOCITY) * min(air_drag * DELTA, 1.0);
	VELOCITY.y -= GRAVITY * DELTA;
	// The engine moves the particle by VELOCITY after process().
	float age = CUSTOM.y / max(LIFETIME, 0.001);
	COLOR.a = 1.0 - smoothstep(0.6, 1.0, age);
	if (TRANSFORM[3].y < sea_level - 0.5 && VELOCITY.y < 0.0) {
		ACTIVE = false;
	}
}
