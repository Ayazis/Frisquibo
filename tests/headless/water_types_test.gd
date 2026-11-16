extends SceneTree
## No GUT dependency: godot --headless --path . --script res://tests/headless/water_types_test.gd
const LOOKS := "res://world/water/ocean/looks/%s.tres"
var _failures: int = 0


func _initialize() -> void:
	var clear := load(LOOKS % "clear_ocean") as OceanLook
	var coastal := load(LOOKS % "coastal") as OceanLook
	var murky := load(LOOKS % "murky") as OceanLook
	_check(clear != null and coastal != null and murky != null, "All water types load")
	var a_clear := OceanLookBinding.absorption(clear, {})
	var a_coastal := OceanLookBinding.absorption(coastal, {})
	var a_murky := OceanLookBinding.absorption(murky, {})
	_check(a_clear.x > a_clear.y and a_clear.y > a_clear.z, "Clear ocean: red dies first, blue travels furthest")
	_check(a_coastal.y < a_coastal.z, "Coastal water: green travels furthest (blue is absorbed by plankton)")
	_check(a_murky.y < a_murky.x and a_murky.y < a_murky.z, "Murky water: green-brown")
	for channel in range(3):
		_check(a_clear[channel] < a_coastal[channel] and a_coastal[channel] < a_murky[channel],
				"Each type is murkier than the one before (channel %d)" % channel)
	var sea := Sea.new()
	sea.set_look(murky)
	var pushed: Vector3 = sea.material.get_shader_parameter("absorption")
	_check(pushed.is_equal_approx(a_murky), "A lake takes a water type")
	var deep: Color = sea.material.get_shader_parameter("deep_color")
	_check(deep.is_equal_approx(murky.deep_color), "Including its colours")
	sea.free()
	print("Water types: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(_failures)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		print("  FAIL: ", label)
