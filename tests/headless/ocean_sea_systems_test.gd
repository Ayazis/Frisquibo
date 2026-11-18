extends SceneTree
## Swell and surface waves as two wave systems: old sea states still load, the Gerstner fallback
## (web / Compatibility) follows the bigger system, and the tuner puts every section in a step.
## No GUT dependency: godot --headless --path . --script res://tests/headless/ocean_sea_systems_test.gd
const TOLERANCE: float = 0.001
const SAVE_PATH := "user://ocean_sea_systems_test.tres"
## A sea state from before wind_spread existed: crest alignment was `swell`, blending was `spread`.
const LEGACY_SPECTRUM := """[gd_resource type="Resource" script_class="OceanSpectrum" load_steps=2 format=3]

[ext_resource type="Script" path="res://world/water/ocean/ocean_spectrum.gd" id="1"]

[resource]
script = ExtResource("1")
wind_speed = 7.0
swell = 0.25
spread = 0.3
"""
## A sea state from when the wind built the surface waves: 9 m/s over 80 km made 1.72 m, 48.7 m long.
const WIND_BUILT_SPECTRUM := """[gd_resource type="Resource" script_class="OceanSpectrum" load_steps=2 format=3]

[ext_resource type="Script" path="res://world/water/ocean/ocean_spectrum.gd" id="1"]

[resource]
script = ExtResource("1")
swell_height = 1.0
wind_speed = 9.0
wind_direction = 40.0
fetch = 80.0
wind_spread = 0.6
height_scale = 2.0
wavelength_scale = 1.5
"""
var _failures: int = 0
var _ocean: Ocean


func _initialize() -> void:
	_check_legacy_values()
	_check_presets()
	_check_sections()
	_start_fallback()


## Nodes added during _initialize get _ready() on the first frame, so the fallback is checked there.
func _process(_delta: float) -> bool:
	_check_fallback()
	print("ocean_sea_systems_test: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)
	return true


func _check_legacy_values() -> void:
	var loaded := _load_text(LEGACY_SPECTRUM)
	_check(loaded != null, "A sea state saved before wind_spread still loads")
	if loaded == null:
		return
	_near(loaded.wind_speed, 7.0, "Its other values load as before")
	_near(loaded.surface_spread, 1.0 / (1.0 + OceanSpectrum.LEGACY_ALIGNMENT_FACTOR * 0.25),
			"Old crest alignment becomes the matching spread")
	_check(OceanParameterCatalog.of(loaded, "").all(
			func(p: OceanParameter) -> bool: return p.name != &"swell" and p.name != &"spread"),
			"The old names are no longer tunables")
	var built := _load_text(WIND_BUILT_SPECTRUM)
	_check(built != null, "A sea state whose wind built the waves still loads")
	if built == null:
		return
	_near(built.surface_height, 1.72 * 2.0, "Old wind and fetch become the surface wave height (times the old height scale)", 0.01)
	_near(built.surface_length, 48.7 * 1.5, "...and length (times the old length scale)", 0.2)
	_near(built.surface_direction, 40.0, "The surface waves keep the old wind's direction")
	_near(built.surface_spread, 0.6, "The old wind wave spread becomes the surface wave spread")
	_near(built.swell_height, 2.0, "The old height scale applied to the swell too")
	_check(OceanParameterCatalog.of(built, "").all(
			func(p: OceanParameter) -> bool: return not [&"fetch", &"height_scale", &"wavelength_scale"].has(p.name)),
			"Fetch and the size overrides are no longer tunables")


func _load_text(text: String) -> OceanSpectrum:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	var loaded := ResourceLoader.load(SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as OceanSpectrum
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	return loaded


func _check_presets() -> void:
	for preset_name: String in ["calm_sea", "fresh_breeze", "breeze_over_swell", "storm"]:
		var preset := load("res://world/water/ocean/presets/%s.tres" % preset_name) as OceanSpectrum
		_check(preset.swell_height > 0.0, "The %s preset has main waves (swell)" % preset_name)
		_check(not is_equal_approx(preset.swell_direction, preset.surface_direction),
				"In the %s preset swell and surface waves have their own directions" % preset_name)
		_check(preset.surface_height > 0.0, "The %s preset has surface waves" % preset_name)


func _start_fallback() -> void:
	if OceanSimulation.is_supported():
		print("ocean_sea_systems_test: fallback checks need --headless (no RenderingDevice)")
		return
	var sea := OceanSpectrum.new()
	sea.surface_height = 0.33
	sea.surface_length = 9.3
	sea.surface_direction = 30.0
	sea.wind_direction = 100.0
	sea.swell_height = 2.0
	sea.swell_period = 12.0
	sea.swell_direction = -60.0
	_ocean = Ocean.new()
	_ocean.spectrum = sea
	_ocean.planar_reflection = false
	root.add_child(_ocean)


func _check_fallback() -> void:
	if _ocean == null:
		return
	var ocean := _ocean
	_check(ocean.is_parameter_live(&"swell_height"), "The fallback reacts to the swell")
	var fallback := _fallback_sea(ocean)
	_check(fallback != null, "Headless runs the Gerstner fallback")
	if fallback != null:
		var heading: Vector2 = fallback.material.get_shader_parameter("wind_direction")
		_near(rad_to_deg(heading.angle()), -60.0, "A swell bigger than the surface waves leads the fallback")
		ocean.set_parameter(&"swell_height", 0.0)
		heading = fallback.material.get_shader_parameter("wind_direction")
		_near(rad_to_deg(heading.angle()), 30.0, "Without swell the surface waves lead, not the wind")
		var amplitude: float = fallback.material.get_shader_parameter("wave_amplitude")
		ocean.set_parameter(&"wind_speed", 30.0)
		var windy: float = fallback.material.get_shader_parameter("wave_amplitude")
		_near(windy, amplitude, "Wind leaves the fallback waves alone")
	ocean.free()


func _fallback_sea(ocean: Ocean) -> Sea:
	for child: Node in ocean.get_children():
		if child is Sea:
			return child as Sea
	return null


func _check_sections() -> void:
	var ocean := Ocean.new()
	ocean.spectrum = OceanSpectrum.new()
	ocean.look = OceanLook.new()
	for parameter: OceanParameter in ocean.parameters():
		_check(OceanTunerPanel.step_of(parameter.group) >= 0,
				"'%s' is in a step of the panel (%s)" % [parameter.name, parameter.group])
	for group: String in OceanTunerPanel.COLOR_GROUPS.values():
		_check(OceanTunerPanel.step_of(group) >= 0, "Colour section '%s' is in a step" % group)
	for entry: Array in OceanTunerLinks.LINKS:
		var section: String = entry[3]
		_check(OceanTunerPanel.step_of(section) >= 0, "Link section '%s' is in a step" % section)
	_check(OceanTunerPanel.step_of("Main waves (swell)") == 0, "Wave shape comes first")
	_check(OceanTunerPanel.step_of("Surface waves") == 1 and OceanTunerPanel.step_of("Wind") == 1,
			"Surface waves and wind come second")
	_check(OceanTunerPanel.step_of("Foam") == 2, "Foam comes third")
	_check(OceanTunerPanel.step_of("Shore waves") == 3 and OceanTunerPanel.step_of("Beach") == 3,
			"Coast and beach come fourth")
	for key: StringName in OceanTunerPanel.FINE_TUNING:
		_check(_has_parameter(ocean, key), "Fine-tuning value '%s' exists" % key)
	var panel := OceanTunerPanel.new(ocean)
	panel.free()
	ocean.free()


func _has_parameter(ocean: Ocean, key: StringName) -> bool:
	for parameter: OceanParameter in ocean.parameters():
		if parameter.name == key:
			return true
	return false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: " + what)


func _near(value: float, expected: float, what: String, tolerance: float = TOLERANCE) -> void:
	_check(absf(value - expected) < tolerance, "%s (got %f, expected %f)" % [what, value, expected])
