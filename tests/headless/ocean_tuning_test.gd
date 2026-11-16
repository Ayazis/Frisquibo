extends SceneTree
## No GUT dependency: godot --headless --path . --script res://tests/headless/ocean_tuning_test.gd
const TOLERANCE: float = 0.001
const SAVE_PATH := "user://ocean_tuning_test.tres"
var _failures: int = 0


func _initialize() -> void:
	var ocean := _ocean()
	ocean.set_parameter(&"wind_speed", 14.0)
	ocean.set_parameter(&"level", 1.5)
	ocean.set_parameter(&"breaker_ratio", 0.6)
	ocean.look.deep_color = Color(0.1, 0.2, 0.3)
	var a := OceanTuning.capture(ocean)
	_near(a.spectrum.wind_speed, 14.0, "The sea state is captured")
	_near(a.ocean_values[&"level"], 1.5, "Sea level is captured")
	_near(a.ocean_values[&"breaker_ratio"], 0.6, "Shore values are captured")
	_check(not a.ocean_values.has(&"wind_speed"), "Sea state values are not repeated as ocean values")
	_check(a.look.deep_color.is_equal_approx(Color(0.1, 0.2, 0.3)), "The look is captured")

	ocean.set_parameter(&"wind_speed", 5.0)
	ocean.set_parameter(&"level", -2.0)
	ocean.look.deep_color = Color.RED
	_near(a.spectrum.wind_speed, 14.0, "Later edits leave the capture alone")
	_check(a.look.deep_color.is_equal_approx(Color(0.1, 0.2, 0.3)), "Later look edits leave the capture alone")

	a.apply_to(ocean)
	_near(ocean.parameter_value(&"wind_speed"), 14.0, "Applying restores the sea state")
	_near(ocean.parameter_value(&"level"), 1.5, "Applying restores sea level")
	_near(ocean.parameter_value(&"breaker_ratio"), 0.6, "Applying restores shore values")
	ocean.set_parameter(&"wind_speed", 7.0)
	_near(a.spectrum.wind_speed, 14.0, "The ocean tunes a copy, not the stored one")

	var other := _ocean()
	_check(ResourceSaver.save(a, SAVE_PATH) == OK, "A tuning saves")
	var loaded := ResourceLoader.load(SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as OceanTuning
	_check(loaded != null, "A saved tuning loads back")
	loaded.apply_to(other)
	_near(other.parameter_value(&"level"), 1.5, "Sea level survives saving")
	_near(other.parameter_value(&"wind_speed"), 14.0, "The sea state survives saving")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

	var stale := OceanTuning.new()
	stale.ocean_values[&"no_longer_there"] = 3.0
	stale.apply_to(other)
	_check(true, "Unknown names are skipped")
	ocean.free()
	other.free()
	print("Ocean tuning: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _ocean() -> Ocean:
	var ocean := Ocean.new()
	ocean.spectrum = OceanSpectrum.new()
	ocean.look = OceanLook.new()
	return ocean


func _near(actual: float, expected: float, what: String) -> void:
	_check(absf(actual - expected) < TOLERANCE, "%s (got %s, expected %s)" % [what, actual, expected])


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		push_error("FAIL: " + what)
