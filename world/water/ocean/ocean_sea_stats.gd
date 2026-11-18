class_name OceanSeaStats
extends RefCounted
## What a sea state means in sailor's terms: wave period, length, steepness, Beaufort force, and
## whether the settings still describe a sea that can exist. Pure logic for readouts and warnings.

const GRAVITY := 9.81
## Fully developed sea (Pierson-Moskowitz): Hs = this * wind speed^2 / g. Wind can't build higher waves.
const FULL_SEA_HEIGHT := 0.24
## Waves steeper than height / length = 1/7 break (Stokes limit).
const BREAKING_STEEPNESS := 1.0 / 7.0
## Real swell is gentle, height / length well below this; anything steeper is still a wind sea.
const SWELL_MAX_STEEPNESS := 1.0 / 25.0
## Above this choppiness the crests fold through themselves (see OceanSpectrum.choppiness).
const FOLDING_CHOPPINESS := 1.2
## Upper wind speed (m/s) of Beaufort forces 0 to 11; anything above is force 12.
const BEAUFORT_LIMITS: Array[float] = [0.5, 1.5, 3.3, 5.5, 7.9, 10.7, 13.8, 17.1, 20.7, 24.4, 28.4, 32.6]
const BEAUFORT_NAMES: Array[String] = ["Calm", "Light air", "Light breeze", "Gentle breeze",
		"Moderate breeze", "Fresh breeze", "Strong breeze", "Near gale", "Gale", "Strong gale", "Storm",
		"Violent storm", "Hurricane"]


## Seconds between dominant wave crests.
static func peak_period(sea: OceanSpectrum) -> float:
	return TAU / sea.peak_frequency()


## Seconds between crests of the bigger wave system: the swell when it is higher than the wind sea.
static func dominant_period(sea: OceanSpectrum) -> float:
	if swell_wave_height(sea) > surface_wave_height(sea):
		return sea.swell_period
	return peak_period(sea)


## Highest significant wave height (m) this wind can keep up, however long the fetch.
static func full_sea_height(sea: OceanSpectrum) -> float:
	return FULL_SEA_HEIGHT * sea.wind_speed * sea.wind_speed / GRAVITY


## Significant height (m) of the main waves (swell).
static func swell_wave_height(sea: OceanSpectrum) -> float:
	return sea.swell_height


## Significant height (m) of the surface waves, in deep water.
static func surface_wave_height(sea: OceanSpectrum) -> float:
	return sea.surface_height


## Significant wave height (m) the sea state should show in deep water: surface waves and swell
## together (their energies add).
static func expected_wave_height(sea: OceanSpectrum) -> float:
	var wind := surface_wave_height(sea)
	var swell := swell_wave_height(sea)
	return sqrt(wind * wind + swell * swell)


## Height over length of the dominant surface waves. `wave_height` is the measured height of the whole
## sea; the swell's share is taken out first, because long swell is never steep.
static func steepness(sea: OceanSpectrum, wave_height: float) -> float:
	var swell := swell_wave_height(sea)
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
	if sea.swell_height > 0.0 and sea.swell_height / sea.swell_wavelength() > SWELL_MAX_STEEPNESS:
		result.append("Swell steeper than 1/%.0f: real swell this steep is still a wind sea. Use a longer period." % (
				1.0 / SWELL_MAX_STEEPNESS))
	if sea.choppiness > FOLDING_CHOPPINESS:
		result.append("Choppiness above %.1f: crests fold through themselves." % FOLDING_CHOPPINESS)
	if sea.surface_height > full_sea_height(sea):
		result.append("Surface waves are higher than a %.0f m/s wind could build (fine for a sea after a storm)." % sea.wind_speed)
	return result
