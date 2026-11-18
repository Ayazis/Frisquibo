class_name Atmosphere
extends Node3D
## Lights a scene from its time of day and weather: the sky (AtmosphereSky), the environment
## (AtmosphereEnvironment), the sun and moon lights and lightning, updated every frame.
## Give it a TimeOfDay; the weather changes gradually with set_weather().

const DEFAULT_QUALITY := preload("res://data/quality/atmosphere_high.tres")
## Web build (Compatibility renderer): the Low tier.
const WEB_QUALITY := preload("res://data/quality/atmosphere_low.tres")
const DEFAULT_WEATHER := preload("res://world/time_of_day/weather/fair.tres")
## Seconds a change of weather takes.
const WEATHER_TRANSITION := 6.0
## The clouds race in a time lapse, but no faster than this many times their real speed.
const MAX_CLOUD_TIME_SCALE := 60.0
## Sun shadow cascades: where each split ends, as a share of the shadow distance.
const SHADOW_SPLITS := Vector3(0.05, 0.15, 0.4)
const MOON_ANGULAR_DIAMETER := 0.52
## Lightning: the flash's light on the world and how much it lights up the clouds.
const LIGHTNING_ENERGY := 3.0
const LIGHTNING_COLOR := Color(0.8, 0.85, 1.0)
const LIGHTNING_CLOUD_GLOW := 0.6
const LIGHTNING_SEED := 7
## The light is worked out again once the sun or moon has moved this far (radians), or the weather changes.
const RELIGHT_ANGLE := 0.0005

@export var time: TimeOfDay
@export var weather: SkyWeather
@export var quality: AtmosphereQuality

var environment: Environment
var sun := DirectionalLight3D.new()
var moon := DirectionalLight3D.new()
var lighting: AtmosphereLighting
var _sky: AtmosphereSky
var _flash := DirectionalLight3D.new()
var _lightning := LightningStrikes.new(LIGHTNING_SEED)
var _from: SkyWeather
var _current: SkyWeather
var _blend := 1.0
var _transition := WEATHER_TRANSITION
var _lit_sun := Vector3.ZERO
var _lit_moon := Vector3.ZERO
var _lit_weather: SkyWeather


func _ready() -> void:
	if quality == null:
		quality = WEB_QUALITY if OS.has_feature("web") else DEFAULT_QUALITY
	if weather == null:
		weather = DEFAULT_WEATHER
	if time == null:
		time = TimeOfDay.new()
		add_child(time)
	_from = weather
	_current = weather
	_sky = AtmosphereSky.new(quality)
	environment = AtmosphereEnvironment.build(quality, _sky.sky)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	_setup_light(sun, quality.sun_angular_diameter)
	sun.directional_shadow_max_distance = quality.shadow_distance
	_setup_light(moon, MOON_ANGULAR_DIAMETER)
	moon.directional_shadow_max_distance = quality.shadow_distance
	_flash.light_color = LIGHTNING_COLOR
	_flash.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	_flash.visible = false
	add_child(sun)
	add_child(moon)
	add_child(_flash)
	update_now()


## Changes the weather to `next` over `seconds` (0: at once).
func set_weather(next: SkyWeather, seconds: float = WEATHER_TRANSITION) -> void:
	_from = _current
	weather = next
	_transition = seconds
	_blend = 0.0 if seconds > 0.0 else 1.0
	if _blend >= 1.0:
		_current = next


## The weather as it is now, partway through a change.
func current_weather() -> SkyWeather:
	return _current


func _process(delta: float) -> void:
	if _blend < 1.0:
		_blend = minf(_blend + delta / maxf(_transition, 1e-3), 1.0)
		_current = SkyWeather.blend(_from, weather, smoothstep(0.0, 1.0, _blend))
	_sky.drift(delta, _current.wind, minf(time.time_scale(), MAX_CLOUD_TIME_SCALE))
	var flash := _lightning.advance(delta, _current.lightning_per_minute)
	_flash.visible = flash > AtmosphereLighting.MIN_LIGHT_ENERGY
	if _flash.visible:
		_flash.light_energy = flash * LIGHTNING_ENERGY
		_point(_flash, _lightning.direction)
	_relight(false)
	_sky.apply(time, _current, lighting, flash * LIGHTNING_CLOUD_GLOW)


## Applies the time and weather right away (after jumping the clock, or before a screenshot).
func update_now() -> void:
	_current = weather if _blend >= 1.0 else _current
	_relight(true)
	_sky.apply(time, _current, lighting, 0.0)


func _relight(force: bool) -> void:
	var sun_direction := time.sun_direction()
	var moon_direction := time.moon_direction()
	var moved := sun_direction.angle_to(_lit_sun) > RELIGHT_ANGLE or moon_direction.angle_to(_lit_moon) > RELIGHT_ANGLE
	if not force and not moved and _current == _lit_weather:
		return
	_lit_sun = sun_direction
	_lit_moon = moon_direction
	_lit_weather = _current
	lighting = AtmosphereLighting.evaluate(sun_direction, moon_direction, time.moon_phase, _current)
	_apply_light(sun, sun_direction, lighting.sun_color, lighting.sun_energy, lighting.sun_casts_shadows)
	_apply_light(moon, moon_direction, lighting.moon_color, lighting.moon_energy, not lighting.sun_casts_shadows)
	AtmosphereEnvironment.apply(environment, _current, lighting)


func _setup_light(light: DirectionalLight3D, angular_diameter: float) -> void:
	light.shadow_enabled = true
	light.light_angular_distance = angular_diameter
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	light.directional_shadow_split_1 = SHADOW_SPLITS.x
	light.directional_shadow_split_2 = SHADOW_SPLITS.y
	light.directional_shadow_split_3 = SHADOW_SPLITS.z
	light.directional_shadow_blend_splits = true
	# The sky shader takes the sun and moon from its own uniforms.
	light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY


## Only the brighter light casts shadows: two would share, and halve, the shadow map.
func _apply_light(light: DirectionalLight3D, towards: Vector3, color: Color, energy: float, shadows: bool) -> void:
	light.visible = energy > AtmosphereLighting.MIN_LIGHT_ENERGY and towards.y > -0.1
	if not light.visible:
		return
	light.light_color = color
	light.light_energy = energy
	light.shadow_enabled = shadows
	_point(light, towards)


## Turns a light so it shines from `towards` (a direction to the light).
static func _point(light: DirectionalLight3D, towards: Vector3) -> void:
	var up := Vector3.UP if absf(towards.normalized().y) < 0.999 else Vector3.FORWARD
	light.basis = Basis.looking_at(-towards, up)
