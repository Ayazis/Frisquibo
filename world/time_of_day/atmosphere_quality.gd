class_name AtmosphereQuality
extends Resource
## Scalable settings of the sky, the air and the sun's shadows for one quality tier
## (files in data/quality/atmosphere_*.tres).

## Texels per side of each face of the sky's radiance map (ambient light and reflections).
@export_range(32, 1024) var radiance_size := 256
## Samples along each view ray through the air: on screen (half resolution) and in the radiance map.
@export_range(4, 64) var atmosphere_steps := 16
@export_range(4, 64) var radiance_atmosphere_steps := 8
## Samples through the cumulus layer on screen and in the radiance map, and towards the light from each.
@export_range(0, 128) var cloud_steps := 48
@export_range(0, 64) var radiance_cloud_steps := 16
@export_range(1, 16) var cloud_light_steps := 5
## Fine erosion of the cloud edges (a second noise).
@export var cloud_detail := true
## Volumetric fog (light shafts): on or off, froxel grid size and depth, and how far it reaches.
@export var volumetric_fog := true
@export_range(16, 256) var volumetric_fog_size := 128
@export_range(16, 256) var volumetric_fog_depth := 96
@export_range(16.0, 2000.0, 1.0, "suffix:m") var volumetric_fog_length := 400.0
## Sun shadows: how far they reach, and the soft penumbra of the sun's real size (0 for hard shadows).
@export_range(20.0, 2000.0, 1.0, "suffix:m") var shadow_distance := 400.0
@export_range(0.0, 2.0, 0.01, "suffix:°") var sun_angular_diameter := 0.53
## Screen-space ambient occlusion and indirect light.
@export var ssao := true
@export var ssil := true
