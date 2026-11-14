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
const SHORELINE_Z := 6.0
const SHORE_WAVINESS := 0.045
const SHORE_WANDER := 3.0
var ocean: Ocean
var _beach := BeachProfile.new()
var _state: int = 1
## Editable copy of the active preset; the sliders write into it.
var _live: OceanSpectrum
var _panel: OceanControlPanel

func _init() -> void:
	title = "Custom FFT ocean"
	camera_target = Vector3(0, 0, -5)
	camera_distance = 32.0

func _ready() -> void:
	var beach: MeshInstance3D = BasinMesh.build(BEACH_SIZE, BEACH_CELLS, _height)
	add_child(beach)
	beach.create_trimesh_collision()
	ocean = Ocean.new()
	_live = STATES[_state].duplicate() as OceanSpectrum
	ocean.spectrum = _live
	add_child(ocean)
	ocean.set_seabed(_height, Rect2(-BEACH_SIZE / 2.0, BEACH_SIZE))
	for i: int in range(BARREL_COUNT):
		_add_barrel(Vector3((i - (BARREL_COUNT - 1) / 2.0) * BARREL_SPACING, 0.6, -5.0))
	_update_notes()

func cycle_sea_state() -> void:
	set_sea_state(_state + 1)

func set_sea_state(index: int) -> void:
	_state = posmod(index, STATES.size())
	_live = STATES[_state].duplicate() as OceanSpectrum
	ocean.set_spectrum(_live)
	if _panel:
		_panel.set_spectrum(_live)
	_update_notes()

func make_controls() -> Control:
	_panel = OceanControlPanel.new(ocean, _live)
	return _panel

func _update_notes() -> void:
	var mode: String = "FFT" if OceanSimulation.is_supported() else "Gerstner fallback"
	notes = "%s | %s (edited with sliders) | C: next preset | F: drop objects" % [mode, STATE_NAMES[_state]]

## Coastline runs along x; the sea lies towards -z. The shoreline wanders a little along the coast.
func _height(x: float, z: float) -> float:
	var shoreline_z := SHORELINE_Z - sin(x * SHORE_WAVINESS) * SHORE_WANDER
	return _beach.height(shoreline_z - z, x, z)

func _add_barrel(pos: Vector3) -> void:
	var body: RigidBody3D = RigidBody3D.new()
	body.mass = BARREL_MASS
	body.position = pos
	var cylinder: CylinderMesh = CylinderMesh.new()
	cylinder.top_radius = BARREL_RADIUS
	cylinder.bottom_radius = BARREL_RADIUS
	cylinder.height = BARREL_HEIGHT
	cylinder.material = WaterProp.material(Color(0.28, 0.13, 0.055), 0.8)
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


func water_height_at(xz: Vector2) -> float:
	return ocean.height_at(xz)
