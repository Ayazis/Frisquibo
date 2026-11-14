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
## Slider rows: property on OceanSpectrum, label, min, max, step.
const SLIDERS: Array[Array] = [
	[&"wind_speed", "Wind (wave size)", 1.0, 30.0, 0.5],
	[&"height_scale", "Wave height", 0.0, 2.5, 0.05],
	[&"choppiness", "Choppiness", 0.0, 1.6, 0.05],
	[&"foam_threshold", "Foam amount", 0.0, 1.2, 0.02],
	[&"foam_lifetime", "Foam lifetime (s)", 0.5, 12.0, 0.25],
	[&"wind_direction", "Wind direction", -180.0, 180.0, 5.0],
	[&"swell", "Swell", 0.0, 1.0, 0.05],
	[&"short_wave_cutoff", "Smoothness", 0.0, 2.5, 0.05],
	[&"sea_level", "Sea level (m)", -3.0, 3.0, 0.1],
]
## Not a spectrum property: moves the Ocean itself.
const SEA_LEVEL_KEY := &"sea_level"
const PANEL_WIDTH := 330.0
const LABEL_WIDTH := 140.0
var ocean: Ocean
var _state: int = 1
## Editable copy of the active preset; the sliders write into it.
var _live: OceanSpectrum
var _sliders: Dictionary[StringName, HSlider] = {}
var _values: Dictionary[StringName, Label] = {}

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
	_sync_sliders()
	_update_notes()

func make_controls() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = PANEL_WIDTH
	var rows := VBoxContainer.new()
	panel.add_child(rows)
	var heading := Label.new()
	heading.text = "Sea state (S cycles presets)"
	rows.add_child(heading)
	for row: Array in SLIDERS:
		var key: StringName = row[0]
		var line := HBoxContainer.new()
		var label := Label.new()
		label.text = row[1]
		label.custom_minimum_size.x = LABEL_WIDTH
		line.add_child(label)
		var slider := HSlider.new()
		slider.min_value = row[2]
		slider.max_value = row[3]
		slider.step = row[4]
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.focus_mode = Control.FOCUS_NONE
		slider.value_changed.connect(_on_slider_changed.bind(key))
		line.add_child(slider)
		var value := Label.new()
		value.custom_minimum_size.x = 44.0
		line.add_child(value)
		rows.add_child(line)
		_sliders[key] = slider
		_values[key] = value
	_sync_sliders()
	return panel

func _sync_sliders() -> void:
	for key: StringName in _sliders:
		var v: float = ocean.level if key == SEA_LEVEL_KEY else _live.get(key)
		_sliders[key].set_value_no_signal(v)
		_values[key].text = "%.2f" % v

func _on_slider_changed(value: float, key: StringName) -> void:
	_values[key].text = "%.2f" % value
	if key == SEA_LEVEL_KEY:
		ocean.set_level(value)
		return
	_live.set(key, value)
	ocean.set_spectrum(_live)
	_update_notes()

func _update_notes() -> void:
	var mode: String = "FFT" if OceanSimulation.is_supported() else "Gerstner fallback"
	notes = "%s | %s (edited with sliders) | S: next preset | D: drop objects" % [mode, STATE_NAMES[_state]]

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
