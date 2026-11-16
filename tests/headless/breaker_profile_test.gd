extends SceneTree
## No GUT dependency: godot --headless --path . --script res://tests/headless/breaker_profile_test.gd
## The plunging breaker's curl: which waves plunge, when, and the shape of the folded sheet.

const CREST := 0.4
const TROUGH := 3.0
const STEPS := 400
var _failures: int = 0


func _initialize() -> void:
	_check_types()
	_check_stage()
	_check_sheet()
	_check_shader_twin()
	print("Breaker profile: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(_failures)


## Battjes (1974): breaker type from the surf similarity number.
func _check_types() -> void:
	# A 0.5 m, 6 s wave on a 1:14 beach (the demo island's shallows): xi = 0.07 / sqrt(0.5 / 56.2) = 0.74.
	var xi := BreakerProfile.surf_similarity(0.07, 0.5, 6.0)
	_near(xi, 0.742, 0.01, "Surf similarity of a small wave on the island's shallows")
	_near(BreakerProfile.plunge_share(xi, 1.0), 1.0, 1e-6, "...which plunges")
	var storm := BreakerProfile.surf_similarity(0.02, 2.0, 8.0)
	_check(storm < 0.3 and BreakerProfile.plunge_share(storm, 1.0) == 0.0, "A big sea on a flat beach spills (xi %.2f)" % storm)
	var surge := BreakerProfile.surf_similarity(0.3, 0.3, 10.0)
	_check(surge > 3.3 and BreakerProfile.plunge_share(surge, 1.0) == 0.0, "Long swell on a steep beach surges (xi %.2f)" % surge)
	_near(BreakerProfile.plunge_share(xi, 0.5), 0.5, 1e-6, "Curl strength scales the plunge")


func _check_stage() -> void:
	_check(BreakerProfile.stage(1.0, 0.9, 0.05, 0.39) < 0.0, "Not breaking below the depth limit")
	var early := BreakerProfile.stage(1.0, 1.05, 0.05, 0.39)
	var later := BreakerProfile.stage(0.8, 1.05 * pow(1.0 / 0.8, 1.25), 0.05, 0.39)
	_check(early >= 0.0 and later > early, "The stage grows as the crest runs into shallower water (%.2f, %.2f)" % [early, later])
	_near(BreakerProfile.breaking_depth(0.8, pow(1.0 / 0.8, 1.25)), 1.0, 1e-4, "The breaking depth is found back")
	_near(BreakerProfile.fold(-1.0, 1.0), 0.0, 1e-6, "No fold before breaking")
	_near(BreakerProfile.fold(0.8, 1.0), 1.0, 1e-6, "Full fold while the lip flies")
	_near(BreakerProfile.fold(3.0, 1.0), 0.0, 1e-6, "The tube has collapsed into a bore")
	_near(BreakerProfile.fold(0.8, 0.0), 0.0, 1e-6, "Spilling waves don't fold")


func _check_sheet() -> void:
	var start := BreakerProfile.curve(0.0, 0.7, CREST, TROUGH)
	_check(Vector2(start.x, start.y).is_equal_approx(Vector2(0.0, CREST)), "The sheet starts at the crest")
	var end := BreakerProfile.curve(1.0, 0.7, CREST, TROUGH)
	_check(Vector2(end.x, end.y).distance_to(Vector2(TROUGH, -CREST)) < 0.01, "...and ends in the trough ahead")
	# Continuous along the sheet and in time.
	var worst := 0.0
	var worst_time := 0.0
	for i in range(STEPS):
		var phi := float(i) / STEPS
		var a := BreakerProfile.curve(phi, 0.7, CREST, TROUGH)
		var b := BreakerProfile.curve(phi + 1.0 / STEPS, 0.7, CREST, TROUGH)
		worst = maxf(worst, Vector2(a.x, a.y).distance_to(Vector2(b.x, b.y)))
		var c := BreakerProfile.curve(phi, 0.701, CREST, TROUGH)
		worst_time = maxf(worst_time, Vector2(a.x, a.y).distance_to(Vector2(c.x, c.y)))
	_check(worst < 0.1, "No gaps along the sheet (largest step %.3f m)" % worst)
	_check(worst_time < 0.02, "The sheet moves smoothly (largest move %.4f m per 0.001 stage)" % worst_time)
	# The lip tip lands in the trough after one flight time.
	var tip := _part_end(BreakerProfile.Part.OUTER_LIP, 1.0)
	_near(tip.y, -CREST, 0.02, "The lip lands in the trough")
	_check(tip.x > 0.0 and tip.x < TROUGH, "...ahead of the crest, before the next trough")
	var halfway := _part_end(BreakerProfile.Part.OUTER_LIP, 0.5)
	_near(halfway.y, CREST - 2.0 * CREST * 0.25, 0.02, "Half way through its flight it has fallen a quarter (ballistic)")
	# Normals: up on top of the lip, down under it, towards the shore on the tube's back wall.
	_check(_normal_on(BreakerProfile.Part.OUTER_LIP, 0.1).y > 0.7, "The top of the lip faces up")
	_check(_normal_on(BreakerProfile.Part.CEILING, 0.7).y < -0.5, "The tube's ceiling faces down")
	_check(_normal_on(BreakerProfile.Part.BACK_WALL, 0.5).x > 0.5, "The tube's back wall faces the shore")
	_check(_normal_on(BreakerProfile.Part.TROUGH, 0.9).y > 0.9, "The trough faces up")
	# After landing, the water splashes up where the lip came down.
	var splashed := 0.0
	for i in range(STEPS):
		var p := BreakerProfile.curve(float(i) / STEPS, 1.2, CREST, TROUGH)
		if int(p.z) == BreakerProfile.Part.TROUGH:
			splashed = maxf(splashed, p.y + CREST)
	_check(splashed > 0.5 * BreakerProfile.SPLASH_HEIGHT * CREST, "Splash-up where the lip lands (%.2f m)" % splashed)


## The shader carries the same numbers.
func _check_shader_twin() -> void:
	var code := FileAccess.get_file_as_string("res://world/water/ocean/breakers/ocean_breakers.gdshaderinc")
	for constant: String in ["LIP_REACH = %s;" % BreakerProfile.LIP_REACH, "ROOT_THICKNESS = %s;" % BreakerProfile.ROOT_THICKNESS,
			"TIP_THICKNESS = %s;" % BreakerProfile.TIP_THICKNESS, "SPLASH_HEIGHT = %s;" % BreakerProfile.SPLASH_HEIGHT,
			"LIP_GROW = %s;" % BreakerProfile.LIP_GROW, "BACK_WALL = %s;" % BreakerProfile.BACK_WALL]:
		_check(code.contains(constant), "The shader twin has " + constant)


func _part_end(part: int, breaker_stage: float) -> Vector2:
	var last := Vector2.ZERO
	for i in range(STEPS * 4 + 1):
		var p := BreakerProfile.curve(float(i) / (STEPS * 4), breaker_stage, CREST, TROUGH)
		if int(p.z) == part:
			last = Vector2(p.x, p.y)
	return last


func _normal_on(part: int, share: float) -> Vector2:
	for i in range(STEPS * 4 + 1):
		var phi := float(i) / (STEPS * 4)
		var p := BreakerProfile.curve(phi, 0.8, CREST, TROUGH)
		if int(p.z) == part and p.z - part >= share:
			return BreakerProfile.normal(phi, 0.8, CREST, TROUGH)
	return Vector2.ZERO


func _near(actual: float, expected: float, tolerance: float, label: String) -> void:
	_check(absf(actual - expected) <= tolerance, "%s (got %.4f, expected %.4f)" % [label, actual, expected])


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		print("  FAIL: ", label)
