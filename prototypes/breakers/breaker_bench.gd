extends Node3D
## Breaker test bench (docs/plans/breaking_waves.md, phase B): a straight sandy beach in the FFT ocean,
## sloping 1:17 out to sea, where moderate seas plunge. Judge the curl, the lip glow, the white water and
## the spray against real surf footage at the same distance and light.
## Keys: 1-5 viewpoints, T slow motion, P pause, K curls on/off, L sun behind / in front of the waves,
## C next sea state. Drag to look around, wheel to zoom. Prototype only: nothing depends on it.

const PRESETS: Array[OceanSpectrum] = [
	preload("res://world/water/ocean/presets/breeze_over_swell.tres"),
	preload("res://world/water/ocean/presets/calm_sea.tres"),
	preload("res://world/water/ocean/presets/fresh_breeze.tres"),
	preload("res://world/water/ocean/presets/storm.tres"),
]
const PRESET_NAMES: Array[String] = ["breeze over swell", "calm sea", "fresh breeze", "storm"]
const GROUND_SHADER := preload("res://world/terrain/terrain_ground.gdshader")
## The beach: land rises at BEACH_RISE inland of x = 0, the seabed falls at SEABED_SLOPE out to sea
## (+x), down to SEABED_FLOOR.
const SEABED_SLOPE := 0.06
const BEACH_RISE := 0.08
const SEABED_FLOOR := -30.0
const LENGTH := 400.0
const WIDTH := 600.0
const GROUND_CELL := 1.0
const SEABED_RESOLUTION := 512
const SAND_COLOR := Color(0.76, 0.66, 0.48)
## Viewpoints: name, camera position, point looked at.
const VIEWS: Array[Array] = [
	["side, 15 m", Vector3(18.0, 2.0, -15.0), Vector3(18.0, 0.3, 10.0)],
	["front, 40 m", Vector3(-6.0, 2.5, 0.0), Vector3(34.0, 0.0, 0.0)],
	["low in the surf", Vector3(12.0, 0.6, -4.0), Vector3(24.0, 0.4, 2.0)],
	["from the sea", Vector3(60.0, 4.0, 0.0), Vector3(10.0, 0.0, 0.0)],
	["high, along the beach", Vector3(-20.0, 25.0, -60.0), Vector3(25.0, 0.0, 20.0)],
]
const ORBIT_SENSITIVITY := 0.004
const ZOOM_STEP := 1.15
const SLOW_MOTION := 0.25
const HUD_POSITION := Vector2(16, 16)

var _ocean: Ocean
var _cam: Camera3D
var _sun: DirectionalLight3D
var _hud: Label
var _preset := 0
var _backlit := true
var _plunges := 0
var _look := Vector3.ZERO


func _ready() -> void:
	_make_environment()
	add_child(_ground())
	_ocean = Ocean.new()
	_ocean.spectrum = PRESETS[_preset].duplicate() as OceanSpectrum
	_ocean.foreshore_slope = BEACH_RISE
	add_child(_ocean)
	var area := Rect2(-WIDTH * 0.25, -LENGTH * 0.5, WIDTH, LENGTH)
	_ocean.set_seabed(func(x: float, _z: float) -> float: return _height(x), area, SEABED_RESOLUTION)
	_ocean.breaker_plunged.connect(func(_at: Vector3, _h: float) -> void: _plunges += 1)
	_cam = Camera3D.new()
	_cam.far = 3000.0
	add_child(_cam)
	_hud = Label.new()
	_hud.position = HUD_POSITION
	var layer := CanvasLayer.new()
	layer.add_child(_hud)
	add_child(layer)
	_show_view(0)


func _height(x: float) -> float:
	return -x * BEACH_RISE if x < 0.0 else maxf(-x * SEABED_SLOPE, SEABED_FLOOR)


func _ground() -> MeshInstance3D:
	var columns := int(WIDTH / GROUND_CELL)
	var rows := int(LENGTH / GROUND_CELL)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(rows):
		for i in range(columns):
			var x0 := -WIDTH * 0.25 + i * GROUND_CELL
			var z0 := -LENGTH * 0.5 + j * GROUND_CELL
			var a := Vector3(x0, _height(x0), z0)
			var b := Vector3(x0 + GROUND_CELL, _height(x0 + GROUND_CELL), z0)
			var c := Vector3(x0 + GROUND_CELL, _height(x0 + GROUND_CELL), z0 + GROUND_CELL)
			var d := Vector3(x0, _height(x0), z0 + GROUND_CELL)
			for v: Vector3 in [a, c, b, a, d, c]:
				surface.add_vertex(v)
	surface.generate_normals()
	var material := ShaderMaterial.new()
	material.shader = GROUND_SHADER
	material.set_shader_parameter("sand_color", SAND_COLOR)
	material.set_shader_parameter("beach_top", 100.0)
	var mesh := MeshInstance3D.new()
	mesh.mesh = surface.commit()
	mesh.material_override = material
	return mesh


func _make_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	add_child(_sun)
	_set_sun()


## Backlit: a low sun over the sea, behind the breakers seen from the beach (the lip glows). Otherwise
## the sun is behind the viewer on the beach.
func _set_sun() -> void:
	_sun.rotation_degrees = Vector3(-14.0, -90.0, 0.0) if _backlit else Vector3(-40.0, 90.0, 0.0)


func _show_view(index: int) -> void:
	var view := VIEWS[index]
	var from: Vector3 = view[1]
	_look = view[2]
	_cam.position = from
	_cam.look_at(_look)


func _process(_delta: float) -> void:
	var state := _ocean.breaker_at(Vector2(_look.x, _look.z))
	_hud.text = "%s | %s | time x%.2f | plunges %d | at the look point: stage %.2f, plunge %.2f%s\n1-5 views  T slow  P pause  K curls  L sun  C sea  drag/wheel: look/zoom" % [
		PRESET_NAMES[_preset], "curls on" if _ocean.parameter_value(&"curl_strength") > 0.0 else "curls off",
		Engine.time_scale, _plunges, state.stage, state.plunge, "  (inside the tube)" if state.inside_tube else ""]


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	var motion := event as InputEventMouseMotion
	var button := event as InputEventMouseButton
	if motion and (motion.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_cam.rotate_y(-motion.relative.x * ORBIT_SENSITIVITY)
		_cam.rotate_object_local(Vector3.RIGHT, -motion.relative.y * ORBIT_SENSITIVITY)
	elif button and button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var step := 1.0 / ZOOM_STEP if button.button_index == MOUSE_BUTTON_WHEEL_UP else ZOOM_STEP
		_cam.position = _look + (_cam.position - _look) * step
	elif key and key.pressed and not key.echo:
		var number := key.physical_keycode - KEY_1
		if number >= 0 and number < VIEWS.size():
			_show_view(number)
		elif key.physical_keycode == KEY_T:
			Engine.time_scale = SLOW_MOTION if Engine.time_scale == 1.0 else 1.0
		elif key.physical_keycode == KEY_P:
			Engine.time_scale = 0.0 if Engine.time_scale > 0.0 else 1.0
		elif key.physical_keycode == KEY_K:
			_ocean.set_parameter(&"curl_strength", 0.0 if _ocean.parameter_value(&"curl_strength") > 0.0 else 1.0)
		elif key.physical_keycode == KEY_L:
			_backlit = not _backlit
			_set_sun()
		elif key.physical_keycode == KEY_C:
			_preset = (_preset + 1) % PRESETS.size()
			_ocean.set_spectrum(PRESETS[_preset].duplicate() as OceanSpectrum)
