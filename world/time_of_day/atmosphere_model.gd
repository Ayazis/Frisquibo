class_name AtmosphereModel
extends RefCounted
## Physically based clear air: Rayleigh scattering by the air, Mie scattering by haze, ozone absorption,
## over a round earth. The sky shader (sky_atmosphere.gdshaderinc) runs the same model per pixel; this is
## the CPU side, used to colour the sun and moon lights, light the clouds and set the exposure, and as
## the reference the tests check. The constants must match the shader's (tests/headless/atmosphere_test.gd
## compares them).
## Units: metres; colours are Vector3 (r, g, b) in the engine's light units.

const EARTH_RADIUS := 6360000.0
const ATMOSPHERE_RADIUS := 6460000.0
## Rayleigh scattering of air at sea level, per metre (Bruneton 2017), and its scale height.
const RAYLEIGH := Vector3(5.802e-6, 13.558e-6, 33.1e-6)
const RAYLEIGH_HEIGHT := 8000.0
## Haze at sea level (turbidity 1), per metre, and its scale height. Turbidity scales both.
const MIE_SCATTERING := 3.996e-6
const MIE_EXTINCTION := 4.44e-6
const MIE_HEIGHT := 1200.0
## Forward lobe of the haze's phase function (Cornette-Shanks).
const MIE_ANISOTROPY := 0.8
## Ozone absorption, expressed per metre of the Rayleigh column (the ozone layer's 15 km equivalent
## thickness over the 8 km Rayleigh scale height). Ozone keeps the twilight zenith blue.
const OZONE := Vector3(0.650e-6, 1.881e-6, 0.085e-6) * 1.875
## Light scattered more than once, as a share of the single-scattered light, spread evenly over the
## sphere. Brightens the horizon and the twilight sky towards the measured values.
const MULTIPLE_SCATTERING := 1.5
## Width (m) of the soft edge of the earth's shadow on the air: about the sun's size at the distances
## twilight is lit from.
const EARTH_SHADOW_SOFTNESS := 1000.0
## Steps of the CPU sky integral. The shader uses its quality tier's count.
const DEFAULT_STEPS := 24


## Fraction of sunlight (per colour) that reaches `altitude` metres from a body whose direction has
## the cosine `cos_zenith` with the vertical. Zero once the earth hides it.
static func transmittance(altitude: float, cos_zenith: float, turbidity: float) -> Vector3:
	var visible := sun_visibility(altitude, cos_zenith)
	if visible <= 0.0:
		return Vector3.ZERO
	var rayleigh_column := column(altitude, cos_zenith, RAYLEIGH_HEIGHT)
	var mie_column := column(altitude, cos_zenith, MIE_HEIGHT)
	return _exp(-((RAYLEIGH + OZONE) * rayleigh_column + Vector3.ONE * MIE_EXTINCTION * turbidity * mie_column)) * visible


## How much of the sun's disc the earth leaves uncovered from `altitude`, looking at `cos_zenith`.
static func sun_visibility(altitude: float, cos_zenith: float) -> float:
	if cos_zenith >= 0.0:
		return 1.0
	var tangent := (EARTH_RADIUS + altitude) * sqrt(maxf(1.0 - cos_zenith * cos_zenith, 0.0))
	return smoothstep(-EARTH_SHADOW_SOFTNESS, EARTH_SHADOW_SOFTNESS, tangent - EARTH_RADIUS)


## Air (of one kind, by its scale height) along a ray from `altitude` to space, in metres of
## sea-level-density air: the Chapman function, after Schüler (GPU Pro 3). Below the horizon it goes
## through the ray's lowest point; callers multiply by sun_visibility for rays that hit the ground.
static func column(altitude: float, cos_zenith: float, scale_height: float) -> float:
	var x := (EARTH_RADIUS + altitude) / scale_height
	var h := altitude / scale_height
	var c := sqrt(0.5 * PI * x)
	if cos_zenith >= 0.0:
		return scale_height * c / (c * cos_zenith + 1.0) * exp(-h)
	# The lowest point of the ray, kept on the ground so a hidden sun's column stays finite.
	var x0 := maxf(sqrt(maxf(1.0 - cos_zenith * cos_zenith, 0.0)) * x, EARTH_RADIUS / scale_height)
	var c0 := sqrt(0.5 * PI * x0)
	return scale_height * (2.0 * c0 * exp(EARTH_RADIUS / scale_height - x0) - c / (1.0 - c * cos_zenith) * exp(-h))


## Radiance of the clear sky looking along `view` with the light (sun or moon) along `light`, which
## lights the top of the atmosphere with `irradiance`. Directions below the horizon look along it.
static func sky_radiance(view: Vector3, light: Vector3, irradiance: float, turbidity: float,
		altitude: float = 0.0, steps: int = DEFAULT_STEPS) -> Vector3:
	var d := Vector3(view.x, maxf(view.y, 0.0), view.z).normalized()
	var origin := Vector3(0.0, EARTH_RADIUS + altitude, 0.0)
	var length := _ray_sphere_far(origin, d, ATMOSPHERE_RADIUS)
	var rayleigh_view := 0.0
	var mie_view := 0.0
	var rayleigh_sum := Vector3.ZERO
	var mie_sum := Vector3.ZERO
	var previous := 0.0
	for i in range(steps):
		# Samples crowd near the observer, where the air is densest.
		var t := length * pow((i + 1.0) / steps, 2.0)
		var ds := t - previous
		var p := origin + d * (previous + 0.5 * ds)
		previous = t
		var r := p.length()
		var height := r - EARTH_RADIUS
		var rayleigh_density := exp(-height / RAYLEIGH_HEIGHT)
		var mie_density := exp(-height / MIE_HEIGHT)
		var cos_light := p.dot(light) / r
		var visible := sun_visibility(height, cos_light)
		if visible > 0.0:
			var rayleigh_column := rayleigh_view + 0.5 * rayleigh_density * ds + column(height, cos_light, RAYLEIGH_HEIGHT)
			var mie_column := mie_view + 0.5 * mie_density * ds + column(height, cos_light, MIE_HEIGHT)
			var through := _exp(-((RAYLEIGH + OZONE) * rayleigh_column
					+ Vector3.ONE * MIE_EXTINCTION * turbidity * mie_column)) * visible
			rayleigh_sum += through * rayleigh_density * ds
			mie_sum += through * mie_density * ds
		rayleigh_view += rayleigh_density * ds
		mie_view += mie_density * ds
	var mu := d.dot(light)
	var rayleigh_light := RAYLEIGH * rayleigh_sum
	var mie_light := mie_sum * MIE_SCATTERING * turbidity
	var single := rayleigh_light * rayleigh_phase(mu) + mie_light * mie_phase(mu)
	var multiple := (rayleigh_light + mie_light) * MULTIPLE_SCATTERING / (4.0 * PI)
	return (single + multiple) * irradiance


## Mean radiance of the clear sky dome: the zenith and a ring of directions 20 degrees up, which is
## close to the cosine-weighted mean that lights a level surface.
static func sky_mean_radiance(light: Vector3, irradiance: float, turbidity: float) -> Vector3:
	var sum := sky_radiance(Vector3.UP, light, irradiance, turbidity)
	const RING := 6
	const RING_ELEVATION := 0.35
	for i in range(RING):
		var a := TAU * i / RING
		sum += sky_radiance(Vector3(cos(a) * cos(RING_ELEVATION), sin(RING_ELEVATION), sin(a) * cos(RING_ELEVATION)),
				light, irradiance, turbidity)
	return sum / (RING + 1.0)


static func rayleigh_phase(mu: float) -> float:
	return 3.0 / (16.0 * PI) * (1.0 + mu * mu)


static func mie_phase(mu: float) -> float:
	var g := MIE_ANISOTROPY
	var g2 := g * g
	return 3.0 / (8.0 * PI) * (1.0 - g2) * (1.0 + mu * mu) / ((2.0 + g2) * pow(1.0 + g2 - 2.0 * g * mu, 1.5))


## Relative luminance (Rec. 709) of a linear colour.
static func luminance(color: Vector3) -> float:
	return color.dot(Vector3(0.2126, 0.7152, 0.0722))


static func _ray_sphere_far(origin: Vector3, direction: Vector3, radius: float) -> float:
	var b := origin.dot(direction)
	var c := origin.length_squared() - radius * radius
	return -b + sqrt(maxf(b * b - c, 0.0))


static func _exp(v: Vector3) -> Vector3:
	return Vector3(exp(v.x), exp(v.y), exp(v.z))
