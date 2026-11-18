class_name OceanSpectrum
extends Resource
## Sea state for the FFT ocean, as two wave systems on top of each other: the main waves (swell, long
## waves from a distant storm) and the shorter surface waves. Each has its own height, length and
## direction, set directly: the wind does not build or shape them. The wind drives what rides on top
## (ripples, gusts, spray, foam drift and streaks). Then the foam and the depth.
## The export groups are the sections of the tuner panel. Presets live in world/water/ocean/presets/.
## Changing one at runtime regenerates the spectrum.

@export_group("Main waves (swell)")
## Significant height of swell: long, regular waves from a distant storm, on top of the surface
## waves and with their own direction. 0 = no swell.
@export_range(0.0, 8.0, 0.05, "suffix:m") var swell_height := 0.0
## Seconds between swell crests. Longer swell comes from further away and travels faster.
@export_range(5.0, 22.0, 0.1, "suffix:s") var swell_period := 11.0
@export_range(-180.0, 180.0, 1.0, "degrees") var swell_direction := -20.0
## How far swell directions stray from the main one. Swell is far better sorted than a wind sea.
@export_range(1.0, 30.0, 0.5, "degrees") var swell_spread := 8.0
@export_group("Crest shape")
## Horizontal pull towards the crests. Above about 1.2 the surface starts to fold through itself.
## Applies to all waves, but long swell is too gentle (height / length ~ 1/100) to be sharpened much.
@export_range(0.0, 4.0) var choppiness := 0.9
## Forward lean of the surface waves: crests are pushed along their direction of travel by this many
## times their height (troughs back), so a wave's front face is steeper than its back by about this
## times its slope. Steep waves turn lopsided; gentle swell barely changes. Never folds the surface further.
@export_range(0.0, 3.0, 0.05) var crest_lean := 0.1
## Height of the tumbling white water on crests that are breaking now, as a share of the breaking
## wave's height. Makes the crest's outline lumpy and torn instead of a smooth line.
@export_range(0.0, 0.6, 0.01) var white_water_height := 0.45
## Suppresses waves shorter than about this length; keeps the smallest cascade from looking noisy.
@export_range(0.0, 3.0, 0.005, "suffix:m") var short_wave_cutoff := 0.02
@export_group("Surface waves")
## Significant height of the surface waves (a JONSWAP sea): the shorter, irregular waves on top of
## the swell. 0 = none.
@export_range(0.0, 15.0, 0.01, "suffix:m") var surface_height := 1.72
## Length of the dominant surface waves (crest to crest, deep water). Their period follows from it.
@export_range(2.0, 600.0, 0.1, "or_greater", "suffix:m") var surface_length := 48.7
@export_range(-180.0, 180.0, 1.0, "degrees") var surface_direction := 25.0
## Width of the surface waves' spread of directions, relative to a real wind sea (Donelan-Banner):
## 1 = physical, lower = long, aligned crests, higher = a confused sea. Leaves the height alone.
@export_range(0.1, 6.0, 0.01) var surface_spread := 1.0
@export_group("Wind")
## Wind speed 10 m above the sea. Drives ripples, gusts, spray, foam drift and streaks; it does not
## change the waves. Beaufort 12 starts at 32.7.
@export_range(0.5, 40.0, 0.1, "suffix:m/s") var wind_speed := 9.0
@export_range(-180.0, 180.0, 1.0, "degrees") var wind_direction := 25.0
## Spray the wind tears off breaking crests (droplets and veils of spindrift), relative to the natural
## amount. Only in strong wind (from about Beaufort 6); 0 turns it off.
@export_range(0.0, 4.0, 0.05) var spray_amount := 1.0
@export_group("Foam")
## Foam appears where the surface compresses: jacobian below this value.
@export_range(0.0, 3.0) var foam_threshold := 0.55
@export_range(0.0, 20.0) var foam_gain := 3.0
## Time for whitecap foam to fade to about a third.
@export_range(0.1, 40.0, 0.1, "suffix:s") var foam_lifetime := 3.5
@export_group("Water depth")
## Water depth used for the dispersion and the TMA depth correction of the spectrum.
@export_range(1.0, 1000.0, 0.5, "suffix:m") var depth := 40.0
@export_group("")
## Wave lengths of the cascades, longest first. Ratios are deliberately irrational so tiles never line up.
@export var cascade_tile_lengths := PackedFloat32Array([233.0, 61.7, 17.3, 4.9])
@export var seed := 1

const GRAVITY := 9.81
## Fixed-point steps solving the dispersion relation for the swell; converges well within these.
const DISPERSION_STEPS := 40
## Variance of a JONSWAP sea with peak enhancement 3.3: this * alpha * g^2 / peak frequency^4.
const JONSWAP_VARIANCE := 0.305
## Before surface_spread, `swell` (0..2) narrowed the surface waves' spreading by 1 + this * swell.
const LEGACY_ALIGNMENT_FACTOR := 4.0
## Old sea states built the surface waves from wind and fetch (JONSWAP growth laws, Hasselmann 1973).
const LEGACY_ALPHA := 0.076
const LEGACY_ALPHA_POWER := 0.22
const LEGACY_PEAK := 22.0
const KM := 1000.0


## Angular frequency of the dominant surface waves (rad/s), from their deep-water length.
## Must match the peak in compute/ocean_spectrum.glsl.
func peak_frequency() -> float:
	return sqrt(TAU * GRAVITY / maxf(surface_length, 0.01))


## Phillips constant of the JONSWAP spectrum that gives the surface waves their significant height.
func jonswap_alpha() -> float:
	var peak := peak_frequency()
	var variance := surface_height * surface_height / 16.0
	return variance * pow(peak, 4.0) / (JONSWAP_VARIANCE * GRAVITY * GRAVITY)


## Length of the dominant surface waves in metres.
func peak_wavelength() -> float:
	return surface_length


## Wavenumber of the swell (rad/m) at this sea's depth: solves w^2 = g k tanh(k depth).
func swell_wavenumber() -> float:
	var w := TAU / swell_period
	var k := w * w / GRAVITY
	for i: int in range(DISPERSION_STEPS):
		k = w * w / (GRAVITY * tanh(k * depth))
	return k


## Length of the swell waves in metres at this sea's depth.
func swell_wavelength() -> float:
	return TAU / swell_wavenumber()


## Length of the longest waves that matter: the dominant surface waves, or the swell when there is one.
func longest_wavelength() -> float:
	if swell_height <= 0.0:
		return peak_wavelength()
	return maxf(peak_wavelength(), swell_wavelength())


## Reads sea states saved before the surface waves had their own size (presets, saved tunings, A/B
## snapshots). Their wind and fetch become the height and length those gave; the direction is the
## wind's, which is stored before fetch. Saves leave out default values, so this is best effort.
func _set(property: StringName, value: Variant) -> bool:
	match property:
		&"fetch":
			var fetch_km: float = value
			var fetch_m := fetch_km * KM
			var alpha := LEGACY_ALPHA * pow(wind_speed * wind_speed / (fetch_m * GRAVITY), LEGACY_ALPHA_POWER)
			var peak := LEGACY_PEAK * pow(GRAVITY * GRAVITY / (wind_speed * fetch_m), 1.0 / 3.0)
			surface_height = 4.0 * sqrt(JONSWAP_VARIANCE * alpha * GRAVITY * GRAVITY / pow(peak, 4.0))
			surface_length = TAU * GRAVITY / (peak * peak)
			surface_direction = wind_direction
			return true
		&"wind_spread":
			var old_spread: float = value
			surface_spread = old_spread
			return true
		&"wavelength_scale":
			var length_scale: float = value
			surface_length *= length_scale
			return true
		&"height_scale":
			var height_scale: float = value
			surface_height *= height_scale
			swell_height *= height_scale
			return true
		&"swell":
			var alignment: float = value
			surface_spread = 1.0 / (1.0 + LEGACY_ALIGNMENT_FACTOR * alignment)
			return true
		&"spread":
			return true
	return false
