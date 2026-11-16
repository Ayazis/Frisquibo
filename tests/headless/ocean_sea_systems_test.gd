extends SceneTree
## Swell and wind sea as two wave systems: old sea states still load, the Gerstner fallback
## (web / Compatibility) follows the bigger system, and the tuner lists every section in order.
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
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(LEGACY_SPECTRUM)
	file.close()
	var loaded := ResourceLoader.load(SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as OceanSpectrum
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	_check(loaded != null, "A sea state saved before wind_spread still loads")
	if loaded == null:
		return
	_near(loaded.wind_speed, 7.0, "Its other values load as before")
	_near(loaded.wind_spread, 1.0 / (1.0 + OceanSpectrum.LEGACY_ALIGNMENT_FACTOR * 0.25),
			"Old crest alignment becomes the matching spread")
	_check(OceanParameterCatalog.of(loaded, "").all(
			func(p: OceanParameter) -> bool: return p.name != &"swell" and p.name != &"spread"),
			"The old names are no longer tunables")


func _check_presets() -> void:
	for preset_name: String in ["calm_sea", "fresh_breeze", "breeze_over_swell", "storm"]:
		var preset := load("res://world/water/ocean/presets/%s.tres" % preset_name) as OceanSpectrum
		_check(preset.swell_height > 0.0, "The %s preset has main waves (swell)" % preset_name)
		_check(not is_equal_approx(preset.swell_direction, preset.wind_direction),
				"In the %s preset swell and wind have their own directions" % preset_name)


func _start_fallback() -> void:
	if OceanSimulation.is_supported():
		print("ocean_sea_systems_test: fallback checks need --headless (no RenderingDevice)")
		return
	var sea := OceanSpectrum.new()
	sea.wind_speed = 4.0
	sea.wind_direction = 30.0
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
		_near(rad_to_deg(heading.angle()), -60.0, "A swell bigger than the wind sea leads the fallback")
		ocean.set_parameter(&"swell_height", 0.0)
		heading = fallback.material.get_shader_parameter("wind_direction")
		_near(rad_to_deg(heading.angle()), 30.0, "Without swell the wind leads again")
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
		_check(OceanTunerPanel.SECTION_ORDER.has(parameter.group),
				"'%s' is in a section the panel knows (%s)" % [parameter.name, parameter.group])
	for group: String in OceanTunerPanel.COLOR_GROUPS.values():
		_check(OceanTunerPanel.SECTION_ORDER.has(group), "Colour section '%s' is known" % group)
	var order := OceanTunerPanel.SECTION_ORDER
	_check(order.find("Main waves (swell)") < order.find("Wind and surface waves"), "Main waves come first")
	_check(order.find(OceanTunerPanel.ARTISTIC_TITLE) > order.find("Caustics"), "Artistic overrides come last")
	ocean.free()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: " + what)


func _near(value: float, expected: float, what: String) -> void:
	_check(absf(value - expected) < TOLERANCE, "%s (got %f, expected %f)" % [what, value, expected])
