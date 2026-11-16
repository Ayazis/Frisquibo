extends Node3D
## Water demo: the island in the FFT ocean (IslandScene) with one sky and sun, an orbit camera,
## viewpoints (keys 1-5), the ocean tuner and objects to drop.

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
const BUTTON_BAR_Y := 130.0
## The controls start this far below the top of the button bar, clear of the buttons.
const CONTROLS_BELOW_BUTTONS := 44.0
## Gap between the controls panel and the right edge of the screen.
const CONTROLS_MARGIN := 16.0
const BANNER_Y := 14.0
const BANNER_FONT_SIZE := 34
const BANNER_COLOR := Color(0.55, 0.95, 0.6)
const SHADOW_DISTANCE := 150.0
const FOG_DENSITY := 0.0006
const FOG_AERIAL_PERSPECTIVE := 1.0


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
var _sun: DirectionalLight3D
var _env: Environment
var _hud: Label
var _banner: Label
var _view_buttons: Array[Button] = []
var _yaw := 0.0
var _pitch := -0.3
var _distance := 30.0
## Where WASD has moved the orbit point, relative to the viewpoint's target.
var _target_offset := Vector3.ZERO
var _golden_hour := false
var _hud_layer: CanvasLayer
var _dropper: ObjectDropper


func _ready() -> void:
	_make_env()
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
	_apply_time()
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


func _make_env() -> void:
	_env = Environment.new()
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.22, 0.42, 0.78)
	sky_material.sky_horizon_color = Color(0.72, 0.8, 0.88)
	sky.sky_material = sky_material
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_env.tonemap_exposure = 1.1
	_env.ssr_enabled = RenderingServer.get_current_rendering_method() == "forward_plus"
	_env.glow_enabled = true
	_env.fog_enabled = true
	_env.fog_density = FOG_DENSITY
	# The fog takes the sky's own colour, so it doesn't paint the sky (and the sea reflecting it) grey.
	_env.fog_aerial_perspective = FOG_AERIAL_PERSPECTIVE
	var world_environment := WorldEnvironment.new()
	world_environment.environment = _env
	add_child(world_environment)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = SHADOW_DISTANCE
	add_child(_sun)


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
	_add_button(buttons, "Sea state (C)", _island.cycle_sea_state)
	_add_button(buttons, "Water type (L)", _cycle_water_type)
	_add_button(buttons, "Time of day (T)", _toggle_time)
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
	add_child(_hud_layer)


func _add_button(bar: HBoxContainer, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	bar.add_child(b)


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
		if number >= 0 and number < _views.size():
			show_view(number)
		elif key.physical_keycode == KEY_C:
			_island.cycle_sea_state()
		elif key.physical_keycode == KEY_L:
			_cycle_water_type()
		elif key.physical_keycode == KEY_T:
			_toggle_time()
		elif key.physical_keycode == KEY_F:
			_drop_objects()


func _cycle_water_type() -> void:
	print("Water type: ", _island.cycle_water_type())


func _drop_objects() -> void:
	# Drop where the camera is looking, also after moving with WASD.
	_dropper.drop_centre = _target()
	_dropper.drop_burst()


func _toggle_time() -> void:
	_golden_hour = not _golden_hour
	_apply_time()


func _target() -> Vector3:
	return _views[_view].target + _target_offset


func _process(delta: float) -> void:
	_move_target(delta)
	var target := _target()
	_cam.global_position = target + Basis.from_euler(Vector3(_pitch, _yaw, 0)) * Vector3(0, 0, _distance)
	_cam.look_at(target)
	_hud.text = "%s   (FPS %d)\nWASD move, Q/E down/up, Shift faster, drag to orbit, wheel to zoom, 1-5 views, F drop objects" % [
			_island.notes, Engine.get_frames_per_second()]


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


## Called by tools/visual_check before each shot. Keys: view (index, see _make_views), golden_hour
## (bool), sea_state (index into IslandScene.STATES), ocean ({parameter name: value} set after the sea
## state, e.g. {"wind_speed": 40.0}). The shot list places the camera itself.
func apply_visual_check_state(state: Dictionary) -> void:
	_hud_layer.visible = false
	var view: int = state.get("view", 0)
	show_view(view)
	_golden_hour = state.get("golden_hour", false)
	_apply_time()
	var sea_state: int = state.get("sea_state", 1)
	_island.set_sea_state(sea_state)
	var values: Dictionary = state.get("ocean", {})
	for parameter: String in values:
		var value: float = values[parameter]
		if not _island.ocean.set_parameter(StringName(parameter), value):
			push_error("Visual check: the ocean has no parameter '%s'" % parameter)
