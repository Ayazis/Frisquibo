extends SceneTree
## No GUT dependency: godot --headless --path . --script res://tests/headless/shore_runup_test.gd
const TOLERANCE := 0.005
var _failures: int = 0


func _initialize() -> void:
	# Worked by hand from Stockdon et al. (2006): H0 = 1 m, T = 8 s, beach face 1:12.5.
	_near(ShoreRunup.stockdon(1.0, 8.0, 0.08), 0.788, "A 1 m, 8 s sea runs about 0.8 m up a medium beach")
	_check(ShoreRunup.stockdon(2.0, 8.0, 0.08) > ShoreRunup.stockdon(1.0, 8.0, 0.08), "Higher waves run further")
	_check(ShoreRunup.stockdon(1.0, 12.0, 0.08) > ShoreRunup.stockdon(1.0, 8.0, 0.08), "Longer waves run further")
	_check(ShoreRunup.stockdon(1.0, 8.0, 0.15) > ShoreRunup.stockdon(1.0, 8.0, 0.03), "Steeper beaches see more run-up")
	_near(ShoreRunup.stockdon(0.0, 8.0, 0.08), 0.0, "No waves, no run-up")

	var sea := OceanSpectrum.new()
	sea.swell_height = 0.0
	_near(OceanSeaStats.dominant_period(sea), OceanSeaStats.peak_period(sea), "Without swell the wind sea sets the period")
	sea.swell_height = 3.0
	sea.swell_period = 13.0
	_near(OceanSeaStats.dominant_period(sea), 13.0, "A big swell sets the period")
	var ocean := Ocean.new()
	_check(ocean.parameters().any(func(p: OceanParameter) -> bool: return p.name == &"foreshore_slope"),
			"The beach slope is a tunable")
	ocean.free()
	print("Shore run-up: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(_failures)


func _near(actual: float, expected: float, label: String) -> void:
	_check(absf(actual - expected) <= TOLERANCE, "%s (got %.4f, expected %.4f)" % [label, actual, expected])


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		print("  FAIL: ", label)
