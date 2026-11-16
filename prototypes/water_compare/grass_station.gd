class_name GrassStation
extends WaterStation
## Station 5: the original grass playground (main.tscn) with its own sky, sun, camera and controls,
## so the whole demo is reachable from the comparison scene.

const GRASS_DEMO := preload("res://main.tscn")
## Drops land on the island's hills, which reach about this height.
const DROP_TARGET := Vector3(0, 4, 0)

var _demo: Node3D


func _init() -> void:
	title = "Grass playground"
	notes = "main.tscn: WASD rolls the ball, click to capture the mouse and throw balls, Esc releases it."
	camera_target = DROP_TARGET
	takes_over_view = true


func _ready() -> void:
	_demo = GRASS_DEMO.instantiate() as Node3D
	add_child(_demo)
	var cam: Camera3D = _demo.get("cam")
	cam.make_current()


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
