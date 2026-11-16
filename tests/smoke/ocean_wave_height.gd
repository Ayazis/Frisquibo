extends SceneTree
## Runs the real FFT ocean and checks that the simulated wave height is what the sea state promises:
## the wind sea's own spectrum, and a swell of exactly the height asked for.
## Needs a RenderingDevice (not --headless); see tests/smoke/README.md.

const SETTLE_FRAMES := 240
const TOLERANCE := 0.05
## Frames between freeing the ocean and quitting, so its GPU resources are released first.
const SHUTDOWN_FRAMES := 5
## Swell cases: (height in m, period in s).
const SWELLS: Array[Vector2] = [Vector2(2.0, 12.0), Vector2(1.0, 7.0)]

var _ocean: Ocean
var _sea := OceanSpectrum.new()
var _frames := 0
var _case := -1
var _wind_height := 0.0
var _failures := 0
var _done := false


func _initialize() -> void:
	if not OceanSimulation.is_supported():
		print("OCEAN WAVE HEIGHT skipped: no RenderingDevice")
		quit()
		return
	_sea.wind_speed = 9.0
	_sea.fetch = 80.0
	_sea.depth = 400.0
	_ocean = Ocean.new()
	_ocean.spectrum = _sea
	_ocean.planar_reflection = false
	root.add_child(_ocean)


func _process(_delta: float) -> bool:
	if _done:
		_frames += 1
		if _frames >= SHUTDOWN_FRAMES:
			quit(1 if _failures > 0 else 0)
		return false
	if _ocean == null:
		return false
	_frames += 1
	if _frames < SETTLE_FRAMES:
		return false
	_frames = 0
	var measured := _ocean.wave_height()
	if _case < 0:
		_wind_height = measured
		_expect(measured, OceanSeaStats.wind_wave_height(_sea), "wind sea")
	else:
		var swell := sqrt(maxf(measured * measured - _wind_height * _wind_height, 0.0))
		_expect(swell, SWELLS[_case].x, "swell %.1f m, %.0f s" % [SWELLS[_case].x, SWELLS[_case].y])
	_case += 1
	if _case >= SWELLS.size():
		print("OCEAN WAVE HEIGHT %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
		_ocean.queue_free()
		_done = true
		return false
	_ocean.set_parameter(&"swell_period", SWELLS[_case].y)
	_ocean.set_parameter(&"swell_height", SWELLS[_case].x)
	return false


func _expect(measured: float, expected: float, what: String) -> void:
	var ok := absf(measured - expected) <= TOLERANCE * expected
	print("OCEAN WAVE HEIGHT %s: measured %.2f m, expected %.2f m%s" % [what, measured, expected, "" if ok else "  FAIL"])
	if not ok:
		_failures += 1
