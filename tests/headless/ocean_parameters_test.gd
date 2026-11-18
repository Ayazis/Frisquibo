extends SceneTree
## No GUT dependency: godot --headless --path . --script res://tests/headless/ocean_parameters_test.gd
const TOLERANCE: float = 0.001
## How close Auto must come to what the presets were tuned to by eye.
const AUTO_PRESET_TOLERANCE: float = 0.08
var _failures: int = 0


func _initialize() -> void:
	var sea := OceanSpectrum.new()
	var listed := OceanParameterCatalog.of(sea, "Waves")
	var wind := _find(listed, &"wind_speed")
	_check(wind != null and wind.has_range, "Wind speed is listed with a range")
	_near(wind.minimum, 0.5, "Range minimum comes from the export hint")
	_near(wind.maximum, 40.0, "Range maximum comes from the export hint")
	_near(wind.step, 0.1, "Step comes from the export hint")
	_check(wind.unit == "m/s", "Unit comes from the suffix")
	_check(wind.group == "Wind", "Group comes from @export_group")
	_check(wind.label == "Wind speed", "Label defaults to the property name in sentence case")
	_check(wind.description != "", "Wind speed has a description")
	_check(_find(listed, &"foam_gain").group == "Foam", "A later group replaces the earlier one")
	_check(_find(listed, &"wind_direction").unit == "°", "The degrees hint becomes a unit")
	_check(_find(listed, &"choppiness").label == "Crest sharpness", "A friendlier label overrides the name")
	_check(_find(listed, &"seed") == null, "Whole numbers are not tunable sliders")
	var chop := _find(listed, &"choppiness")
	_near(chop.step, 0.02, "Without a step the range is cut into 200")
	_near(chop.clamp_value(5.0), 4.0, "Values clamp to the range")
	for parameter: OceanParameter in listed:
		_check(parameter.description != "", "'%s' has a description" % parameter.name)

	var ocean := Ocean.new()
	ocean.spectrum = sea
	var all := ocean.parameters()
	var level := _find(all, &"level")
	_check(level != null and level.group == "Water depth", "Ocean values are listed under their group")
	_check(level.limits().y == INF, "or_greater leaves the limit open")
	_near(level.clamp_value(50.0), 50.0, "An open range does not clamp")
	_check(_find(all, &"breaker_ratio").group == "Shore waves", "Ocean groups are read past the node's own")
	_check(_find(all, &"depth").group == level.group, "Sea state and ocean share the depth and shore section")
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
	_check(OceanRuleEngine.limits(sea)[&"wind_speed"] == Vector2(0.5, 40.0), "Rules see the same limits")
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
	_near(4.0 * sqrt(OceanSpectrum.JONSWAP_VARIANCE * breeze.jonswap_alpha() * 9.81 * 9.81
			/ pow(breeze.peak_frequency(), 4.0)), breeze.surface_height, "The JONSWAP sea has the height asked for", 0.01)
	_near(TAU * 9.81 / pow(breeze.peak_frequency(), 2.0), breeze.surface_length, "...and the length", 0.01)
	var alpha := breeze.jonswap_alpha()
	var peak := breeze.peak_frequency()
	breeze.wind_speed = 30.0
	breeze.wind_direction = -90.0
	_check(is_equal_approx(breeze.jonswap_alpha(), alpha) and is_equal_approx(breeze.peak_frequency(), peak),
			"Wind leaves the waves alone")
	breeze.wind_speed = 9.0
	_near(OceanSeaStats.surface_wave_height(breeze), 1.72, "Surface waves are as high as set", 0.01)
	breeze.swell_height = 2.0
	_near(OceanSeaStats.expected_wave_height(breeze), sqrt(1.72 * 1.72 + 4.0), "Wind sea and swell energies add", 0.01)
	_near(OceanSeaStats.steepness(breeze, OceanSeaStats.expected_wave_height(breeze)) * breeze.peak_wavelength(),
			OceanSeaStats.surface_wave_height(breeze), "Steepness leaves the swell out", 0.01)
	breeze.swell_height = 0.0
	breeze.depth = 4000.0
	breeze.swell_period = 10.0
	_near(breeze.swell_wavelength(), 9.81 * 100.0 / TAU, "Deep-water swell length is g T^2 / 2 pi", 0.01)
	_check(breeze.longest_wavelength() == breeze.peak_wavelength(), "No swell: the wind waves are the longest")
	breeze.swell_height = 1.0
	_near(breeze.longest_wavelength(), breeze.swell_wavelength(), "With swell, its length counts")
	_check(OceanSimulation.tiles_for(breeze, 4)[0] >= OceanSimulation.PEAK_WAVES_PER_TILE * breeze.swell_wavelength() - TOLERANCE,
			"The longest cascade grows to hold the swell")
	breeze.depth = 5.0
	_near(breeze.swell_wavelength(), 10.0 * sqrt(9.81 * 5.0), "Shallow-water swell slows to sqrt(g depth)", 3.0)
	breeze.swell_height = 0.0
	breeze.depth = 40.0
	breeze.wind_speed = 3.0
	_check(OceanSeaStats.warnings(breeze, 1.0).size() == 1, "Surface waves too high for the wind warn")
	breeze.wind_speed = 10.0
	_near(OceanSeaStats.peak_period(breeze) * breeze.peak_frequency(), TAU, "Period matches the peak frequency")
	_check(OceanSeaStats.warnings(breeze, 1.0).is_empty(), "A plain wind sea has no warnings")
	_check(OceanSeaStats.warnings(breeze, breeze.peak_wavelength() / 5.0).size() == 1, "Too steep waves warn")
	breeze.choppiness = 2.0
	_check(OceanSeaStats.warnings(breeze, 1.0).size() == 1, "Folding warns")

	_check(OceanAutoValues.has(&"foam_threshold") and not OceanAutoValues.has(&"wind_speed"), "Only derived values are auto")
	_check(not OceanAutoValues.has(&"choppiness"), "Crest sharpness doesn't follow the wind")
	_check(is_nan(OceanAutoValues.value(&"wind_speed", breeze)), "A value without a rule has no auto value")
	var calm := OceanSpectrum.new()
	calm.wind_speed = 4.0
	breeze.wind_speed = 19.0
	_check(OceanAutoValues.value(&"foam_threshold", breeze) > OceanAutoValues.value(&"foam_threshold", calm),
			"More wind, more whitecaps")
	for auto: StringName in OceanAutoValues.PARAMETERS:
		var described := _find(listed, auto)
		_check(described != null, "Auto value '%s' is a tunable" % auto)
		for state: OceanSpectrum in [calm, breeze]:
			var derived := OceanAutoValues.value(auto, state)
			_near(described.clamp_value(derived), derived, "Auto '%s' stays inside its range" % auto)

	for preset_name: String in ["calm_sea", "fresh_breeze", "storm"]:
		var preset := load("res://world/water/ocean/presets/%s.tres" % preset_name) as OceanSpectrum
		for auto: StringName in OceanAutoValues.PARAMETERS:
			var authored: float = preset.get(auto)
			_check(absf(OceanAutoValues.value(auto, preset) - authored) < AUTO_PRESET_TOLERANCE,
					"Auto '%s' matches the %s preset (%.2f vs %.2f)" % [auto, preset_name,
					OceanAutoValues.value(auto, preset), authored])

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


func _near(value: float, expected: float, what: String, tolerance: float = TOLERANCE) -> void:
	_check(absf(value - expected) < tolerance, "%s (got %f, expected %f)" % [what, value, expected])
