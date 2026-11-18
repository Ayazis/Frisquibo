class_name LightningStrikes
extends RefCounted
## Lightning at random moments: each strike is a few quick flickers that die away, lighting the
## clouds from inside and the world from one side of the sky. Seeded, so runs repeat exactly.

## Flickers per strike, the time between them and how fast each fades (seconds).
const FLICKERS := 3
const FLICKER_SPACING := 0.11
const FLICKER_FADE := 0.07
## Each flicker is this much weaker than the one before.
const FLICKER_FALLOFF := 0.55
## Strikes light the world from this high in the sky (radians above the horizon).
const ELEVATION_RANGE := Vector2(0.5, 1.2)
const STRIKE_POWER_RANGE := Vector2(0.5, 1.0)

## Where the latest strike lights the world from.
var direction := Vector3.UP
var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _next := INF
var _strike_at := -INF
var _power := 0.0


func _init(seed_value: int) -> void:
	_rng.seed = seed_value


## Runs on by `delta` seconds at `per_minute` strikes; returns the flash brightness now (0 to about 1.5).
func advance(delta: float, per_minute: float) -> float:
	_clock += delta
	if per_minute <= 0.0:
		_next = INF
	elif _next == INF:
		_next = _clock + _interval(per_minute)
	elif _clock >= _next:
		_strike()
		_next = _clock + _interval(per_minute)
	return flash(_clock - _strike_at) * _power


## Brightness `age` seconds after a strike of power 1.
static func flash(age: float) -> float:
	var sum := 0.0
	var power := 1.0
	for k in range(FLICKERS):
		var since := age - k * FLICKER_SPACING
		if since >= 0.0:
			sum += power * exp(-since / FLICKER_FADE)
		power *= FLICKER_FALLOFF
	return sum


func _strike() -> void:
	_strike_at = _clock
	_power = _rng.randf_range(STRIKE_POWER_RANGE.x, STRIKE_POWER_RANGE.y)
	var azimuth := _rng.randf_range(0.0, TAU)
	var elevation := _rng.randf_range(ELEVATION_RANGE.x, ELEVATION_RANGE.y)
	direction = Vector3(cos(azimuth) * cos(elevation), sin(elevation), sin(azimuth) * cos(elevation))


## Random wait until the next strike: strikes come independently, at `per_minute` on average.
func _interval(per_minute: float) -> float:
	return -log(1.0 - _rng.randf() * 0.999) * 60.0 / per_minute
