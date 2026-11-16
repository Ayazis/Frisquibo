class_name Sea
extends MeshInstance3D
## Flat, subdivided body of open water at a fixed level (sea, lake, moat). Waves, colour, foam and
## reflections come from water.gdshader; a PlanarReflection child mirrors the scene on desktop.

const WATER_SHADER := preload("res://world/water/water.gdshader")

@export var size := 400.0
## Desktop gets a dense grid for smooth waves; the web build a lighter one.
@export var subdivisions := 400
@export var web_subdivisions := 160
@export var level := 0.0
@export var planar_reflection := true

var material: ShaderMaterial


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

func _parameter(key: StringName, fallback: float) -> float:
	var value: Variant = material.get_shader_parameter(key)
	if value is float:
		return value
	if value is int:
		var integer: int = value
		return float(integer)
	return fallback
