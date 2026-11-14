extends SceneTree

var _scene: Node3D
var _station: CustomOceanStation
var _frames: int = 0
var _minimum: float = INF
var _maximum: float = -INF

func _initialize() -> void:
	_start.call_deferred()

func _start() -> void:
	var packed: PackedScene = load("res://prototypes/water_compare/water_compare.tscn")
	_scene = packed.instantiate() as Node3D
	root.add_child(_scene)
	_scene.call("_show_station", 3)
	_station = _scene.get_child(_scene.get_child_count() - 1) as CustomOceanStation

func _process(_delta: float) -> bool:
	if _scene == null:
		return false
	_frames += 1
	if _frames < 300:
		var height: float = _station.ocean.height_at(Vector2(0, -5))
		if not is_finite(height):
			push_error("Non-finite ocean height")
			quit(1)
		_minimum = minf(_minimum, height)
		_maximum = maxf(_maximum, height)
	if _frames == 100 or _frames == 200:
		_station.cycle_sea_state()
	if _frames == 300:
		print("OCEAN SMOKE range=", _minimum, "..", _maximum)
		_scene.call("_show_station", 0)
	if _frames == 320:
		_scene.call("_show_station", 3)
	if _frames == 400:
		print("OCEAN SMOKE recreated and completed")
		_scene.call("_show_station", 0)
	if _frames == 430:
		quit()
	return false
