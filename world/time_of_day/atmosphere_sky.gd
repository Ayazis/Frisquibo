class_name AtmosphereSky
extends RefCounted
## The sky resource and its shader (sky.gdshader): builds them for a quality tier and passes them the
## light, weather and sky position of each frame.

const SKY_SHADER := preload("res://world/time_of_day/sky.gdshader")
## The moon's disc radiance (before the air), tinted like its light: bright enough to read as the
## brightest thing in the night sky, and visible as a pale disc by day.
const MOON_DISC_RADIANCE := 0.25
## The camera's height the sky is drawn for. A fixed height keeps the radiance map from being redrawn
## whenever the camera moves; within a few hundred metres the sky looks the same.
const OBSERVER_ALTITUDE := 2.0
## Cirrus drifts slower across the sky than the low cumulus (it is farther away), relative to the wind.
const CIRRUS_DRIFT := 1.6

var sky := Sky.new()
var material := ShaderMaterial.new()
var _cloud_offset := Vector2.ZERO
var _cirrus_offset := Vector2.ZERO
var _clock := 0.0


func _init(quality: AtmosphereQuality) -> void:
	material.shader = SKY_SHADER
	sky.sky_material = material
	sky.radiance_size = _radiance_size(quality.radiance_size)
	# The clouds drift every frame; incremental updates spread the radiance map's cost over frames.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	material.set_shader_parameter("cloud_shape_noise", SkyNoise.shape())
	material.set_shader_parameter("cloud_detail_noise", SkyNoise.detail())
	material.set_shader_parameter("atmosphere_steps", quality.atmosphere_steps)
	material.set_shader_parameter("radiance_atmosphere_steps", quality.radiance_atmosphere_steps)
	material.set_shader_parameter("cloud_steps", quality.cloud_steps)
	material.set_shader_parameter("radiance_cloud_steps", quality.radiance_cloud_steps)
	material.set_shader_parameter("cloud_light_steps", quality.cloud_light_steps)
	material.set_shader_parameter("cloud_detail", quality.cloud_detail)
	material.set_shader_parameter("observer_altitude", OBSERVER_ALTITUDE)
	material.set_shader_parameter("night_sky", AtmosphereLighting.NIGHT_SKY)
	material.set_shader_parameter("sun_irradiance", AtmosphereLighting.SUN_IRRADIANCE)
	# Web: the Compatibility renderer has no half-resolution sky pass; the full pass draws it all.
	material.set_shader_parameter("use_half_res", RenderingServer.get_current_rendering_method() != "gl_compatibility")


## Moves the clouds on by `delta` real seconds of wind, `time_scale` times faster in a time lapse.
func drift(delta: float, wind: Vector2, time_scale: float) -> void:
	_cloud_offset += wind * delta * time_scale
	_cirrus_offset += wind * CIRRUS_DRIFT * delta * time_scale
	_clock += delta


func apply(time: TimeOfDay, weather: SkyWeather, lighting: AtmosphereLighting, flash: float) -> void:
	var m := material
	m.set_shader_parameter("sun_direction", time.sun_direction())
	m.set_shader_parameter("moon_direction", time.moon_direction())
	m.set_shader_parameter("moon_sky_light", lighting.moon_sky_light)
	m.set_shader_parameter("moon_disc_light", AtmosphereLighting.MOON_TINT * MOON_DISC_RADIANCE)
	m.set_shader_parameter("star_rotation", time.star_basis())
	m.set_shader_parameter("night", lighting.night)
	m.set_shader_parameter("sky_time", _clock)
	m.set_shader_parameter("turbidity", weather.turbidity)
	m.set_shader_parameter("cloud_coverage", weather.cloud_coverage)
	m.set_shader_parameter("cloud_density", weather.cloud_density)
	m.set_shader_parameter("cloud_bottom", weather.cloud_bottom)
	m.set_shader_parameter("cloud_top", maxf(weather.cloud_top, weather.cloud_bottom + 100.0))
	m.set_shader_parameter("cirrus_amount", weather.cirrus_amount)
	m.set_shader_parameter("cloud_offset", _cloud_offset)
	m.set_shader_parameter("cirrus_offset", _cirrus_offset)
	m.set_shader_parameter("cloud_light_direction", lighting.cloud_light_direction)
	m.set_shader_parameter("cloud_light", lighting.cloud_light)
	m.set_shader_parameter("cirrus_light", lighting.cirrus_light)
	m.set_shader_parameter("cloud_ambient", lighting.cloud_ambient)
	m.set_shader_parameter("cloud_flash", flash)


static func _radiance_size(texels: int) -> Sky.RadianceSize:
	if texels <= 32:
		return Sky.RADIANCE_SIZE_32
	if texels <= 64:
		return Sky.RADIANCE_SIZE_64
	if texels <= 128:
		return Sky.RADIANCE_SIZE_128
	if texels <= 256:
		return Sky.RADIANCE_SIZE_256
	if texels <= 512:
		return Sky.RADIANCE_SIZE_512
	if texels <= 1024:
		return Sky.RADIANCE_SIZE_1024
	return Sky.RADIANCE_SIZE_2048
