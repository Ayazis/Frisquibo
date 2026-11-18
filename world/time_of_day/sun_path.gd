class_name SunPath
extends RefCounted
## Where the sun, the moon and the stars stand in the sky for a solar clock time, a day of the year and
## a latitude. Directions point from the observer towards the body.
## World axes: +Y is up. With a north heading of 0, north is -Z and east is +X; `north_heading` turns
## the whole sky about +Y (radians), so a scene can choose where the sun sets.

const AXIAL_TILT_DEGREES := 23.44
const DAYS_PER_YEAR := 365.0
## The declination is lowest at the December solstice, about 10 days before the year starts.
const SOLSTICE_OFFSET_DAYS := 10.0
## Day of the year of the March equinox: the sun's right ascension is 0 there.
const MARCH_EQUINOX_DAY := 80.0
const HOURS_PER_DAY := 24.0
const SOLAR_NOON := 12.0


## The sun's declination (radians) on `day_of_year` (0 = 1 January).
static func declination(day_of_year: float) -> float:
	return -deg_to_rad(AXIAL_TILT_DEGREES) * cos(TAU * (day_of_year + SOLSTICE_OFFSET_DAYS) / DAYS_PER_YEAR)


## The sun's hour angle (radians) at solar time `hour`: 0 at noon, growing through the afternoon.
static func hour_angle(hour: float) -> float:
	return TAU * (hour - SOLAR_NOON) / HOURS_PER_DAY


## Unit vector towards a body at `body_hour_angle` and `body_declination` (radians), seen from
## `latitude` (radians), with the sky turned by `north_heading`.
static func direction(body_hour_angle: float, body_declination: float, latitude: float, north_heading: float) -> Vector3:
	var east := -cos(body_declination) * sin(body_hour_angle)
	var north := cos(latitude) * sin(body_declination) - sin(latitude) * cos(body_declination) * cos(body_hour_angle)
	var up := sin(latitude) * sin(body_declination) + cos(latitude) * cos(body_declination) * cos(body_hour_angle)
	return Vector3(east, up, -north).rotated(Vector3.UP, north_heading)


static func sun_direction(hour: float, day_of_year: float, latitude_degrees: float, north_heading: float) -> Vector3:
	return direction(hour_angle(hour), declination(day_of_year), deg_to_rad(latitude_degrees), north_heading)


## The moon at `phase` (0 new, 0.5 full): it trails the sun by the phase's share of a full turn, and at
## full moon stands opposite the sun's declination. Ignores the 5 degree tilt of its orbit.
static func moon_direction(hour: float, day_of_year: float, latitude_degrees: float, north_heading: float,
		phase: float) -> Vector3:
	var moon_hour_angle := hour_angle(hour) - TAU * phase
	var moon_declination := declination(day_of_year) * cos(TAU * phase)
	return direction(moon_hour_angle, moon_declination, deg_to_rad(latitude_degrees), north_heading)


## Turns star directions in equatorial coordinates (Z towards the celestial north pole, X towards the
## March equinox) into world directions for this moment. Columns are the equatorial axes in world space.
static func star_basis(hour: float, day_of_year: float, latitude_degrees: float, north_heading: float) -> Basis:
	var latitude := deg_to_rad(latitude_degrees)
	# Hour angle of the March equinox (local sidereal angle): the sun's plus its right ascension.
	var sidereal := hour_angle(hour) + TAU * (day_of_year - MARCH_EQUINOX_DAY) / DAYS_PER_YEAR
	var equinox := direction(sidereal, 0.0, latitude, north_heading)
	var ninety := direction(sidereal - PI / 2.0, 0.0, latitude, north_heading)
	var pole := direction(0.0, PI / 2.0, latitude, north_heading)
	return Basis(equinox, ninety, pole)


## Elevation of a direction above the horizon, in degrees.
static func elevation_degrees(towards: Vector3) -> float:
	return rad_to_deg(asin(clampf(towards.normalized().y, -1.0, 1.0)))
