shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_disabled, shadows_disabled, fog_disabled,
		ambient_light_disabled;
// Keeps water out of a dry space, such as an open hull (WaterMask). Drawn invisibly over the opening
// before the water, it only writes depth: water behind the opening (inside the hull) then fails the
// depth test, while water in front of it (a crest between the camera and the boat) still draws.

// Lets the headless shader check see that this shader compiled (a shader without uniforms looks the same
// as one that failed). 0 keeps the mask fully invisible, as it should be.
uniform float debug_tint : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	ALBEDO = vec3(1.0, 0.0, 1.0);
	ALPHA = debug_tint;
}
