class_name WaterProp
extends RefCounted
## Materials for props that can be partly under water. A StandardMaterial3D can't be clipped for the
## planar reflection, so its submerged half would appear mirrored above the surface; these can.

const SHADER := preload("res://world/water/water_prop.gdshader")


static func material(color: Color, roughness: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("roughness", roughness)
	return m
