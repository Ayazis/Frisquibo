extends SceneTree
## No GUT dependency: godot --headless --path . --script res://tests/headless/water_quality_test.gd
## Every scalable water value grows from Low to Ultra, and High is what code uses by default.
const TIERS: Array[String] = ["low", "medium", "high", "ultra"]
const OCEAN_VALUES: Array[StringName] = [&"cascade_count", &"radial_segments", &"reflection_resolution_scale",
		&"reflection_blur_samples", &"reflection_march_steps", &"underwater_shaft_steps", &"spray_particles",
		&"spray_area", &"breaker_reach", &"breaker_segments", &"breaker_spray"]
const WATER_VALUES: Array[StringName] = [&"ripple_resolution", &"ripple_area", &"splash_particle_scale"]
var _failures: int = 0


func _initialize() -> void:
	_check_tiers("ocean_%s", OCEAN_VALUES)
	_check_tiers("water_%s", WATER_VALUES)
	var high_ocean := load("res://data/quality/ocean_high.tres") as OceanQuality
	_check(UnderwaterView.DEFAULT_SHAFT_STEPS == high_ocean.underwater_shaft_steps, "Lakes' shaft steps are High's")
	_check(PlanarReflection.DEFAULT_BLUR_SAMPLES == high_ocean.reflection_blur_samples, "Lakes' reflection blur is High's")
	var march: Dictionary = ProjectSettings.get_setting("shader_globals/water_ssr_steps")
	var march_steps: int = march.get("value", -1)
	_check(march_steps == high_ocean.reflection_march_steps, "Lakes' reflection march is High's")
	var low_ocean := load("res://data/quality/ocean_low.tres") as OceanQuality
	_check(low_ocean.reflection_march_steps == 0, "Low has no reflection march")
	_check(WaterRipples.DEFAULT_QUALITY.resource_path.ends_with("water_high.tres"), "Ripples default to High")
	var spray := OceanSpray.new(123, 80.0)
	_check(spray.amount == 123 and not spray.local_coords, "Spray: given droplets, flying in world space")
	_check(spray.process_shader_material.shader != null, "Spray has its particle shader")
	spray.free()
	print("Water quality: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(_failures)


func _check_tiers(pattern: String, values: Array[StringName]) -> void:
	var previous: Resource = null
	for tier: String in TIERS:
		var current := load("res://data/quality/%s.tres" % (pattern % tier))
		_check(current != null, "Tier %s loads" % (pattern % tier))
		if previous != null and current != null:
			for key: StringName in values:
				var before: Variant = previous.get(key)
				var now: Variant = current.get(key)
				_check(_number(now) >= _number(before), "%s: %s does not shrink from the tier below" % [pattern % tier, key])
		previous = current


func _number(value: Variant) -> float:
	if value is int:
		var whole: int = value
		return float(whole)
	var real: float = value
	return real


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		print("  FAIL: ", label)
