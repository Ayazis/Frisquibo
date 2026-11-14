class_name OceanLookBinding
extends RefCounted
## Pushes an OceanLook into the ocean surface material. Numbers go to the uniform of the same name;
## `values` (the sea state after the rules) wins over the authored number when it holds one.

const ABSORPTION_UNIFORM := &"absorption"
const ABSORPTION_CHANNELS: Array[StringName] = [&"absorption_red", &"absorption_green", &"absorption_blue"]
const COLORS: Array[StringName] = [&"scatter_color", &"sss_color", &"deep_color", &"foam_color"]
const COLOR_LABELS: Dictionary[StringName, String] = {
	&"scatter_color": "Deep water colour",
	&"sss_color": "Crest glow colour",
	&"deep_color": "Colour from below",
	&"foam_color": "Foam colour",
}


static func apply(look: OceanLook, material: ShaderMaterial, values: Dictionary[StringName, float]) -> void:
	for parameter: OceanParameter in OceanParameterCatalog.of(look, ""):
		if not ABSORPTION_CHANNELS.has(parameter.name):
			material.set_shader_parameter(parameter.name, _number(look, values, parameter.name))
	material.set_shader_parameter(ABSORPTION_UNIFORM, absorption(look, values))
	for color_name: StringName in COLORS:
		var color: Color = look.get(color_name)
		material.set_shader_parameter(color_name, color)


## Light lost per metre of water, per colour channel.
static func absorption(look: OceanLook, values: Dictionary[StringName, float]) -> Vector3:
	return Vector3(_number(look, values, ABSORPTION_CHANNELS[0]), _number(look, values, ABSORPTION_CHANNELS[1]),
			_number(look, values, ABSORPTION_CHANNELS[2]))


static func _number(look: OceanLook, values: Dictionary[StringName, float], key: StringName) -> float:
	if values.has(key):
		return values[key]
	var authored: float = look.get(key)
	return authored
