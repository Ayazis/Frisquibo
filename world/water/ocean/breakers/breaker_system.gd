class_name BreakerSystem
extends Node3D
## Everything plunging breakers need, for one Ocean: the wave rays over its shore field (ShoreRays), the
## ribbons that draw the curls (OceanBreakers), the CPU query (ShoreBreakers), and the spray, mist and
## landing signal (BreakerEffects). The Ocean makes one when its seabed is baked and its quality tier
## asks for curls, and drives it each frame.

## A lip comes down here (where, how high the breaker was).
signal plunged(position: Vector3, height: float)

## Room above and below the sea level in the breakers' bounds (the ribbons add their own).
const BOUNDS_HEIGHT := 20.0
## Updates per second of the spray, mist and landing checks: they sample every crest on the CPU (about
## 2 ms a time on High), and droplets that start 50 ms late still look right.
const EFFECTS_RATE := 20.0

var rays: ShoreRays
var query := ShoreBreakers.new()
var _ribbons: OceanBreakers
var _effects: BreakerEffects
var _effects_wait := 0.0
var _material: ShaderMaterial


## `material`: the ocean surface's (the ribbons share it); `area`: the baked seabed's.
func _init(shore: ShoreWaves, material: ShaderMaterial, quality: OceanQuality, area: Rect2, level: float,
		depth_at: Callable, still_at: Callable) -> void:
	rays = ShoreRays.trace(shore.field, still_at)
	query.waves = shore
	query.depth_at = depth_at
	query.still_at = still_at
	query.level = level
	var bounds := AABB(Vector3(area.position.x, level - BOUNDS_HEIGHT, area.position.y),
			Vector3(area.size.x, 2.0 * BOUNDS_HEIGHT, area.size.y))
	material.set_shader_parameter("shore_rays", ImageTexture.create_from_image(rays.image))
	material.set_shader_parameter("shore_rays_size", Vector2(rays.columns, maxi(rays.rows, 1)))
	material.set_shader_parameter("shore_rays_step", ShoreRays.TIME_STEP)
	material.set_shader_parameter("breaker_reach", quality.breaker_reach)
	_material = material
	_ribbons = OceanBreakers.new(rays, material, quality.breaker_reach, quality.breaker_segments, bounds)
	add_child(_ribbons)
	_effects = BreakerEffects.new(_ribbons, rays, query, quality.breaker_spray, quality.breaker_mist, bounds)
	_effects.plunged.connect(func(at: Vector3, height: float) -> void: plunged.emit(at, height))
	add_child(_effects)


## The sea's rest level and how hard waves plunge (1: physical), after the rules.
func set_sea(level: float, curl_strength: float) -> void:
	query.level = level
	query.curl_strength = curl_strength


## Deepest water any wave can start breaking in: the biggest wave (size 1) with the most refraction
## gain, where its shoaled crest reaches the depth limit at the onset of breaking:
## gain * (zone / h)^(1/4) = onset * breaker_ratio * h.
func _deepest_break() -> float:
	var waves := query.waves
	var gain := waves.amplitude * sqrt(waves.share) * ShoreField.REFRACTION_MAX
	var zone := minf(waves.zone_depth, ShoreField.MAX_DEPTH)
	var limit := ShoreWaves.BREAK_ONSET * waves.breaker_ratio
	return minf(pow(gain * pow(zone, 0.25) / maxf(limit, 1e-3), 0.8), zone)


## Lays the ribbons every frame; samples the crests for the effects EFFECTS_RATE times a second.
func update(camera_xz: Vector2, time: float, period: float, wind: Vector2, delta: float) -> void:
	_ribbons.update(camera_xz, time, period, _deepest_break())
	_material.set_shader_parameter("breaker_waves", Vector2(_ribbons.covered))
	_effects_wait -= delta
	if _effects_wait <= 0.0:
		_effects_wait = maxf(_effects_wait + 1.0 / EFFECTS_RATE, 0.0)
		_effects.update(time, period, wind)
