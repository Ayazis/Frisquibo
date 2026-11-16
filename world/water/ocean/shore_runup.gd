class_name ShoreRunup
extends RefCounted
## How far up a beach the waves run: the height above still water that 2% of waves reach (R2%), from
## Stockdon et al. (2006), fitted on ten field sites. Wave set-up and the swash on top of it both grow
## with the wave height and length and with the slope of the beach face.

const GRAVITY := 9.81
const SETUP_FACTOR := 0.35
const SWASH_SLOPE_FACTOR := 0.563
const SWASH_INFRAGRAVITY := 0.004
const R2_FACTOR := 1.1


## R2% run-up in metres above still water. wave_height: significant height offshore (m);
## period: peak period (s); beach_slope: slope of the beach face (rise over run).
static func stockdon(wave_height: float, period: float, beach_slope: float) -> float:
	if wave_height <= 0.0 or period <= 0.0:
		return 0.0
	var deep_wavelength := GRAVITY * period * period / TAU
	var hl := wave_height * deep_wavelength
	var setup := SETUP_FACTOR * beach_slope * sqrt(hl)
	var swash := sqrt(hl * (SWASH_SLOPE_FACTOR * beach_slope * beach_slope + SWASH_INFRAGRAVITY)) / 2.0
	return R2_FACTOR * (setup + swash)
