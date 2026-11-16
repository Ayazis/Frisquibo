extends SceneTree
## No GUT dependency: godot --headless --path . --script res://tests/headless/water_ripples_test.gd
## The simulation itself runs in a shader; this checks what feeds it.
var _failures: int = 0
var _ripples: WaterRipples
var _body: Node3D
var _frames: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(WaterRipples.find(self) == null, "No ripples before a water body makes them")
	_ripples = WaterRipples.new()
	root.add_child(_ripples)
	# Each step hands the queued disturbances to the shader; keep them here to look at.
	_ripples.set_process(false)
	_check(WaterRipples.find(self) == _ripples, "Found through its group")
	var area := _ripples.area()
	_check(is_equal_approx(area.z, _ripples.quality.ripple_area), "Area is the quality tier's size")
	_check(is_equal_approx(area.x + area.z * 0.5, 0.0), "Area is centred on the camera (none yet: the origin)")
	for i in range(WaterRipples.MAX_SOURCES):
		_ripples.disturb(Vector3(i, 0.0, 0.0), 1.0, 0.01)
	_ripples.disturb(Vector3(99.0, 0.0, 0.0), 1.0, 0.5)
	_ripples.disturb(Vector3(98.0, 0.0, 0.0), 1.0, 0.001)
	_check(_ripples._sources.size() == WaterRipples.MAX_SOURCES, "At most MAX_SOURCES per step")
	var strongest_kept := false
	var weakest_dropped := true
	for s: Vector4 in _ripples._sources:
		strongest_kept = strongest_kept or is_equal_approx(s.w, 0.5)
		weakest_dropped = weakest_dropped and not is_equal_approx(s.w, 0.001)
	_check(strongest_kept, "A strong disturbance replaces the weakest")
	_check(weakest_dropped, "A weaker one than all kept is dropped")
	_ripples._sources.clear()
	_ripples._source_foam.clear()

	_body = Node3D.new()
	root.add_child(_body)
	var emitter := RippleEmitter.new()
	emitter.body = _body
	emitter.water_height = func(_xz: Vector2) -> float: return 0.0
	_body.add_child(emitter)
	var droplets_before := _count_particles()
	WaterSplash.spawn(root, Vector3.ZERO, 5.0)
	_check(_count_particles() == droplets_before + 1, "A fast splash throws droplets")
	WaterSplash.spawn(root, Vector3.ZERO, 0.5)
	_check(_count_particles() == droplets_before + 1, "A slow touch does not splash")
	_check(_ripples._sources.size() == 1 and _ripples._source_foam[0] > 0.0, "A splash rings the water and leaves foam")
	_ripples._sources.clear()
	_ripples._source_foam.clear()
	physics_frame.connect(_move_body)


## Moves the body through the surface for a few physics frames, then flies it above the water.
func _move_body() -> void:
	_frames += 1
	if _frames <= 3:
		_body.global_position = Vector3(_frames * 0.1, 0.0, 0.0)
		return
	if _frames == 4:
		_check(_ripples._sources.size() >= 1, "A body moving through the surface disturbs it")
		_ripples._sources.clear()
		_body.global_position = Vector3(1.0, 5.0, 0.0)
		return
	if _frames == 6:
		_check(_ripples._sources.is_empty(), "A body above the water does not")
		physics_frame.disconnect(_move_body)
		print("Water ripples: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
		quit(_failures)


func _count_particles() -> int:
	var count := 0
	for child: Node in root.get_children():
		if child is CPUParticles3D:
			count += 1
	return count


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		print("  FAIL: ", label)
