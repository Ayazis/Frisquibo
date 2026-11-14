extends SceneTree
## No GUT dependency: godot --headless --path . --script res://tests/headless/beach_profile_test.gd
const TOLERANCE: float = 0.05
var _failures: int = 0

func _initialize() -> void:
	var beach: BeachProfile = BeachProfile.new()
	beach.noise_amplitude = 0.0
	_near(beach.height(0.0, 0.0, 0.0), 0.0, "Waterline at sea level")
	_check(beach.height(-10.0, 0, 0) > 0.5, "Beach rises inland")
	_near(beach.height(-200.0, 0, 0), beach.berm_height, "Berm levels off inland")
	_check(beach.height(10.0, 0, 0) < 0.0, "Underwater offshore")
	var previous: float = 0.0
	var steepest_near: float = absf(beach.height(2.0, 0, 0) - beach.height(1.0, 0, 0))
	var gentle_mid: float = absf(beach.height(101.0, 0, 0) - beach.height(100.0, 0, 0))
	_check(steepest_near > gentle_mid, "Dean profile: steeper near shore than offshore")
	_check(beach.height(beach.bar_distance, 0, 0) > beach.height(beach.bar_distance - beach.bar_width, 0, 0), "Sandbar rises above the trough before it")
	for d: int in range(200, 600, 50):
		var h: float = beach.height(float(d), 0, 0)
		if d > 200:
			_check(h < previous, "Seabed keeps deepening at %d m (no flat cap)" % d)
		previous = h
	print("Beach profile: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(_failures)

func _near(actual: float, expected: float, label: String) -> void:
	_check(absf(actual - expected) <= TOLERANCE, "%s (got %.3f, expected %.3f)" % [label, actual, expected])

func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", label)
