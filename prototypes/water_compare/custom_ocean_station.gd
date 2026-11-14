class_name CustomOceanStation
extends WaterStation
## Our FFT ocean, shallow beach and physics-driven barrels.

const STATES: Array[OceanSpectrum] = [
	preload("res://world/water/ocean/presets/calm_sea.tres"),
	preload("res://world/water/ocean/presets/fresh_breeze.tres"),
	preload("res://world/water/ocean/presets/storm.tres")]
const STATE_NAMES: Array[String] = ["Calm", "Fresh breeze", "Storm"]
const BEACH_SIZE: Vector2 = Vector2(600, 600)
const BEACH_CELLS: Vector2i = Vector2i(300, 300)
const BARREL_COUNT: int = 5
const BARREL_SPACING: float = 2.0
const BARREL_RADIUS: float = 0.45
const BARREL_HEIGHT: float = 1.1
const BARREL_MASS: float = 50.0
var ocean: Ocean
var _state: int = 1

func _init() -> void:
	title = "Custom FFT ocean"
	camera_target = Vector3(0, 0, -5)
	camera_distance = 32.0

func _ready() -> void:
	var beach: MeshInstance3D = BasinMesh.build(BEACH_SIZE, BEACH_CELLS, _height)
	add_child(beach)
	beach.create_trimesh_collision()
	ocean = Ocean.new()
	ocean.spectrum = STATES[_state]
	add_child(ocean)
	ocean.set_seabed(_height, Rect2(-BEACH_SIZE / 2.0, BEACH_SIZE))
	for i: int in range(BARREL_COUNT):
		_add_barrel(Vector3((i - (BARREL_COUNT - 1) / 2.0) * BARREL_SPACING, 0.6, -5.0))
	_update_notes()

func cycle_sea_state() -> void:
	_state = (_state + 1) % STATES.size()
	ocean.set_spectrum(STATES[_state])
	_update_notes()

func set_sea_state(index: int) -> void:
	_state = posmod(index, STATES.size())
	ocean.set_spectrum(STATES[_state])
	_update_notes()

func _update_notes() -> void:
	var mode: String = "FFT" if OceanSimulation.is_supported() else "Gerstner fallback"
	notes = "%s | %s | S: sea state | Floating barrels + shallow beach" % [mode, STATE_NAMES[_state]]

func _height(x: float, z: float) -> float:
	return lerpf(-8.0, 3.0, smoothstep(-30.0, 25.0, z + sin(x * 0.045) * 3.0))

func _add_barrel(pos: Vector3) -> void:
	var body: RigidBody3D = RigidBody3D.new()
	body.mass = BARREL_MASS
	body.position = pos
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = BARREL_RADIUS
	cylinder.bottom_radius = BARREL_RADIUS
	cylinder.height = BARREL_HEIGHT
	var wood: StandardMaterial3D = StandardMaterial3D.new()
	wood.albedo_color = Color(0.28, 0.13, 0.055)
	wood.roughness = 0.8
	cylinder.material = wood
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.mesh = cylinder
	body.add_child(mesh)
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: CylinderShape3D = CylinderShape3D.new()
	shape.radius = BARREL_RADIUS
	shape.height = BARREL_HEIGHT
	collision.shape = shape
	body.add_child(collision)
	var buoyancy: Buoyancy = Buoyancy.new()
	buoyancy.body = body
	buoyancy.water_height = ocean.height_at
	body.add_child(buoyancy)
	add_child(body)
