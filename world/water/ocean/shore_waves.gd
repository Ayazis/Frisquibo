class_name ShoreWaves
extends RefCounted
## Waves near the coast, on the CPU: the twin of ocean_shore_waves.gdshaderinc, so floating objects ride
## the waves the screen shows. Keep the two in step: same constants, same order of operations.
##
## Inside `zone_depth` a share of the open sea's energy turns into waves that follow the ShoreField:
## crests along the lines of equal travel time (refracted towards the beach), growing as the water
## shallows (Green's law, H ~ h^-1/4) until the depth limit breaks them (crest <= breaker_ratio * h).
## Steep waves lean forward: the front gets short and steep, the back long. Their timing and size are
## the swash's (swash.gdshaderinc), so each crest runs up the sand as far as the swash says it does.

## Same as SWASH_* in swash.gdshaderinc.
const SWASH_SMALLEST := 0.45
const SWASH_ALONGSHORE := 25.0
const SWASH_PHASE_SPREAD := 0.5
const SWASH_WAVE_STEP := 7.31
const SWASH_HASH_OFFSET := 1048576
const HASH_A := 1597334677
const HASH_B := 3812015801
const UINT_MASK := 0xFFFFFFFF
const LOW_MASK := 0xFFFF
const HALF_BITS := 16
const UINT_MAX := 4294967295.0
## Same as SHORE_* in ocean_shore_waves.gdshaderinc.
## Share of a wavelength the front of a fully steepened wave takes (0.5: symmetric).
const FRONT_SHARE_MIN := 0.18
## Crest height, as a share of the breaking limit, where waves start to lean forward.
const SKEW_START := 0.3
## Forward lean of a fully steepened crest: its horizontal sway as a share of its height.
const LEAN := 0.9
## Offshore wave direction against the direction towards the beach (cosine): from LEE_FROM the shore
## is sheltered, from LEE_TO it faces the waves.
const LEE_FROM := -0.3
const LEE_TO := 0.7
## Breaking starts when the unbroken crest reaches this share of the depth limit.
const BREAK_ONSET := 0.85
## The white water of a spilling breaker (the roller) rides this upper share of the front face...
const ROLLER_REACH := 0.4
## ...and rounds it out by up to this share of the crest height.
const ROLLER_HEIGHT := 0.12
## Fixed-point steps that find which rest point the sway carried over a spot (as OceanHeightField does).
const INVERSE_ITERATIONS := 3

var field: ShoreField
## The wave clock (Ocean publishes the same value as `water_wave_time`).
var time := 0.0
## Seconds between crests (the swash's period).
var period := 8.0
## Typical crest height of the open sea (m).
var amplitude := 1.0
## Unit direction the open sea's main waves travel in.
var direction := Vector2.RIGHT
var breaker_ratio := 0.39
## Shore waves fade in from this depth (m) to half of it; never deeper than ShoreField.MAX_DEPTH.
var zone_depth := 8.0
## Share of the open sea's wave energy that becomes shore waves inside the zone.
var share := 0.7
## Share of the shore waves left on a coast facing away from the open sea's waves.
var lee_share := 0.3


## Integer hash of a lattice point in 0..1, bit for bit the swash_hash() of swash.gdshaderinc.
static func hash(lattice: Vector2) -> float:
	var qx := (int(lattice.x) + SWASH_HASH_OFFSET) & UINT_MASK
	var qy := (int(lattice.y) + SWASH_HASH_OFFSET) & UINT_MASK
	var n := _mul32(_mul32(qx, HASH_A) ^ _mul32(qy, HASH_B), HASH_A)
	return float(n) / UINT_MAX


## 32-bit unsigned multiplication with wrap-around, as on the GPU, without overflowing a 64-bit int.
static func _mul32(a: int, b: int) -> int:
	var low := a * (b & LOW_MASK)
	var high := ((a * (b >> HALF_BITS)) & LOW_MASK) << HALF_BITS
	return (low + high) & UINT_MASK


## Smooth value noise, as swash_noise().
static func noise(p: Vector2) -> float:
	var i := p.floor()
	var f := p - i
	var u := f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	var bottom := lerpf(hash(i), hash(i + Vector2(1.0, 0.0)), u.x)
	var top := lerpf(hash(i + Vector2(0.0, 1.0)), hash(i + Vector2(1.0, 1.0)), u.x)
	return lerpf(bottom, top, u.y)


## Size of wave number `wave` at `p` relative to the biggest: the same draw the swash makes for its reach.
static func wave_size(p: Vector2, wave: float) -> float:
	return lerpf(SWASH_SMALLEST, 1.0, noise(p / SWASH_ALONGSHORE + Vector2.ONE * wave * SWASH_WAVE_STEP))


## How much of the shore waves is present at still water depth `depth` (0 offshore, 1 well inside the zone).
func weight(depth: float) -> float:
	if field == null or depth <= 0.0 or depth >= _zone():
		return 0.0
	return 1.0 - smoothstep(0.5 * _zone(), _zone(), depth)


## Amplitude share the open-sea (FFT) waves keep at `depth`: what the shore waves did not take.
func open_sea_share(depth: float) -> float:
	return sqrt(1.0 - share * weight(depth))


## Displacement of the water that rests at `rest`, where the still water is `depth` deep.
func displacement(rest: Vector2, depth: float) -> Vector3:
	var w := weight(depth)
	if w <= 0.0:
		return Vector3.ZERO
	var f := field.sample(rest)
	var gradient := Vector2(f.g, f.b)
	var slowness := gradient.length()
	if f.a < 0.5 or slowness <= 0.0:
		return Vector3.ZERO
	var towards_shore := -gradient / slowness
	# What varies along the coast is drawn at the waterline point this wave is heading for: the same
	# draw the swash makes there, and unchanged along the wave's way in.
	var end := field.origin(rest)
	var cycle := maxf(period, 0.1)
	var phase := (time + f.r) / cycle + noise(end / SWASH_ALONGSHORE) * SWASH_PHASE_SPREAD
	var wave := floorf(phase)
	var u := phase - wave
	var size := lerpf(wave_size(end, wave), wave_size(end, wave + 1.0), smoothstep(0.0, 1.0, u))
	var lee := lerpf(lee_share, 1.0, smoothstep(LEE_FROM, LEE_TO, towards_shore.dot(direction)))
	var free_crest := amplitude * sqrt(share) * lee * size * pow(_zone() / maxf(depth, ShoreField.MIN_DEPTH), 0.25)
	var limit := breaker_ratio * depth
	var crest := minf(free_crest, limit) * w
	var ratio := free_crest / maxf(limit, 1e-4)
	var skew := smoothstep(SKEW_START, 1.0, ratio)
	var breaking := smoothstep(BREAK_ONSET, 1.0, ratio)
	var front := lerpf(0.5, FRONT_SHARE_MIN, skew)
	var profile := shape(u, front)
	var sway := crest * LEAN * skew * profile.y
	var lift := profile.x + ROLLER_HEIGHT * breaking * roller_bump(u, front)
	return Vector3(towards_shore.x * sway, crest * lift, towards_shore.y * sway)


## Water height above the rest level at world `xz` from the shore waves alone. `depth_at` gives the
## still water depth at a rest point (Vector2 -> float).
func height_at(xz: Vector2, depth_at: Callable) -> float:
	if field == null:
		return 0.0
	var rest := xz
	for i in range(INVERSE_ITERATIONS):
		var depth: float = depth_at.call(rest)
		var d := displacement(rest, depth)
		rest = xz - Vector2(d.x, d.z)
	var final_depth: float = depth_at.call(rest)
	return displacement(rest, final_depth).y


## One wave cycle: `u` is the share of the period since the crest passed, `front` the share the rising
## front takes. Returns (height, forward sway) in -1..1: the crest at u = 0, the trough at 1 - front;
## water moves towards the crest on both sides of it, as in a Gerstner wave.
static func shape(u: float, front: float) -> Vector2:
	var back := 1.0 - front
	if u < back:
		var x := u / back
		return Vector2(cos(PI * x), sin(PI * x))
	var y := (u - back) / front
	return Vector2(-cos(PI * y), -sin(PI * y))


## The roller's bulge on the upper front face, 0..1: zero with zero slope at both its ends (part way
## down the face and at the crest), so the surface stays smooth.
static func roller_bump(u: float, front: float) -> float:
	var back := 1.0 - front
	if u < back:
		return 0.0
	var t := ((u - back) / front - (1.0 - ROLLER_REACH)) / ROLLER_REACH
	if t <= 0.0:
		return 0.0
	return 16.0 * t * t * (1.0 - t) * (1.0 - t)


func _zone() -> float:
	return minf(zone_depth, ShoreField.MAX_DEPTH)
