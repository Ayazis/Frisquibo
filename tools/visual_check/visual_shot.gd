class_name VisualShot
extends Resource
## One fixed camera shot to render and compare.

## Used as the file name of the render and its baseline.
@export var name: String = ""
@export var camera_position: Vector3 = Vector3.ZERO
@export var look_at_target: Vector3 = Vector3.FORWARD
@export_range(10.0, 120.0) var fov: float = 65.0
## Passed to the scene's `apply_visual_check_state(state)` if it has one (e.g. {"time_preset": 1}).
@export var state: Dictionary = {}
