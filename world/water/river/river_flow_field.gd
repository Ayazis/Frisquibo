class_name RiverFlowField
extends RefCounted
## Baked surface flow of a river section: velocity, turbulence and surface height on a grid.
## The river shader samples it as a texture and gameplay (floating objects) samples the same data,
## so what you see is what carries you.
##
## Built from the channel (a centreline, its half width and the mid-channel speed) and round obstacles
## (rocks). Around each rock the current parts like ideal flow around a cylinder; behind it trails a
## slowed, turbulent wake with a trough and V-shaped standing waves; in front of it water piles up into
## a bow wave. Texel layout (RGBA float): x velocity, z velocity, turbulence 0..1, surface height (m).

## Fraction of the obstacle-local current lost directly behind a rock.
const WAKE_DEFICIT := 0.75
## How fast the wake widens with distance downstream (fraction of the rock radius per radius).
const WAKE_SPREAD := 0.35
## Wake length in rock radii before it has mostly recovered.
const WAKE_LENGTH := 14.0
## Bow wave height per (m/s)^2 of current: stagnation head v^2 / 2g.
const BOW_HEAD := 1.0 / (2.0 * 9.81)
## Fraction of the full stagnation head the bow wave reaches, and its reach in rock radii.
const BOW_HEIGHT := 0.6
const BOW_REACH := 0.4
## Standing waves behind a rock: amplitude per stagnation head, and half-angle of the V (Kelvin wedge).
const CHEVRON_AMPLITUDE := 0.55
const CHEVRON_HALF_ANGLE := 0.34
const CHEVRON_WIDTH := 0.6
const GRAVITY := 9.81
## Turbulence where the current is sheared against the banks.
const BANK_TURBULENCE := 0.25

var rect: Rect2
var resolution: Vector2i
var image: Image

var _centre: Callable
var _half_width: float
var _speed: float
var _rocks: Array[Vector3] = []


## `centre` takes (x: float) and returns the channel centre z. `rocks` are (x, z, radius).
func _init(area: Rect2, texels_per_metre: float, centre: Callable, half_width: float, speed: float,
		rocks: Array[Vector3]) -> void:
	rect = area
	resolution = Vector2i(ceili(area.size.x * texels_per_metre), ceili(area.size.y * texels_per_metre))
	_centre = centre
	_half_width = half_width
	_speed = speed
	_rocks = rocks
	image = Image.create_empty(resolution.x, resolution.y, false, Image.FORMAT_RGBAF)
	for y in range(resolution.y):
		for x in range(resolution.x):
			var p := rect.position + rect.size * Vector2(x + 0.5, y + 0.5) / Vector2(resolution)
			image.set_pixelv(Vector2i(x, y), sample_exact(p))


## Channel current alone at `p`, without obstacles: along the centreline, parabolic across.
func channel_velocity(p: Vector2) -> Vector2:
	var centre: float = _centre.call(p.x)
	var ahead: float = _centre.call(p.x + 0.5)
	var dir := Vector2(0.5, ahead - centre).normalized()
	var across := clampf(absf(p.y - centre) / _half_width, 0.0, 1.0)
	return dir * _speed * (1.0 - across * across)


## Full computation at `p` (slow; used for baking). Returns (vx, vz, turbulence, height).
func sample_exact(p: Vector2) -> Color:
	var base := channel_velocity(p)
	var velocity := base
	var turbulence := 0.0
	var height := 0.0
	var centre: float = _centre.call(p.x)
	var across := clampf(absf(p.y - centre) / _half_width, 0.0, 1.0)
	turbulence += BANK_TURBULENCE * smoothstep(0.6, 1.0, across) * (base.length() / maxf(_speed, 0.001) + 0.3)
	for rock in _rocks:
		var r := rock.z
		var u := channel_velocity(Vector2(rock.x, rock.y))
		var speed := u.length()
		if speed < 0.01:
			continue
		var along := u / speed
		var side := Vector2(-along.y, along.x)
		var rel := p - Vector2(rock.x, rock.y)
		var lx := rel.dot(along)    # downstream distance
		var ly := rel.dot(side)     # sideways distance
		var d2 := lx * lx + ly * ly
		if d2 < r * r:
			return Color(0.0, 0.0, 1.0, 0.0)
		# Ideal flow around a cylinder: u - iv = U (1 - R^2 / z^2), added as a perturbation of the base flow.
		var inv := r * r / (d2 * d2)
		var du := -speed * (lx * lx - ly * ly) * inv
		var dv := -speed * 2.0 * lx * ly * inv
		velocity += along * du + side * dv
		var head := speed * speed * BOW_HEAD
		if lx < 0.0:
			# Bow wave: water piles up in front of the rock, falling off over about one radius.
			var dist := sqrt(d2) - r
			var facing := maxf(-lx, 0.0) / sqrt(d2)
			height += head * BOW_HEIGHT * exp(-dist / (BOW_REACH * r)) * facing * facing
			turbulence += 0.7 * exp(-dist / (BOW_REACH * r)) * facing
		else:
			var x := lx / r
			var width := r * (1.0 + WAKE_SPREAD * x)
			var core := exp(-ly * ly / (width * width))
			var recover := exp(-x / WAKE_LENGTH)
			velocity -= along * speed * WAKE_DEFICIT * core * recover * r / width
			turbulence += core * recover * (0.4 + 0.6 * exp(-x / 3.0))
			height -= head * 0.6 * core * exp(-x / 2.0)
			# V-shaped standing waves: crests on the two arms of the wedge, wavelength set by the current
			# (a standing gravity wave travels upstream at exactly the current speed: k = g / U^2).
			var k := GRAVITY / maxf(speed * speed, 0.05)
			var arm := absf(ly) - lx * tan(CHEVRON_HALF_ANGLE)
			var on_arm := exp(-arm * arm / (CHEVRON_WIDTH * CHEVRON_WIDTH * (1.0 + 0.2 * x)))
			height += head * CHEVRON_AMPLITUDE * on_arm * cos(k * lx) * exp(-x / WAKE_LENGTH) / (1.0 + 0.15 * x)
	return Color(velocity.x, velocity.y, clampf(turbulence, 0.0, 1.0), height)


## Bilinear lookup in the baked grid. Outside the grid: still water.
func sample(p: Vector2) -> Color:
	var t := (p - rect.position) / rect.size * Vector2(resolution) - Vector2(0.5, 0.5)
	if t.x < 0.0 or t.y < 0.0 or t.x > resolution.x - 1 or t.y > resolution.y - 1:
		return Color(0.0, 0.0, 0.0, 0.0)
	var x0 := mini(floori(t.x), resolution.x - 2)
	var y0 := mini(floori(t.y), resolution.y - 2)
	var fx := t.x - x0
	var fy := t.y - y0
	var a := image.get_pixel(x0, y0).lerp(image.get_pixel(x0 + 1, y0), fx)
	var b := image.get_pixel(x0, y0 + 1).lerp(image.get_pixel(x0 + 1, y0 + 1), fx)
	return a.lerp(b, fy)


func velocity_at(p: Vector2) -> Vector3:
	var c := sample(p)
	return Vector3(c.r, 0.0, c.g)


func height_at(p: Vector2) -> float:
	return sample(p).a


func texture() -> ImageTexture:
	return ImageTexture.create_from_image(image)
