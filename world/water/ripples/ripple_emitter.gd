class_name RippleEmitter
extends Node
## Makes a body disturb the water where it crosses the surface: rings when it bobs, a V-shaped wake and
## foam when it moves. Add it as a child of the body; the owner supplies the water height.

## Waves leave the wake only when the body moves at least this fast (m/s).
const MIN_SPEED := 0.05
## Foam starts at this speed through the water and is full at FULL_FOAM_SPEED (m/s).
const FOAM_START_SPEED := 0.8
const FULL_FOAM_SPEED := 4.0

@export var body: Node3D
## Radius of the body's footprint on the water (m).
@export_range(0.05, 10.0, 0.05, "suffix:m") var radius := 0.5
## Metres the surface is pushed down per metre the body moves through it.
@export_range(0.0, 0.2, 0.001) var push_per_metre := 0.02
## How much foam a fast body leaves (0..1).
@export_range(0.0, 1.0, 0.01) var foam := 0.6
## Takes (xz: Vector2) and returns the water surface height.
var water_height: Callable

var _last_position := Vector3.ZERO
var _has_last := false


func _physics_process(delta: float) -> void:
	if not is_instance_valid(body) or not water_height.is_valid() or delta <= 0.0:
		return
	var p := body.global_position
	var velocity := (p - _last_position) / delta if _has_last else Vector3.ZERO
	_last_position = p
	_has_last = true
	var surface: float = water_height.call(Vector2(p.x, p.z))
	# Only while the body is in the surface: not when it flies above or has sunk below.
	if absf(p.y - surface) > radius:
		return
	var speed := velocity.length()
	if speed < MIN_SPEED:
		return
	var ripples := WaterRipples.find(get_tree())
	if ripples == null:
		return
	var wake_foam := foam * smoothstep(FOAM_START_SPEED, FULL_FOAM_SPEED, speed)
	ripples.disturb(Vector3(p.x, surface, p.z), radius, push_per_metre * speed * delta, wake_foam)
