class_name OceanSpectrum
extends Resource
## Sea state for the FFT ocean, as two wave systems on top of each other: the main waves (swell, long
## waves from a distant storm) and the surface waves the local wind builds (wind sea). Each has its
## own direction. Then the shape of the crests, the foam, the depth, and artistic overrides.
## The export groups are the sections of the tuner panel. Presets live in world/water/ocean/presets/.
## Changing one at runtime regenerates the spectrum.

@export_group("Main waves (swell)")
## Significant height of swell: long, regular waves from a distant storm, on top of the local wind
## sea and with their own direction. 0 = no swell.
@export_range(0.0, 8.0, 0.05, "suffix:m") var swell_height := 0.0
## Seconds between swell crests. Longer swell comes from further away and travels faster.
@export_range(5.0, 22.0, 0.1, "suffix:s") var swell_period := 11.0
@export_range(-180.0, 180.0, 1.0, "degrees") var swell_direction := -20.0
## How far swell directions stray from the main one. Swell is far better sorted than a wind sea.
@export_range(1.0, 30.0, 0.5, "degrees") var swell_spread := 8.0
@export_group("Wind and surface waves")
## Wind speed 10 m above the sea. Wave height grows roughly with its square. Beaufort 12 starts at 32.7.
@export_range(0.5, 40.0, 0.1, "suffix:m/s") var wind_speed := 9.0
@export_range(-180.0, 180.0, 1.0, "degrees") var wind_direction := 25.0
## Open water the wind has blown over. Short fetch (a bay) gives short, choppy waves; long fetch gives swell.
@export_range(1.0, 2000.0, 1.0, "suffix:km") var fetch := 80.0
## Width of the wind sea's spread of directions, relative to a real one (Donelan-Banner): 1 = physical,
## lower = long, aligned crests, higher = a confused sea. Leaves the wave height alone.
@export_range(0.1, 6.0, 0.01) var wind_spread := 1.0
@export_group("Crest shape")
## Horizontal pull towards the crests. Above about 1.2 the surface starts to fold through itself.
## Applies to all waves, but long swell is too gentle (height / length ~ 1/100) to be sharpened much.
@export_range(0.0, 4.0) var choppiness := 0.9
## Suppresses waves shorter than about this length; keeps the smallest cascade from looking noisy.
@export_range(0.0, 3.0, 0.005, "suffix:m") var short_wave_cutoff := 0.02
@export_group("Foam")
## Foam appears where the surface compresses: jacobian below this value.
@export_range(0.0, 3.0) var foam_threshold := 0.55
@export_range(0.0, 20.0) var foam_gain := 3.0
## Time for whitecap foam to fade to about a third.
@export_range(0.1, 40.0, 0.1, "suffix:s") var foam_lifetime := 3.5
@export_group("Depth and shore")
## Water depth used for the dispersion and the TMA depth correction of the spectrum.
@export_range(1.0, 1000.0, 0.5, "suffix:m") var depth := 40.0
@export_group("Artistic overrides")
## Multiplies the height of all waves; 1 is what the swell and the wind really give.
@export_range(0.0, 6.0) var height_scale := 1.0
## Horizontal size of the wind waves: multiplies the length of the dominant ones (the spectral peak),
## as a longer fetch would. Their height stays the same, ripples keep their real size, and longer
## waves travel faster, as in nature. Pair with height_scale (or the steepness link) for bigger seas.
## The swell has its own length through its period.
@export_range(0.1, 8.0) var wavelength_scale := 1.0
@export_group("")
## Wave lengths of the cascades, longest first. Ratios are deliberately irrational so tiles never line up.
@export var cascade_tile_lengths := PackedFloat32Array([233.0, 61.7, 17.3, 4.9])
@export var seed := 1

const GRAVITY := 9.81
## Fixed-point steps solving the dispersion relation for the swell; converges well within these.
const DISPERSION_STEPS := 40
## Before wind_spread, `swell` (0..2) narrowed the wind sea's spreading by a factor 1 + this * swell.
const LEGACY_ALIGNMENT_FACTOR := 4.0


## Angular frequency of the dominant waves (rad/s): JONSWAP peak, shifted by wavelength_scale.
## Must match the peak in compute/ocean_spectrum.glsl.
func peak_frequency() -> float:
	var natural := 22.0 * pow(GRAVITY * GRAVITY / (wind_speed * fetch * 1000.0), 1.0 / 3.0)
	return natural / sqrt(wavelength_scale)


## Length of the dominant waves in metres (deep-water dispersion).
func peak_wavelength() -> float:
	var w := peak_frequency()
	return TAU * GRAVITY / (w * w)


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


## Length of the longest waves that matter: the dominant wind waves, or the swell when there is one.
func longest_wavelength() -> float:
	if swell_height <= 0.0:
		return peak_wavelength()
	return maxf(peak_wavelength(), swell_wavelength())


## Reads sea states saved before wind_spread existed (presets, saved tunings, A/B snapshots).
## `swell` was crest alignment: it becomes the matching spread. `spread` blended towards waves from
## every direction; wind_spread above 1 now does that, so the old value is dropped.
func _set(property: StringName, value: Variant) -> bool:
	match property:
		&"swell":
			var alignment: float = value
			wind_spread = 1.0 / (1.0 + LEGACY_ALIGNMENT_FACTOR * alignment)
			return true
		&"spread":
			return true
	return false
