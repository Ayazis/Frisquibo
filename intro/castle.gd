extends RefCounted
## Procedural castle: curtain walls with crenellations, round corner towers, gatehouse with
## portcullis, keep, wall-walk stairs, timber houses and the bell on the west wall.
## Courtyard spans x,z in [-14, 14]; the gate faces +Z.

const B := preload("res://intro/build.gd")
const H := 7.0  # wall height (wall-walk level)
const T := 2.0  # wall thickness
const R := 15.0 # wall centre line


static func crenellate(parent: Node3D, a: Vector3, b: Vector3, mat: Material, step := 1.5) -> void:
	var d := b - a
	var n := int(d.length() / step)
	var horiz := absf(d.x) > absf(d.z)
	for i in n + 1:
		var p := a + d * (float(i) / maxf(n, 1))
		var size := Vector3(0.8, 0.9, 0.5) if horiz else Vector3(0.5, 0.9, 0.8)
		B.box(parent, p + Vector3(0, 0.45, 0), size, mat, true)


static func build(root: Node3D, is_web: bool) -> Dictionary:
	var out := {}
	var stone := B.stone()
	var tower_stone := B.stone(Color(0.6, 0.56, 0.5), Vector2(0.8, 0.4))
	var slate := B.mat(Color(0.17, 0.2, 0.28), 0.7)
	var wood := B.mat(Color(0.28, 0.17, 0.09))
	var iron := B.mat(Color(0.12, 0.12, 0.13), 0.5, 0.8)
	var window := B.glow_mat(Color(1.0, 0.62, 0.25), 2.5)

	# --- curtain walls (outer merlons only, so the inner side of the wall-walk is open)
	B.box(root, Vector3(0, H / 2, -R), Vector3(2 * R, H, T), stone)
	B.box(root, Vector3(R, H / 2, 0), Vector3(T, H, 2 * R), stone)
	B.box(root, Vector3(-R, H / 2, 0), Vector3(T, H, 2 * R), stone)
	B.box(root, Vector3(-8.75, H / 2, R), Vector3(12.5, H, T), stone)
	B.box(root, Vector3(8.75, H / 2, R), Vector3(12.5, H, T), stone)
	crenellate(root, Vector3(-12, H, -R - 0.75), Vector3(12, H, -R - 0.75), stone)
	crenellate(root, Vector3(R + 0.75, H, -12), Vector3(R + 0.75, H, 12), stone)
	crenellate(root, Vector3(-R - 0.75, H, -12), Vector3(-R - 0.75, H, 12), stone)
	crenellate(root, Vector3(-12, H, R + 0.75), Vector3(-7, H, R + 0.75), stone)
	crenellate(root, Vector3(7, H, R + 0.75), Vector3(12, H, R + 0.75), stone)

	# --- corner towers
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var c := Vector3(sx * R, 0, sz * R)
			B.cyl(root, c + Vector3(0, 5.5, 0), 3.2, 3.4, 11.0, tower_stone, true, 28)
			B.cyl(root, c + Vector3(0, 11.2, 0), 3.6, 3.6, 0.4, tower_stone, false, 28)
			B.cyl(root, c + Vector3(0, 13.9, 0), 0.0, 3.8, 5.0, slate, false, 28)
			B.cyl(root, c + Vector3(0, 17.0, 0), 0.03, 0.03, 1.4, iron, false, 6)
			B.banner(root, c + Vector3(0, 17.6, 0), Vector2(0.5, 1.1), B.cloth(Color(0.55, 0.06, 0.08), false, 0.12, sx + sz), Vector3(0, 0, -PI / 2))
			# arrow slits facing outward
			for k in 3:
				var ang := atan2(sx, sz) + (k - 1) * 0.6
				var p := c + Vector3(sin(ang) * 3.25, 4.0 + k * 2.2, cos(ang) * 3.25)
				B.box(root, p, Vector3(0.18, 1.0, 0.18), B.mat(Color(0.03, 0.03, 0.03)), false, Vector3(0, ang, 0))

	# --- gatehouse
	for sx in [-1.0, 1.0]:
		var gx: float = sx * 4.5
		B.box(root, Vector3(gx, 5, R), Vector3(4, 10, 4), tower_stone)
		crenellate(root, Vector3(gx - 1.6, 10, R + 1.75), Vector3(gx + 1.6, 10, R + 1.75), tower_stone, 1.0)
		crenellate(root, Vector3(gx - 1.6, 10, R - 1.75), Vector3(gx + 1.6, 10, R - 1.75), tower_stone, 1.0)
		B.banner(root, Vector3(gx, 8.8, R + 2.06), Vector2(1.3, 2.8), B.cloth(Color(0.12, 0.2, 0.5), true, 0.1, sx))
	B.box(root, Vector3(0, 7.25, R), Vector3(5, 4.5, 3), tower_stone)
	B.box(root, Vector3(0, 5.15, R + 1.2), Vector3(5.2, 0.3, 0.4), stone, false) # arch lip
	crenellate(root, Vector3(-2, 9.5, R + 1.25), Vector3(2, 9.5, R + 1.25), tower_stone, 1.0)

	# portcullis (animatable so it carries collision while it rises)
	var port := AnimatableBody3D.new()
	port.sync_to_physics = false
	port.position = Vector3(0, 0, R + 0.6)
	root.add_child(port)
	for i in 10:
		B.box(port, Vector3(-2.25 + i * 0.5, 2.5, 0), Vector3(0.1, 5.0, 0.1), iron, false)
	for j in 5:
		B.box(port, Vector3(0, 0.6 + j * 1.05, 0), Vector3(4.9, 0.1, 0.12), iron, false)
	for i in 10:
		B.cyl(port, Vector3(-2.25 + i * 0.5, -0.1, 0), 0.0, 0.06, 0.25, iron, false, 6) # spikes
	var pcs := CollisionShape3D.new()
	var pbox := BoxShape3D.new()
	pbox.size = Vector3(5, 5, 0.3)
	pcs.shape = pbox
	pcs.position.y = 2.5
	port.add_child(pcs)
	out["portcullis"] = port

	# gate lever on the outer face of the right gate tower
	var lever := Node3D.new()
	lever.position = Vector3(3.2, 0, R + 2.25)
	root.add_child(lever)
	B.box(lever, Vector3(0, 0.6, 0), Vector3(0.6, 1.2, 0.4), wood)
	var handle := Node3D.new()
	handle.position = Vector3(0, 1.15, 0)
	handle.rotation.x = 0.7
	lever.add_child(handle)
	B.box(handle, Vector3(0, 0.45, 0), Vector3(0.08, 0.9, 0.08), iron, false)
	B.sphere(handle, Vector3(0, 0.92, 0), 0.08, B.mat(Color(0.5, 0.1, 0.08)))
	out["lever"] = lever
	out["lever_handle"] = handle

	# --- keep
	var keep_c := Vector3(0, 0, -9.5)
	B.box(root, keep_c + Vector3(0, 6, 0), Vector3(10, 12, 8), stone)
	crenellate(root, keep_c + Vector3(-4.6, 12, 3.8), keep_c + Vector3(4.6, 12, 3.8), stone, 1.2)
	crenellate(root, keep_c + Vector3(-4.6, 12, -3.8), keep_c + Vector3(4.6, 12, -3.8), stone, 1.2)
	crenellate(root, keep_c + Vector3(-4.8, 12, -3), keep_c + Vector3(-4.8, 12, 3), stone, 1.2)
	crenellate(root, keep_c + Vector3(4.8, 12, -3), keep_c + Vector3(4.8, 12, 3), stone, 1.2)
	B.cyl(root, keep_c + Vector3(4, 8, 3), 1.4, 1.4, 16, tower_stone, false, 20)
	B.cyl(root, keep_c + Vector3(4, 18, 3), 0.0, 1.8, 4, slate, false, 20)
	B.box(root, keep_c + Vector3(0, 1.7, 4.05), Vector3(2.2, 3.4, 0.2), wood, false)
	B.box(root, keep_c + Vector3(0, 3.55, 4.1), Vector3(2.8, 0.35, 0.35), stone, false)
	for wx in [-3.0, 3.0]:
		B.box(root, keep_c + Vector3(wx, 6.5, 4.02), Vector3(0.7, 1.4, 0.1), window, false)
		B.box(root, keep_c + Vector3(wx, 9.5, 4.02), Vector3(0.7, 1.4, 0.1), window, false)
		B.banner(root, keep_c + Vector3(wx * 0.55, 11.4, 4.08), Vector2(1.4, 3.6), B.cloth(Color(0.55, 0.06, 0.08), true, 0.08, wx))
	out["keep_door"] = keep_c + Vector3(0, 0, 4.5)

	# flagstone plaza in front of the keep
	B.box(root, Vector3(0, 0.03, -2.5), Vector3(9, 0.12, 6), B.stone(Color(0.5, 0.48, 0.45), Vector2(0.7, 0.7)), false)

	# --- stairs up to the west wall-walk (visual steps over an invisible ramp)
	var steps := 14
	for i in steps:
		var top := (i + 1) * H / steps
		B.box(root, Vector3(-13, top / 2, 10.5 - i), Vector3(2, top, 1), stone, false)
	var ang := atan2(H, float(steps))
	var rl := sqrt(H * H + steps * steps)
	var ramp := BoxShape3D.new()
	ramp.size = Vector3(2, 0.4, rl + 0.6)
	B.collider(root, ramp, Vector3(-13, H / 2 + 0.05, 11 - steps / 2.0), Vector3(ang, 0, 0))

	# --- the bell on the west wall-walk
	var bc := Vector3(-R, H, -7)
	for dz in [-1.2, 1.2]:
		B.box(root, bc + Vector3(0, 1.4, dz), Vector3(0.25, 2.8, 0.25), wood)
	B.box(root, bc + Vector3(0, 2.9, 0), Vector3(0.3, 0.3, 2.7), wood, false)
	B.cyl(root, bc + Vector3(0, 3.3, 0), 0.0, 1.0, 0.8, B.mat(Color(0.35, 0.2, 0.12)), false, 4)
	var bell := Node3D.new()
	bell.position = bc + Vector3(0, 2.75, 0)
	root.add_child(bell)
	var bronze := B.mat(Color(0.72, 0.5, 0.22), 0.3, 0.85)
	B.cyl(bell, Vector3(0, -0.5, 0), 0.28, 0.55, 0.8, bronze, false, 24)
	B.sphere(bell, Vector3(0, -0.1, 0), 0.28, bronze)
	B.sphere(bell, Vector3(0, -0.95, 0), 0.1, iron)
	out["bell"] = bell

	# --- timber houses along the east wall
	var plaster := B.mat(Color(0.86, 0.8, 0.66))
	var roof_m := B.mat(Color(0.48, 0.24, 0.15), 0.85)
	var beam := B.mat(Color(0.22, 0.13, 0.07))
	var chimneys: Array[Vector3] = []
	for hz in [-9.0, 4.5]:
		var c := Vector3(11, 0, hz)
		B.box(root, c + Vector3(0, 0.6, 0), Vector3(5, 1.2, 5.4), stone)
		B.box(root, c + Vector3(0, 2.5, 0), Vector3(5, 2.6, 5.4), plaster)
		var f := c.x - 2.52 # front face (towards the courtyard)
		for bz in [-2.6, -0.9, 0.9, 2.6]:
			B.box(root, Vector3(f, 2.5, c.z + bz), Vector3(0.1, 2.6, 0.22), beam, false)
		B.box(root, Vector3(f, 1.27, c.z), Vector3(0.1, 0.18, 5.4), beam, false)
		B.box(root, Vector3(f, 3.75, c.z), Vector3(0.1, 0.18, 5.4), beam, false)
		B.box(root, Vector3(f, 2.5, c.z - 1.75), Vector3(0.08, 2.9, 0.16), beam, false, Vector3(0.6, 0, 0))
		B.box(root, Vector3(f, 2.5, c.z + 1.75), Vector3(0.08, 2.9, 0.16), beam, false, Vector3(-0.6, 0, 0))
		B.box(root, Vector3(f - 0.02, 1.05, c.z), Vector3(0.1, 2.1, 1.1), wood, false)
		B.box(root, Vector3(f - 0.02, 2.7, c.z - 1.75), Vector3(0.1, 0.7, 0.6), window, false)
		B.box(root, Vector3(f - 0.02, 2.7, c.z + 1.75), Vector3(0.1, 0.7, 0.6), window, false)
		var prism := PrismMesh.new()
		prism.size = Vector3(5.8, 2.4, 6.0)
		B.mesh(root, prism, c + Vector3(0, 5.0, 0), roof_m)
		B.box(root, c + Vector3(1.2, 5.6, 1.6), Vector3(0.6, 2.2, 0.6), stone, false)
		chimneys.append(c + Vector3(1.2, 6.8, 1.6))
	out["chimneys"] = chimneys

	# --- forge (open shed between the houses)
	var fc := Vector3(11.5, 0, -2.3)
	for p in [Vector3(-2, 0, -1.6), Vector3(-2, 0, 1.6), Vector3(2, 0, -1.6), Vector3(2, 0, 1.6)]:
		B.box(root, fc + p + Vector3(0, 1.5, 0), Vector3(0.25, 3.0, 0.25), wood)
	B.box(root, fc + Vector3(0, 3.2, 0), Vector3(4.6, 0.2, 3.8), roof_m, false, Vector3(0, 0, -0.15))
	B.box(root, fc + Vector3(1.3, 0.6, 0), Vector3(1.4, 1.2, 1.8), stone)
	B.box(root, fc + Vector3(0.7, 0.75, 0), Vector3(0.1, 0.6, 1.0), B.glow_mat(Color(1.0, 0.4, 0.08), 6.0), false)
	B.box(root, fc + Vector3(-0.6, 0.35, 0.2), Vector3(0.4, 0.7, 0.4), wood)
	B.box(root, fc + Vector3(-0.6, 0.78, 0.2), Vector3(0.7, 0.18, 0.3), iron, false)
	out["forge"] = fc + Vector3(0.6, 1.0, 0)

	# --- well
	var wc := Vector3(4.5, 0, 3)
	B.cyl(root, wc + Vector3(0, 0.45, 0), 1.0, 1.05, 0.9, B.stone(Color(0.5, 0.47, 0.43), Vector2(0.5, 0.25)), true, 20)
	B.cyl(root, wc + Vector3(0, 0.75, 0), 0.82, 0.82, 0.05, B.mat(Color(0.05, 0.1, 0.14), 0.05), false, 20)
	for dx in [-0.9, 0.9]:
		B.box(root, wc + Vector3(dx, 1.3, 0), Vector3(0.14, 1.8, 0.14), wood, false)
	var wr := PrismMesh.new()
	wr.size = Vector3(2.4, 0.8, 1.4)
	B.mesh(root, wr, wc + Vector3(0, 2.5, 0), roof_m, Vector3(0, PI / 2, 0))
	var axle := B.cyl(root, wc + Vector3(0, 1.85, 0), 0.08, 0.08, 1.7, wood, false, 8)
	axle.rotation.z = PI / 2
	B.cyl(root, wc + Vector3(0.3, 1.3, 0), 0.16, 0.13, 0.25, wood, false, 10)

	# --- market stall near the keep
	var mc := Vector3(-6.5, 0, -2)
	B.box(root, mc + Vector3(0, 0.8, 0), Vector3(3, 0.1, 1.3), wood)
	B.box(root, mc + Vector3(0, 0.4, 0), Vector3(2.8, 0.8, 1.1), wood, false)
	for p in [Vector3(-1.45, 0, -0.6), Vector3(1.45, 0, -0.6), Vector3(-1.45, 0, 0.6), Vector3(1.45, 0, 0.6)]:
		B.box(root, mc + p + Vector3(0, 1.2, 0), Vector3(0.1, 2.4, 0.1), wood, false)
	for i in 6:
		var col := Color(0.75, 0.15, 0.1) if i % 2 == 0 else Color(0.92, 0.88, 0.78)
		B.box(root, mc + Vector3(-1.25 + i * 0.5, 2.45, 0.1), Vector3(0.5, 0.06, 1.7), B.mat(col), false, Vector3(0.18, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 18:
		var fruit := Color(0.75, 0.1, 0.08) if i < 10 else Color(0.9, 0.6, 0.1)
		B.sphere(root, mc + Vector3(rng.randf_range(-1.2, 1.2), 0.93, rng.randf_range(-0.45, 0.45)), 0.08, B.mat(fruit, 0.5))
	out["stall"] = mc

	# --- training dummy (pivot at its base so it can wobble)
	var dummy := Node3D.new()
	dummy.position = Vector3(-7, 0, 7)
	root.add_child(dummy)
	var straw := B.mat(Color(0.8, 0.66, 0.32))
	B.cyl(dummy, Vector3(0, 0.9, 0), 0.07, 0.07, 1.8, wood, false, 8)
	B.cyl(dummy, Vector3(0, 1.25, 0), 0.28, 0.3, 0.8, straw, false, 12)
	B.box(dummy, Vector3(0, 1.45, 0), Vector3(1.3, 0.1, 0.1), wood, false)
	B.sphere(dummy, Vector3(0, 1.9, 0), 0.2, B.mat(Color(0.7, 0.6, 0.45)))
	B.box(dummy, Vector3(0, 1.25, -0.31), Vector3(0.3, 0.3, 0.02), B.mat(Color(0.7, 0.1, 0.08)), false)
	var dcol := CylinderShape3D.new()
	dcol.radius = 0.3
	dcol.height = 2.0
	B.collider(root, dcol, Vector3(-7, 1, 7))
	out["dummy"] = dummy
	for p in [Vector3(-9, 0.4, 5.5), Vector3(-9.2, 0.4, 8.5), Vector3(-9.1, 1.2, 7.0)]:
		B.box(root, p, Vector3(1.0, 0.8, 1.6), straw, true, Vector3(0, 0.2, 0)) # hay bales

	# --- torches: [position, outward direction]
	out["torches"] = [
		Vector3(-2.9, 3.4, R + 2.3), Vector3(2.9, 3.4, R + 2.3),
		Vector3(-2.9, 3.4, R - 2.3), Vector3(2.9, 3.4, R - 2.3),
		keep_c + Vector3(-1.9, 2.8, 4.3), keep_c + Vector3(1.9, 2.8, 4.3),
		Vector3(8.3, 2.8, -9), Vector3(8.3, 2.8, 4.5),
		bc + Vector3(1.0, 1.6, 2.0), Vector3(-12, 2.6, 12.6),
	]
	return out


static func torch(root: Node3D, pos: Vector3, shadows: bool) -> OmniLight3D:
	B.cyl(root, pos + Vector3(0, -0.3, 0), 0.06, 0.04, 0.6, B.mat(Color(0.25, 0.15, 0.07)), false, 8)
	B.cyl(root, pos + Vector3(0, 0.02, 0), 0.1, 0.07, 0.12, B.mat(Color(0.15, 0.15, 0.15), 0.5, 0.7), false, 8)
	var fire := fire_particles(Color(1.0, 0.55, 0.15), 0.28)
	fire.position = pos + Vector3(0, 0.1, 0)
	root.add_child(fire)
	var l := OmniLight3D.new()
	l.position = pos + Vector3(0, 0.35, 0)
	l.light_color = Color(1.0, 0.6, 0.28)
	l.light_energy = 2.2
	l.omni_range = 9.0
	l.omni_attenuation = 1.4
	l.shadow_enabled = shadows
	root.add_child(l)
	return l


static func _soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	return t


static func _ramp(colors: Array) -> GradientTexture1D:
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in colors.size():
		offs.append(float(i) / (colors.size() - 1))
		cols.append(colors[i])
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func _particle_mat(additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot()
	return m


static func fire_particles(col: Color, size: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 28
	p.lifetime = 0.7
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.07
	pm.direction = Vector3.UP
	pm.spread = 12
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.7
	pm.gravity = Vector3(0.15, 1.6, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.1
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.6))
	sc.add_point(Vector2(0.25, 1.0))
	sc.add_point(Vector2(1, 0.1))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	pm.color_ramp = _ramp([Color(1, 0.95, 0.6, 1), col, Color(0.8, 0.15, 0.05, 0.6), Color(0.2, 0.05, 0.02, 0)])
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _particle_mat(true)
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-1, -0.5, -1), Vector3(2, 3, 2))
	return p


static func smoke_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 24
	p.lifetime = 6.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 8
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 0.8
	pm.gravity = Vector3(0.35, 0.15, 0.1)
	pm.scale_min = 0.8
	pm.scale_max = 1.4
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.3))
	sc.add_point(Vector2(1, 1.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	pm.color_ramp = _ramp([Color(0.35, 0.33, 0.32, 0), Color(0.35, 0.33, 0.32, 0.45), Color(0.4, 0.38, 0.38, 0)])
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 1.6)
	q.material = _particle_mat(false)
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(10, 10, 10))
	return p


static func spark_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 1.0
	p.explosiveness = 0.85
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 45
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 4.5
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.color_ramp = _ramp([Color(1, 0.95, 0.6, 1), Color(1, 0.5, 0.1, 1), Color(0.6, 0.1, 0.0, 0)])
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	q.material = _particle_mat(true)
	p.draw_pass_1 = q
	return p


static func burst_particles(col: Color) -> GPUParticles3D:
	var p := spark_particles()
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 1.0
	p.amount = 30
	var pm := p.process_material as ParticleProcessMaterial
	pm.color_ramp = _ramp([col, Color(col, 0)])
	pm.spread = 70
	pm.gravity = Vector3(0, -5, 0)
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.5
	(p.draw_pass_1 as QuadMesh).size = Vector2(0.1, 0.04)
	return p
