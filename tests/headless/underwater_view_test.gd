extends SceneTree
## No GUT dependency: godot --headless --path . --script res://tests/headless/underwater_view_test.gd
var _failures: int = 0


func _initialize() -> void:
	# The root only enters the tree once the main loop runs.
	_run.call_deferred()


func _run() -> void:
	var view := UnderwaterView.new()
	root.add_child(view)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.global_position = Vector3(0.0, 5.0, 0.0)
	view.follow(cam, 0.0, 0.0, 1.0, 1.0)
	_check(not view.is_active(), "Off well above the water")
	cam.global_position = Vector3(0.0, 0.5, 0.0)
	view.follow(cam, 0.0, 0.0, 1.0, 1.0)
	_check(view.is_active(), "On when a wave can reach the lens")
	cam.global_position = Vector3(3.0, -4.0, 2.0)
	view.follow(cam, 0.2, 0.0, 0.6, 1.0)
	_check(view.is_active(), "On under water")
	var level: float = view.material.get_shader_parameter("surface_level")
	var scale: float = view.material.get_shader_parameter("wave_scale")
	_check(is_equal_approx(level, 0.0) and is_equal_approx(scale, 0.6), "Rest level and wave scale reach the shader")
	view.follow(null, 0.0, 0.0, 0.0, 0.0)
	_check(not view.is_active(), "Off without a camera")
	view.set_optics(Vector3(1.0, 0.5, 0.25), Color(0.1, 0.2, 0.3))
	var absorbed: Vector3 = view.material.get_shader_parameter("absorption")
	_check(absorbed.is_equal_approx(Vector3(1.0, 0.5, 0.25)), "Absorption reaches the shader")
	_check(view.material.render_priority < 0, "Draws before the water surface")

	var sea := Sea.new()
	sea.size = 20.0
	sea.subdivisions = 4
	sea.planar_reflection = false
	root.add_child(sea)
	var found := false
	for child: Node in sea.get_children():
		found = found or child is UnderwaterView
	_check(found, "A lake gets an underwater view")
	print("Underwater view: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(_failures)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		print("  FAIL: ", label)
