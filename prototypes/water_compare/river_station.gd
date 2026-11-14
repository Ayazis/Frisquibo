class_name RiverStation
extends WaterStation
## Custom water #2: a meandering river with a flow-map style shader and rocks that break the current.

const RIVER_SHADER := preload("res://prototypes/water_compare/river.gdshader")
const AREA := Vector2(90, 40)
const CELLS := Vector2i(180, 80)
const MEANDER_AMPLITUDE := 4.0
const MEANDER_FREQUENCY := 0.08
const CHANNEL_HALF_WIDTH := 3.0
const BANK_DISTANCE := 7.5
const RIVER_BED := -1.6
const BANK_HEIGHT := 1.4
const SURFACE_CELLS := Vector2i(180, 80)
const ROCK_COUNT := 9
const ROCK_COLOR := Color(0.32, 0.31, 0.29)

var _noise := FastNoiseLite.new()


func _init() -> void:
	title = "Flowing river"
	notes = "prototypes/water_compare/river.gdshader + world/water optics. Mirror reflections on desktop."
	camera_distance = 24.0


func _ready() -> void:
	_noise.seed = 5
	_noise.frequency = 0.1
	add_child(BasinMesh.build(AREA, CELLS, _height))
	_make_surface()
	_make_rocks()


func _centre(x: float) -> float:
	return sin(x * MEANDER_FREQUENCY) * MEANDER_AMPLITUDE


func _height(x: float, z: float) -> float:
	var d := absf(z - _centre(x)) + _noise.get_noise_2d(x, z) * 0.8
	return lerpf(RIVER_BED, BANK_HEIGHT, smoothstep(CHANNEL_HALF_WIDTH, BANK_DISTANCE, d))


func _make_surface() -> void:
	var plane := PlaneMesh.new()
	plane.size = AREA
	plane.subdivide_width = SURFACE_CELLS.x
	plane.subdivide_depth = SURFACE_CELLS.y
	var mat := ShaderMaterial.new()
	mat.shader = RIVER_SHADER
	mat.set_shader_parameter("meander_amplitude", MEANDER_AMPLITUDE)
	mat.set_shader_parameter("meander_frequency", MEANDER_FREQUENCY)
	mat.set_shader_parameter("channel_half_width", BANK_DISTANCE)
	# River water: greener and murkier than the lake.
	mat.set_shader_parameter("absorption", Vector3(0.6, 0.22, 0.3))
	mat.set_shader_parameter("scatter_color", Color(0.06, 0.16, 0.1))
	WaterTextures.apply(mat)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.layers = PlanarReflection.water_layer_mask()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	add_child(PlanarReflection.new())


func _make_rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ROCK_COLOR
	mat.roughness = 0.9
	for i in range(ROCK_COUNT):
		var x := rng.randf_range(-AREA.x * 0.4, AREA.x * 0.4)
		var z := _centre(x) + rng.randf_range(-CHANNEL_HALF_WIDTH, CHANNEL_HALF_WIDTH) * 0.8
		var r := rng.randf_range(0.35, 0.9)
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 1.4
		sm.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		mi.position = Vector3(x, _height(x, z) + r * 0.9, z)
		mi.rotation = Vector3(rng.randf(), rng.randf() * TAU, rng.randf()) * 0.4
		add_child(mi)
