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


## False when this renderer can't show the water type; the HUD then shows `notes` as the reason.
func is_supported() -> bool:
	return true
