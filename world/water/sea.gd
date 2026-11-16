class_name Sea
extends MeshInstance3D
## Flat, subdivided body of open water at a fixed level (sea, lake, moat). Waves, colour, foam and
## reflections come from water.gdshader; a PlanarReflection child mirrors the scene on desktop, and an
## UnderwaterView child draws the view while the camera is under the surface.

const WATER_SHADER := preload("res://world/water/water.gdshader")
## Defaults of water.gdshader's colour uniforms, for when the material leaves them unset.
const DEFAULT_ABSORPTION := Vector3(0.45, 0.075, 0.05)
const DEFAULT_DEEP_COLOR := Color(0.006, 0.035, 0.04)
## Shader TIME wraps after this many seconds unless the project overrides it.
const DEFAULT_TIME_ROLLOVER := 3600.0

@export var size := 400.0
## Desktop gets a dense grid for smooth waves; the web build a lighter one.
@export var subdivisions := 400
@export var web_subdivisions := 160
@export var level := 0.0
@export var planar_reflection := true
@export var underwater_view := true

var material: ShaderMaterial
var _underwater: UnderwaterView


func _init() -> void:
	material = ShaderMaterial.new()
	material.shader = WATER_SHADER
	WaterTextures.apply(material)


func _ready() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	var subdiv := web_subdivisions if OS.has_feature("web") else subdivisions
	plane.subdivide_width = subdiv
	plane.subdivide_depth = subdiv
	mesh = plane
	material_override = material
	layers = PlanarReflection.water_layer_mask()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	position.y = level
	if planar_reflection:
		var reflection := PlanarReflection.new()
		reflection.plane_height = level
		add_child(reflection)
	if underwater_view:
		_underwater = UnderwaterView.new()
		add_child(_underwater)


func _process(_delta: float) -> void:
	if _underwater == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		_underwater.follow(null, 0.0, 0.0, 0.0, 0.0)
		return
	var surface := height_at(Vector2(cam.global_position.x, cam.global_position.z), _wave_time())
	# The lens waterline is drawn flat at the height under the camera: no cascades to follow here.
	var reach := 2.0 * _parameter(&"wave_amplitude", 0.12) + UnderwaterView.DEFAULT_REACH
	_underwater.follow(cam, surface, surface, 0.0, reach)
	if _underwater.is_active():
		# Read every frame while drawn: whoever set up this water may change its colour at any time.
		_underwater.set_optics(_vector_parameter(&"absorption", DEFAULT_ABSORPTION),
				_color_parameter(&"deep_color", DEFAULT_DEEP_COLOR))


## The time water.gdshader animates with: wave_time when set (the ocean fallback), else the engine's.
func _wave_time() -> float:
	var forced := _parameter(&"wave_time", -1.0)
	if forced >= 0.0:
		return forced
	var rollover: float = ProjectSettings.get_setting("rendering/limits/time/time_rollover_secs", DEFAULT_TIME_ROLLOVER)
	return fposmod(Time.get_ticks_msec() / 1000.0, rollover)


## Same Gerstner displacement as water.gdshader, inverted to find the requested world point.
func height_at(xz: Vector2, time: float) -> float:
	var rest: Vector2 = xz
	for i: int in range(4):
		var displacement: Vector3 = _wave_displacement(rest, time)
		rest = xz - Vector2(displacement.x, displacement.z)
	return level + _wave_displacement(rest, time).y

func _wave_displacement(rest: Vector2, time: float) -> Vector3:
	var amplitude: float = _parameter(&"wave_amplitude", 0.12)
	var wavelength: float = _parameter(&"wave_length", 9.0)
	var steepness: float = _parameter(&"wave_steepness", 0.55)
	var speed: float = _parameter(&"wave_speed", 1.0)
	var spread: float = _parameter(&"wave_spread", 0.6)
	var count: int = int(_parameter(&"wave_count", 6.0))
	var wind: Vector2 = Vector2(1.0, 0.35)
	var custom_wind: Variant = material.get_shader_parameter("wind_direction")
	if custom_wind is Vector2:
		wind = custom_wind
	var displacement: Vector3 = Vector3.ZERO
	count = clampi(count, 1, 8)
	for i: int in range(count):
		var angle: float = wind.angle() + spread * sin(i * 2.4 + 0.7)
		var direction: Vector2 = Vector2(cos(angle), sin(angle))
		var k: float = TAU / (wavelength * pow(0.72, i))
		var a: float = amplitude * pow(0.66, i)
		var phase: float = k * (direction.dot(rest) - sqrt(9.81 / k) * speed * time) + i * 1.7
		var horizontal: Vector2 = steepness / (k * count) * direction * cos(phase)
		displacement += Vector3(horizontal.x, a * sin(phase), horizontal.y)
	return displacement

func _vector_parameter(key: StringName, fallback: Vector3) -> Vector3:
	var value: Variant = material.get_shader_parameter(key)
	if value is Vector3:
		return value
	return fallback


func _color_parameter(key: StringName, fallback: Color) -> Color:
	var value: Variant = material.get_shader_parameter(key)
	if value is Color:
		return value
	return fallback


func _parameter(key: StringName, fallback: float) -> float:
	var value: Variant = material.get_shader_parameter(key)
	if value is float:
		return value
	if value is int:
		var integer: int = value
		return float(integer)
	return fallback
