class_name WaterSplash
extends RefCounted
## A splash where something hits the water: droplets thrown up, a ring of waves and foam in the ripple
## simulation. Connect Buoyancy.entered_water to a function that calls spawn().

const MIN_SPEED := 1.5
const PARTICLES_PER_MPS := 18.0
const MAX_PARTICLES := 160
const LIFETIME := 1.4
const UP_SPEED_PER_MPS := 0.55
const SPREAD_DEGREES := 35.0
const EXPLOSIVENESS := 0.9
const EMISSION_RADIUS := 0.35
const SCALE_MIN := 0.5
const SCALE_MAX := 1.4
const DROPLET_SIZE := 0.06
const DROPLET_COLOR := Color(0.9, 0.95, 1.0)
const DROPLET_ROUGHNESS := 0.1
## Metres the surface is pushed down per m/s of impact, and the ring's radius per m/s.
const PUSH_PER_MPS := 0.025
const RING_RADIUS_PER_MPS := 0.12
const MIN_RING_RADIUS := 0.3
const FOAM := 0.9

static var _droplet_mesh: SphereMesh


## Splash at `point` on the surface of the water, hit at `speed` m/s, under `parent`.
static func spawn(parent: Node, point: Vector3, speed: float, quality: WaterQuality = null) -> void:
	if speed < MIN_SPEED or parent == null:
		return
	var ripples := WaterRipples.find(parent.get_tree())
	if ripples != null:
		ripples.disturb(point, maxf(MIN_RING_RADIUS, speed * RING_RADIUS_PER_MPS), speed * PUSH_PER_MPS, FOAM)
	if quality == null:
		quality = ripples.quality if ripples != null and ripples.quality != null else WaterRipples.DEFAULT_QUALITY
	var amount := mini(int(speed * PARTICLES_PER_MPS * quality.splash_particle_scale), MAX_PARTICLES)
	if amount <= 0:
		return
	# CPU particles: the same on desktop and web, and few enough per splash not to matter.
	var p := CPUParticles3D.new()
	p.mesh = _droplet()
	p.one_shot = true
	p.explosiveness = EXPLOSIVENESS
	p.amount = amount
	p.lifetime = LIFETIME
	p.direction = Vector3.UP
	p.spread = SPREAD_DEGREES
	p.initial_velocity_min = speed * UP_SPEED_PER_MPS * 0.5
	p.initial_velocity_max = speed * UP_SPEED_PER_MPS
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = EMISSION_RADIUS
	p.scale_amount_min = SCALE_MIN
	p.scale_amount_max = SCALE_MAX
	parent.add_child(p)
	p.global_position = point
	p.emitting = true
	p.finished.connect(p.queue_free)


static func _droplet() -> SphereMesh:
	if _droplet_mesh == null:
		_droplet_mesh = SphereMesh.new()
		_droplet_mesh.radius = DROPLET_SIZE
		_droplet_mesh.height = DROPLET_SIZE * 2.0
		_droplet_mesh.radial_segments = 6
		_droplet_mesh.rings = 3
		_droplet_mesh.material = WaterProp.material(DROPLET_COLOR, DROPLET_ROUGHNESS)
	return _droplet_mesh
