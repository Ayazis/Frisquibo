class_name BeachProfile
extends RefCounted
## Ground height across a sandy coast, as a function of distance from the shoreline.
##
## - Land: the beach face rises at `beach_slope` up to the berm (`berm_height`), then levels off.
## - Sea: Dean's equilibrium profile, depth = A * x^(2/3), the standard model for sandy coasts: steep near
##   the waterline, flattening offshore. A is set by the sand grain size (about 0.1 for medium sand).
## - A longshore sandbar where waves break, and beyond the surf zone the shelf keeps deepening at
##   `shelf_slope`, so the seabed never ends in a flat cap.
## Distances are in metres; positive offshore distance is out to sea. Heights are relative to `sea_level`.

const SMOOTHING := 1.5          # metres over which slopes blend into the berm and the shelf
const DEAN_START := 1.0          # avoids the vertical tangent of x^(2/3) at the waterline

var sea_level := 0.0
var beach_slope := 0.08         # 1:12, a typical medium-sand beach face
var berm_height := 2.5
var dean_a := 0.2                # m^(1/3); 0.1 fine sand, 0.2 coarse sand (steeper, deeper sooner)
var shelf_start := 140.0         # offshore distance where the shelf slope takes over
var shelf_slope := 0.035
var bar_distance := 45.0
var bar_height := 1.0
var bar_width := 12.0
var noise_amplitude := 0.25

var _noise := FastNoiseLite.new()


func _init(seed_value: int = 7) -> void:
	_noise.seed = seed_value
	_noise.frequency = 0.03
	_noise.fractal_octaves = 3


## Ground height at `offshore` metres from the shoreline (negative = inland), at world point (x, z)
## for the small-scale noise.
func height(offshore: float, x: float, z: float) -> float:
	var h: float
	if offshore <= 0.0:
		# Beach face up to the berm, blended smoothly into the flat top.
		var rise := -offshore * beach_slope
		h = _smooth_min(rise, berm_height, SMOOTHING * beach_slope)
	else:
		var depth := dean_a * (pow(offshore + DEAN_START, 2.0 / 3.0) - pow(DEAN_START, 2.0 / 3.0))
		depth += shelf_slope * _smooth_max(offshore - shelf_start, 0.0, SMOOTHING * 10.0)
		var bar := bar_height * exp(-pow((offshore - bar_distance) / bar_width, 2.0))
		h = -depth + bar
	# Noise fades in away from the waterline, so the shoreline itself stays where it is designed.
	var fade := clampf(absf(offshore) / 10.0, 0.0, 1.0)
	return sea_level + h + _noise.get_noise_2d(x, z) * noise_amplitude * fade


static func _smooth_min(a: float, b: float, k: float) -> float:
	var h := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)


static func _smooth_max(a: float, b: float, k: float) -> float:
	return -_smooth_min(-a, -b, k)
