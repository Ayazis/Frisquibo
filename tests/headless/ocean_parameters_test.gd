extends SceneTree
## No GUT dependency: godot --headless --path . --script res://tests/headless/ocean_parameters_test.gd
const TOLERANCE: float = 0.001
var _failures: int = 0


func _initialize() -> void:
	var sea := OceanSpectrum.new()
	var listed := OceanParameterCatalog.of(sea, "Waves")
	var wind := _find(listed, &"wind_speed")
	_check(wind != null and wind.has_range, "Wind speed is listed with a range")
	_near(wind.minimum, 0.5, "Range minimum comes from the export hint")
	_near(wind.maximum, 80.0, "Range maximum comes from the export hint")
	_near(wind.step, 0.1, "Step comes from the export hint")
	_check(wind.unit == "m/s", "Unit comes from the suffix")
	_check(wind.group == "Wind", "Group comes from @export_group")
	_check(wind.label == "Wind speed", "Label defaults to the property name in sentence case")
	_check(wind.description != "", "Wind speed has a description")
	_check(_find(listed, &"foam_gain").group == "Foam", "A later group replaces the earlier one")
	_check(_find(listed, &"wind_direction").unit == "°", "The degrees hint becomes a unit")
	_check(_find(listed, &"height_scale").label == "Vertical size", "A friendlier label overrides the name")
	_check(_find(listed, &"seed") == null, "Whole numbers are not tunable sliders")
	var swell := _find(listed, &"swell")
	_near(swell.step, 0.01, "Without a step the range is cut into 200")
	_near(swell.clamp_value(5.0), 2.0, "Values clamp to the range")
	for parameter: OceanParameter in listed:
		_check(parameter.description != "", "'%s' has a description" % parameter.name)

	var ocean := Ocean.new()
	ocean.spectrum = sea
	var all := ocean.parameters()
	var level := _find(all, &"level")
	_check(level != null and level.group == Ocean.SEA_GROUP, "Ocean values outside a group use the default")
	_check(level.limits().y == INF, "or_greater leaves the limit open")
	_near(level.clamp_value(50.0), 50.0, "An open range does not clamp")
	_check(_find(all, &"breaker_ratio").group == "Shore", "Ocean groups are read past the node's own")
	_check(_find(all, &"wind_speed") != null, "The ocean lists its sea state too")
	for parameter: OceanParameter in all:
		_check(parameter.description != "", "'%s' has a description" % parameter.name)
	_check(ocean.set_parameter(&"wind_speed", 12.0), "A sea state value can be set by name")
	_near(sea.wind_speed, 12.0, "It lands in the spectrum")
	ocean.set_parameter(&"breaker_ratio", 9.0)
	_near(ocean.breaker_ratio, 0.05 + 1.95, "An ocean value is set and clamped")
	_near(ocean.parameter_value(&"breaker_ratio"), 2.0, "Values read back by name")
	_check(not ocean.set_parameter(&"nonsense", 1.0), "Unknown names are refused")
	_check(is_nan(ocean.parameter_value(&"nonsense")), "Unknown names read as NAN")
	_check(OceanRuleEngine.limits(sea)[&"wind_speed"] == Vector2(0.5, 80.0), "Rules see the same limits")
	var look := _find(all, &"caustic_strength")
	_check(look != null and look.group == "Caustics", "The ocean lists its look too")
	_check(ocean.set_parameter(&"caustic_strength", 4.0), "A look value can be set by name")
	_near(ocean.look.caustic_strength, 4.0, "It lands in the look")
	_check(ocean.rule_targets().has("whitecap_strength"), "Rules can change the look")
	ocean.free()

	# The headless renderer can't report uniform defaults, so they are read from the shader source.
	var defaults := OceanLook.new()
	var shader: Shader = load("res://world/water/ocean/ocean.gdshader")
	for parameter: OceanParameter in OceanParameterCatalog.of(defaults, ""):
		if OceanLookBinding.ABSORPTION_CHANNELS.has(parameter.name):
			continue
		var found := _uniform_default(shader.code, "float", parameter.name)
		_check(found.size() == 1, "Look value '%s' has a float shader uniform" % parameter.name)
		var look_default: float = defaults.get(parameter.name)
		if found.size() == 1:
			_near(look_default, found[0], "Look default of '%s' equals the shader's" % parameter.name)
	for color_name: StringName in OceanLookBinding.COLORS:
		var found := _uniform_default(shader.code, "vec3", color_name)
		var color: Color = defaults.get(color_name)
		_check(found.size() == 3 and Vector3(color.r, color.g, color.b).is_equal_approx(
				Vector3(found[0], found[1], found[2])), "Look colour '%s' equals the shader's" % color_name)
	var absorbed := _uniform_default(shader.code, "vec3", OceanLookBinding.ABSORPTION_UNIFORM)
	_check(absorbed.size() == 3 and OceanLookBinding.absorption(defaults, {}).is_equal_approx(
			Vector3(absorbed[0], absorbed[1], absorbed[2])), "Default absorption equals the shader's")
	_near(OceanLookBinding.absorption(defaults, {&"absorption_red": 1.5}).x, 1.5, "Rule results win over the authored look")
	var material := ShaderMaterial.new()
	material.shader = shader
	OceanLookBinding.apply(defaults, material, {&"caustic_strength": 7.0})
	var pushed: float = material.get_shader_parameter(&"caustic_strength")
	_near(pushed, 7.0, "The binding pushes numbers to the material")

	_check(OceanSeaStats.beaufort(0.2) == 0, "Beaufort 0 is calm")
	_check(OceanSeaStats.beaufort(9.0) == 5, "9 m/s is a fresh breeze")
	_check(OceanSeaStats.beaufort(40.0) == 12, "Beyond the table is a hurricane")
	var breeze := OceanSpectrum.new()
	breeze.wind_speed = 10.0
	breeze.fetch = 100.0
	_near(OceanSeaStats.expected_wave_height(breeze), 0.0016 * 10.0 * sqrt(100000.0 / 9.81), "Fetch-limited height")
	breeze.fetch = 2000.0
	_near(OceanSeaStats.expected_wave_height(breeze), 0.24 * 100.0 / 9.81, "A long fetch stops at the full sea")
	_near(OceanSeaStats.peak_period(breeze) * breeze.peak_frequency(), TAU, "Period matches the peak frequency")
	_check(OceanSeaStats.warnings(breeze, 1.0).is_empty(), "A plain wind sea has no warnings")
	_check(OceanSeaStats.warnings(breeze, breeze.peak_wavelength() / 5.0).size() == 1, "Too steep waves warn")
	breeze.choppiness = 2.0
	breeze.height_scale = 2.0
	_check(OceanSeaStats.warnings(breeze, 1.0).size() == 2, "Folding and artistic size warn")

	print("ocean_parameters_test: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## Default of `uniform <type> <name> ... = <value>;` in shader source: one number, or the three of a vec3.
func _uniform_default(code: String, type: String, uniform_name: StringName) -> PackedFloat64Array:
	var pattern := RegEx.create_from_string("uniform\\s+%s\\s+%s\\b[^=;]*=\\s*([^;]+);" % [type, uniform_name])
	var found := pattern.search(code)
	var numbers := PackedFloat64Array()
	if found == null:
		return numbers
	for part: String in found.get_string(1).trim_prefix("vec3(").trim_suffix(")").split(","):
		numbers.append(part.to_float())
	return numbers


func _find(listed: Array[OceanParameter], key: StringName) -> OceanParameter:
	for parameter: OceanParameter in listed:
		if parameter.name == key:
			return parameter
	return null


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: " + what)


func _near(value: float, expected: float, what: String) -> void:
	_check(absf(value - expected) < TOLERANCE, "%s (got %f, expected %f)" % [what, value, expected])
