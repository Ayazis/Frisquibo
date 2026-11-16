extends Node3D
## Grass playground on a small island: shader-animated blades, wind gusts, a sandy beach and sea,
## and physics balls that push the grass.

const SIZE := 80
var IS_WEB := OS.has_feature("web")
var BLADES := 100000 if IS_WEB else 320000
const MAX_BALLS := 15

var island := IslandShape.new(SIZE, 7)
var patch_noise := FastNoiseLite.new()
var grass_mat: ShaderMaterial
var player: RigidBody3D
var balls: Array[RigidBody3D] = []
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var hud: Label
var pollen: GPUParticles3D

var yaw := 0.6
var pitch := -0.3
var cam_dist := 9.0
var wind := 0.35
var time_preset := 0


func height(x: float, z: float) -> float:
	return island.height(x, z)


func _ready() -> void:
	patch_noise.seed = 3
	patch_noise.frequency = 0.05
	_make_env()
	_make_ground()
	_make_grass()
	add_child(Sea.new())
	_make_pollen()
	player = _spawn_ball(Vector3(0, height(0, 0) + 2.0, 0), 0.6, Color(0.95, 0.35, 0.15))
	cam = Camera3D.new()
	cam.fov = 65
	add_child(cam)
	_make_hud()
	_apply_time()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Called by the visual check tool (tools/visual_check) to put the scene in a fixed state for a shot.
func apply_visual_check_state(state: Dictionary) -> void:
	hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	time_preset = state.get("time_preset", time_preset)
	wind = state.get("wind", wind)
	_apply_time()


func _make_env() -> void:
	env = Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.22, 0.42, 0.78)
	sm.sky_horizon_color = Color(0.72, 0.8, 0.88)
	sm.ground_horizon_color = Color(0.5, 0.55, 0.45)
	sm.ground_bottom_color = Color(0.15, 0.18, 0.1)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.ssao_enabled = not IS_WEB
	env.ssao_radius = 1.5
	env.glow_enabled = true
	env.glow_bloom = 0.08
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.78, 0.88)
	env.fog_density = 0.006
	env.fog_sun_scatter = 0.35
	env.fog_aerial_perspective = 0.4
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0 if IS_WEB else 50.0
	sun.shadow_blur = 1.5
	add_child(sun)


func _make_ground() -> void:
	var half := SIZE / 2.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hmap := PackedFloat32Array()
	for iz in range(SIZE + 1):
		for ix in range(SIZE + 1):
			var px := ix - half
			var pz := iz - half
			var y := height(px, pz)
			hmap.append(y)
			st.set_uv(Vector2(px, pz) * 0.25)
			st.add_vertex(Vector3(px, y, pz))
	for iz in range(SIZE):
		for ix in range(SIZE):
			var i := iz * (SIZE + 1) + ix
			st.add_index(i); st.add_index(i + 1); st.add_index(i + SIZE + 1)
			st.add_index(i + 1); st.add_index(i + SIZE + 2); st.add_index(i + SIZE + 1)
	st.generate_normals()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://world/terrain/terrain_ground.gdshader")
	mat.set_shader_parameter("sea_level", IslandShape.SEA_LEVEL)
	mat.set_shader_parameter("beach_top", IslandShape.BEACH_TOP)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)

	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := HeightMapShape3D.new()
	shape.map_width = SIZE + 1
	shape.map_depth = SIZE + 1
	shape.map_data = hmap
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


func _blade_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 5
	for i in range(segs + 1):
		var t := float(i) / segs
		var w := 0.03 * pow(1.0 - t, 0.7) + 0.002
		var z := t * t * 0.12
		st.set_normal(Vector3(0, 0, 1))
		st.set_uv(Vector2(0, t))
		st.add_vertex(Vector3(-w, t, z))
		st.set_normal(Vector3(0, 0, 1))
		st.set_uv(Vector2(1, t))
		st.add_vertex(Vector3(w, t, z))
	for i in range(segs):
		var a := i * 2
		st.add_index(a); st.add_index(a + 2); st.add_index(a + 1)
		st.add_index(a + 1); st.add_index(a + 2); st.add_index(a + 3)
	return st.commit()


func _make_grass() -> void:
	grass_mat = ShaderMaterial.new()
	grass_mat.shader = load("res://grass.gdshader")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _blade_mesh()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var lim := SIZE / 2.0 - 1.0
	var transforms: Array[Transform3D] = []
	var customs: Array[Color] = []
	for i in range(BLADES):
		var x := rng.randf_range(-lim, lim)
		var z := rng.randf_range(-lim, lim)
		if island.is_beach(x, z):
			continue
		var patch := clampf(patch_noise.get_noise_2d(x, z) * 1.5 + 0.2, 0.0, 1.0)
		var tall := rng.randf_range(0.45, 0.95) * (1.0 + patch * 0.5)
		var b := Basis(Vector3.UP, rng.randf() * TAU)
		b = Basis(Vector3(rng.randf() - 0.5, 0, rng.randf() - 0.5).normalized(), rng.randf() * 0.25) * b
		b = b.scaled_local(Vector3(rng.randf_range(0.8, 1.5), tall, 1.0))
		transforms.append(Transform3D(b, Vector3(x, height(x, z) - 0.03, z)))
		customs.append(Color(rng.randf(), patch * rng.randf_range(0.5, 1.0), 0, 0))
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_custom_data(i, customs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = grass_mat
	mmi.extra_cull_margin = 2.0
	add_child(mmi)


func _make_pollen() -> void:
	pollen = GPUParticles3D.new()
	pollen.amount = 400
	pollen.lifetime = 8.0
	pollen.visibility_aabb = AABB(Vector3(-20, -5, -20), Vector3(40, 15, 40))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(18, 2, 18)
	pm.gravity = Vector3(0.3, 0.02, 0.1)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.5
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pollen.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.04, 0.04)
	var qm := StandardMaterial3D.new()
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.albedo_color = Color(1.0, 0.95, 0.7)
	qm.emission_enabled = true
	qm.emission = Color(1.0, 0.9, 0.5)
	qm.emission_energy_multiplier = 2.0
	q.material = qm
	pollen.draw_pass_1 = q
	add_child(pollen)


func _spawn_ball(pos: Vector3, r: float, col: Color) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.mass = r * 3.0
	var pmat := PhysicsMaterial.new()
	pmat.bounce = 0.3
	pmat.friction = 0.9
	rb.physics_material_override = pmat
	rb.angular_damp = 0.5
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = r
	cs.shape = sh
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.25
	m.metallic = 0.1
	sm.material = m
	mi.mesh = sm
	rb.add_child(mi)
	add_child(rb)
	rb.global_position = pos
	return rb


func _make_hud() -> void:
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	hud.add_theme_constant_override("shadow_offset_x", 1)
	hud.add_theme_constant_override("shadow_offset_y", 1)
	var layer := CanvasLayer.new()
	layer.add_child(hud)
	add_child(layer)


func _apply_time() -> void:
	match time_preset:
		0: # midday
			sun.rotation_degrees = Vector3(-50, -40, 0)
			sun.light_color = Color(1.0, 0.95, 0.85)
			sun.light_energy = 1.4
			env.fog_light_color = Color(0.7, 0.78, 0.88)
		1: # golden hour
			sun.rotation_degrees = Vector3(-12, -70, 0)
			sun.light_color = Color(1.0, 0.68, 0.38)
			sun.light_energy = 1.8
			env.fog_light_color = Color(0.95, 0.72, 0.5)
		2: # dusk
			sun.rotation_degrees = Vector3(-4, -100, 0)
			sun.light_color = Color(1.0, 0.45, 0.3)
			sun.light_energy = 1.0
			env.fog_light_color = Color(0.45, 0.35, 0.45)


func _unhandled_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	var button := event as InputEventMouseButton
	var key := event as InputEventKey
	if motion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= motion.relative.x * 0.004
		pitch = clampf(pitch - motion.relative.y * 0.004, -1.3, 0.15)
	elif button and button.pressed:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_dist = maxf(cam_dist - 0.7, 2.5)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_dist = minf(cam_dist + 0.7, 30.0)
		elif button.button_index == MOUSE_BUTTON_LEFT:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				_throw_ball()
	elif key and key.pressed and not key.echo:
		match key.keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_T:
				time_preset = (time_preset + 1) % 3
				_apply_time()
			KEY_E:
				wind = minf(wind + 0.1, 1.5)
			KEY_Q:
				wind = maxf(wind - 0.1, 0.0)
			KEY_R:
				player.global_position = Vector3(0, height(0, 0) + 2.0, 0)
				player.linear_velocity = Vector3.ZERO
			KEY_SPACE:
				if player.global_position.y - height(player.global_position.x, player.global_position.z) < 0.85:
					player.apply_central_impulse(Vector3.UP * 9.0)


func _throw_ball() -> void:
	var fwd := -cam.global_basis.z
	var col := Color.from_hsv(randf(), 0.6, 0.95)
	var b := _spawn_ball(cam.global_position + fwd * 1.5, randf_range(0.3, 0.8), col)
	b.linear_velocity = fwd * 22.0
	balls.append(b)
	if balls.size() > MAX_BALLS - 1:
		var oldest: RigidBody3D = balls.pop_front()
		oldest.queue_free()


## The player and every thrown ball; all of them are spheres.
func _bodies() -> Array[RigidBody3D]:
	var all: Array[RigidBody3D] = [player]
	all.append_array(balls)
	return all


func _physics_process(_delta: float) -> void:
	var f := Vector3.ZERO
	var fwd := -cam.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	if Input.is_key_pressed(KEY_W): f += fwd
	if Input.is_key_pressed(KEY_S): f -= fwd
	if Input.is_key_pressed(KEY_D): f += right
	if Input.is_key_pressed(KEY_A): f -= right
	if f != Vector3.ZERO:
		player.apply_central_force(f.normalized() * 30.0 * player.mass)
	# keep things on the field
	for b in _bodies():
		if b.global_position.y < -20.0:
			b.global_position = Vector3(0, 8, 0)
			b.linear_velocity = Vector3.ZERO


func _process(delta: float) -> void:
	var target := player.global_position
	var offset := Basis.from_euler(Vector3(pitch, yaw, 0)) * Vector3(0, 0, cam_dist)
	var cp := target + offset
	cp.y = maxf(cp.y, height(cp.x, cp.z) + 0.6)
	cam.global_position = cam.global_position.lerp(cp, 1.0 - exp(-12.0 * delta)) if cam.global_position != Vector3.ZERO else cp
	cam.look_at(target + Vector3.UP * 0.6)
	pollen.global_position = Vector3(target.x, target.y + 1.0, target.z)

	var pushers: Array = []
	for b in _bodies():
		var sphere := (b.get_child(0) as CollisionShape3D).shape as SphereShape3D
		var r := sphere.radius
		var p: Vector3 = b.global_position
		pushers.append(Vector4(p.x, p.y, p.z, r))
	grass_mat.set_shader_parameter("pushers", pushers)
	grass_mat.set_shader_parameter("pusher_count", pushers.size())
	grass_mat.set_shader_parameter("wind_strength", wind)

	hud.text = "FPS %d   |   WASD roll   Space jump   Mouse look   Wheel zoom   Click throw ball\nQ/E wind (%.1f)   T time of day   R reset   Esc free mouse" % [Engine.get_frames_per_second(), wind]