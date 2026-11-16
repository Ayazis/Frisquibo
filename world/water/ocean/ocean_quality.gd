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
## Ray-march steps of the screen-space reflections on all water (water_ssr.gdshaderinc); 0 turns
## them off. Lakes and rivers in a scene without an ocean use the project default (High's value).
@export_range(0, 64) var reflection_march_steps := 24
## Ray-march steps of the underwater light shafts; 0 turns them off.
@export_range(0, 64) var underwater_shaft_steps := 16
## Droplets of wind-blown spray around the camera in strong wind; 0 turns spray off.
@export_range(0, 50000) var spray_particles := 6000
## Metres per side of the area around the camera that spray is drawn in.
@export_range(10.0, 500.0, 1.0, "suffix:m") var spray_area := 120.0
## Physics frames between GPU readbacks for floating objects; 0 disables the readback.
@export_range(0, 30) var readback_interval := 3
