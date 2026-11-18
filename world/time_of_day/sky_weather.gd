class_name SkyWeather
extends Resource
## One kind of weather for the sky and the air (files in world/time_of_day/weather/): clouds, haze,
## fog, wind and grading. The Atmosphere node blends between two of these when the weather changes.

@export var display_name := "Clear"
## Share of the sky the cumulus layer covers, before its large-scale variation.
@export_range(0.0, 1.0) var cloud_coverage := 0.2
## Thickness of the cloud material: 1 is fair-weather cumulus, higher is heavier, darker cloud.
@export_range(0.0, 4.0) var cloud_density := 1.0
## Base and top of the cumulus layer above sea level.
@export_range(200.0, 6000.0, 10.0, "suffix:m") var cloud_bottom := 1500.0
@export_range(500.0, 12000.0, 10.0, "suffix:m") var cloud_top := 3500.0
## High ice cloud streaks.
@export_range(0.0, 1.0) var cirrus_amount := 0.2
## Haze in the air: 1 is a clean day, 3 summer haze, 6 thick haze. Reddens and dims low sun.
@export_range(0.5, 10.0) var turbidity := 1.5
## Share of the direct sun the cloud cover hides on average (an overcast sky lets almost none through).
@export_range(0.0, 1.0) var sun_occlusion := 0.0
## Distance fog (per metre), and a low veil below fog_height: Godot fogs everything under that height by
## how far below it lies (1 - exp(-depth * fog_height_density)), near or far alike, so keep it small.
@export_range(0.0, 0.02, 0.00001) var fog_density := 0.0002
@export_range(0.0, 0.5, 0.0001) var fog_height_density := 0.002
@export_range(-50.0, 300.0, 1.0, "suffix:m") var fog_height := 20.0
## How much the fog veils the sky itself: 0 for clear air, more in rain and mist.
@export_range(0.0, 1.0) var fog_sky_affect := 0.0
## Volumetric fog near the camera (per metre): carries the light shafts.
@export_range(0.0, 0.1, 0.0001) var volumetric_fog_density := 0.002
## Forward scattering of the volumetric fog: high values glow brightly towards the sun.
@export_range(0.0, 0.95) var volumetric_fog_anisotropy := 0.6
## Wind at cloud height, in metres per second (x, z).
@export var wind := Vector2(8.0, 3.0)
## Grading.
@export_range(0.0, 2.0) var saturation := 1.05
@export_range(0.5, 1.5) var contrast := 1.0
## Lightning strikes per minute; 0 for none.
@export_range(0.0, 60.0) var lightning_per_minute := 0.0


## A weather between `from` (t = 0) and `to` (t = 1), for gradual changes.
static func blend(from: SkyWeather, to: SkyWeather, t: float) -> SkyWeather:
	var w := SkyWeather.new()
	w.display_name = to.display_name if t >= 0.5 else from.display_name
	w.cloud_coverage = lerpf(from.cloud_coverage, to.cloud_coverage, t)
	w.cloud_density = lerpf(from.cloud_density, to.cloud_density, t)
	w.cloud_bottom = lerpf(from.cloud_bottom, to.cloud_bottom, t)
	w.cloud_top = lerpf(from.cloud_top, to.cloud_top, t)
	w.cirrus_amount = lerpf(from.cirrus_amount, to.cirrus_amount, t)
	w.turbidity = lerpf(from.turbidity, to.turbidity, t)
	w.sun_occlusion = lerpf(from.sun_occlusion, to.sun_occlusion, t)
	w.fog_density = lerpf(from.fog_density, to.fog_density, t)
	w.fog_height_density = lerpf(from.fog_height_density, to.fog_height_density, t)
	w.fog_height = lerpf(from.fog_height, to.fog_height, t)
	w.fog_sky_affect = lerpf(from.fog_sky_affect, to.fog_sky_affect, t)
	w.volumetric_fog_density = lerpf(from.volumetric_fog_density, to.volumetric_fog_density, t)
	w.volumetric_fog_anisotropy = lerpf(from.volumetric_fog_anisotropy, to.volumetric_fog_anisotropy, t)
	w.wind = from.wind.lerp(to.wind, t)
	w.saturation = lerpf(from.saturation, to.saturation, t)
	w.contrast = lerpf(from.contrast, to.contrast, t)
	w.lightning_per_minute = lerpf(from.lightning_per_minute, to.lightning_per_minute, t)
	return w
