extends SceneTree
## No GUT dependency: godot --headless --path . --script res://tests/headless/water_mask_test.gd
## Water masks keep the sea out of open hulls: they draw after the underwater view, before every water
## surface, write depth and nothing else.

const LID_POINTS := 5
var _failures: int = 0


func _initialize() -> void:
	var material := WaterMask.shared_material()
	_check(material.render_priority < 0, "Draws before the water surfaces")
	_check(material.render_priority > UnderwaterView.RENDER_PRIORITY, "Draws after the underwater view")
	_check(not material.shader.get_shader_uniform_list().is_empty(), "The mask shader compiles")
	var code := material.shader.code
	_check(code.contains("depth_draw_always"), "Writes depth, so water behind the opening fails the depth test")
	_check(material.get_shader_parameter("debug_tint") == null, "Invisible: the tint keeps its default of 0")

	var port := PackedVector3Array()
	var starboard := PackedVector3Array()
	for i in range(LID_POINTS):
		port.append(Vector3(i, 0.5, 1.0))
		starboard.append(Vector3(i, 0.5, -1.0))
	var lid := WaterMask.lid(port, starboard)
	var vertices: PackedVector3Array = lid.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check(vertices.size() == (LID_POINTS - 1) * 6, "Two triangles per span of the rims")
	var span := lid.get_aabb().size
	_check(is_equal_approx(span.x, LID_POINTS - 1) and is_equal_approx(span.z, 2.0), "The lid spans the opening")

	var mask := WaterMask.new(lid)
	_check(mask.layers == PlanarReflection.water_layer_mask(), "On the water layer, out of the mirror cameras")
	_check(mask.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Casts no shadow")
	mask.free()

	var boat := ScaleBoat.new(func(_xz: Vector2) -> float: return 0.0)
	var masks := boat.get_children().filter(func(n: Node) -> bool: return n is WaterMask)
	_check(masks.size() == 1, "The demo boat keeps the sea out of its hull")
	boat.free()
	print("Water mask: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(_failures)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		print("  FAIL: ", label)
