class_name ObjectDropper
extends Node3D
## Drops physics objects onto a water station: barrels, crates and planks float (lighter than water),
## stones sink. Each body gets a Buoyancy component; hitting the water fast makes a splash.
## The station supplies the water height (and optionally its current) as callables.

enum Kind { BARREL, CRATE, PLANK, STONE }

const WATER_DENSITY := 1000.0
const MAX_OBJECTS := 40
const DROPS_PER_BURST := 5
const DROP_RADIUS := 5.0
const DROP_HEIGHT_MIN := 6.0
const DROP_HEIGHT_MAX := 12.0
const DESPAWN_DEPTH := -60.0
## Probes sit at this fraction of the half extents, so they stay inside the shape.
const PROBE_INSET := 0.75
const SPLASH_MIN_SPEED := 1.5
const SPLASH_PARTICLES_PER_MPS := 18
const SPLASH_MAX_PARTICLES := 160
const SPLASH_LIFETIME := 1.4
const SPLASH_UP_SPEED_PER_MPS := 0.55
const SPLASH_DROPLET_SIZE := 0.06

## Takes (xz: Vector2), returns the water surface height.
var water_height: Callable
## Optional. Takes (xz: Vector2), returns the water velocity (Vector3).
var water_velocity: Callable
var drop_centre := Vector3.ZERO

var _rng := RandomNumberGenerator.new()
var _bodies: Array[RigidBody3D] = []
var _materials: Dictionary[Kind, ShaderMaterial] = {}
var _droplet_mesh: SphereMesh


func _ready() -> void:
	_rng.seed = 1234
	_materials[Kind.BARREL] = _material(Color(0.3, 0.15, 0.06), 0.75)
	_materials[Kind.CRATE] = _material(Color(0.55, 0.4, 0.22), 0.85)
	_materials[Kind.PLANK] = _material(Color(0.42, 0.29, 0.16), 0.8)
	_materials[Kind.STONE] = _material(Color(0.36, 0.35, 0.33), 0.95)
	_droplet_mesh = SphereMesh.new()
	_droplet_mesh.radius = SPLASH_DROPLET_SIZE
	_droplet_mesh.height = SPLASH_DROPLET_SIZE * 2.0
	_droplet_mesh.radial_segments = 6
	_droplet_mesh.rings = 3
	_droplet_mesh.material = _material(Color(0.9, 0.95, 1.0), 0.1)


func drop_burst() -> void:
	for i in range(DROPS_PER_BURST):
		drop(_rng.randi_range(0, Kind.size() - 1) as Kind)


func drop(kind: Kind) -> void:
	var angle := _rng.randf() * TAU
	var r := sqrt(_rng.randf()) * DROP_RADIUS
	var pos := drop_centre + Vector3(cos(angle) * r, _rng.randf_range(DROP_HEIGHT_MIN, DROP_HEIGHT_MAX), sin(angle) * r)
	var body := _make_body(kind)
	body.position = pos
	body.rotation = Vector3(_rng.randf(), _rng.randf(), _rng.randf()) * TAU
	body.angular_velocity = Vector3(_rng.randf_range(-2, 2), _rng.randf_range(-2, 2), _rng.randf_range(-2, 2))
	add_child(body)
	_bodies.append(body)
	while _bodies.size() > MAX_OBJECTS:
		var oldest: RigidBody3D = _bodies.pop_front()
		oldest.queue_free()


func _physics_process(_delta: float) -> void:
	for body: RigidBody3D in _bodies.duplicate():
		if body.global_position.y < DESPAWN_DEPTH:
			_bodies.erase(body)
			body.queue_free()


func _make_body(kind: Kind) -> RigidBody3D:
	var mesh: Mesh
	var shape: Shape3D
	var half := Vector3.ONE
	var density := 0.0
	match kind:
		Kind.BARREL:
			var c := CylinderMesh.new()
			c.top_radius = 0.4
			c.bottom_radius = 0.4
			c.height = 1.0
			mesh = c
			var cs := CylinderShape3D.new()
			cs.radius = 0.4
			cs.height = 1.0
			shape = cs
			half = Vector3(0.4, 0.5, 0.4)
			density = 350.0
		Kind.CRATE:
			var b := BoxMesh.new()
			b.size = Vector3(0.8, 0.8, 0.8)
			mesh = b
			var bs := BoxShape3D.new()
			bs.size = b.size
			shape = bs
			half = b.size / 2.0
			density = 450.0
		Kind.PLANK:
			var b := BoxMesh.new()
			b.size = Vector3(2.6, 0.18, 0.45)
			mesh = b
			var bs := BoxShape3D.new()
			bs.size = b.size
			shape = bs
			half = b.size / 2.0
			density = 550.0
		_:
			var s := SphereMesh.new()
			s.radius = 0.35
			s.height = 0.6
			mesh = s
			var ss := SphereShape3D.new()
			ss.radius = 0.33
			shape = ss
			half = Vector3(0.33, 0.3, 0.33)
			density = 2600.0
	(mesh as PrimitiveMesh).material = _materials[kind]
	var volume := _volume(kind, half)

	var body := RigidBody3D.new()
	body.mass = volume * density
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)

	var buoyancy := Buoyancy.new()
	buoyancy.body = body
	buoyancy.water_height = water_height
	buoyancy.water_velocity = water_velocity
	buoyancy.water_density = WATER_DENSITY
	buoyancy.displaced_volume = volume
	# Two layers of probes, so lift grows smoothly from first contact to full immersion.
	buoyancy.immersion_depth = half.y
	var probes := PackedVector3Array()
	for y: float in [-0.5, 0.5]:
		for x: float in [-1.0, 1.0]:
			for z: float in [-1.0, 1.0]:
				probes.append(Vector3(x, y, z) * half * PROBE_INSET)
	buoyancy.probes = probes
	buoyancy.entered_water.connect(_splash)
	body.add_child(buoyancy)
	return body


func _volume(kind: Kind, half: Vector3) -> float:
	match kind:
		Kind.BARREL:
			return PI * half.x * half.x * half.y * 2.0
		Kind.STONE:
			return 4.0 / 3.0 * PI * half.x * half.y * half.z
		_:
			return 8.0 * half.x * half.y * half.z


func _splash(point: Vector3, speed: float) -> void:
	if speed < SPLASH_MIN_SPEED:
		return
	var p := CPUParticles3D.new()
	p.mesh = _droplet_mesh
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = mini(int(speed * SPLASH_PARTICLES_PER_MPS), SPLASH_MAX_PARTICLES)
	p.lifetime = SPLASH_LIFETIME
	p.direction = Vector3.UP
	p.spread = 35.0
	p.initial_velocity_min = speed * SPLASH_UP_SPEED_PER_MPS * 0.5
	p.initial_velocity_max = speed * SPLASH_UP_SPEED_PER_MPS
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.35
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.4
	var surface: float = water_height.call(Vector2(point.x, point.z))
	p.position = Vector3(point.x, surface, point.z)
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


func _material(color: Color, roughness: float) -> ShaderMaterial:
	return WaterProp.material(color, roughness)
