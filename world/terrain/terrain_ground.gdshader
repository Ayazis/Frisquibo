shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Ground material: grass soil inland, dry sand on the beach, dark wet sand at the waterline.
// With an Ocean in the scene the wet sand follows the waves (swash.gdshaderinc): damp up to the run-up
// of the highest waves (ShoreRunup), and a glossy film the backwash leaves behind each wave. The water
// running up the sand is the ocean surface itself. As each wave turns back it leaves foam on the sand:
// a lacy line where it stopped and a sheet of bubbles that drains away behind it (foam_lace).

uniform vec3 soil_color : source_color = vec3(0.09, 0.14, 0.04);
uniform vec3 sand_color : source_color = vec3(0.76, 0.66, 0.48);
uniform vec3 wet_sand_color : source_color = vec3(0.38, 0.31, 0.22);
uniform float sea_level = 0.0;
uniform float beach_top = 0.9;
uniform float blend_width = 0.35;
uniform float wet_band = 0.35;
uniform vec3 foam_color : source_color = vec3(0.86, 0.9, 0.9);
// Glossy film of water the backwash leaves on the sand: roughness, and how much darker the sand gets.
const float FILM_EDGE = 0.03;
const float FILM_ROUGHNESS = 0.06;
const float FILM_DARKENING = 0.85;
// Foam left by the backwash: the line where the wave stopped is this many metres high on the slope...
const float RESIDUE_MARK_WIDTH = 0.03;
// ...and the bubbles below it age this much faster, starting part open, and cover less.
const float RESIDUE_SHEET_AGEING = 1.6;
const float RESIDUE_SHEET_START = 0.35;
const float RESIDUE_SHEET_COVER = 0.6;
// Foam on sand: rough, a little shiny where it is wet, never quite opaque.
const float RESIDUE_OPACITY = 0.9;
const float RESIDUE_ROUGHNESS = 0.6;
// Metres per tile of the broad noise that makes the lace wear unevenly.
const float RESIDUE_BREAKUP_TILE = 7.0;

#include "res://world/water/swash.gdshaderinc"
#include "res://world/water/foam_lace.gdshaderinc"

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
	vec4 swash = water_swash_state(v_world.xz, water_wave_time);
	float film = runup > 0.0 ? (1.0 - smoothstep(swash.x, swash.y + FILM_EDGE, h)) * sand : 0.0;

	// Foam the backwash leaves behind, from the moment the wave turns until the next one arrives.
	float residue = 0.0;
	if (runup > 0.0 && swash.z >= SWASH_UPRUSH_SHARE && h > swash.x) {
		float age = (swash.z - SWASH_UPRUSH_SHARE) / (1.0 - SWASH_UPRUSH_SHARE);
		float breakup = vnoise(v_world.xz / RESIDUE_BREAKUP_TILE);
		float mark = 1.0 - smoothstep(0.0, RESIDUE_MARK_WIDTH, abs(h - swash.y + 0.5 * RESIDUE_MARK_WIDTH));
		float sheet = 1.0 - smoothstep(swash.y - RESIDUE_MARK_WIDTH, swash.y, h);
		float sheet_age = min(age * RESIDUE_SHEET_AGEING + RESIDUE_SHEET_START, 1.0);
		residue = max(water_lace(v_world.xz, age, swash.w, breakup) * mark,
				water_lace(v_world.xz, sheet_age, swash.w + 0.5, breakup) * sheet * RESIDUE_SHEET_COVER) * sand;
	}

	vec3 beach = mix(sand_color, wet_sand_color, wet) * (0.9 + grain);
	vec3 ground = mix(soil_color, beach, sand) * mix(1.0, FILM_DARKENING, film);
	ALBEDO = mix(ground, foam_color, residue * RESIDUE_OPACITY);
	ROUGHNESS = mix(mix(mix(1.0, mix(0.9, 0.35, wet), sand), FILM_ROUGHNESS, film), RESIDUE_ROUGHNESS, residue);
	SPECULAR = mix(mix(0.3, 0.5, wet * sand), 0.5, film);
}
