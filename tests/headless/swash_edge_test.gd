extends SceneTree
## No GUT dependency: godot --headless --path . --script res://tests/headless/swash_edge_test.gd
## The CPU twin of the swash (SwashEdge): the water height gameplay reads runs up the beach like the
## drawn surface does.

const RUNUP := 0.8
const PERIOD := 7.0
var _failures: int = 0


func _initialize() -> void:
	_check(SwashEdge.state(Vector2(3.0, 4.0), 10.0, 0.0, PERIOD) == Vector4.ZERO, "No run-up, no swash")
	var worst_step := 0.0
	var lowest_reach := INF
	var highest_reach := 0.0
	var previous := SwashEdge.state(Vector2(12.0, -40.0), 0.0, RUNUP, PERIOD)
	for i in range(1, 3000):
		var s := SwashEdge.state(Vector2(12.0, -40.0), i * 0.01, RUNUP, PERIOD)
		_check(s.x >= 0.0 and s.x <= s.y + 1e-6, "The edge never passes this wave's reach")
		worst_step = maxf(worst_step, absf(s.x - previous.x))
		lowest_reach = minf(lowest_reach, s.y)
		highest_reach = maxf(highest_reach, s.y)
		previous = s
	_check(worst_step < 0.02, "The water's edge moves smoothly, also from one wave to the next (step %.4f m)" % worst_step)
	_check(lowest_reach >= ShoreWaves.SWASH_SMALLEST * RUNUP - 1e-6 and highest_reach <= RUNUP + 1e-6,
			"Each wave reaches between the smallest share and all of the run-up")
	_check(highest_reach - lowest_reach > 0.1 * RUNUP, "Waves reach different heights")
	# Same numbers as the shader.
	var code := FileAccess.get_file_as_string("res://world/water/swash.gdshaderinc")
	for constant: String in ["SWASH_UPRUSH_SHARE = %s;" % SwashEdge.UPRUSH_SHARE, "SWASH_SMALLEST = %s;" % ShoreWaves.SWASH_SMALLEST,
			"SWASH_ALONGSHORE = %s;" % ShoreWaves.SWASH_ALONGSHORE, "SWASH_PHASE_SPREAD = %s;" % ShoreWaves.SWASH_PHASE_SPREAD,
			"SWASH_WAVE_STEP = %s;" % ShoreWaves.SWASH_WAVE_STEP]:
		_check(code.contains(constant), "The shader has " + constant)
	print("Swash edge: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(_failures)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		print("  FAIL: ", label)
