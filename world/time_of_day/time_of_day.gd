class_name TimeOfDay
extends Node
## The scene's solar clock and place on earth: where the sun, the moon and the stars stand. Runs on
## its own when `hours_per_second` is set. The Atmosphere node reads it every frame.

@export_range(0.0, 24.0, 0.01, "suffix:h") var hour := 12.0
## Day of the year (0 = 1 January). Late summer by default: long golden evenings, a high noon sun.
@export_range(0.0, 365.0, 1.0) var day_of_year := 228.0
## Southern France and northern Italy.
@export_range(-89.0, 89.0, 0.1, "suffix:°") var latitude := 43.0
## Where north lies in the world, as a turn about +Y from -Z. Turns the whole sky: it decides where the
## sun rises and sets over the scene.
@export_range(-180.0, 180.0, 0.1, "suffix:°") var north_heading_degrees := 0.0
## 0 new moon, 0.5 full moon. A waxing gibbous moon stands in the evening sky.
@export_range(0.0, 1.0) var moon_phase := 0.4
## Game hours per real second: 0 stops the clock.
@export var hours_per_second := 0.0


func _process(delta: float) -> void:
	advance(delta)


## Runs the clock on by `delta` real seconds.
func advance(delta: float) -> void:
	if hours_per_second != 0.0:
		hour = fposmod(hour + delta * hours_per_second, SunPath.HOURS_PER_DAY)


## Game seconds that pass per real second (1 when the clock stands still: clouds keep drifting).
func time_scale() -> float:
	return maxf(absf(hours_per_second) * 3600.0, 1.0)


func sun_direction() -> Vector3:
	return SunPath.sun_direction(hour, day_of_year, latitude, deg_to_rad(north_heading_degrees))


func moon_direction() -> Vector3:
	return SunPath.moon_direction(hour, day_of_year, latitude, deg_to_rad(north_heading_degrees), moon_phase)


func star_basis() -> Basis:
	return SunPath.star_basis(hour, day_of_year, latitude, deg_to_rad(north_heading_degrees))


## The clock as "hh:mm".
func clock_text() -> String:
	var minutes := int(roundf(hour * 60.0)) % (24 * 60)
	return "%02d:%02d" % [minutes / 60, minutes % 60]
