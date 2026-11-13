extends Node3D
## Medieval intro: arrive at a castle at dusk, open the gate, talk to the guard, train on the dummy,
## then ring the bell on the west wall. Everything (geometry, materials, particles, audio) is procedural.
##
## Debug args (after `--`): --skip-intro, --test (auto-plays the quest), --shot=<file.png>,
## --view=x,y,z,tx,ty,tz (fixed camera for screenshots), --delay=<seconds>.

const B := preload("res://intro/build.gd")
const Castle := preload("res://intro/castle.gd")
const Sfx := preload("res://intro/sfx.gd")
const PlayerScript := preload("res://intro/player.gd")
const UIScript := preload("res://intro/ui.gd")

const SIZE := 160
const START := Vector3(0, 0, 40)

var IS_WEB := OS.has_feature("web")
var noise := FastNoiseLite.new()
var patch_noise := FastNoiseLite.new()
var env: Environment
var sky_mat: ProceduralSkyMaterial
var sun: DirectionalLight3D
var grass_mat: ShaderMaterial
var player: PlayerScript
var ui: UIScript
var cine: Camera3D
var cine_look := Vector3(0, 5, 0)
var parts := {}
var torches: Array[OmniLight3D] = []
var fireflies: GPUParticles3D
var straw_burst: GPUParticles3D
var sounds := {}

var stage := 0 # 0 open gate, 1 talk to guard, 2 dummy, 3 report back, 4 ring bell, 5 ending
var mode := "intro" # intro | play | dialog | ending
var interactables: Array[Dictionary] = []
var current: Dictionary = {}
var dialog: Array = []
var dialog_i := 0
var gate_open := false
var dummy_hits := 0
var dummy_ang := Vector2.ZERO
var dummy_vel := Vector2.ZERO
var bell_ang := 0.0
var bell_vel := 0.0
var t := 0.0
var args := {}


func height(x: float, z: float) -> float:
	var d := maxf(absf(x), absf(z))
	var k := smoothstep(22.0, 55.0, d)
	var rim := smoothstep(50.0, 80.0, d)
	return noise.get_noise_2d(x, z) * 9.0 * k + k * 1.5 + rim * rim * 22.0


func is_grass(x: float, z: float) -> bool:
	if absf(x) < 17.0 and absf(z) < 17.0:
		return false
	if z > 15.0 and absf(x) < 2.6 + patch_noise.get_noise_1d(z) * 0.8:
		return false
	return true


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := (a as String).trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	noise.seed = 11
	noise.frequency = 0.018
	noise.fractal_octaves = 4
	patch_noise.seed = 3
	patch_noise.frequency = 0.05

	_make_env()
	_make_ground()
	_make_grass()
	_make_trees()
	parts = Castle.build(self, IS_WEB)
	for i in parts["torches"].size():
		torches.append(Castle.torch(self, parts["torches"][i], not IS_WEB and i < 2))
	for c in parts["chimneys"]:
		var sm := Castle.smoke_particles()
		sm.position = c
		add_child(sm)
	var sparks := Castle.spark_particles()
	sparks.position = parts["forge"]
	add_child(sparks)
	var forge_light := OmniLight3D.new()
	forge_light.position = parts["forge"] + Vector3(-0.5, 0.5, 0)
	forge_light.light_color = Color(1.0, 0.45, 0.12)
	forge_light.light_energy = 3.0
	forge_light.omni_range = 6.0
	add_child(forge_light)
	torches.append(forge_light)
	straw_burst = Castle.burst_particles(Color(0.95, 0.8, 0.4))
	add_child(straw_burst)
	_make_fireflies()
	_make_props()
	_make_guard()
	_make_audio()

	player = PlayerScript.new()
	player.position = START + Vector3(0, height(START.x, START.z) + 0.1, 0)
	add_child(player)
	player.swung.connect(_on_swing)
	ui = UIScript.new()
	add_child(ui)

	_register("lever", parts["lever"], "Pull the gate lever", _use_lever, 2.2)
	_register("guard", parts["guard"], "Speak with the guard", _talk_guard, 2.6)
	_register("bell", parts["bell"], "Ring the bell", _ring_bell, 2.6)
	_register("well", null, "Peer into the well", _peer_well, 1.9, Vector3(4.5, 0.5, 3))
	_register("stall", null, "Browse the market stall", _browse_stall, 2.2, parts["stall"])

	cine = Camera3D.new()
	cine.fov = 55
	cine.far = 400
	add_child(cine)
	cine.make_current()
	if args.has("view"):
		var v: PackedFloat64Array = (args["view"] as String).split_floats(",")
		cine.position = Vector3(v[0], v[1], v[2])
		cine_look = Vector3(v[3], v[4], v[5])
		mode = "view"
		ui.fade.color.a = 0.0
		ui.hide_hud()
	elif args.has("skip-intro") or args.has("test"):
		_start_play()
		ui.fade.color.a = 0.0
	else:
		_play_intro()
	if args.has("test"):
		_run_test()
	if args.has("shot"):
		var delay := float(args.get("delay", "4"))
		get_tree().create_timer(delay).timeout.connect(_take_shot)


# ---------------------------------------------------------------- world

func _make_env() -> void:
	env = Environment.new()
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.13, 0.17, 0.36)
	sky_mat.sky_horizon_color = Color(0.95, 0.55, 0.36)
	sky_mat.sky_curve = 0.12
	sky_mat.ground_horizon_color = Color(0.4, 0.27, 0.22)
	sky_mat.ground_bottom_color = Color(0.06, 0.05, 0.06)
	sky_mat.sun_angle_max = 25.0
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15
	env.ssao_enabled = not IS_WEB
	env.glow_enabled = true
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.5, 0.42)
	env.fog_density = 0.0045
	env.fog_sun_scatter = 0.5
	env.fog_aerial_perspective = 0.5
	if not IS_WEB:
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.005
		env.volumetric_fog_albedo = Color(0.9, 0.75, 0.65)
		env.volumetric_fog_length = 80.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-11, -135, 0)
	sun.light_color = Color(1.0, 0.6, 0.38)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0 if IS_WEB else 90.0
	sun.shadow_blur = 1.2
	add_child(sun)


func _make_ground() -> void:
	var half := SIZE / 2
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hmap := PackedFloat32Array()
	for iz in range(SIZE + 1):
		for ix in range(SIZE + 1):
			var x := float(ix - half)
			var z := float(iz - half)
			var y := height(x, z)
			hmap.append(y)
			var n := patch_noise.get_noise_2d(x * 2.0, z * 2.0) * 0.5 + 0.5
			var col: Color
			if absf(x) < 14.5 and absf(z) < 14.5:
				col = Color(0.3, 0.24, 0.17).lerp(Color(0.24, 0.2, 0.15), n)
			elif not is_grass(x, z):
				col = Color(0.36, 0.28, 0.18).lerp(Color(0.3, 0.25, 0.16), n)
			else:
				col = Color(0.09, 0.14, 0.045).lerp(Color(0.17, 0.17, 0.06), n)
			st.set_color(col)
			st.add_vertex(Vector3(x, y, z))
	for iz in range(SIZE):
		for ix in range(SIZE):
			var i := iz * (SIZE + 1) + ix
			st.add_index(i); st.add_index(i + 1); st.add_index(i + SIZE + 1)
			st.add_index(i + 1); st.add_index(i + SIZE + 2); st.add_index(i + SIZE + 1)
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	B.mesh(self, st.commit(), Vector3.ZERO, mat)
	var shape := HeightMapShape3D.new()
	shape.map_width = SIZE + 1
	shape.map_depth = SIZE + 1
	shape.map_data = hmap
	B.collider(self, shape, Vector3.ZERO)


func _blade_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 4
	for i in range(segs + 1):
		var h := float(i) / segs
		var w := 0.035 * pow(1.0 - h, 0.7) + 0.002
		var z := h * h * 0.12
		st.set_normal(Vector3(0, 0, 1))
		st.set_uv(Vector2(0, h))
		st.add_vertex(Vector3(-w, h, z))
		st.set_normal(Vector3(0, 0, 1))
		st.set_uv(Vector2(1, h))
		st.add_vertex(Vector3(w, h, z))
	for i in range(segs):
		var a := i * 2
		st.add_index(a); st.add_index(a + 2); st.add_index(a + 1)
		st.add_index(a + 1); st.add_index(a + 2); st.add_index(a + 3)
	return st.commit()


## Same wind/push grass as the grass demo (reuses res://grass.gdshader), only outside the walls.
func _make_grass() -> void:
	grass_mat = ShaderMaterial.new()
	grass_mat.shader = load("res://grass.gdshader")
	grass_mat.set_shader_parameter("wind_strength", 0.3)
	grass_mat.set_shader_parameter("dry_color", Color(0.75, 0.55, 0.28))
	var count := 60000 if IS_WEB else 200000
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _blade_mesh()
	mm.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var i := 0
	while i < count:
		# denser near the castle and path, sparser far away
		var r := sqrt(rng.randf()) * 50.0
		var a := rng.randf() * TAU
		var x := sin(a) * r
		var z := cos(a) * r + 8.0
		if not is_grass(x, z):
			continue
		var patch := clampf(patch_noise.get_noise_2d(x, z) * 1.5 + 0.2, 0.0, 1.0)
		var tall := rng.randf_range(0.4, 0.9) * (1.0 + patch * 0.6)
		var bs := Basis(Vector3.UP, rng.randf() * TAU)
		bs = Basis(Vector3(rng.randf() - 0.5, 0, rng.randf() - 0.5).normalized(), rng.randf() * 0.25) * bs
		bs = bs.scaled_local(Vector3(rng.randf_range(0.8, 1.5), tall, 1.0))
		mm.set_instance_transform(i, Transform3D(bs, Vector3(x, height(x, z) - 0.03, z)))
		mm.set_instance_custom_data(i, Color(rng.randf(), patch * rng.randf_range(0.5, 1.0), 0, 0))
		i += 1
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = grass_mat
	mmi.extra_cull_margin = 2.0
	add_child(mmi)


func _make_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var bark := B.mat(Color(0.22, 0.14, 0.08))
	var leaves := [B.mat(Color(0.07, 0.16, 0.08)), B.mat(Color(0.09, 0.19, 0.07)), B.mat(Color(0.12, 0.17, 0.06))]
	var placed := 0
	while placed < 70:
		var a := rng.randf() * TAU
		var r := rng.randf_range(26.0, 75.0)
		var x := sin(a) * r
		var z := cos(a) * r
		if absf(x) < 9.0 and z > 15.0: # keep the road and the view of the gate clear
			continue
		var s := rng.randf_range(0.8, 1.6)
		var base := Vector3(x, height(x, z) - 0.2, z)
		B.cyl(self, base + Vector3(0, 1.0 * s, 0), 0.15 * s, 0.25 * s, 2.0 * s, bark, true, 8)
		var lm: Material = leaves[rng.randi() % 3]
		for k in 3:
			B.cyl(self, base + Vector3(0, (2.2 + k * 1.3) * s, 0), 0.0, (1.9 - k * 0.45) * s, 2.4 * s, lm, false, 10)
		placed += 1
	for k in 25: # boulders
		var a := rng.randf() * TAU
		var r := rng.randf_range(20.0, 60.0)
		var p := Vector3(sin(a) * r, 0, cos(a) * r)
		if not is_grass(p.x, p.z):
			continue
		p.y = height(p.x, p.z)
		var rs := rng.randf_range(0.4, 1.3)
		B.sphere(self, p, rs, B.mat(Color(0.4, 0.39, 0.37)), Vector3(1.3, 0.7, 1.0)).rotation.y = rng.randf() * TAU


func _make_fireflies() -> void:
	fireflies = GPUParticles3D.new()
	fireflies.amount = 160
	fireflies.lifetime = 7.0
	fireflies.visibility_aabb = AABB(Vector3(-25, -5, -25), Vector3(50, 15, 50))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 1.5, 22)
	pm.gravity = Vector3(0, 0.03, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.0
	pm.color_ramp = Castle._ramp([Color(0.9, 1.0, 0.4, 0), Color(0.9, 1.0, 0.4, 1), Color(0.9, 1.0, 0.4, 0)])
	fireflies.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.07)
	q.material = Castle._particle_mat(true)
	fireflies.draw_pass_1 = q
	add_child(fireflies)


func _crate(pos: Vector3, size: Vector3, barrel := false) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.mass = 6.0 if barrel else 4.0
	rb.add_to_group("props")
	var cs := CollisionShape3D.new()
	if barrel:
		var sh := CylinderShape3D.new()
		sh.radius = size.x / 2
		sh.height = size.y
		cs.shape = sh
		B.cyl(rb, Vector3.ZERO, size.x * 0.45, size.x * 0.45, size.y, B.mat(Color(0.38, 0.22, 0.1)), false, 14)
		for yy in [-0.3, 0.3]:
			B.cyl(rb, Vector3(0, size.y * yy, 0), size.x * 0.5, size.x * 0.5, 0.06, B.mat(Color(0.15, 0.15, 0.15), 0.5, 0.7), false, 14)
	else:
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		B.box(rb, Vector3.ZERO, size, B.mat(Color(0.5, 0.36, 0.2)), false)
		B.box(rb, Vector3.ZERO, size * Vector3(1.02, 0.25, 1.02), B.mat(Color(0.32, 0.2, 0.1)), false)
	rb.add_child(cs)
	rb.position = pos
	add_child(rb)
	return rb


func _make_props() -> void:
	var c := 0.7
	for p in [Vector3(7.6, 0.36, 9.0), Vector3(8.4, 0.36, 9.2), Vector3(8.0, 1.07, 9.1), Vector3(-10, 0.36, -6), Vector3(5, 0.36, -5.5)]:
		_crate(p, Vector3(c, c, c))
	for p in [Vector3(8.0, 0.5, -0.4), Vector3(8.0, 0.5, 0.6), Vector3(3.2, 0.5, 13.0), Vector3(-6.8, 0.5, 13.0)]:
		_crate(p, Vector3(0.75, 1.0, 0.75), true)


func _make_guard() -> void:
	var g := B.knight(Color(0.6, 0.08, 0.08), Color(0.95, 0.85, 0.3))
	g.position = Vector3(3.6, 0, 11.6)
	g.rotation.y = PI + 0.5 # facing the gate
	add_child(g)
	var wood := B.mat(Color(0.3, 0.18, 0.09))
	B.cyl(g, Vector3(0.42, 1.3, -0.1), 0.03, 0.03, 2.6, wood, false, 6)
	B.cyl(g, Vector3(0.42, 2.7, -0.1), 0.0, 0.07, 0.3, B.mat(Color(0.8, 0.8, 0.85), 0.25, 0.9), false, 6)
	var col := CapsuleShape3D.new()
	col.radius = 0.35
	col.height = 1.8
	B.collider(self, col, g.position + Vector3(0, 0.9, 0))
	parts["guard"] = g


func _make_audio() -> void:
	sounds["bell"] = Sfx.bell()
	sounds["clank"] = Sfx.clank()
	sounds["chain"] = Sfx.chain()
	sounds["whoosh"] = Sfx.whoosh()
	sounds["thud"] = Sfx.thud()
	var amb := AudioStreamPlayer.new()
	amb.stream = Sfx.wind()
	amb.volume_db = -16.0
	amb.autoplay = true
	add_child(amb)


func _play(snd: String, at: Vector3, db := 0.0) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = sounds[snd]
	p.volume_db = db
	p.unit_size = 12.0
	add_child(p)
	p.global_position = at
	p.play()
	p.finished.connect(p.queue_free)


# ---------------------------------------------------------------- sequence

func _play_intro() -> void:
	mode = "intro"
	cine.position = Vector3(70, 34, 85)
	cine_look = Vector3(0, 6, 0)
	ui.fade.color.a = 1.0
	ui.fade_to(0.0, 2.5)
	var tw := create_tween()
	tw.tween_property(cine, "position", Vector3(16, 9, 48), 9.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(self, "cine_look", Vector3(0, 4, 15), 9.0).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_callback(ui.title_card.bind("Chapter I  ·  The Gate at Dusk", "", true, 2.0)).set_delay(1.5)
	tw.parallel().tween_callback(ui.title_card.bind("Chapter I  ·  The Gate at Dusk", "", false, 1.5)).set_delay(6.5)
	tw.tween_callback(_cine_to_player)


func _cine_to_player() -> void:
	if mode != "intro":
		return
	var tw := create_tween()
	tw.tween_property(cine, "global_transform", player.cam.global_transform, 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(_start_play)


func _start_play() -> void:
	mode = "play"
	player.cam.make_current()
	player.controls_enabled = true
	ui.title_card("", "", false, 0.3)
	ui.set_objective(_objective_text())
	if not args.has("test"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _objective_text() -> String:
	match stage:
		0: return "Find a way through the castle gate"
		1: return "Speak with the guard"
		2: return "Strike the training dummy  (%d/3)" % dummy_hits
		3: return "Report back to the guard"
		4: return "Ring the bell atop the west wall"
	return ""


func _advance(to: int) -> void:
	stage = to
	ui.set_objective(_objective_text())


func _register(id: String, node: Node3D, prompt: String, fn: Callable, radius: float, pos := Vector3.ZERO) -> void:
	interactables.append({"id": id, "node": node, "pos": pos, "prompt": prompt, "fn": fn, "r": radius})


func _say(lines: Array) -> void:
	dialog = lines
	dialog_i = 0
	mode = "dialog"
	player.controls_enabled = false
	ui.show_prompt("")
	ui.show_dialog(dialog[0][0], dialog[0][1])


func _dialog_next() -> void:
	dialog_i += 1
	if dialog_i >= dialog.size():
		ui.hide_dialog()
		mode = "play"
		player.controls_enabled = true
		return
	ui.show_dialog(dialog[dialog_i][0], dialog[dialog_i][1])


func _use_lever() -> void:
	if gate_open:
		_say([["", "The lever is locked in place. The way is open."]])
		return
	gate_open = true
	var lv: Node3D = parts["lever"]
	_play("clank", lv.global_position)
	create_tween().tween_property(parts["lever_handle"], "rotation:x", -0.7, 0.35).set_trans(Tween.TRANS_BACK)
	var port: Node3D = parts["portcullis"]
	_play("chain", port.global_position + Vector3(0, 3, 0), 3.0)
	var tw := create_tween()
	tw.tween_interval(0.4)
	tw.tween_property(port, "position:y", 4.7, 2.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(_play.bind("clank", port.global_position + Vector3(0, 5, 0), -4.0))
	_advance(1)


func _talk_guard() -> void:
	var g := "Sir Aldric, Gate Warden"
	match stage:
		0, 1:
			_say([
				[g, "Ho there! You raised the portcullis yourself? Bold — or foolish."],
				[g, "Welcome to Frisquibo, traveller. Our lord seeks new blades to guard the valley."],
				[g, "But words are wind. Show me your arm on yon training dummy — three clean strikes."],
			])
			_advance(2)
		2:
			_say([[g, "The dummy by the hay bales. Three strikes — I'm counting."]])
		3:
			_say([
				[g, "Ha! The straw will remember that. You'll do nicely."],
				[g, "Climb the stair to the west wall and ring the great bell."],
				[g, "Let the whole valley hear that Frisquibo has a new knight."],
			])
			_advance(4)
		_:
			_say([[g, "The bell, friend! Up the west stair."]])


func _peer_well() -> void:
	_say([["", "Your reflection stares back, helm askew. Somewhere far below, a drip echoes."]])


func _browse_stall() -> void:
	_say([["Merchant", "Apples from the valley, oranges from beyond the sea! ...Come back when you've earned a coin, sir knight."]])


func _on_swing() -> void:
	_play("whoosh", player.global_position + Vector3(0, 1.2, 0), -6.0)
	var p := player.global_position
	var fwd := player.facing()
	var dummy: Node3D = parts["dummy"]
	var to := dummy.global_position - p
	to.y = 0
	if to.length() < 2.4 and fwd.dot(to.normalized()) > 0.2:
		var push := to.normalized()
		dummy_vel += Vector2(push.z, -push.x) * 4.5
		_play("thud", dummy.global_position + Vector3(0, 1.2, 0))
		straw_burst.global_position = dummy.global_position + Vector3(0, 1.3, 0) - push * 0.3
		straw_burst.restart()
		if stage == 2:
			dummy_hits += 1
			if dummy_hits >= 3:
				_advance(3)
			else:
				ui.set_objective(_objective_text())
	for n in get_tree().get_nodes_in_group("props"):
		var rb := n as RigidBody3D
		var d := rb.global_position - p
		if d.length() < 2.2 and fwd.dot(d.normalized()) > 0.2:
			rb.apply_central_impulse((fwd + Vector3.UP * 0.4) * 9.0)
			_play("thud", rb.global_position, -6.0)


func _ring_bell() -> void:
	if stage < 4:
		_say([["", "A great bronze bell. Best not ring it without the warden's leave."]])
		return
	bell_vel += 2.2
	_play("bell", (parts["bell"] as Node3D).global_position, 6.0)
	if stage == 4:
		stage = 5
		_ending()


func _ending() -> void:
	mode = "ending"
	player.controls_enabled = false
	ui.hide_hud()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	cine.global_transform = player.cam.global_transform
	cine_look = player.global_position + Vector3(0, 1.5, 0)
	cine.make_current()
	var tw := create_tween()
	tw.tween_interval(1.0)
	tw.tween_callback(_ring_again)
	tw.tween_property(cine, "position", Vector3(-62, 26, 30), 10.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(self, "cine_look", Vector3(0, 6, 0), 6.0)
	tw.parallel().tween_property(sun, "light_energy", 0.12, 9.0)
	tw.parallel().tween_property(sun, "light_color", Color(0.5, 0.6, 1.0), 9.0)
	tw.parallel().tween_property(sky_mat, "sky_top_color", Color(0.02, 0.03, 0.09), 9.0)
	tw.parallel().tween_property(sky_mat, "sky_horizon_color", Color(0.22, 0.14, 0.24), 9.0)
	tw.parallel().tween_property(env, "ambient_light_energy", 0.25, 9.0)
	tw.parallel().tween_property(env, "fog_light_color", Color(0.15, 0.13, 0.22), 9.0)
	tw.parallel().tween_callback(ui.title_card.bind("Your tale begins…", "Press R to play again", true, 3.0)).set_delay(5.0)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _run_test() -> void:
	# Drives the whole quest without input so a run can verify the flow end to end.
	await _wait(0.5)
	print("[test] stage=", stage)
	_use_lever()
	await _wait(3.6)
	print("[test] gate y=", (parts["portcullis"] as Node3D).position.y, " stage=", stage)
	player.global_position = Vector3(2.4, 0.1, 10.4)
	_talk_guard()
	for k in 3:
		_dialog_next()
	print("[test] after guard stage=", stage, " mode=", mode)
	for k in 3:
		player.global_position = Vector3(-7, 0.1, 8.6)
		player.face(Vector3(0, 0, -1))
		_on_swing()
		await _wait(0.5)
	print("[test] hits=", dummy_hits, " stage=", stage)
	_talk_guard()
	for k in 3:
		_dialog_next()
	print("[test] stage=", stage)
	player.global_position = Vector3(-14.5, 0.2, 11.5)
	player.velocity = Vector3.ZERO
	print("[test] walking up the stairs...")
	player.controls_enabled = true
	player.yaw = 0.0
	var ev := InputEventKey.new()
	ev.keycode = KEY_W
	ev.physical_keycode = KEY_W
	ev.pressed = true
	Input.parse_input_event(ev)
	await _wait(3.5)
	ev = ev.duplicate()
	ev.pressed = false
	Input.parse_input_event(ev)
	print("[test] after stairs pos=", player.global_position)
	player.global_position = Vector3(-15, 7.2, -5.2)
	await _wait(0.5)
	print("[test] player on wall y=", player.global_position.y)
	_ring_bell()
	print("[test] ending stage=", stage, " mode=", mode)


func _take_shot() -> void:
	var path: String = args["shot"]
	if path == "":
		path = "shot.png"
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://" + path))
	print("[shot] saved ", path)
	get_tree().quit()


# ---------------------------------------------------------------- loop

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E:
				if mode == "dialog":
					_dialog_next()
				elif mode == "play" and not current.is_empty():
					(current["fn"] as Callable).call()
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_R:
				if mode == "ending":
					get_tree().reload_current_scene()
			KEY_SPACE, KEY_ENTER:
				if mode == "intro":
					_cine_to_player()
	elif event is InputEventMouseButton and event.pressed and mode == "intro":
		_cine_to_player()


func _process(delta: float) -> void:
	t += delta
	# torch flicker
	for i in torches.size():
		var l := torches[i]
		var f := 0.82 + 0.18 * sin(t * 13.0 + i * 3.1) * sin(t * 7.3 + i * 1.7) + 0.06 * sin(t * 29.0 + i)
		l.light_energy = (3.0 if i == torches.size() - 1 else 2.2) * f

	# dummy + bell springs
	var dacc := -dummy_ang * 60.0 - dummy_vel * 3.5
	dummy_vel += dacc * delta
	dummy_ang += dummy_vel * delta
	var dummy: Node3D = parts["dummy"]
	dummy.rotation = Vector3(dummy_ang.x, 0, dummy_ang.y)
	bell_vel += (-bell_ang * 9.0 - bell_vel * 0.4) * delta
	bell_ang += bell_vel * delta
	(parts["bell"] as Node3D).rotation.x = bell_ang

	if mode == "intro" or mode == "ending" or mode == "view":
		cine.look_at(cine_look)

	# grass reacts to the knight
	var pp := player.global_position
	grass_mat.set_shader_parameter("pushers", [Vector4(pp.x, pp.y + 0.4, pp.z, 0.45)])
	grass_mat.set_shader_parameter("pusher_count", 1)
	fireflies.global_position = Vector3(pp.x, height(pp.x, pp.z) + 1.0, pp.z)

	# nearest interactable
	current = {}
	if mode == "play":
		var best := 999.0
		for it in interactables:
			var n: Node3D = it["node"]
			var pos: Vector3 = n.global_position if n else it["pos"]
			var d := Vector2(pos.x - pp.x, pos.z - pp.z).length()
			if d < it["r"] and absf(pos.y - pp.y) < 3.5 and d < best:
				best = d
				current = it
		ui.show_prompt("" if current.is_empty() else "[E]  " + String(current["prompt"]))




func _ring_again() -> void:
	_play("bell", (parts["bell"] as Node3D).global_position, 6.0)
	bell_vel += 2.2
