extends Node3D
## Water comparison prototype: one shared sky, sun and orbit camera; keys 1-4 swap the water station.

const STATION_COUNT := 4
const STATION_LABELS: Array[String] = ["1  Lake  (custom)", "2  River  (custom)", "3  FFT ocean  (library)", "4  FFT ocean  (custom)"]
const HUD_Y := 70.0
const BUTTON_BAR_Y := 130.0
const BANNER_Y := 14.0
const BANNER_FONT_SIZE := 34
const CUSTOM_COLOR := Color(0.55, 0.95, 0.6)
const LIBRARY_COLOR := Color(1.0, 0.72, 0.35)
const ORBIT_SENSITIVITY := 0.005
const ZOOM_STEP := 1.15
const MIN_DISTANCE := 4.0
const MAX_DISTANCE := 120.0
const MIN_PITCH := -1.4
const MAX_PITCH := -0.05
const CAMERA_FOV := 60.0
## Gap between the station controls panel and the right edge of the screen.
const CONTROLS_MARGIN := 16.0

var _station: WaterStation
var _cam: Camera3D
var _sun: DirectionalLight3D
var _env: Environment
var _hud: Label
var _banner: Label
var _station_buttons: Array[Button] = []
var _yaw := 0.7
var _pitch := -0.35
var _distance := 20.0
var _golden_hour := false
var _hud_layer: CanvasLayer
var _dropper: ObjectDropper
var _controls: Control


func _ready() -> void:
	_make_env()
	_cam = Camera3D.new()
	_cam.fov = CAMERA_FOV
	_cam.far = 2000.0
	add_child(_cam)
	_make_hud()
	_apply_time()
	_show_station(0)


func _make_env() -> void:
	_env = Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.22, 0.42, 0.78)
	sm.sky_horizon_color = Color(0.72, 0.8, 0.88)
	sky.sky_material = sm
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.1
	_env.ssr_enabled = RenderingServer.get_current_rendering_method() == "forward_plus"
	_env.glow_enabled = true
	_env.fog_enabled = true
	_env.fog_density = 0.002
	_env.fog_aerial_perspective = 0.5
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 80.0
	add_child(_sun)


func _make_hud() -> void:
	var layer := CanvasLayer.new()
	_hud = Label.new()
	_hud.position = Vector2(16, HUD_Y)
	_hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	_hud.add_theme_constant_override("shadow_offset_x", 1)
	_hud.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(_hud)
	_banner = Label.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.position.y = BANNER_Y
	_banner.add_theme_font_size_override("font_size", BANNER_FONT_SIZE)
	_banner.add_theme_color_override("font_shadow_color", Color.BLACK)
	_banner.add_theme_constant_override("shadow_offset_x", 2)
	_banner.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(_banner)
	var buttons := HBoxContainer.new()
	buttons.position = Vector2(16, BUTTON_BAR_Y)
	var group := ButtonGroup.new()
	for i in range(STATION_COUNT):
		var b := Button.new()
		b.text = STATION_LABELS[i]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = i == 0
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_show_station.bind(i))
		buttons.add_child(b)
		_station_buttons.append(b)
	var time_button := Button.new()
	time_button.text = "Time of day (T)"
	time_button.focus_mode = Control.FOCUS_NONE
	time_button.pressed.connect(_toggle_time)
	buttons.add_child(time_button)
	var drop_button := Button.new()
	drop_button.text = "Drop objects (D)"
	drop_button.focus_mode = Control.FOCUS_NONE
	drop_button.pressed.connect(_drop_objects)
	buttons.add_child(drop_button)
	layer.add_child(buttons)
	add_child(layer)
	_hud_layer = layer


func _show_station(index: int) -> void:
	if _station:
		remove_child(_station)
		_station.queue_free()
	match index:
		0: _station = LakeStation.new()
		1: _station = RiverStation.new()
		2: _station = OceanStation.new()
		_: _station = CustomOceanStation.new()
	add_child(_station)
	_distance = _station.camera_distance
	_dropper = ObjectDropper.new()
	_dropper.water_height = _station.water_height_at
	_dropper.water_velocity = _station.water_velocity
	_dropper.drop_centre = _station.camera_target
	_station.add_child(_dropper)
	if _controls:
		_controls.queue_free()
	_controls = _station.make_controls()
	if _controls:
		# Anchored to the top-right corner and growing leftwards to its own minimum width.
		_controls.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_controls.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_controls.offset_left = -CONTROLS_MARGIN
		_controls.offset_right = -CONTROLS_MARGIN
		_controls.offset_top = HUD_Y
		_hud_layer.add_child(_controls)
	for i in range(_station_buttons.size()):
		_station_buttons[i].set_pressed_no_signal(i == index)
	var kind := "LIBRARY" if _station.is_library else "CUSTOM"
	_banner.text = "%s   ·   %s" % [kind, _station.title]
	_banner.add_theme_color_override("font_color", LIBRARY_COLOR if _station.is_library else CUSTOM_COLOR)


func _apply_time() -> void:
	if _golden_hour:
		_sun.rotation_degrees = Vector3(-10, -60, 0)
		_sun.light_color = Color(1.0, 0.68, 0.4)
		_sun.light_energy = 1.7
	else:
		_sun.rotation_degrees = Vector3(-50, -40, 0)
		_sun.light_color = Color(1.0, 0.95, 0.85)
		_sun.light_energy = 1.4


func _unhandled_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	var button := event as InputEventMouseButton
	var key := event as InputEventKey
	if motion and (motion.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT)) != 0:
		_yaw -= motion.relative.x * ORBIT_SENSITIVITY
		_pitch = clampf(_pitch - motion.relative.y * ORBIT_SENSITIVITY, MIN_PITCH, MAX_PITCH)
	elif button and button.pressed:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(_distance / ZOOM_STEP, MIN_DISTANCE)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(_distance * ZOOM_STEP, MAX_DISTANCE)
	elif key and key.pressed and not key.echo:
		# Physical keys so the number row works on any layout; the keypad digits work too.
		var number := key.physical_keycode - KEY_1
		if key.keycode >= KEY_KP_1 and key.keycode <= KEY_KP_9:
			number = key.keycode - KEY_KP_1
		if number >= 0 and number < STATION_COUNT:
			_show_station(number)
		elif key.physical_keycode == KEY_S and _station is CustomOceanStation:
			(_station as CustomOceanStation).cycle_sea_state()
		elif key.physical_keycode == KEY_T:
			_toggle_time()
		elif key.physical_keycode == KEY_D:
			_drop_objects()


func _drop_objects() -> void:
	_dropper.drop_burst()


func _toggle_time() -> void:
	_golden_hour = not _golden_hour
	_apply_time()


func _process(_delta: float) -> void:
	var target := _station.camera_target
	_cam.global_position = target + Basis.from_euler(Vector3(_pitch, _yaw, 0)) * Vector3(0, 0, _distance)
	_cam.look_at(target)
	var status := _station.notes if _station.is_supported() else "NOT AVAILABLE on this renderer. " + _station.notes
	_hud.text = "%s   (FPS %d)\nDrag to orbit, wheel to zoom" % [status, Engine.get_frames_per_second()]


## Called by tools/visual_check before each shot. Keys: station (0-3), golden_hour (bool),
## sea_state (index into CustomOceanStation.STATES).
func apply_visual_check_state(state: Dictionary) -> void:
	_hud_layer.visible = false
	var station: int = state.get("station", 0)
	_show_station(station)
	_golden_hour = state.get("golden_hour", false)
	_apply_time()
	var custom := _station as CustomOceanStation
	if custom != null:
		var sea_state: int = state.get("sea_state", 1)
		custom.set_sea_state(sea_state)
