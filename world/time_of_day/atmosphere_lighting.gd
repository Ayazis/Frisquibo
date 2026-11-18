class_name AtmosphereLighting
extends RefCounted
## The light of one moment: the sun's and moon's colour and strength after the air, what lights the
## clouds, and the exposure the eye would settle on. Pure logic from AtmosphereModel; the Atmosphere node
## applies it to the lights, the sky shader and the environment.

## The sun's irradiance above the atmosphere, in engine light units (a high summer sun gives about 1.5).
const SUN_IRRADIANCE := 1.75
## The full moon's, in the same units: far brighter than in nature (1/400 000 of the sun), as night in
## games and film is; the exposure does the rest.
const MOON_IRRADIANCE := 0.07
## Moonlight seen by night-adapted eyes: cooler than the sunlight it reflects.
const MOON_TINT := Vector3(0.62, 0.78, 1.0)
## Starlight and airglow: the darkest a clear night sky gets.
const NIGHT_SKY := Vector3(0.0004, 0.0006, 0.0012)
## Height at which the clouds' and the cirrus's light is taken.
const CLOUD_LIGHT_ALTITUDE := 2500.0
const CIRRUS_ALTITUDE := 8000.0
## Exposure: a mid-grey surface (see facing()) under the high clear sun (REFERENCE_SUN_ELEVATION) is exposed to
## EXPOSURE_KEY. Darker scenes are brightened by only part of the difference (ADAPTATION), as the eye
## does, up to MAX_GAIN times: night stays night.
const EXPOSURE_KEY := 0.16
const MID_GREY := 0.18
const REFERENCE_SUN_ELEVATION := 60.0
const ADAPTATION := 0.7
const MAX_GAIN := 7.0
## A scene is not only level ground: upright faces (cliffs, walls, trees) catch a low sun square on.
## The exposure weighs direct light on level and on upright surfaces by these shares.
const LEVEL_SHARE := 0.6
const UPRIGHT_SHARE := 0.25
## The sun light is switched off below this energy (and the moon's shadows take over at night).
const MIN_LIGHT_ENERGY := 0.0005

var sun_color := Color.WHITE
var sun_energy := 0.0
var moon_color := Color.WHITE
var moon_energy := 0.0
## Which of the two casts the shadows (the brighter one).
var sun_casts_shadows := true
## The light on the clouds: direction towards it and irradiance there, plus the sky around them.
var cloud_light_direction := Vector3.UP
var cloud_light := Vector3.ZERO
var cirrus_light := Vector3.ZERO
var cloud_ambient := Vector3.ZERO
## Irradiance of the moon above the atmosphere, tinted, for the sky shader's moonlit air.
var moon_sky_light := Vector3.ZERO
## Stars and the moon's disc: 0 by day, 1 by night.
var night := 0.0
var exposure := 1.0


static func evaluate(sun: Vector3, moon: Vector3, moon_phase: float, weather: SkyWeather) -> AtmosphereLighting:
	var l := AtmosphereLighting.new()
	var turbidity := weather.turbidity
	var clear := 1.0 - weather.sun_occlusion
	var sun_through := AtmosphereModel.transmittance(0.0, sun.y, turbidity) * SUN_IRRADIANCE
	var moon_full := MOON_IRRADIANCE * illuminated_fraction(moon_phase)
	l.moon_sky_light = MOON_TINT * moon_full
	var moon_through := AtmosphereModel.transmittance(0.0, moon.y, turbidity) * l.moon_sky_light
	_set_light_color(sun_through * clear, l, true)
	_set_light_color(moon_through * clear, l, false)
	l.sun_casts_shadows = l.sun_energy >= l.moon_energy
	var sky_mean := AtmosphereModel.sky_mean_radiance(sun, SUN_IRRADIANCE, turbidity) + NIGHT_SKY
	if moon_full > 0.0 and moon.y > -0.2:
		sky_mean += AtmosphereModel.sky_mean_radiance(moon, 1.0, turbidity) * l.moon_sky_light
	l.cloud_ambient = sky_mean
	var sun_clouds := AtmosphereModel.transmittance(CLOUD_LIGHT_ALTITUDE, sun.y, turbidity) * SUN_IRRADIANCE
	var moon_clouds := AtmosphereModel.transmittance(CLOUD_LIGHT_ALTITUDE, moon.y, turbidity) * l.moon_sky_light
	var sun_lights_clouds := AtmosphereModel.luminance(sun_clouds) >= AtmosphereModel.luminance(moon_clouds)
	l.cloud_light_direction = sun if sun_lights_clouds else moon
	l.cloud_light = sun_clouds if sun_lights_clouds else moon_clouds
	var above := Vector3.ONE * SUN_IRRADIANCE if sun_lights_clouds else l.moon_sky_light
	l.cirrus_light = AtmosphereModel.transmittance(CIRRUS_ALTITUDE, l.cloud_light_direction.y, turbidity) * above
	l.night = 1.0 - smoothstep(-0.12, 0.02, sun.y)
	var direct := (AtmosphereModel.luminance(sun_through) * facing(sun.y)
			+ AtmosphereModel.luminance(moon_through) * facing(moon.y)) * clear
	l.exposure = exposure_for(scene_radiance(direct, sky_mean, clear))
	return l


## Radiance of a mid-grey surface under `direct` irradiance (luminance, already weighted by facing())
## from the sun and moon and the sky's mean radiance. Cloud cover (`clear` < 1) dims the sky only partly: overcast skies are bright.
static func scene_radiance(direct: float, sky_mean: Vector3, clear: float) -> float:
	var sky := AtmosphereModel.luminance(sky_mean) * lerpf(0.6, 1.0, clear)
	return MID_GREY * (direct / PI + sky)


## The exposure for a scene of radiance `ground`, partly adapted from the high clear sun's.
static func exposure_for(ground: float) -> float:
	var reference := reference_radiance()
	var ratio := reference / maxf(ground, 1e-9)
	return EXPOSURE_KEY / reference * minf(pow(ratio, ADAPTATION), MAX_GAIN)


## Radiance of a mid-grey surface under the reference sun on a clean day.
static func reference_radiance() -> float:
	var e := deg_to_rad(REFERENCE_SUN_ELEVATION)
	var sun := Vector3(0.0, sin(e), -cos(e))
	var direct := AtmosphereModel.luminance(AtmosphereModel.transmittance(0.0, sun.y, 1.0)) * SUN_IRRADIANCE * facing(sun.y)
	return scene_radiance(direct, AtmosphereModel.sky_mean_radiance(sun, SUN_IRRADIANCE, 1.0), 1.0)


## How square on the scene's surfaces face a light at height `sin_elevation` (0 below the horizon).
static func facing(sin_elevation: float) -> float:
	if sin_elevation <= 0.0:
		return 0.0
	return LEVEL_SHARE * sin_elevation + UPRIGHT_SHARE * sqrt(1.0 - sin_elevation * sin_elevation)


## Share of the moon's disc that is lit at `phase` (0 new, 0.5 full).
static func illuminated_fraction(phase: float) -> float:
	return 0.5 * (1.0 - cos(TAU * phase))


## Splits an irradiance into a light colour (brightest channel 1) and an energy.
static func _set_light_color(irradiance: Vector3, l: AtmosphereLighting, sun: bool) -> void:
	var peak := maxf(irradiance.x, maxf(irradiance.y, irradiance.z))
	var color := Color(irradiance.x / peak, irradiance.y / peak, irradiance.z / peak) if peak > 0.0 else Color.WHITE
	if sun:
		l.sun_color = color
		l.sun_energy = peak
	else:
		l.moon_color = color
		l.moon_energy = peak
