extends SceneTree
## No GUT dependency: godot --headless --path . --script res://tests/headless/shore_waves_test.gd
## The shore field (travel times over the seabed) and the shore waves built on it.

const SLOPE := 0.05
const AREA := Rect2(-20.0, -100.0, 300.0, 200.0)
## The fast marching solution is first-order and the speed is singular at the waterline: the first
## cells arrive a little early, so absolute times are within this share of the exact ones...
const TIME_TOLERANCE := 0.1
## ...while times between two points offshore (what sets the wavelength there) are within this share.
const SPAN_TOLERANCE := 0.04
## Island: a cone whose waterline is a circle of this radius, sloping as SLOPE.
const ISLAND_RADIUS := 60.0
const ISLAND_AREA := Rect2(-200.0, -200.0, 400.0, 400.0)
## The demo island's seabed (1200 m square) must bake fast enough to do at load.
const MAX_BAKE_MS := 3000
var _failures: int = 0


func _initialize() -> void:
	_check_hash()
	_check_straight_beach()
	_check_island()
	_check_waves()
	_check_island_demo_bake()
	_check_ocean_surface()
	print("Shore waves: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(_failures)


## The CPU hash must be the shader's 32-bit integer hash, bit for bit (values worked out with uint32
## arithmetic outside Godot).
func _check_hash() -> void:
	_near(ShoreWaves.hash(Vector2(0.0, 0.0)), 0.7255859377, 1e-9, "Hash of (0, 0)")
	_near(ShoreWaves.hash(Vector2(-7.0, 3.0)), 0.1132742311, 1e-9, "Hash of (-7, 3)")
	_near(ShoreWaves.hash(Vector2(123.0, -456.0)), 0.7312030857, 1e-9, "Hash of (123, -456)")


## A straight beach along z, deepening seawards (+x) by SLOPE. Shallow-water waves take
## T(x) = 2 sqrt(x / (g s)) to reach the waterline from x metres out.
func _check_straight_beach() -> void:
	var field := ShoreField.bake(func(p: Vector2) -> float: return p.x * SLOPE, AREA)
	for x: float in [20.0, 60.0, 120.0, 200.0]:
		var depth := x * SLOPE
		if depth > ShoreField.MAX_DEPTH:
			continue
		var exact := 2.0 * sqrt(x / (ShoreField.GRAVITY * SLOPE))
		var f := field.sample(Vector2(x, 0.0))
		_check(absf(f.r - exact) <= exact * TIME_TOLERANCE,
				"Travel time %.0f m out (got %.2f s, expected %.2f s)" % [x, f.r, exact])
		_check(f.g > 0.0 and absf(f.b) < f.g * 0.05, "Crests run parallel to a straight beach (%.0f m)" % x)
		_near(Vector2(f.g, f.b).length(), 1.0 / ShoreField.wave_speed(depth), 0.12 / ShoreField.wave_speed(depth),
				"Slowness is 1 / sqrt(g h) at %.0f m" % x)
	var span := field.sample(Vector2(160.0, 0.0)).r - field.sample(Vector2(40.0, 0.0)).r
	var exact_span := 2.0 * (sqrt(160.0) - sqrt(40.0)) / sqrt(ShoreField.GRAVITY * SLOPE)
	_check(absf(span - exact_span) <= exact_span * SPAN_TOLERANCE,
			"Travel time from 160 m to 40 m out (got %.2f s, expected %.2f s)" % [span, exact_span])
	_check(field.origin(Vector2(100.0, 17.0)).distance_to(Vector2(0.0, 17.0)) < 3.0,
			"A wave heads for the waterline straight ahead of it")
	_check(field.sample(Vector2(-10.0, 0.0)).a < 0.5, "Land away from the water has no field")
	var deep_x := (ShoreField.MAX_DEPTH + 2.0) / SLOPE
	_check(field.sample(Vector2(deep_x + 10.0, 0.0)).a < 0.5, "Water well past MAX_DEPTH is left out")


## Around a conical island the crests are circles: waves arrive straight at every bit of the shore.
func _check_island() -> void:
	var field := ShoreField.bake(func(p: Vector2) -> float: return (p.length() - ISLAND_RADIUS) * SLOPE, ISLAND_AREA)
	for degrees: float in [0.0, 45.0, 130.0, 250.0]:
		var outward := Vector2.from_angle(deg_to_rad(degrees))
		var f := field.sample(outward * (ISLAND_RADIUS + 50.0))
		var gradient := Vector2(f.g, f.b).normalized()
		_check(gradient.dot(outward) > 0.97, "Waves head straight for the island at %.0f degrees" % degrees)


func _check_waves() -> void:
	var waves := ShoreWaves.new()
	waves.field = ShoreField.bake(func(p: Vector2) -> float: return p.x * SLOPE, AREA)
	waves.amplitude = 0.8
	waves.period = 8.0
	waves.direction = Vector2(-1.0, 0.0)
	_near(waves.weight(20.0), 0.0, 1e-6, "No shore waves offshore")
	_near(waves.open_sea_share(20.0), 1.0, 1e-6, "The open sea keeps all its waves offshore")
	_check(waves.weight(2.0) > 0.99, "Full shore waves well inside the zone")
	_near(waves.open_sea_share(2.0), sqrt(1.0 - waves.share), 1e-3, "Energy is shared, not added")
	var highest := 0.0
	var steps := 64
	for i in range(steps):
		waves.time = waves.period * float(i) / steps
		for x: float in [4.0, 10.0, 30.0, 80.0]:
			var d := waves.displacement(Vector2(x, 0.0), x * SLOPE)
			_check(d.y <= waves.breaker_ratio * x * SLOPE + 1e-4, "Crests never exceed the depth limit")
			highest = maxf(highest, d.y)
	_check(highest > 0.05, "Shore waves have height (%.2f m)" % highest)
	# A crest travels shorewards: it passes 36 m out before 32 m out, as late as the travel times say.
	var outer := _crest_time(waves, 36.0)
	var inner := _crest_time(waves, 32.0)
	var delay := fposmod(inner - outer, waves.period)
	var expected := waves.field.sample(Vector2(36.0, 0.0)).r - waves.field.sample(Vector2(32.0, 0.0)).r
	_near(delay, expected, 0.6, "Crests move towards the beach at the shallow-water speed")
	# The surface is continuous in time, also where one wave's size hands over to the next.
	var worst := 0.0
	for i in range(2000):
		var t := 0.01 * i
		waves.time = t
		var h0 := waves.displacement(Vector2(40.0, 3.0), 2.0).y
		waves.time = t + 0.001
		var h1 := waves.displacement(Vector2(40.0, 3.0), 2.0).y
		worst = maxf(worst, absf(h1 - h0))
	_check(worst < 0.01, "No jumps in the shore waves over time (largest step %.4f m in 1 ms)" % worst)
	var still := func(p: Vector2) -> float: return p.x * SLOPE
	waves.time = 3.0
	var h := waves.height_at(Vector2(40.0, 0.0), still)
	_check(absf(h) <= waves.breaker_ratio * 40.0 * SLOPE + 0.05, "height_at stays within the waves")


## Time within one period at which the crest passes `x` (the highest point of the cycle there).
func _crest_time(waves: ShoreWaves, x: float) -> float:
	var best := -INF
	var at := 0.0
	for i in range(800):
		waves.time = waves.period * float(i) / 800.0
		var h := waves.displacement(Vector2(x, 0.0), x * SLOPE).y
		if h > best:
			best = h
			at = waves.time
	return at


func _check_island_demo_bake() -> void:
	var terrain := IslandTerrain.new()
	var start := Time.get_ticks_msec()
	var field := ShoreField.bake(func(p: Vector2) -> float: return IslandTerrain.SEA_LEVEL - terrain.height.call(p.x, p.y),
			Rect2(-600.0, -600.0, 1200.0, 1200.0))
	var elapsed := Time.get_ticks_msec() - start
	print("  Island shore field: %d x %d texels in %d ms" % [field.width, field.height, elapsed])
	_check(elapsed < MAX_BAKE_MS, "The island's shore field bakes in under %d ms (%d ms)" % [MAX_BAKE_MS, elapsed])
	var coast := terrain.coast_radius(0.0)
	_check(field.sample(Vector2(coast + 40.0, 0.0)).a > 0.5, "The field covers the island's shallows")


## The surface shader carries the shore waves and the ocean exposes their tunables.
func _check_ocean_surface() -> void:
	var names: Array[StringName] = []
	for uniform: Dictionary in Ocean.SURFACE_SHADER.get_shader_uniform_list():
		var uniform_name: String = uniform.name
		names.append(StringName(uniform_name))
	for expected: StringName in [&"shore_field", &"shore_wave_depth", &"shore_wave_share", &"shore_wave_direction"]:
		_check(expected in names, "The ocean surface has uniform " + expected)
	var ocean := Ocean.new()
	for parameter: StringName in [&"shore_wave_depth", &"shore_wave_share", &"shore_lee_share"]:
		_check(ocean.parameters().any(func(p: OceanParameter) -> bool: return p.name == parameter),
				"Tunable: " + parameter)
	ocean.free()


func _near(actual: float, expected: float, tolerance: float, label: String) -> void:
	_check(absf(actual - expected) <= tolerance, "%s (got %.6f, expected %.6f)" % [label, actual, expected])


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		print("  FAIL: ", label)
