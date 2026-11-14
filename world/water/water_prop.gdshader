shader_type spatial;
// Plain PBR material for props that sit in water (rocks, barrels, crates, posts). Same look as a
// StandardMaterial3D with albedo and roughness, plus the clip that keeps their submerged part out of
// planar water reflections. Create it with WaterProp.material().

#include "res://world/water/reflection_clip.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.5);
uniform float roughness : hint_range(0.0, 1.0) = 0.8;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	water_reflection_clip(v_world);
	ALBEDO = albedo;
	ROUGHNESS = roughness;
}
