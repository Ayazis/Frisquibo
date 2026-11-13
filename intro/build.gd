extends RefCounted
## Static helpers for building procedural geometry (meshes + colliders) and materials.

const STONE_SHADER := preload("res://intro/stone.gdshader")
const BANNER_SHADER := preload("res://intro/banner.gdshader")


static func mat(col: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


static func glow_mat(col: Color, energy := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col * 0.3
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m


static func stone(col := Color(0.56, 0.53, 0.48), brick := Vector2(0.9, 0.45)) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = STONE_SHADER
	m.set_shader_parameter("stone_color", col)
	m.set_shader_parameter("mortar_color", col * 0.45)
	m.set_shader_parameter("brick_size", brick)
	return m


static func cloth(col: Color, emblem := true, wave := 0.15, phase := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = BANNER_SHADER
	m.set_shader_parameter("cloth_color", col)
	m.set_shader_parameter("emblem", emblem)
	m.set_shader_parameter("wave", wave)
	m.set_shader_parameter("phase", phase)
	return m


static func mesh(parent: Node3D, m: Mesh, pos: Vector3, material: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func collider(parent: Node3D, shape: Shape3D, pos: Vector3, rot := Vector3.ZERO) -> StaticBody3D:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	sb.add_child(cs)
	sb.position = pos
	sb.rotation = rot
	parent.add_child(sb)
	return sb


static func box(parent: Node3D, pos: Vector3, size: Vector3, material: Material, collide := true, rot := Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := mesh(parent, bm, pos, material, rot)
	if collide:
		var sh := BoxShape3D.new()
		sh.size = size
		collider(parent, sh, pos, rot)
	return mi


static func cyl(parent: Node3D, pos: Vector3, r_top: float, r_bot: float, h: float, material: Material, collide := true, segs := 24) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = segs
	var mi := mesh(parent, cm, pos, material)
	if collide:
		var sh := CylinderShape3D.new()
		sh.radius = maxf(r_top, r_bot)
		sh.height = h
		collider(parent, sh, pos)
	return mi


static func sphere(parent: Node3D, pos: Vector3, r: float, material: Material, scale := Vector3.ONE) -> MeshInstance3D:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	var mi := mesh(parent, sm, pos, material)
	mi.scale = scale
	return mi


static func banner(parent: Node3D, pos: Vector3, size: Vector2, material: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	q.subdivide_width = 6
	q.subdivide_depth = 14
	q.center_offset = Vector3(0, -size.y / 2.0, 0) # hang from the top edge
	return mesh(parent, q, pos, material, rot)


## A knight/guard figure facing -Z, feet at origin. Returns the root node.
static func knight(tabard: Color, plume: Color) -> Node3D:
	var root := Node3D.new()
	var steel := mat(Color(0.62, 0.64, 0.68), 0.32, 0.85)
	var dark := mat(Color(0.18, 0.17, 0.16), 0.8)
	var tab := mat(tabard, 0.9)
	box(root, Vector3(-0.12, 0.4, 0), Vector3(0.17, 0.8, 0.2), dark, false)
	box(root, Vector3(0.12, 0.4, 0), Vector3(0.17, 0.8, 0.2), dark, false)
	cyl(root, Vector3(0, 1.15, 0), 0.3, 0.26, 0.7, steel, false, 16)
	box(root, Vector3(0, 1.0, -0.2), Vector3(0.44, 0.78, 0.18), tab, false)
	box(root, Vector3(0, 0.82, 0), Vector3(0.58, 0.08, 0.58), mat(Color(0.3, 0.18, 0.08)), false)
	box(root, Vector3(0, 1.1, -0.295), Vector3(0.08, 0.4, 0.01), mat(Color(0.95, 0.85, 0.4)), false)
	box(root, Vector3(0, 1.2, -0.295), Vector3(0.3, 0.08, 0.01), mat(Color(0.95, 0.85, 0.4)), false)
	sphere(root, Vector3(-0.36, 1.42, 0), 0.13, steel)
	sphere(root, Vector3(0.36, 1.42, 0), 0.13, steel)
	box(root, Vector3(-0.38, 1.12, 0), Vector3(0.13, 0.55, 0.15), steel, false)
	box(root, Vector3(0.38, 1.12, 0), Vector3(0.13, 0.55, 0.15), steel, false)
	cyl(root, Vector3(0, 1.68, 0), 0.19, 0.2, 0.34, steel, false, 16)
	box(root, Vector3(0, 1.7, -0.19), Vector3(0.26, 0.035, 0.03), dark, false)
	sphere(root, Vector3(0, 1.92, 0.04), 0.12, mat(plume), Vector3(0.6, 1.0, 1.6))
	return root
