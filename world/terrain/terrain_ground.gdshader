shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Ground material: grass soil inland, dry sand on the beach, dark wet sand at the waterline.
// With an Ocean in the scene the wet sand follows the waves (swash.gdshaderinc): damp up to the run-up
// of the highest waves (ShoreRunup), and a glossy film the backwash leaves behind each wave. The water
// running up the sand is the ocean surface itself.

uniform vec3 soil_color : source_color = vec3(0.09, 0.14, 0.04);
uniform vec3 sand_color : source_color = vec3(0.76, 0.66, 0.48);
uniform vec3 wet_sand_color : source_color = vec3(0.38, 0.31, 0.22);
uniform float sea_level = 0.0;
uniform float beach_top = 0.9;
uniform float blend_width = 0.35;
uniform float wet_band = 0.35;
// Glossy film of water the backwash leaves on the sand: roughness, and how much darker the sand gets.
const float FILM_EDGE = 0.03;
const float FILM_ROUGHNESS = 0.06;
const float FILM_DARKENING = 0.85;

#include "res://world/water/swash.gdshaderinc"

varying vec3 v_world;

#include "res://world/water/reflection_clip.gdshaderinc"

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	water_reflection_clip(v_world);
	float h = v_world.y - sea_level;
	float edge_jitter = (vnoise(v_world.xz * 0.6) - 0.5) * blend_width;
	float sand = 1.0 - smoothstep(beach_top - blend_width, beach_top, h + edge_jitter);
	float wet = 1.0 - smoothstep(0.0, wet_band, h);
	float grain = vnoise(v_world.xz * 9.0) * 0.12 + vnoise(v_world.xz * 2.3) * 0.08;

	// Waves keep the sand damp up to the highest swash, and each backwash leaves a glossy film between
	// where the water is now and where this wave reached.
	float runup = max(water_swash_runup, 0.0);
	if (runup > 0.0) {
		wet = max(wet, 1.0 - smoothstep(runup * 0.7, runup, h - edge_jitter * 0.3));
	}
	vec2 swash = water_swash(v_world.xz, water_wave_time);
	float film = runup > 0.0 ? (1.0 - smoothstep(swash.x, swash.y + FILM_EDGE, h)) * sand : 0.0;

	vec3 beach = mix(sand_color, wet_sand_color, wet) * (0.9 + grain);
	vec3 ground = mix(soil_color, beach, sand) * mix(1.0, FILM_DARKENING, film);
	ALBEDO = ground;
	ROUGHNESS = mix(mix(1.0, mix(0.9, 0.35, wet), sand), FILM_ROUGHNESS, film);
	SPECULAR = mix(mix(0.3, 0.5, wet * sand), 0.5, film);
}
