class_name OceanStation
extends WaterStation
## Library water: GodotOceanWaves (FFT ocean on compute shaders). Needs a RenderingDevice, so Forward+ only.

const OCEAN_SCRIPT := preload("res://prototypes/water_compare/vendor/godot_ocean_waves/water.gd")
const OCEAN_MATERIAL := preload("res://prototypes/water_compare/vendor/godot_ocean_waves/mat_water.tres")
## Same value as the library demo: draw the ocean after other transparents.
const SORTING_OFFSET := 999.0
const MAP_SIZE := 256
const MESH_QUALITY_HIGH := 1
## The clipmap is re-centred under the camera in steps of this size, like the library's own demo.
const CLIPMAP_STEP := 1.0
const WATER_COLOR := Color(0.1, 0.15, 0.18)
const FOAM_COLOR := Color(0.73, 0.67, 0.62)

var _ocean: MeshInstance3D


func _init() -> void:
	title = "GodotOceanWaves FFT ocean"
	is_library = true
	notes = "MIT, commit a171446. Compute shaders: desktop Forward+ only, no web."
	camera_target = Vector3(0, 1, 0)
	camera_distance = 30.0


func is_supported() -> bool:
	return RenderingServer.get_rendering_device() != null


func _ready() -> void:
	if not is_supported():
		return
	_ocean = MeshInstance3D.new()
	_ocean.set_script(OCEAN_SCRIPT)
	_ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The library's demo assigns this in its scene file, not in water.gd.
	_ocean.material_override = OCEAN_MATERIAL
	_ocean.sorting_offset = SORTING_OFFSET
	_ocean.set("water_color", WATER_COLOR)
	_ocean.set("foam_color", FOAM_COLOR)
	_ocean.set("map_size", MAP_SIZE)
	_ocean.set("mesh_quality", MESH_QUALITY_HIGH)
	# Same three cascades as the library demo: long swell, mid waves, fine detail.
	var cascades: Array[WaveCascadeParameters] = [
		_cascade(Vector2(88, 88), 1.0, 1.0, 10.0, 20.0, 150.0, 0.2, 0.5, 8.0),
		_cascade(Vector2(57, 57), 0.75, 1.0, 5.0, 15.0, 150.0, 0.4, 0.5, 0.0),
		_cascade(Vector2(16, 16), 0.0, 0.25, 20.0, 20.0, 550.0, 0.4, 0.25, 3.0),
	]
	_ocean.set("parameters", cascades)
	add_child(_ocean)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if _ocean == null or cam == null:
		return
	var p := cam.global_position
	_ocean.global_position = (Vector3(p.x, 0.0, p.z) / CLIPMAP_STEP).ceil() * CLIPMAP_STEP


func _cascade(tile: Vector2, displacement: float, normal: float, wind: float, direction: float,
		fetch: float, spread: float, whitecap: float, foam: float) -> WaveCascadeParameters:
	var c := WaveCascadeParameters.new()
	c.tile_length = tile
	c.displacement_scale = displacement
	c.normal_scale = normal
	c.wind_speed = wind
	c.wind_direction = direction
	c.fetch_length = fetch
	c.spread = spread
	c.whitecap = whitecap
	c.foam_amount = foam
	return c
