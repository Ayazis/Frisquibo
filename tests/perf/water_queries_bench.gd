extends SceneTree
## Times the CPU side of the FFT ocean, which headless runs can't reach through a scene (no
## RenderingDevice, so the Ocean falls back to Gerstner waves): the water height that floating objects
## read per probe, the shore waves, the breaker query, and the per-frame work of the rules and the
## breaker effects. The Ocean is set up by hand around a height field of fixed pseudo-random waves, over
## the water demo's island.
##   godot --headless --path . --script res://tests/perf/water_queries_bench.gd
## REF_OUT=<file> also writes exact results at many points, to diff before and after an optimisation
## that must not change them.

const SPECTRUM := preload("res://world/water/ocean/presets/fresh_breeze.tres")
const QUALITY := preload("res://data/quality/ocean_high.tres")
const RULES := preload("res://world/water/ocean/rules/presets/coastal_rules.tres")
## The water demo's seabed (IslandScene.SEABED_SIZE / SEABED_RESOLUTION).
const SEABED_SIZE := 1200.0
const SEABED_RESOLUTION := 768
## Tile lengths of the four cascades, about those of the fresh breeze, and the waves' size in them.
const TILES: Array[float] = [250.0, 70.0, 17.0, 5.0]
const WAVE_RANGE := 0.5
const SEED := 42
const QUERIES := 2000
const FRAMES := 200
## Points on the island's south coast: (direction in degrees, metres off the coast).
const BEACH := Vector2(-90.0, -4.0)
const SURF := Vector2(-90.0, 30.0)
const OPEN_SEA := Vector2(-120.0, 520.0)
const OUTSIDE_SEABED := Vector2(2000.0, 2000.0)
## Spread of the query points around each place, so they don't hit one texel.
const JITTER := 0.3
## Reference output: points round the coast and how far apart.
const REFERENCE_POINTS := 400
const REFERENCE_DEGREES := 0.9
const REFERENCE_OFFSHORE := Vector2(-6.0, 1.5)
const REFERENCE_ROWS := 40
const REFERENCE_BREAKER_EVERY := 4
const REFERENCE_TIME := 3.7
const WIND := Vector2(5.0, 0.0)
const FRAME_TIME := 1.0 / 60.0

var _ocean: Ocean
var _terrain := IslandTerrain.new()


func _initialize() -> void:
	var t0 := Time.get_ticks_usec()
	_build_ocean()
	print("Set-up (seabed, shore field, rays): %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	var reference := OS.get_environment("REF_OUT")
	if reference != "":
		_write_reference(reference)
	print("Ocean.height_at, per query:")
	_time_height("  beach", _coast(BEACH))
	_time_height("  surf zone", _coast(SURF))
	_time_height("  open sea", _coast(OPEN_SEA))
	_time_height("  outside the seabed", OUTSIDE_SEABED)
	var shore: ShoreWaves = _ocean.get("_shore")
	var still_depth := Callable(_ocean, "_still_depth")
	var surf := _coast(SURF)
	t0 = Time.get_ticks_usec()
	for i in range(QUERIES):
		shore.height_at(surf + _jitter(i), still_depth)
	print("ShoreWaves.height_at: %.1f us" % (float(Time.get_ticks_usec() - t0) / QUERIES))
	var breakers: BreakerSystem = _ocean.get("_breakers")
	t0 = Time.get_ticks_usec()
	for i in range(QUERIES):
		breakers.query.at_crest(surf + _jitter(i), float(i % 3))
	print("ShoreBreakers.at_crest: %.1f us" % (float(Time.get_ticks_usec() - t0) / QUERIES))
	print("Per frame:")
	t0 = Time.get_ticks_usec()
	for i in range(FRAMES):
		_ocean.call("_update_rules", false)
	print("  Ocean rules: %.2f ms" % (float(Time.get_ticks_usec() - t0) / FRAMES / 1000.0))
	t0 = Time.get_ticks_usec()
	for i in range(FRAMES):
		breakers.update(_coast(BEACH), i * FRAME_TIME, shore.period, WIND)
	print("  Breakers, camera on the beach: %.2f ms" % (float(Time.get_ticks_usec() - t0) / FRAMES / 1000.0))
	quit(0)


## An Ocean on the FFT path without a GPU: the private height field filled by hand.
func _build_ocean() -> void:
	_ocean = Ocean.new()
	_ocean.spectrum = SPECTRUM.duplicate() as OceanSpectrum
	_ocean.quality = QUALITY
	_ocean.rules = RULES
	_ocean.material = ShaderMaterial.new()
	_ocean.set("_effective", _ocean.spectrum.duplicate())
	var field := OceanHeightField.new(OceanSimulation.MAP_SIZE, PackedFloat32Array(TILES))
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var texels := OceanSimulation.MAP_SIZE * OceanSimulation.MAP_SIZE
	for c in range(TILES.size()):
		var bytes := PackedByteArray()
		bytes.resize(texels * OceanHeightField.BYTES_PER_TEXEL)
		for i in range(texels * OceanHeightField.BYTES_PER_TEXEL / OceanHeightField.BYTES_PER_CHANNEL):
			bytes.encode_half(i * OceanHeightField.BYTES_PER_CHANNEL, rng.randf_range(-WAVE_RANGE, WAVE_RANGE))
		field.set_cascade(c, bytes)
	_ocean.set("_height_field", field)
	_ocean.call("_update_rules", true)
	var half := SEABED_SIZE / 2.0
	_ocean.set_seabed(_terrain.height, Rect2(-half, -half, SEABED_SIZE, SEABED_SIZE), SEABED_RESOLUTION)
	_ocean.call("_apply_shore_waves")


func _write_reference(path: String) -> void:
	var shore: ShoreWaves = _ocean.get("_shore")
	shore.time = REFERENCE_TIME
	var breakers: BreakerSystem = _ocean.get("_breakers")
	var lines := PackedStringArray()
	for i in range(REFERENCE_POINTS):
		var p := _coast(Vector2(i * REFERENCE_DEGREES,
				REFERENCE_OFFSHORE.x + (i % REFERENCE_ROWS) * REFERENCE_OFFSHORE.y))
		var damping: float = _ocean.call("_damping_at", p)
		lines.append("%d %.9f %.9f" % [i, _ocean.height_at(p), damping])
		if i % REFERENCE_BREAKER_EVERY == 0:
			var s := breakers.query.at(p)
			lines.append("breaker %.9f %.9f %.9f %.9f %s" % [s.stage, s.plunge, s.fold, s.crest, s.tip])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Can't write %s" % path)
		return
	file.store_string("\n".join(lines))
	print("Reference written to %s" % path)


func _time_height(label: String, at: Vector2) -> void:
	var t0 := Time.get_ticks_usec()
	for i in range(QUERIES):
		_ocean.height_at(at + _jitter(i))
	print("%s: %.1f us" % [label, float(Time.get_ticks_usec() - t0) / QUERIES])


## (direction in degrees, metres off the coast) as a world point.
func _coast(place: Vector2) -> Vector2:
	var angle := deg_to_rad(place.x)
	var r := _terrain.coast_radius(angle) + place.y
	return Vector2(cos(angle), sin(angle)) * r


func _jitter(i: int) -> Vector2:
	return Vector2(i % 7, i % 5) * JITTER
