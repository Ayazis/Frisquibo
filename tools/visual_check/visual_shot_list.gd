class_name VisualShotList
extends Resource
## A scene plus the fixed camera shots used to check how it looks.
## Golden images live next to the list, in golden/<list file name>/<shot name>.png.

@export_file("*.tscn") var scene_path: String = ""
@export var resolution: Vector2i = Vector2i(1600, 900)
## Frames rendered before capturing, so temporal effects (TAA, GI, auto-exposure) settle.
@export_range(1, 600) var settle_frames: int = 60
## Seed for the global random generator, set before the scene is created for each shot.
@export var random_seed: int = 1
## A pixel counts as changed when a colour channel differs by more than this (0..1).
@export_range(0.0, 1.0) var pixel_threshold: float = 0.08
## A shot fails when more than this fraction of its pixels changed (0..1).
@export_range(0.0, 1.0) var max_changed_ratio: float = 0.005
@export var shots: Array[VisualShot] = []
