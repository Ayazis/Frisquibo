class_name Buoyancy
extends Node
## Apply buoyancy at body-local probes. The owner supplies the body and water-height callable.

@export var body: RigidBody3D
@export var probes: PackedVector3Array = PackedVector3Array([
	Vector3(-0.3, -0.4, -0.3), Vector3(0.3, -0.4, -0.3),
	Vector3(-0.3, -0.4, 0.3), Vector3(0.3, -0.4, 0.3)])
@export var displaced_volume: float = 0.12
@export var immersion_depth: float = 0.8
@export var water_density: float = 1000.0
@export var water_drag: float = 2.5
@export var angular_water_drag: float = 1.5
var water_height: Callable

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(body) or not water_height.is_valid() or probes.is_empty():
		return
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var wet_fraction: float = 0.0
	for probe: Vector3 in probes:
		var offset: Vector3 = body.global_basis * probe
		var point: Vector3 = body.global_position + offset
		var height: float = water_height.call(Vector2(point.x, point.z))
		var submerged: float = clampf((height - point.y) / maxf(immersion_depth, 0.001), 0.0, 1.0)
		wet_fraction += submerged / probes.size()
		var velocity: Vector3 = body.linear_velocity + body.angular_velocity.cross(offset)
		var lift: Vector3 = Vector3.UP * water_density * gravity * displaced_volume * submerged / probes.size()
		var drag: Vector3 = -velocity * water_drag * body.mass * submerged / probes.size()
		body.apply_force(lift + drag, offset)
	body.apply_torque(-body.angular_velocity * angular_water_drag * body.mass * wet_fraction)
