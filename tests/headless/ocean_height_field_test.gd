extends SceneTree
## No GUT dependency: godot --headless --path . --script res://tests/headless/ocean_height_field_test.gd
var _failures: int = 0

func _initialize() -> void:
	var field: OceanHeightField = OceanHeightField.new(2, PackedFloat32Array([2.0, 4.0]))
	_check(not field.is_ready(), "Waits for all cascades")
	field.set_cascade(0, _data([Vector3(0, 1, 0), Vector3(0, 3, 0), Vector3(0, 5, 0), Vector3(0, 7, 0)]))
	_check(not field.is_ready(), "One cascade is insufficient")
	field.set_cascade(1, _data([Vector3(0, 2, 0), Vector3(0, 2, 0), Vector3(0, 2, 0), Vector3(0, 2, 0)]))
	_check(field.is_ready(), "All cascades ready")
	_near(field.height_at(Vector2(0.5, 0.5)), 3.0, "Texel centre and cascade sum")
	_near(field.height_at(Vector2(1, 1)), 6.0, "Bilinear interpolation")
	_near(field.height_at(Vector2(-1.5, -1.5)), 3.0, "Negative wrapping")
	_near(field.height_at(Vector2(2.5, 2.5)), 3.0, "Positive wrapping")
	field.set_cascade(0, PackedByteArray([0]))
	_near(field.height_at(Vector2(0.5, 0.5)), 3.0, "Truncated readback ignored")
	var shifted: OceanHeightField = OceanHeightField.new(2, PackedFloat32Array([2.0]))
	shifted.set_cascade(0, _data([Vector3(0.25, 1, 0), Vector3(0.25, 3, 0), Vector3(0.25, 1, 0), Vector3(0.25, 3, 0)]))
	_near(shifted.height_at(Vector2(0.75, 0.5)), 1.0, "Horizontal displacement inversion")
	shifted.damping_at = func(_p: Vector2) -> float: return 0.5
	_near(shifted.height_at(Vector2(0.625, 0.5)), 0.5, "Shore damping affects height and horizontal inversion")
	print("Ocean height field: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(_failures)

func _data(values: Array[Vector3]) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(values.size() * OceanHeightField.BYTES_PER_TEXEL)
	for i: int in range(values.size()):
		bytes.encode_half(i * 8, values[i].x)
		bytes.encode_half(i * 8 + 2, values[i].y)
		bytes.encode_half(i * 8 + 4, values[i].z)
	return bytes

func _near(actual: float, expected: float, label: String) -> void:
	_check(absf(actual - expected) < 0.001, label + ": " + str(actual))

func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error(label)
