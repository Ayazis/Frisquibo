class_name OceanQuality
extends Resource
## Scalable settings of the FFT ocean for one quality tier (files in data/quality/ocean_*.tres).

## Wave cascades simulated; fewer drops the shortest waves (their slope variance still shows as roughness).
@export_range(1, 4) var cascade_count := 4
## Angular resolution of the camera-centred surface mesh. Vertex spacing is radius * TAU / segments.
@export_range(64, 1024) var radial_segments := 512
@export var inner_radius := 1.5
@export var far_radius := 6000.0
## Planar reflection resolution as a fraction of the screen.
@export_range(0.25, 1.0) var reflection_resolution_scale := 0.75
## Taps of the planar reflection's blur on rough water. More taps: smoother streaks.
@export_range(1, 32) var reflection_blur_samples := 12
## Ray-march steps of the underwater light shafts; 0 turns them off.
@export_range(0, 64) var underwater_shaft_steps := 16
## Physics frames between GPU readbacks for floating objects; 0 disables the readback.
@export_range(0, 30) var readback_interval := 3
