class_name CustomOceanStation
extends WaterStation
## Our FFT ocean, shallow beach and physics-driven barrels.

const STATES: Array[OceanSpectrum] = [
	preload("res://world/water/ocean/presets/calm_sea.tres"),
	preload("res://world/water/ocean/presets/fresh_breeze.tres"),
	preload("res://world/water/ocean/presets/storm.tres"),
	preload("res://world/water/ocean/presets/breeze_over_swell.tres")]
const RULES: OceanRuleSet = preload("res://world/water/ocean/rules/presets/coastal_rules.tres")
const STATE_NAMES: Array[String] = ["Calm", "Fresh breeze", "Storm", "Breeze over swell"]
## The coast: 150 m of land, then about 1.25 km of sea: a wide shallow sandy shelf, a steeper outer
## shelf that is already fairly deep, and a shelf break dropping into deep water.
const BEACH_SIZE: Vector2 = Vector2(1600, 1400)
const BEACH_CENTER: Vector2 = Vector2(0, -550)
const BEACH_CELLS: Vector2i = Vector2i(320, 600)
## Row spacing: this fraction of the rows lies on the sea side of the shoreline, and spacing grows
## away from it (linear share SHORE_ROW_LINEAR, the rest quadratic), so the beach gets the detail.
const SHORE_ROW_FRACTION := 0.75
const SHORE_ROW_LINEAR := 0.15
const SEABED_RESOLUTION := 1024
const CONTROLS_VIEW_SIZE := Vector2(560, 640)
const DEAN_A := 0.1                 # fine sand: a gentle, wide surf zone
const BAR_DISTANCE := 70.0
const BAR_HEIGHT := 0.8
const BAR_WIDTH := 18.0
const SHELF_START := 250.0          # about 4 m deep
const SHELF_SLOPE := 0.04           # about 20 m deep at the shelf break
const DROP_START := 600.0
const DROP_WIDTH := 300.0
const DROP_DEPTH := 120.0           # about 150 m deep beyond 900 m offshore
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
var _panel: OceanTunerPanel

func _init() -> void:
	title = "Custom FFT ocean"
	camera_target = Vector3(0, 0, -5)
	camera_distance = 32.0

func _ready() -> void:
	_beach.dean_a = DEAN_A
	_beach.bar_distance = BAR_DISTANCE
	_beach.bar_height = BAR_HEIGHT
	_beach.bar_width = BAR_WIDTH
	_beach.shelf_start = SHELF_START
	_beach.shelf_slope = SHELF_SLOPE
	_beach.drop_start = DROP_START
	_beach.drop_width = DROP_WIDTH
	_beach.drop_depth = DROP_DEPTH
	var beach: MeshInstance3D = BasinMesh.build(BEACH_SIZE, BEACH_CELLS, _height, BEACH_CENTER, _row_spacing)
	add_child(beach)
	beach.create_trimesh_collision()
	ocean = Ocean.new()
	_live = STATES[_state].duplicate() as OceanSpectrum
	ocean.spectrum = _live
	ocean.rules = RULES
	add_child(ocean)
	ocean.set_seabed(_height, Rect2(BEACH_CENTER - BEACH_SIZE / 2.0, BEACH_SIZE), SEABED_RESOLUTION)
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
		_panel.mark_defaults()
	_update_notes()

func make_controls() -> Control:
	var tabs := TabContainer.new()
	tabs.focus_mode = Control.FOCUS_NONE
	_panel = OceanTunerPanel.new(ocean)
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Big seas are long seas: start with horizontal size following vertical size.
	_panel.set_link(OceanTunerLinks.Link.STEEPNESS, true)
	var sea := ScrollContainer.new()
	sea.name = "Sea"
	sea.custom_minimum_size = CONTROLS_VIEW_SIZE
	sea.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sea.add_child(_panel)
	tabs.add_child(sea)
	var scroll := ScrollContainer.new()
	scroll.name = "Rules"
	scroll.custom_minimum_size = CONTROLS_VIEW_SIZE
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var editor := OceanRuleEditor.new(RULES, ocean.rule_parameters(), ocean.rule_targets())
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor.rules_changed.connect(func(rule_set: OceanRuleSet) -> void:
		ocean.set_rules(rule_set)
		editor.show_problems(ocean.rule_problems()))
	editor.show_problems(ocean.rule_problems())
	scroll.add_child(editor)
	tabs.add_child(scroll)
	return tabs

func _update_notes() -> void:
	var mode: String = "FFT" if OceanSimulation.is_supported() else "Gerstner fallback"
	notes = "%s | %s (edited with sliders) | C: next preset | F: drop objects" % [mode, STATE_NAMES[_state]]

## Row fraction (0 = far out at sea, 1 = inland edge) to z fraction: dense at the shoreline.
func _row_spacing(row: float) -> float:
	var shore := (SHORELINE_Z - (BEACH_CENTER.y - BEACH_SIZE.y / 2.0)) / BEACH_SIZE.y
	if row < SHORE_ROW_FRACTION:
		var t := (SHORE_ROW_FRACTION - row) / SHORE_ROW_FRACTION
		return shore - shore * _grow(t)
	var u := (row - SHORE_ROW_FRACTION) / (1.0 - SHORE_ROW_FRACTION)
	return shore + (1.0 - shore) * _grow(u)


static func _grow(t: float) -> float:
	return SHORE_ROW_LINEAR * t + (1.0 - SHORE_ROW_LINEAR) * t * t


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
