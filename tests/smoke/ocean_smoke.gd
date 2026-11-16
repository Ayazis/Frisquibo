extends SceneTree
## Runs the water demo (prototypes/water_demo) for a few hundred frames: the island with the ocean,
## the pond and the river, sea-state changes, every viewpoint, and the whole scene built a second time.

const SCENE := "res://prototypes/water_demo/water_demo.tscn"

var _scene: Node3D
var _island: IslandScene
var _frames: int = 0
var _minimum: float = INF
var _maximum: float = -INF


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	var packed: PackedScene = load(SCENE)
	_scene = packed.instantiate() as Node3D
	root.add_child(_scene)
	for child: Node in _scene.get_children():
		if child is IslandScene:
			_island = child as IslandScene
	if _island == null:
		push_error("The water demo has no island")
		quit(1)


func _process(_delta: float) -> bool:
	if _island == null:
		return false
	_frames += 1
	if _frames < 300:
		var sea := _island.water_height_at(Vector2(_island.off_coast(-90.0, 20.0).x, _island.off_coast(-90.0, 20.0).z))
		var pond := _island.water_height_at(IslandTerrain.POND_CENTRE)
		var river_x := IslandTerrain.RIVER_START_X + 30.0
		var river := _island.water_height_at(Vector2(river_x, _island.terrain.river_centre(river_x)))
		if not (is_finite(sea) and is_finite(pond) and is_finite(river)):
			push_error("Non-finite water height")
			quit(1)
		if absf(pond - IslandTerrain.POND_LEVEL) > 0.5 or river <= IslandTerrain.SEA_LEVEL:
			push_error("Pond or river water is not where the island puts it")
			quit(1)
		_minimum = minf(_minimum, sea)
		_maximum = maxf(_maximum, sea)
	if _frames == 100 or _frames == 200:
		_island.cycle_sea_state()
	if _frames % 40 == 0:
		_scene.call("show_view", _frames / 40)
	if _frames == 300:
		print("OCEAN SMOKE range=", _minimum, "..", _maximum)
		_island.cycle_water_type()
		_scene.queue_free()
		_island = null
		_frames = 0
		_rebuild.call_deferred()
	return false


func _rebuild() -> void:
	_start()
	_finish.call_deferred()


func _finish() -> void:
	await process_frame
	await process_frame
	print("OCEAN SMOKE recreated and completed")
	quit()
