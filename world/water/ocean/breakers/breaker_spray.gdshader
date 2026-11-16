shader_type particles;
// Spray of plunging breakers (BreakerSpray): droplets peeling off the lip tips and thrown up where the
// lips land. The CPU (BreakerEffects) lists the emitters each frame in a small texture: per emitter a
// position and how many droplets per second it sheds (row 0), a velocity and a droplet size (row 1).
// Each particle that (re)starts picks an emitter at random and lives if the emitter is shedding now.

const float GRAVITY = 9.81;

uniform sampler2D emitters : filter_nearest, repeat_disable;
uniform int emitter_count = 0;
// Chance per restart that an emitter with rate 1 sheds this particle.
uniform float rate_scale = 1.0;
uniform float sea_level = 0.0;
// Droplets leave with this share of the emitter's speed, and scatter by this much (m/s) in any direction.
uniform vec2 speed_share = vec2(0.6, 1.25);
uniform float scatter = 1.2;
uniform float air_drag = 0.6;                          // 1/s
uniform vec2 droplet_size = vec2(0.012, 0.035);        // metres
uniform float lifetime = 1.6;

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
	int index = clamp(int(rand(state) * float(emitter_count)), 0, max(emitter_count - 1, 0));
	vec4 at = texelFetch(emitters, ivec2(index, 0), 0);
	vec4 motion = texelFetch(emitters, ivec2(index, 1), 0);
	ACTIVE = emitter_count > 0 && rand(state) < at.w * rate_scale;
	vec3 jitter = vec3(rand(state), rand(state), rand(state)) * 2.0 - 1.0;
	float size = mix(droplet_size.x, droplet_size.y, rand(state)) * motion.w;
	TRANSFORM = mat4(vec4(size, 0.0, 0.0, 0.0), vec4(0.0, size, 0.0, 0.0), vec4(0.0, 0.0, size, 0.0),
			vec4(at.xyz + jitter * size * 4.0, 1.0));
	VELOCITY = motion.xyz * mix(speed_share.x, speed_share.y, rand(state)) + jitter * scatter;
	// The streak shader reads the velocity from CUSTOM.xyz; CUSTOM.w is the age.
	CUSTOM = vec4(VELOCITY, 0.0);
	COLOR = vec4(1.0);
}

void process() {
	CUSTOM.w += DELTA;
	VELOCITY -= VELOCITY * min(air_drag * DELTA, 1.0);
	VELOCITY.y -= GRAVITY * DELTA;
	// The engine moves the particle by VELOCITY after process().
	CUSTOM.xyz = VELOCITY;
	COLOR.a = 1.0 - smoothstep(0.5, 1.0, CUSTOM.w / max(lifetime, 0.001));
	if (TRANSFORM[3].y < sea_level - 0.3 && VELOCITY.y < 0.0) {
		ACTIVE = false;
	}
}
