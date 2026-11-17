extends SceneTree
## No GUT dependency: godot --headless --path . --script res://tests/headless/breakers_test.gd
## Plunging breakers on the CPU: waterlines, wave rays, the ribbons near the camera, the breaker query
## and the landing signal. The look (the curl, spray, mist) needs a desktop GPU.

const SLOPE := 0.06
const AREA := Rect2(-40.0, -150.0, 340.0, 300.0)
const ISLAND_RADIUS := 60.0
const ISLAND_AREA := Rect2(-200.0, -200.0, 400.0, 400.0)
## A 0.6 m sea at 7 s on a 1:17 beach plunges (surf similarity about 0.7).
const AMPLITUDE := 0.3
const PERIOD := 7.0
const SIMULATED_SECONDS := 40.0
const FRAME := 0.1
## Deepest water the test's waves may break in (m).
const BREAK_DEPTH := 1.5
var _failures: int = 0


func _initialize() -> void:
	_check_waterlines()
	_check_rays()
	_check_ribbons()
	_check_breakers()
	_check_tiers()
	print("Breakers: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(_failures)


func _beach(p: Vector2) -> float:
	return p.x * SLOPE


func _island(p: Vector2) -> float:
	return (p.length() - ISLAND_RADIUS) * SLOPE


func _check_waterlines() -> void:
	var beach := ShoreField.bake(_beach, AREA)
	_check(beach.waterlines.size() == 1, "One waterline along a straight beach (%d)" % beach.waterlines.size())
	if beach.waterlines.size() == 1:
		var line := beach.waterlines[0]
		var off_line := 0.0
		for p: Vector2 in line:
			off_line = maxf(off_line, absf(p.x))
		_check(off_line < 0.5, "It lies on the waterline (x = 0; worst %.2f m)" % off_line)
		_check(line[0].distance_to(line[line.size() - 1]) > AREA.size.y * 0.9, "It runs the length of the beach")
	var island := ShoreField.bake(_island, ISLAND_AREA)
	_check(island.waterlines.size() == 1, "One waterline round an island")
	if island.waterlines.size() == 1:
		var ring := island.waterlines[0]
		_check(ring[0].distance_to(ring[ring.size() - 1]) < 0.01, "...closed")
		var length := 0.0
		for i in range(1, ring.size()):
			length += ring[i - 1].distance_to(ring[i])
		_near(length, TAU * ISLAND_RADIUS, TAU * ISLAND_RADIUS * 0.03, "...as long as the island's coast")


func _check_rays() -> void:
	var field := ShoreField.bake(_beach, AREA)
	var rays := ShoreRays.trace(field, _beach)
	_check(rays.rows > 200, "A ray every metre of the beach (%d)" % rays.rows)
	var row := rays.rows / 2
	var start := rays.position(row, rays.start_time(row))
	var later := rays.position(row, rays.start_time(row) + 10.0)
	_check(later.x > start.x + 5.0 and absf(later.y - start.y) < 1.0, "Rays run straight out to sea off a straight beach")
	_near(field.sample(later).r, rays.start_time(row) + 10.0, 0.15, "A ray is where the field's clock says")
	var island := ShoreRays.trace(ShoreField.bake(_island, ISLAND_AREA), _island)
	_check(island.line_closed.size() == 1 and island.line_closed[0], "The island's rays wrap round")
	var outward := island.position(10, island.start_time(10) + 12.0)
	var at_shore := island.position(10, island.start_time(10))
	_check(outward.normalized().dot(at_shore.normalized()) > 0.99 and outward.length() > at_shore.length() + 10.0,
			"Rays leave a round island radially")
	# Rays fan out from a round island: more are traced between them, so neighbours stay close.
	_check(island.rows > TAU * ISLAND_RADIUS / ShoreRays.SPACING + 10.0,
			"Rays are added where they fan apart (%d)" % island.rows)
	var widest := 0.0
	for k in range(island.rows):
		widest = maxf(widest, island.gap(k, (k + 1) % island.rows))
	_check(widest <= ShoreRays.MAX_GAP, "...so neighbours stay within %.1f m where curls form (%.2f)" % [ShoreRays.MAX_GAP, widest])


func _check_ribbons() -> void:
	var field := ShoreField.bake(_island, ISLAND_AREA)
	var rays := ShoreRays.trace(field, _island)
	var material := ShaderMaterial.new()
	material.shader = Ocean.SURFACE_SHADER
	var reach := 50.0
	var ribbons := OceanBreakers.new(rays, material, reach, 16, AABB(Vector3(-200, -20, -200), Vector3(400, 40, 400)))
	var mesh := ribbons.ribbon_mesh(10, 4)
	_check(mesh.get_faces().size() == 9 * 4 * 2 * 3, "A ribbon is rows x segments quads")
	# A camera on the island's shore at angle 0: a stretch of coast round it gets ribbons, wrapping past
	# the end of the waterline.
	ribbons.update(Vector2(ISLAND_RADIUS + 5.0, 0.0), 100.0, PERIOD, BREAK_DEPTH)
	_check(not ribbons.active.is_empty(), "Ribbons near the camera")
	var waves := {}
	for lay: Vector4 in ribbons.active:
		_check(lay.y <= ribbons.rows_per_ribbon(), "A ribbon is no longer than its mesh")
		waves[int(lay.z)] = true
	_check(waves.size() >= 2, "Several crests can be breaking at once (%d)" % waves.size())
	# A stretch longer than a ribbon is split into ribbons that share their end rows.
	var last_rows: Dictionary[int, int] = {}
	var shared := true
	for lay: Vector4 in ribbons.active:
		var wave := int(lay.z)
		if last_rows.has(wave) and last_rows[wave] != int(lay.x):
			shared = false
		last_rows[wave] = ribbons.row_after(int(lay.x), int(lay.y) - 1)
	_check(shared, "Ribbons along one crest share their end rows")
	var far := OceanBreakers.new(rays, material, reach, 16, AABB())
	far.update(Vector2(500.0, 500.0), 100.0, PERIOD, BREAK_DEPTH)
	_check(far.active.is_empty(), "No ribbons far from the coast")
	_check(far.covered.x > far.covered.y, "...and no crest the ocean should leave a hole for")
	_check(ribbons.covered.x <= ribbons.covered.y, "The crests near the camera are covered by ribbons")
	var deeper := OceanBreakers.new(rays, material, reach, 16, AABB())
	deeper.update(Vector2(ISLAND_RADIUS + 5.0, 0.0), 100.0, PERIOD, 2.0 * BREAK_DEPTH)
	_check(deeper.active.size() >= ribbons.active.size(), "Waves that break further out get ribbons further out")
	deeper.free()
	ribbons.free()
	far.free()


func _check_breakers() -> void:
	var shore := ShoreWaves.new()
	shore.field = ShoreField.bake(_beach, AREA)
	shore.amplitude = AMPLITUDE
	shore.period = PERIOD
	shore.direction = Vector2.LEFT
	var query := ShoreBreakers.new()
	query.waves = shore
	query.depth_at = _beach
	query.still_at = _beach
	# Somewhere along the crests a breaker plunges: its lip flies ahead of the crest and comes down.
	var plunging := 0
	var best := BreakerState.new()
	for x in range(2, 60):
		for wave in range(3):
			var state := query.at_crest(Vector2(x * 0.5, 0.0), wave)
			if state.fold > 0.5 and state.stage > 0.3 and state.stage < 1.0:
				plunging += 1
				best = state
	_check(plunging > 0, "Waves of this sea plunge on this beach")
	if plunging > 0:
		_check(best.tip.x < best.crest_rest.x, "The lip flies ahead of the crest, towards the shore")
		_check(best.tip_velocity.x < 0.0 and best.tip_velocity.y <= 0.0, "...forwards and down")
		_check(best.landing.y < best.tip.y + 1e-4, "...and lands below where it is")
	query.curl_strength = 0.0
	_check(query.at_crest(Vector2(10.0, 0.0), 0.0).fold == 0.0, "Curl strength 0: all breakers spill")
	query.curl_strength = 1.0
	# Over time lips land, and the ribbons' effects say so (for sound).
	var rays := ShoreRays.trace(shore.field, _beach)
	var material := ShaderMaterial.new()
	material.shader = Ocean.SURFACE_SHADER
	var bounds := AABB(Vector3(-40, -20, -150), Vector3(340, 40, 300))
	var ribbons := OceanBreakers.new(rays, material, 60.0, 8, bounds)
	var effects := BreakerEffects.new(ribbons, rays, query, 0, false, bounds)
	var landings: Array[Vector3] = []
	effects.plunged.connect(func(at: Vector3, _height: float) -> void: landings.append(at))
	var t := 0.0
	while t < SIMULATED_SECONDS:
		shore.time = t
		ribbons.update(Vector2(5.0, 0.0), t, PERIOD, BREAK_DEPTH)
		effects.update(t, PERIOD, Vector2.ZERO)
		t += FRAME
	_check(landings.size() > 0, "Lips land, and the landing is signalled (%d)" % landings.size())
	if landings.size() > 0:
		_check(landings[0].x > 0.0 and landings[0].x < 40.0, "...in the surf zone (%.1f m out)" % landings[0].x)
	# A point query finds the breaker a spot belongs to.
	var any_tube := false
	for step in range(0, 60):
		shore.time = step * 0.25
		for x in range(0, 120):
			any_tube = any_tube or query.at(Vector2(x * 0.25, 0.0)).inside_tube
	_check(any_tube or plunging == 0, "Some spot is inside a tube at some moment")
	ribbons.free()
	effects.free()


func _check_tiers() -> void:
	var low := load("res://data/quality/ocean_low.tres") as OceanQuality
	var high := load("res://data/quality/ocean_high.tres") as OceanQuality
	_check(low.breaker_reach == 0.0, "Low has no curls")
	_check(high.breaker_reach > 0.0 and high.breaker_segments >= 32, "High has curls with enough detail")
	var ocean := Ocean.new()
	_check(ocean.parameters().any(func(p: OceanParameter) -> bool: return p.name == &"curl_strength"),
			"Curl strength is a tunable")
	_check(ocean.breaker_at(Vector2.ZERO).stage < 0.0, "No breakers without a seabed")
	ocean.free()


func _near(actual: float, expected: float, tolerance: float, label: String) -> void:
	_check(absf(actual - expected) <= tolerance, "%s (got %.4f, expected %.4f)" % [label, actual, expected])


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		print("  FAIL: ", label)
