extends SceneTree
## Pushes every tunable of the FFT ocean to the ends of its range (past them where the range is open),
## one at a time and in a few nasty combinations, and checks that nothing breaks: the simulated
## surface stays finite, wave heights stay plausible, and the picture doesn't black out (a NaN in
## the shading spreads through glow and reflections and turns the sky black).
## Needs a RenderingDevice (not --headless); see tests/smoke/README.md.
## Optional: ONLY=<case name substring> runs a subset.

## Seconds per case: the measured wave height follows the simulation with a lag (Ocean.AMPLITUDE_RESPONSE).
const SETTLE_SECONDS := 3.0
## The camera rides this far above the water under it, so it never ends up under a big wave.
const CAMERA_CLEARANCE := 6.0
const CAMERA_XZ := Vector2(0, 40)
const LOOK_DISTANCE := 240.0
const SHUTDOWN_FRAMES := 5
## How far past the slider an open-ended range ("or_greater") is pushed.
const OPEN_RANGE_PUSH := 4.0
## Darkest the sky may get (0..1 luminance) before the frame counts as blacked out.
const MIN_SKY_LUMINANCE := 0.15
## Highest believable significant wave height; the tallest measured at sea is about 20 m.
const MAX_WAVE_HEIGHT := 40.0
const GRID_STEP := 25.0
const GRID_HALF := 4
## Seabed: a straight beach rising from SEABED_DEEP at the far edge to land near the camera.
const SEABED_AREA := Rect2(-400, -600, 800, 700)
const SEABED_DEEP := -30.0
const SEABED_LAND := 3.0
const SEABED_RESOLUTION := 256
const COMBOS: Dictionary[String, Dictionary] = {
	"hurricane": {&"wind_speed": 40.0, &"fetch": 2000.0},
	"swell_against_wind": {&"swell_height": 4.0, &"swell_period": 14.0, &"swell_direction": -155.0, &"wind_speed": 20.0},
	"aligned_gale": {&"wind_spread": 0.1, &"wind_speed": 30.0, &"fetch": 1000.0},
	"tall_and_choppy": {&"height_scale": 6.0, &"choppiness": 4.0},
	"short_and_tall": {&"wavelength_scale": 0.1, &"height_scale": 6.0},
	"storm_shallow": {&"wind_speed": 40.0, &"depth": 1.0},
	"breakers_max": {&"wind_speed": 25.0, &"breaker_ratio": 2.0, &"wave_setup": 2.0, &"min_shore_wave": 1.0},
	"swell_max_storm": {&"swell_height": 8.0, &"swell_period": 22.0, &"wind_speed": 40.0},
	"foam_everything": {&"foam_gain": 20.0, &"foam_threshold": 3.0, &"foam_lifetime": 40.0},
}

var _ocean: Ocean
var _camera: Camera3D
var _defaults: OceanTuning
var _cases: Array[String] = []
var _values: Array[Dictionary] = []
var _case := -1
var _frames := 0
var _elapsed := 0.0
var _failures := 0
var _done := false


func _initialize() -> void:
	if not OceanSimulation.is_supported():
		print("OCEAN EXTREMES skipped: no RenderingDevice")
		quit()
		return
	var environment := WorldEnvironment.new()
	environment.environment = _environment()
	root.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	root.add_child(sun)
	_camera = Camera3D.new()
	_camera.far = 4000.0
	root.add_child(_camera)
	_ocean = Ocean.new()
	_ocean.spectrum = (load("res://world/water/ocean/presets/fresh_breeze.tres") as OceanSpectrum).duplicate()
	_ocean.look = OceanLook.new()
	root.add_child(_ocean)
	_ocean.set_seabed(_seabed, SEABED_AREA, SEABED_RESOLUTION)
	_defaults = OceanTuning.capture(_ocean)
	_build_cases()


func _build_cases() -> void:
	var only := OS.get_environment("ONLY")
	for parameter: OceanParameter in _ocean.parameters():
		if not parameter.has_range:
			continue
		var low := parameter.minimum
		var high := parameter.maximum * (OPEN_RANGE_PUSH if parameter.allow_greater else 1.0)
		_add("%s=min" % parameter.name, {parameter.name: low}, only)
		_add("%s=max" % parameter.name, {parameter.name: high}, only)
	for combo: String in COMBOS:
		_add(combo, COMBOS[combo], only)


func _add(case_name: String, values: Dictionary, only: String) -> void:
	if only != "" and not case_name.contains(only):
		return
	_cases.append(case_name)
	_values.append(values)


func _process(delta: float) -> bool:
	if _done:
		_frames += 1
		if _frames >= SHUTDOWN_FRAMES:
			quit(1 if _failures > 0 else 0)
		return false
	_place_camera()
	if _case >= 0:
		_elapsed += delta
		if _elapsed < SETTLE_SECONDS:
			return false
		_check_case()
	_case += 1
	_elapsed = 0.0
	if _case >= _cases.size():
		print("OCEAN EXTREMES %s (%d cases)" % ["PASS" if _failures == 0 else "%d FAILED" % _failures, _cases.size()])
		_ocean.queue_free()
		_done = true
		return false
	_defaults.apply_to(_ocean)
	var values: Dictionary = _values[_case]
	for parameter: StringName in values:
		var value: float = values[parameter]
		_ocean.set_parameter(parameter, value)
	return false


func _place_camera() -> void:
	var y := _ocean.height_at(CAMERA_XZ) + CAMERA_CLEARANCE
	var from := Vector3(CAMERA_XZ.x, y, CAMERA_XZ.y)
	_camera.look_at_from_position(from, from + Vector3(0, -CAMERA_CLEARANCE, -LOOK_DISTANCE))


func _check_case() -> void:
	var problems := PackedStringArray()
	var height := _ocean.wave_height()
	if not is_finite(height):
		problems.append("wave height is %s" % height)
	elif height > MAX_WAVE_HEIGHT:
		problems.append("wave height %.1f m" % height)
	for x: int in range(-GRID_HALF, GRID_HALF + 1):
		for z: int in range(-GRID_HALF, GRID_HALF + 1):
			var h := _ocean.height_at(Vector2(x, z) * GRID_STEP)
			if not is_finite(h):
				problems.append("surface height %s at (%d, %d)" % [h, x, z])
				break
	var image := root.get_texture().get_image()
	var sky := image.get_pixel(image.get_width() / 2, image.get_height() / 20).get_luminance()
	if sky < MIN_SKY_LUMINANCE:
		problems.append("picture blacked out (sky luminance %.2f)" % sky)
	if problems.is_empty():
		print("OCEAN EXTREMES ok    %s (Hs %.2f m)" % [_cases[_case], height])
	else:
		_failures += 1
		print("OCEAN EXTREMES FAIL  %s: %s" % [_cases[_case], ", ".join(problems)])
		if OS.get_environment("SHOTS") != "":
			image.save_png("%s/%s.png" % [OS.get_environment("SHOTS"), _cases[_case].replace("=", "_")])


func _seabed(x: float, z: float) -> float:
	var t := clampf((z - SEABED_AREA.position.y) / SEABED_AREA.size.y, 0.0, 1.0)
	return lerpf(SEABED_DEEP, SEABED_LAND, t) + 0.0 * x


static func _environment() -> Environment:
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.ssr_enabled = true
	return env
