extends SceneTree
## No GUT dependency: godot --headless --path . --script res://tests/headless/planar_reflection_test.gd
## The mirror renders linear scene light: the main camera's environment without the post-processing
## the main pass applies to the whole picture (reflection included).

var _failures: int = 0


func _initialize() -> void:
	var main := Environment.new()
	main.tonemap_mode = Environment.TONE_MAPPER_ACES
	main.tonemap_exposure = 1.1
	main.glow_enabled = true
	main.adjustment_enabled = true
	main.fog_enabled = true
	main.fog_density = 0.0123
	main.background_mode = Environment.BG_SKY
	main.sky = Sky.new()
	var mirror := Environment.new()
	PlanarReflection.copy_environment(main, mirror)
	_check(mirror.tonemap_mode == Environment.TONE_MAPPER_LINEAR, "No tone mapping in the mirror")
	_check(is_equal_approx(mirror.tonemap_exposure, 1.0), "No exposure in the mirror")
	_check(not mirror.glow_enabled, "No glow in the mirror")
	_check(not mirror.adjustment_enabled, "No colour adjustment in the mirror")
	_check(mirror.fog_enabled and is_equal_approx(mirror.fog_density, 0.0123), "The mirror keeps the fog")
	_check(mirror.background_mode == Environment.BG_SKY and mirror.sky == main.sky, "The mirror keeps the sky")
	_check(main.tonemap_mode == Environment.TONE_MAPPER_ACES and main.glow_enabled, "The main environment is untouched")
	print("Planar reflection: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(_failures)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		print("  FAIL: ", label)
