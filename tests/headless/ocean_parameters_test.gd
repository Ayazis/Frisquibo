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
	ocean.free()

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
