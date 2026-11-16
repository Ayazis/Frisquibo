class_name WaterQuality
extends Resource
## Scalable settings shared by all water (sea, lake, river) for one quality tier
## (files in data/quality/water_*.tres).

## Texels per side of the camera-centred interaction ripple simulation.
@export_range(64, 1024) var ripple_resolution := 512
## Metres per side of the area that ripples are simulated in, centred on the camera.
@export_range(8.0, 256.0, 1.0, "suffix:m") var ripple_area := 48.0
## Scales the droplet count of splashes.
@export_range(0.0, 2.0, 0.05) var splash_particle_scale := 1.0
