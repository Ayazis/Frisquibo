class_name RiverStation
extends WaterStation
## Custom water #2: a meandering river whose current, foam and standing waves come from a baked
## RiverFlowField. Boulders split the current; floating objects ride the same field.

const RIVER_SHADER := preload("res://world/water/river/river.gdshader")
const AREA := Vector2(90, 40)
const CELLS := Vector2i(180, 80)
const MEANDER_AMPLITUDE := 4.0
const MEANDER_FREQUENCY := 0.08
const CHANNEL_HALF_WIDTH := 3.0
const BANK_DISTANCE := 7.5
const RIVER_BED := -1.6
const BANK_HEIGHT := 1.4
## Distance from the centreline where the bank rises out of the water (bed height crosses 0).
const WATER_HALF_WIDTH := 5.3
## Four vertices per metre so bow waves and standing waves have geometry to bend.
const SURFACE_CELLS := Vector2i(360, 160)
const FLOW_TEXELS_PER_METRE := 4.0
const ROCK_COUNT := 9
const ROCK_COLOR := Color(0.32, 0.31, 0.29)
const ROCK_RADIUS_MIN := 0.55
const ROCK_RADIUS_MAX := 1.1
## Boulders are ellipsoids this many radii tall, sunk this many radii into the bed.
const ROCK_HEIGHT_RADII := 3.0
const ROCK_SINK_RADII := 0.4
const ROCK_TILT := 0.15
const FLOW_SPEED := 1.8

var _noise := FastNoiseLite.new()
var _field: RiverFlowField


func _init() -> void:
	title = "Flowing river"
	notes = "world/water/river: baked flow field (current, wakes, standing waves) + world/water optics."
	camera_distance = 24.0


func _ready() -> void:
	_noise.seed = 5
	_noise.frequency = 0.1
	var bed := BasinMesh.build(AREA, CELLS, _height)
	add_child(bed)
	bed.create_trimesh_collision()
	var rocks := _make_rocks()
	_field = RiverFlowField.new(Rect2(-AREA / 2.0, AREA), FLOW_TEXELS_PER_METRE, _centre, WATER_HALF_WIDTH,
			FLOW_SPEED, rocks)
	water_velocity = _field.velocity_at
	_make_surface()


func water_height_at(xz: Vector2) -> float:
	return _field.height_at(xz)


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
	mat.set_shader_parameter("flow_map", _field.texture())
	mat.set_shader_parameter("flow_rect", Vector4(-AREA.x / 2.0, -AREA.y / 2.0, AREA.x, AREA.y))
	mat.set_shader_parameter("max_speed", FLOW_SPEED * 2.0)
	# River water: clear, slightly green; foam comes from the flow field, not the shoreline bands.
	mat.set_shader_parameter("absorption", Vector3(0.95, 0.38, 0.5))
	mat.set_shader_parameter("scatter_color", Color(0.03, 0.1, 0.07))
	mat.set_shader_parameter("caustic_strength", 1.2)
	mat.set_shader_parameter("foam_amount", 0.9)
	mat.set_shader_parameter("foam_breakup", 0.0)
	mat.set_shader_parameter("crest_foam_strength", 1.0)
	mat.set_shader_parameter("shore_foam_strength", 0.2)
	mat.set_shader_parameter("shore_foam_width", 0.25)
	WaterTextures.apply(mat)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.layers = PlanarReflection.water_layer_mask()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	add_child(PlanarReflection.new())


## Places boulders in the channel (with collision) and returns those that break the surface as
## (x, z, radius at the waterline) for the flow field.
func _make_rocks() -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var mat := WaterProp.material(ROCK_COLOR, 0.9)
	var breaking: Array[Vector3] = []
	for i in range(ROCK_COUNT):
		var x := rng.randf_range(-AREA.x * 0.4, AREA.x * 0.4)
		var z := _centre(x) + rng.randf_range(-CHANNEL_HALF_WIDTH, CHANNEL_HALF_WIDTH) * 0.8
		var r := rng.randf_range(ROCK_RADIUS_MIN, ROCK_RADIUS_MAX)
		var half_height := r * ROCK_HEIGHT_RADII / 2.0
		var centre_y := _height(x, z) + half_height - r * ROCK_SINK_RADII
		var body := StaticBody3D.new()
		body.position = Vector3(x, centre_y, z)
		body.rotation = Vector3(rng.randf() - 0.5, rng.randf() * TAU, rng.randf() - 0.5) * ROCK_TILT
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = half_height * 2.0
		sm.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		body.add_child(mi)
		var shape := CylinderShape3D.new()
		shape.radius = r
		shape.height = half_height * 2.0
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		add_child(body)
		# Ellipsoid cross-section at the water level (y = 0).
		var t := -centre_y / half_height
		if absf(t) < 1.0:
			breaking.append(Vector3(x, z, r * sqrt(1.0 - t * t)))
	return breaking
