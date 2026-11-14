class_name OceanSeaStats
extends RefCounted
## What a sea state means in sailor's terms: wave period, length, steepness, Beaufort force, and
## whether the settings still describe a sea that can exist. Pure logic for readouts and warnings.

const GRAVITY := 9.81
## Fetch-limited growth (JONSWAP): Hs = this * wind speed * sqrt(fetch / g).
const FETCH_GROWTH := 0.0016
## Fully developed sea (Pierson-Moskowitz): Hs = this * wind speed^2 / g. Waves never outgrow it.
const FULL_SEA_HEIGHT := 0.24
## Waves steeper than height / length = 1/7 break (Stokes limit).
const BREAKING_STEEPNESS := 1.0 / 7.0
## Above this choppiness the crests fold through themselves (see OceanSpectrum.choppiness).
const FOLDING_CHOPPINESS := 1.2
## Size multipliers within this distance of 1 count as physical.
const PHYSICAL_SCALE_TOLERANCE := 0.01
## Upper wind speed (m/s) of Beaufort forces 0 to 11; anything above is force 12.
const BEAUFORT_LIMITS: Array[float] = [0.5, 1.5, 3.3, 5.5, 7.9, 10.7, 13.8, 17.1, 20.7, 24.4, 28.4, 32.6]
const BEAUFORT_NAMES: Array[String] = ["Calm", "Light air", "Light breeze", "Gentle breeze",
		"Moderate breeze", "Fresh breeze", "Strong breeze", "Near gale", "Gale", "Strong gale", "Storm",
		"Violent storm", "Hurricane"]


## Seconds between dominant wave crests.
static func peak_period(sea: OceanSpectrum) -> float:
	return TAU / sea.peak_frequency()


## Significant wave height (m) this wind and fetch build in nature, times the artistic height_scale.
static func expected_wave_height(sea: OceanSpectrum) -> float:
	var growing := FETCH_GROWTH * sea.wind_speed * sqrt(sea.fetch * 1000.0 / GRAVITY)
	var full := FULL_SEA_HEIGHT * sea.wind_speed * sea.wind_speed / GRAVITY
	return minf(growing, full) * sea.height_scale


## Wave height over length of the dominant waves.
static func steepness(sea: OceanSpectrum, wave_height: float) -> float:
	return wave_height / sea.peak_wavelength()


static func beaufort(wind_speed: float) -> int:
	for force: int in range(BEAUFORT_LIMITS.size()):
		if wind_speed < BEAUFORT_LIMITS[force]:
			return force
	return BEAUFORT_LIMITS.size()


static func beaufort_name(wind_speed: float) -> String:
	return BEAUFORT_NAMES[beaufort(wind_speed)]


## Ways in which the sea state has left what real water does. Empty: physically plausible.
static func warnings(sea: OceanSpectrum, wave_height: float) -> PackedStringArray:
	var result := PackedStringArray()
	if steepness(sea, wave_height) > BREAKING_STEEPNESS:
		result.append("Waves are steeper than 1/7: real waves this steep have already broken.")
	if sea.choppiness > FOLDING_CHOPPINESS:
		result.append("Choppiness above %.1f: crests fold through themselves." % FOLDING_CHOPPINESS)
	if (absf(sea.height_scale - 1.0) > PHYSICAL_SCALE_TOLERANCE
			or absf(sea.wavelength_scale - 1.0) > PHYSICAL_SCALE_TOLERANCE):
		result.append("Vertical or horizontal size is not 1: wave size no longer follows from the wind.")
	return result
