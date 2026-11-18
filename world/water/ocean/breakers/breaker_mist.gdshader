shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
// Mist over plunging breakers (BreakerMist): one faint, wide, rising sheet along the line where the lips
// land, built by the CPU each frame. Its strength comes per vertex in COLOR.a (how hard that part of the
// crest is plunging), UV.y runs from the water (0) to the sheet's top (1). A broad, slow pattern breaks
// it up; nothing in it is small or round.

uniform vec3 mist_color : source_color = vec3(0.92, 0.95, 0.97);
uniform float opacity = 0.12;
uniform sampler2D pattern : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float pattern_size = 6.0;                      // metres per tile of the pattern
uniform float rise_speed = 0.6;                        // m/s the pattern drifts up
uniform vec2 drift = vec2(0.0);                        // m/s the mist drifts with the wind
uniform float through_light = 1.5;                     // brightness with the sun behind the mist

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 q = vec2(dot(v_world.xz, vec2(0.7071)), v_world.y - TIME * rise_speed) / pattern_size
			- vec2(dot(drift, vec2(0.7071)), 0.0) * TIME / pattern_size;
	float breakup = texture(pattern, q).r * 0.6 + texture(pattern, q * 0.37 + 0.21).r * 0.4;
	float height = UV.y;
	float body = smoothstep(0.0, 0.15, height) * (1.0 - smoothstep(0.35, 1.0, height));
	ALPHA = opacity * COLOR.a * body * mix(0.5, 1.0, breakup);
	ALBEDO = mist_color;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	DIFFUSE_LIGHT += (0.6 + 0.4 * clamp(dot(NORMAL, LIGHT), 0.0, 1.0)) * ATTENUATION * LIGHT_COLOR / PI;
	// Forward scattering: mist glows with the sun behind it.
	float through = pow(clamp(dot(LIGHT, -VIEW), 0.0, 1.0), 4.0);
	DIFFUSE_LIGHT += through * through_light * ATTENUATION * LIGHT_COLOR / PI;
}
