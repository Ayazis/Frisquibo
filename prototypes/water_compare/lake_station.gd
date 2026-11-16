class_name LakeStation
extends WaterStation
## Custom water #1: our world/water sea shader, tuned calm, in a small lake basin.

const BASIN_SIZE := Vector2(70, 70)
const BASIN_CELLS := Vector2i(140, 140)
const LAKE_RADIUS := 11.0
const BANK_RADIUS := 19.0
const LAKE_DEPTH := -2.5
const BANK_HEIGHT := 1.6
const SHORE_WOBBLE := 2.5
const CALM_WAVE_AMPLITUDE := 0.035
const CALM_WAVE_LENGTH := 3.5
const CALM_STEEPNESS := 0.3
const CALM_DETAIL := 0.22
const TREE_COUNT := 26
const ROCK_COUNT := 10
const SEA_SIZE := 60.0
const SEA_SUBDIVISIONS := 240

var _noise := FastNoiseLite.new()
var _sea: Sea


func _init() -> void:
	title = "Lake / moat"
	notes = "world/water/water.gdshader, calm. Mirror reflections on desktop; sky reflection on web."
	camera_distance = 26.0


func _ready() -> void:
	_noise.seed = 11
	_noise.frequency = 0.08
	var basin := BasinMesh.build(BASIN_SIZE, BASIN_CELLS, _height)
	add_child(basin)
	basin.create_trimesh_collision()
	var sea := Sea.new()
	_sea = sea
	sea.size = SEA_SIZE
	sea.subdivisions = SEA_SUBDIVISIONS
	add_child(sea)
	sea.material.set_shader_parameter("wave_amplitude", CALM_WAVE_AMPLITUDE)
	sea.material.set_shader_parameter("wave_length", CALM_WAVE_LENGTH)
	sea.material.set_shader_parameter("wave_steepness", CALM_STEEPNESS)
	sea.material.set_shader_parameter("detail_strength", CALM_DETAIL)
	sea.material.set_shader_parameter("shore_foam_strength", 0.35)
	_scatter_props()


## Trees and rocks around the shore, so reflections have something to show.
func _scatter_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.25, 0.17, 0.1)
	bark.roughness = 0.95
	var leaves := StandardMaterial3D.new()
	leaves.albedo_color = Color(0.1, 0.26, 0.08)
	leaves.roughness = 0.85
	var stone := WaterProp.material(Color(0.4, 0.39, 0.36), 0.9)
	for i in range(TREE_COUNT):
		var angle := rng.randf() * TAU
		var r := rng.randf_range(BANK_RADIUS + 0.5, BANK_RADIUS + 9.0)
		var pos := Vector3(cos(angle) * r, 0, sin(angle) * r)
		pos.y = _height(pos.x, pos.z)
		var tall := rng.randf_range(4.0, 8.0)
		var trunk := CylinderMesh.new()
		trunk.top_radius = 0.12
		trunk.bottom_radius = 0.22
		trunk.height = tall * 0.45
		trunk.material = bark
		_add_mesh(trunk, pos + Vector3(0, tall * 0.225, 0))
		var crown := CylinderMesh.new()
		crown.top_radius = 0.0
		crown.bottom_radius = tall * 0.24
		crown.height = tall * 0.75
		crown.material = leaves
		_add_mesh(crown, pos + Vector3(0, tall * 0.62, 0))
	for i in range(ROCK_COUNT):
		var angle := rng.randf() * TAU
		var r := rng.randf_range(LAKE_RADIUS + 1.0, BANK_RADIUS - 1.0)
		var pos := Vector3(cos(angle) * r, 0, sin(angle) * r)
		var size := rng.randf_range(0.5, 1.4)
		pos.y = _height(pos.x, pos.z) + size * 0.2
		var rock := SphereMesh.new()
		rock.radius = size
		rock.height = size * 1.1
		rock.material = stone
		_add_mesh(rock, pos)


func _add_mesh(mesh: Mesh, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	add_child(mi)


func _height(x: float, z: float) -> float:
	var r := Vector2(x, z).length() + _noise.get_noise_2d(x, z) * SHORE_WOBBLE
	return lerpf(LAKE_DEPTH, BANK_HEIGHT, smoothstep(LAKE_RADIUS, BANK_RADIUS, r))


func water_height_at(xz: Vector2) -> float:
	# Same clock as the shader's TIME, so floating objects ride the visible waves.
	return _sea.height_at(xz, Time.get_ticks_msec() / 1000.0)
