shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled;
// One droplet of breaker spray (BreakerSpray), drawn as a thin streak along its motion: what the eye
// sees of a drop flying a few metres a second during a frame. Mostly clear, bright where the sun comes
// through it from behind. Never a soft round dot, which is what makes spray read as cotton wool.

uniform vec3 droplet_color : source_color = vec3(0.86, 0.93, 0.95);
uniform float opacity = 0.55;
// Seconds of motion a streak shows (an eye's or a camera's exposure).
uniform float exposure = 0.03;
uniform float through_light = 2.0;                     // brightness with the sun behind the drop

void vertex() {
	vec3 centre = MODEL_MATRIX[3].xyz;
	float size = length(MODEL_MATRIX[0].xyz);
	vec3 centre_view = (VIEW_MATRIX * vec4(centre, 1.0)).xyz;
	vec3 motion_view = (VIEW_MATRIX * vec4(INSTANCE_CUSTOM.xyz, 0.0)).xyz;
	vec2 on_screen = motion_view.xy;
	vec3 along = dot(on_screen, on_screen) > 1e-8 ? vec3(normalize(on_screen), 0.0) : vec3(1.0, 0.0, 0.0);
	vec3 across = vec3(-along.y, along.x, 0.0);
	float length_m = size + length(on_screen) * exposure;
	VERTEX = centre_view + along * VERTEX.x * length_m + across * VERTEX.y * size;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	float across = abs(UV.y - 0.5) * 2.0;
	float along = abs(UV.x - 0.5) * 2.0;
	ALPHA = (1.0 - smoothstep(0.4, 1.0, across)) * (1.0 - smoothstep(0.5, 1.0, along)) * opacity * COLOR.a;
	ALBEDO = droplet_color;
	ROUGHNESS = 0.15;
	SPECULAR = 0.5;
}

void light() {
	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * 0.3 * ATTENUATION * LIGHT_COLOR / PI;
	// Light refracted through the drop towards the eye.
	float through = pow(clamp(dot(LIGHT, -VIEW), 0.0, 1.0), 6.0);
	SPECULAR_LIGHT += through * through_light * ATTENUATION * LIGHT_COLOR;
}
