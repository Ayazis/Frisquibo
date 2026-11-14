class_name WaterStation
extends Node3D
## One water type in the comparison prototype. Subclasses build their scene in _ready().

## Shown in the HUD.
var title := ""
var notes := ""
## True for third-party library water, false for our own shaders.
var is_library := false
var camera_target := Vector3.ZERO
var camera_distance := 20.0
## Optional: takes (xz: Vector2) and returns the water velocity, for currents that carry objects.
var water_velocity: Callable
## True when the station brings its own sky, sun and camera (the comparison scene then steps aside).
var takes_over_view := false


## False when this renderer can't show the water type; the HUD then shows `notes` as the reason.
func is_supported() -> bool:
	return true


## Water surface height at `xz`, for floating objects. Flat water at y = 0 unless overridden.
func water_height_at(_xz: Vector2) -> float:
	return 0.0


## Optional extra controls for this station (sliders); shown in the HUD while the station is active.
func make_controls() -> Control:
	return null
