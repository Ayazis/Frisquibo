class_name OceanSeaStats
extends RefCounted
## What a sea state means in sailor's terms: wave period, length, steepness, Beaufort force, and
## whether the settings still describe a sea that can exist. Pure logic for readouts and warnings.

const GRAVITY := 9.81
## Variance of a JONSWAP sea with peak enhancement 3.3: this * alpha * g^2 / peak frequency^4.
const JONSWAP_VARIANCE := 0.305
## Phillips constant of the JONSWAP spectrum: this * (wind^2 / (fetch * g))^JONSWAP_ALPHA_POWER.
## Must match jonswap() in compute/ocean_spectrum.glsl.
const JONSWAP_ALPHA := 0.076
const JONSWAP_ALPHA_POWER := 0.22
## Fully developed sea (Pierson-Moskowitz): Hs = this * wind speed^2 / g. Wind can't build higher waves.
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


## Significant height (m) of the wind sea the spectrum describes, in deep water and before
## height_scale. wavelength_scale leaves it unchanged by design.
static func wind_wave_height(sea: OceanSpectrum) -> float:
	var fetch_m := sea.fetch * 1000.0
	var alpha := JONSWAP_ALPHA * pow(sea.wind_speed * sea.wind_speed / (fetch_m * GRAVITY), JONSWAP_ALPHA_POWER)
	var peak := sea.peak_frequency() * sqrt(sea.wavelength_scale)
	return 4.0 * sqrt(JONSWAP_VARIANCE * alpha * GRAVITY * GRAVITY / pow(peak, 4.0))


## Highest significant wave height (m) this wind can keep up, however long the fetch.
static func full_sea_height(sea: OceanSpectrum) -> float:
	return FULL_SEA_HEIGHT * sea.wind_speed * sea.wind_speed / GRAVITY


## Significant wave height (m) the sea state should show in deep water: wind sea and swell
## together (their energies add), times the artistic height_scale.
static func expected_wave_height(sea: OceanSpectrum) -> float:
	var wind := wind_wave_height(sea)
	return sqrt(wind * wind + sea.swell_height * sea.swell_height) * sea.height_scale


## Height over length of the dominant wind waves. `wave_height` is the measured height of the whole
## sea; the swell's share is taken out first, because long swell is never steep.
static func steepness(sea: OceanSpectrum, wave_height: float) -> float:
	var swell := sea.swell_height * sea.height_scale
	var wind := sqrt(maxf(wave_height * wave_height - swell * swell, 0.0))
	return wind / sea.peak_wavelength()


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
	if wind_wave_height(sea) > full_sea_height(sea):
		result.append("Fetch is longer than this wind can use: the wind sea is higher than wind can build.")
	if (absf(sea.height_scale - 1.0) > PHYSICAL_SCALE_TOLERANCE
			or absf(sea.wavelength_scale - 1.0) > PHYSICAL_SCALE_TOLERANCE):
		result.append("Vertical or horizontal size is not 1: wave size no longer follows from the wind.")
	return result
