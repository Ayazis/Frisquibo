class_name AtmosphereEnvironment
extends RefCounted
## The Environment of a lit scene: filmic tone mapping (AgX), glow, ambient occlusion and indirect
## light, distance fog and volumetric fog, all from the quality tier, and the parts that follow the
## weather and the light every frame (exposure, fog, grading).
## Volumetric fog and the screen-space effects exist in Forward+ only; elsewhere they stay off.

## AgX: a soft, film-like roll-off of bright light that keeps sunsets orange instead of yellow.
const AGX_CONTRAST := 1.3
## Glow (bloom): only light brighter than white after exposure blooms (the sun, its glitter, lightning),
## spread over the wider levels for a soft halo.
const GLOW_THRESHOLD := 1.0
const GLOW_INTENSITY := 0.4
const GLOW_LEVELS: Array[float] = [0.0, 0.35, 0.7, 0.6, 0.45, 0.3, 0.0]
## Distance fog: takes the colour of the sky behind it (aerial perspective) and brightens towards the sun.
const FOG_AERIAL_PERSPECTIVE := 1.0
const FOG_SUN_SCATTER := 0.12
## Volumetric fog: white droplets, lit by the sky as well as the sun; it leaves the sky to the sky shader.
const VOLUMETRIC_FOG_ALBEDO := Color(0.92, 0.94, 0.96)
const VOLUMETRIC_FOG_AMBIENT := 0.7
const VOLUMETRIC_FOG_REPROJECTION := 0.9
## Ambient occlusion and screen-space indirect light, tuned for outdoor scale.
const SSAO_RADIUS := 1.6
const SSAO_INTENSITY := 1.8
const SSAO_LIGHT_AFFECT := 0.15
const SSIL_RADIUS := 6.0
const SSIL_INTENSITY := 0.8


static func build(quality: AtmosphereQuality, sky: Sky) -> Environment:
	var forward_plus := RenderingServer.get_current_rendering_method() == "forward_plus"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_agx_contrast = AGX_CONTRAST
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = GLOW_THRESHOLD
	env.glow_intensity = GLOW_INTENSITY
	for i in range(GLOW_LEVELS.size()):
		env.set_glow_level(i, GLOW_LEVELS[i])
	env.ssr_enabled = forward_plus
	env.ssao_enabled = forward_plus and quality.ssao
	env.ssao_radius = SSAO_RADIUS
	env.ssao_intensity = SSAO_INTENSITY
	env.ssao_light_affect = SSAO_LIGHT_AFFECT
	env.ssil_enabled = forward_plus and quality.ssil
	env.ssil_radius = SSIL_RADIUS
	env.ssil_intensity = SSIL_INTENSITY
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_aerial_perspective = FOG_AERIAL_PERSPECTIVE
	env.fog_sun_scatter = FOG_SUN_SCATTER
	env.volumetric_fog_enabled = forward_plus and quality.volumetric_fog
	env.volumetric_fog_length = quality.volumetric_fog_length
	env.volumetric_fog_albedo = VOLUMETRIC_FOG_ALBEDO
	env.volumetric_fog_ambient_inject = VOLUMETRIC_FOG_AMBIENT
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.volumetric_fog_temporal_reprojection_amount = VOLUMETRIC_FOG_REPROJECTION
	if env.volumetric_fog_enabled:
		RenderingServer.environment_set_volumetric_fog_volume_size(quality.volumetric_fog_size, quality.volumetric_fog_depth)
	env.adjustment_enabled = true
	return env


## The parts that change with the weather and the light.
static func apply(env: Environment, weather: SkyWeather, lighting: AtmosphereLighting) -> void:
	env.tonemap_exposure = lighting.exposure
	env.fog_density = weather.fog_density
	env.fog_height = weather.fog_height
	env.fog_height_density = weather.fog_height_density
	env.fog_sky_affect = weather.fog_sky_affect
	env.volumetric_fog_density = weather.volumetric_fog_density
	env.volumetric_fog_anisotropy = weather.volumetric_fog_anisotropy
	env.adjustment_saturation = weather.saturation
	env.adjustment_contrast = weather.contrast
