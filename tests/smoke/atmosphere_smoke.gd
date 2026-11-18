extends SceneTree
## Runs the water demo through every time of day, weather and sea state, the way the demo keys and the
## visual check drive it, plus a time lapse across a whole day; fails if the light goes non-finite.
## godot --headless --path . --script res://tests/smoke/atmosphere_smoke.gd   (check the log for errors)

const SCENE := "res://prototypes/water_demo/water_demo.tscn"
const SCRIPT := preload("res://prototypes/water_demo/water_demo.gd")
const FRAMES_PER_STEP := 20
const LAPSE_FRAMES := 400
const LAPSE_HOURS_PER_SECOND := 4.0

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load(SCENE)
	var demo := packed.instantiate()
	root.add_child(demo)
	await _frames(FRAMES_PER_STEP)
	var atmosphere := _find_atmosphere(demo)
	var time := _find_time(demo)
	_check(atmosphere != null and time != null, "The demo has an Atmosphere and a TimeOfDay")
	if atmosphere == null or time == null:
		quit(1)
		return
	for weather in range(SCRIPT.WEATHERS.size()):
		for hour in range(SCRIPT.TIMES.size()):
			demo.call("apply_visual_check_state", {"view": 0, "time": hour, "sea_state": 1, "weather": weather})
			await _frames(FRAMES_PER_STEP)
			_check_light(atmosphere, "%s at %s" % [SCRIPT.WEATHERS[weather].display_name, SCRIPT.TIME_NAMES[hour]])
	for sea_state in range(IslandScene.STATES.size()):
		demo.call("apply_visual_check_state", {"view": 4, "golden_hour": true, "sea_state": sea_state})
		await _frames(FRAMES_PER_STEP)
		_check_light(atmosphere, "sea state %d" % sea_state)
	demo.call("_next_weather")
	time.hours_per_second = LAPSE_HOURS_PER_SECOND
	for i in range(LAPSE_FRAMES):
		await process_frame
		if i % FRAMES_PER_STEP == 0:
			_check_light(atmosphere, "time lapse at %s" % time.clock_text())
	print("Atmosphere smoke: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	demo.queue_free()
	await process_frame
	quit(_failures)


func _check_light(atmosphere: Atmosphere, label: String) -> void:
	var l := atmosphere.lighting
	var finite := is_finite(l.exposure) and is_finite(l.sun_energy) and is_finite(l.moon_energy) \
			and l.cloud_light.is_finite() and l.cloud_ambient.is_finite()
	_check(finite, "Finite light: " + label)
	# The environment stores the exposure as a 32-bit float.
	_check(l.exposure > 0.0 and is_equal_approx(atmosphere.environment.tonemap_exposure, l.exposure),
			"Exposure applied: " + label)


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _find_atmosphere(node: Node) -> Atmosphere:
	for child: Node in node.get_children():
		if child is Atmosphere:
			return child as Atmosphere
	return null


func _find_time(node: Node) -> TimeOfDay:
	for child: Node in node.get_children():
		if child is TimeOfDay:
			return child as TimeOfDay
	return null


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		print("  FAIL: ", label)
