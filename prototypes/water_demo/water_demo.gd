extends Node3D
## Water demo: the island in the FFT ocean (IslandScene) under the time of day and weather (Atmosphere),
## an orbit camera, viewpoints (keys 1-5), the ocean tuner and objects to drop.

const ORBIT_SENSITIVITY := 0.005
const ZOOM_STEP := 1.15
const MIN_DISTANCE := 3.0
const MAX_DISTANCE := 700.0
const MIN_PITCH := -1.4
## Positive pitch looks up: from under the water towards the surface.
const MAX_PITCH := 1.2
const CAMERA_FOV := 60.0
const CAMERA_FAR := 4000.0
## WASD pan speed as a fraction of the orbit distance per second, so it feels the same zoomed in or out.
const MOVE_SPEED_PER_DISTANCE := 0.8
const FAST_MULTIPLIER := 3.0
## Q/E lower and raise the orbit point within these bounds (metres from the viewpoint's target);
## low enough to take the camera under water.
const MIN_TARGET_HEIGHT := -20.0
const MAX_TARGET_HEIGHT := 60.0
const HUD_Y := 70.0
const BUTTON_BAR_Y := 150.0
## The controls start this far below the top of the button bar, clear of the buttons.
const CONTROLS_BELOW_BUTTONS := 44.0
## Gap between the controls panel and the right edge of the screen.
const CONTROLS_MARGIN := 16.0
const BANNER_Y := 14.0
const BANNER_FONT_SIZE := 34
const BANNER_COLOR := Color(0.55, 0.95, 0.6)
## The frame timings (F3) sit this far from the bottom-left corner.
const PERF_MARGIN := 16.0
## Times of day the T key steps through (solar hours on the TimeOfDay's late-summer day).
const TIMES: Array[float] = [5.05, 7.0, 13.0, 16.0, 18.25, 18.75, 19.25, 22.0]
const TIME_NAMES: Array[String] = ["Dawn", "Morning", "Noon", "Afternoon", "Golden hour", "Sunset", "Dusk", "Night"]
const START_TIME := 1
const GOLDEN_HOUR := 4
## Y runs the clock: a whole day in about a minute and a half.
const TIME_LAPSE_HOURS_PER_SECOND := 0.25
## Turns the sky so the sun sets over the sea in front of the beach view (which looks towards -Z), and
## rises behind it.
const NORTH_HEADING_DEGREES := -90.0
## Weathers the V key steps through; each sea state brings its own (SEA_STATE_WEATHER: index per state
## in IslandScene.STATES).
const WEATHERS: Array[SkyWeather] = [
	preload("res://world/time_of_day/weather/clear.tres"),
	preload("res://world/time_of_day/weather/fair.tres"),
	preload("res://world/time_of_day/weather/mist.tres"),
	preload("res://world/time_of_day/weather/overcast.tres"),
	preload("res://world/time_of_day/weather/storm.tres")]
const SEA_STATE_WEATHER: Array[int] = [0, 1, 4, 1]


## A place to look from: the orbit point, distance and angles.
class View:
	var name: String
	var target: Vector3
	var distance: float
	var yaw: float
	var pitch: float

	func _init(view_name: String, view_target: Vector3, view_distance: float, view_yaw: float, view_pitch: float) -> void:
		name = view_name
		target = view_target
		distance = view_distance
		yaw = view_yaw
		pitch = view_pitch


var _island: IslandScene
var _views: Array[View] = []
var _view := 0
var _cam: Camera3D
var _time: TimeOfDay
var _atmosphere: Atmosphere
var _time_index := START_TIME
var _weather := 1
var _hud: Label
var _banner: Label
var _view_buttons: Array[Button] = []
var _yaw := 0.0
var _pitch := -0.3
var _distance := 30.0
## Where WASD has moved the orbit point, relative to the viewpoint's target.
var _target_offset := Vector3.ZERO
var _hud_layer: CanvasLayer
var _perf: PerfOverlay
var _dropper: ObjectDropper


func _ready() -> void:
	_make_atmosphere()
	_cam = Camera3D.new()
	_cam.fov = CAMERA_FOV
	_cam.far = CAMERA_FAR
	add_child(_cam)
	_cam.make_current()
	_island = IslandScene.new()
	add_child(_island)
	_views = _make_views()
	_dropper = ObjectDropper.new()
	_dropper.water_height = _island.water_height_at
	_dropper.water_velocity = _island.water_velocity_at
	_island.add_child(_dropper)
	_make_hud()
	_set_weather(SEA_STATE_WEATHER[_island.sea_state()], 0.0)
	show_view(0)


## Jumps the camera to viewpoint `index` (see _make_views).
func show_view(index: int) -> void:
	_view = clampi(index, 0, _views.size() - 1)
	var view := _views[_view]
	_distance = view.distance
	_yaw = view.yaw
	_pitch = view.pitch
	_target_offset = Vector3.ZERO
	for i in range(_view_buttons.size()):
		_view_buttons[i].set_pressed_no_signal(i == _view)
	_banner.text = "Water demo   ·   " + view.name


func _make_views() -> Array[View]:
	var terrain := _island.terrain
	var beach := _island.off_coast(-90.0, -4.0)
	var river_x := IslandTerrain.RIVER_START_X + (terrain.river_end_x() - IslandTerrain.RIVER_START_X) * 0.45
	var mouth_x := terrain.river_end_x() - 12.0
	var pond := Vector3(IslandTerrain.POND_CENTRE.x, IslandTerrain.POND_LEVEL, IslandTerrain.POND_CENTRE.y)
	return [
		View.new("Beach", Vector3(beach.x, 0.5, beach.z), 30.0, 0.0, -0.3),
		View.new("Pond", pond, 40.0, 0.7, -0.35),
		View.new("River", Vector3(river_x, terrain.river_level(river_x), terrain.river_centre(river_x)), 30.0, -0.9, -0.4),
		View.new("River mouth", Vector3(mouth_x, 0.3, terrain.river_centre(mouth_x)), 45.0, 2.2, -0.3),
		View.new("Island from the sea", Vector3.ZERO, 450.0, 0.6, -0.35),
	]


func _make_atmosphere() -> void:
	_time = TimeOfDay.new()
	_time.north_heading_degrees = NORTH_HEADING_DEGREES
	_time.hour = TIMES[_time_index]
	add_child(_time)
	_atmosphere = Atmosphere.new()
	_atmosphere.time = _time
	_atmosphere.weather = WEATHERS[_weather]
	add_child(_atmosphere)


func _make_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud = Label.new()
	_hud.position = Vector2(16, HUD_Y)
	_hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	_hud.add_theme_constant_override("shadow_offset_x", 1)
	_hud.add_theme_constant_override("shadow_offset_y", 1)
	_hud_layer.add_child(_hud)
	_banner = Label.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.position.y = BANNER_Y
	_banner.add_theme_font_size_override("font_size", BANNER_FONT_SIZE)
	_banner.add_theme_color_override("font_color", BANNER_COLOR)
	_banner.add_theme_color_override("font_shadow_color", Color.BLACK)
	_banner.add_theme_constant_override("shadow_offset_x", 2)
	_banner.add_theme_constant_override("shadow_offset_y", 2)
	_hud_layer.add_child(_banner)
	var buttons := HBoxContainer.new()
	buttons.position = Vector2(16, BUTTON_BAR_Y)
	var group := ButtonGroup.new()
	for i in range(_views.size()):
		var b := Button.new()
		b.text = "%d  %s" % [i + 1, _views[i].name]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(show_view.bind(i))
		buttons.add_child(b)
		_view_buttons.append(b)
	_add_button(buttons, "Sea state (C)", _cycle_sea_state)
	_add_button(buttons, "Water type (L)", _cycle_water_type)
	_add_button(buttons, "Time of day (T)", _next_time)
	_add_button(buttons, "Time lapse (Y)", _toggle_time_lapse)
	_add_button(buttons, "Weather (V)", _next_weather)
	_add_button(buttons, "Drop objects (F)", _drop_objects)
	_hud_layer.add_child(buttons)
	var controls := _island.make_controls()
	# Down the right edge to the bottom of the screen, growing leftwards to its own minimum width.
	controls.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	controls.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	controls.offset_left = -CONTROLS_MARGIN
	controls.offset_right = -CONTROLS_MARGIN
	controls.offset_top = BUTTON_BAR_Y + CONTROLS_BELOW_BUTTONS
	controls.offset_bottom = -CONTROLS_MARGIN
	_hud_layer.add_child(controls)
	_perf = PerfOverlay.new()
	_perf.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_perf.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_perf.offset_left = PERF_MARGIN
	_perf.offset_right = PERF_MARGIN
	_perf.offset_top = -PERF_MARGIN
	_perf.offset_bottom = -PERF_MARGIN
	_hud_layer.add_child(_perf)
	add_child(_hud_layer)


func _add_button(bar: HBoxContainer, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	bar.add_child(b)


## Jumps the clock to TIMES[index] (and stops a time lapse).
func set_time(index: int) -> void:
	_time_index = posmod(index, TIMES.size())
	_time.hours_per_second = 0.0
	_time.hour = TIMES[_time_index]
	_atmosphere.update_now()


func _next_time() -> void:
	set_time(_time_index + 1)


func _toggle_time_lapse() -> void:
	_time.hours_per_second = 0.0 if _time.hours_per_second != 0.0 else TIME_LAPSE_HOURS_PER_SECOND


func _next_weather() -> void:
	_set_weather(_weather + 1, Atmosphere.WEATHER_TRANSITION)


func _set_weather(index: int, seconds: float) -> void:
	_weather = posmod(index, WEATHERS.size())
	_atmosphere.set_weather(WEATHERS[_weather], seconds)


## Next sea state, with its own weather: calm under a clear sky, a storm under storm clouds.
func _cycle_sea_state() -> void:
	_island.cycle_sea_state()
	_set_weather(SEA_STATE_WEATHER[_island.sea_state()], Atmosphere.WEATHER_TRANSITION)


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
		if number >= 0 and number < _views.size():
			show_view(number)
		elif key.physical_keycode == KEY_C:
			_cycle_sea_state()
		elif key.physical_keycode == KEY_L:
			_cycle_water_type()
		elif key.physical_keycode == KEY_T:
			_next_time()
		elif key.physical_keycode == KEY_Y:
			_toggle_time_lapse()
		elif key.physical_keycode == KEY_V:
			_next_weather()
		elif key.physical_keycode == KEY_F:
			_drop_objects()
		elif key.physical_keycode == KEY_K:
			print("Curling breakers: ", "on" if _island.toggle_curls() else "off")
		elif key.physical_keycode == KEY_F3:
			_perf.visible = not _perf.visible


func _cycle_water_type() -> void:
	print("Water type: ", _island.cycle_water_type())


func _drop_objects() -> void:
	# Drop where the camera is looking, also after moving with WASD.
	_dropper.drop_centre = _target()
	_dropper.drop_burst()


func _target() -> Vector3:
	return _views[_view].target + _target_offset


func _process(delta: float) -> void:
	_move_target(delta)
	var target := _target()
	_cam.global_position = target + Basis.from_euler(Vector3(_pitch, _yaw, 0)) * Vector3(0, 0, _distance)
	_cam.look_at(target)
	var lapse := ", time lapse" if _time.hours_per_second != 0.0 else ""
	_hud.text = "%s   (FPS %d)\n%s%s, %s | T: time of day | Y: time lapse | V: weather\nWASD move, Q/E down/up, Shift faster, drag to orbit, wheel to zoom, 1-5 views, F drop objects, F3 timings" % [
			_island.notes, Engine.get_frames_per_second(), _time.clock_text(), lapse,
			_atmosphere.current_weather().display_name]


## WASD moves the orbit point over the ground in the direction the camera faces; Q/E lower and raise it.
func _move_target(delta: float) -> void:
	var input := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): input.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S): input.z += 1.0
	if Input.is_physical_key_pressed(KEY_A): input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): input.x += 1.0
	if Input.is_physical_key_pressed(KEY_Q): input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_E): input.y += 1.0
	if input == Vector3.ZERO:
		return
	var speed := _distance * MOVE_SPEED_PER_DISTANCE
	if Input.is_physical_key_pressed(KEY_SHIFT):
		speed *= FAST_MULTIPLIER
	var flat := Basis(Vector3.UP, _yaw)
	var move := flat * Vector3(input.x, 0.0, input.z)
	if move != Vector3.ZERO:
		move = move.normalized()
	move.y = input.y
	_target_offset += move * speed * delta
	_target_offset.y = clampf(_target_offset.y, MIN_TARGET_HEIGHT, MAX_TARGET_HEIGHT)


## Called by tools/visual_check before each shot. Keys: view (index, see _make_views), time (index into
## TIMES; golden_hour true is TIMES[GOLDEN_HOUR]), hour (solar hour, overrides time), sea_state (index
## into IslandScene.STATES), weather (index into WEATHERS; by default the sea state's), ocean
## ({parameter name: value} set after the sea state, e.g. {"wind_speed": 40.0}), hud (bool: show the
## buttons and tuner, default off), tuner_step (index of the tuner step to open). The shot list places
## the camera itself.
func apply_visual_check_state(state: Dictionary) -> void:
	_hud_layer.visible = state.get("hud", false)
	var view: int = state.get("view", 0)
	show_view(view)
	var golden_hour: bool = state.get("golden_hour", false)
	var time: int = state.get("time", GOLDEN_HOUR if golden_hour else START_TIME)
	set_time(time)
	if state.has("hour"):
		var hour: float = state["hour"]
		_time.hour = hour
	var sea_state: int = state.get("sea_state", 1)
	_island.set_sea_state(sea_state)
	var weather: int = state.get("weather", SEA_STATE_WEATHER[_island.sea_state()])
	_set_weather(weather, 0.0)
	_atmosphere.update_now()
	var values: Dictionary = state.get("ocean", {})
	for parameter: String in values:
		var value: float = values[parameter]
		if not _island.ocean.set_parameter(StringName(parameter), value):
			push_error("Visual check: the ocean has no parameter '%s'" % parameter)
	if state.has("tuner_step"):
		var step: int = state["tuner_step"]
		_island.open_tuner_step(step)
