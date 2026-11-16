class_name IslandTerrain
extends RefCounted
## Ground height of the demo island and where its water lies. An island in open sea: a wandering
## coastline with a sandy beach all round (BeachProfile: beach face, Dean profile, sandbar, shelf and a
## drop into deep water), hills inland, a pond in the middle above sea level, and a river that runs
## from the pond down to the east coast.

const SEA_LEVEL := 0.0
## Coastline: mean radius and how far it wanders in and out (m), and how many bays it has.
const COAST_RADIUS := 150.0
const COAST_WANDER := 14.0
const COAST_NOISE_FREQUENCY := 1.4
## Lookup table of the coastline radius by angle, so the height function needs no noise for it.
const COAST_SAMPLES := 2048
## Inland: the ground rises this much over INLAND_RISE_DISTANCE beyond the berm, plus rolling hills.
const INLAND_RISE := 3.0
const INLAND_RISE_START := 25.0
const INLAND_RISE_DISTANCE := 70.0
const HILL_AMPLITUDE := 3.0
const HILL_FREQUENCY := 0.018
## Sand below this height above sea level (the ground shader's beach_top), grass above.
const BEACH_TOP := 2.3

## The pond: centre (x, z), radius at its waterline, water level, depth in the middle, and the height
## its rim keeps above the water so it never spills.
const POND_CENTRE := Vector2(-20.0, 8.0)
const POND_RADIUS := 18.0
const POND_LEVEL := 3.2
const POND_DEPTH := 2.4
const POND_RIM := 1.0
## The rim is kept up to this far from the waterline (covering the corners of the pond's water square),
## then blends back into the land over POND_RIM_BLEND.
const POND_RIM_WIDTH := 12.0
const POND_RIM_BLEND := 8.0
const POND_BANK_SLOPE := 0.18

## The river leaves the pond eastwards and meets the sea on the east coast. Its centreline meanders;
## its water level falls from the pond's to just above the sea.
const RIVER_START_X := POND_CENTRE.x + POND_RADIUS + 2.0
const RIVER_MEANDER := 7.0
const RIVER_MEANDER_FREQUENCY := 0.045
## Water half width at the surface, channel bottom half width, and where the banks reach full height.
const RIVER_HALF_WIDTH := 4.5
const RIVER_CHANNEL_HALF_WIDTH := 2.5
const RIVER_BANK_DISTANCE := 7.5
const RIVER_DEPTH := 1.4
const RIVER_BANK_HEIGHT := 1.2
## Beyond the banks the corridor rises gently into the land.
const RIVER_VALLEY_SLOPE := 0.25
const RIVER_MOUTH_LEVEL := 0.08
## Smoothing (m) where the pond and river carve into the land.
const CARVE_SMOOTHING := 1.2

var beach := BeachProfile.new(11)
var _hills := FastNoiseLite.new()
var _coast := PackedFloat32Array()
var _river_end_x: float


func _init() -> void:
	beach.dean_a = 0.1
	beach.beach_slope = 0.07
	beach.berm_height = 2.0
	beach.bar_distance = 55.0
	beach.bar_height = 0.7
	beach.bar_width = 14.0
	beach.shelf_start = 220.0
	beach.shelf_slope = 0.04
	beach.drop_start = 450.0
	beach.drop_width = 250.0
	beach.drop_depth = 100.0
	_hills.seed = 3
	_hills.frequency = HILL_FREQUENCY
	_hills.fractal_octaves = 3
	var coast_noise := FastNoiseLite.new()
	coast_noise.seed = 19
	coast_noise.frequency = 1.0
	coast_noise.fractal_octaves = 3
	_coast.resize(COAST_SAMPLES)
	for i in range(COAST_SAMPLES):
		# Sampled around a circle, so the coastline closes on itself without a seam.
		var a := TAU * i / COAST_SAMPLES
		var n := coast_noise.get_noise_2d(cos(a) * COAST_NOISE_FREQUENCY, sin(a) * COAST_NOISE_FREQUENCY)
		_coast[i] = COAST_RADIUS + n * COAST_WANDER
	_river_end_x = _coast_x_at(river_centre(COAST_RADIUS)) + 2.0


## Distance from the island centre to the coastline in the direction of `angle` (radians).
func coast_radius(angle: float) -> float:
	var f := fposmod(angle, TAU) / TAU * COAST_SAMPLES
	var i := floori(f)
	return lerpf(_coast[i % COAST_SAMPLES], _coast[(i + 1) % COAST_SAMPLES], f - i)


## Ground height at world (x, z).
func height(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var offshore := p.length() - coast_radius(p.angle())
	var h := beach.height(offshore, x, z)
	if offshore > 0.0:
		return _carve_river(h, x, z, offshore)
	var inland := -offshore
	h += INLAND_RISE * smoothstep(INLAND_RISE_START, INLAND_RISE_START + INLAND_RISE_DISTANCE, inland)
	h += _hills.get_noise_2d(x, z) * HILL_AMPLITUDE * smoothstep(INLAND_RISE_START, INLAND_RISE_START + INLAND_RISE_DISTANCE, inland)
	h = _carve_pond(h, p)
	return _carve_river(h, x, z, offshore)


## River centreline z at x.
func river_centre(x: float) -> float:
	return POND_CENTRE.y + sin((x - RIVER_START_X) * RIVER_MEANDER_FREQUENCY) * RIVER_MEANDER


## River water level at x: the pond's level where it leaves the pond, falling evenly to the mouth.
func river_level(x: float) -> float:
	var t := clampf((x - RIVER_START_X) / (_river_end_x - RIVER_START_X), 0.0, 1.0)
	return lerpf(POND_LEVEL, SEA_LEVEL + RIVER_MOUTH_LEVEL, t)


## Where the river surface ends, at the beach on the east coast.
func river_end_x() -> float:
	return _river_end_x


func is_in_pond(p: Vector2) -> bool:
	return p.distance_to(POND_CENTRE) < POND_RADIUS


func is_in_river(p: Vector2) -> bool:
	return p.x >= RIVER_START_X and p.x <= _river_end_x and absf(p.y - river_centre(p.x)) < RIVER_HALF_WIDTH


func _carve_pond(h: float, p: Vector2) -> float:
	var r := p.distance_to(POND_CENTRE)
	# Keep a rim above the water, then dig the bowl: deepest in the middle, banks rising outside.
	var rim := POND_LEVEL + POND_RIM
	var rim_weight := 1.0 - smoothstep(POND_RADIUS + POND_RIM_WIDTH, POND_RADIUS + POND_RIM_WIDTH + POND_RIM_BLEND, r)
	h = lerpf(h, maxf(h, rim), rim_weight)
	var bowl: float
	if r < POND_RADIUS:
		var t := r / POND_RADIUS
		bowl = POND_LEVEL - POND_DEPTH * (1.0 - t * t)
	else:
		bowl = POND_LEVEL + (r - POND_RADIUS) * POND_BANK_SLOPE
	return _smooth_min(h, bowl, CARVE_SMOOTHING)


func _carve_river(h: float, x: float, z: float, offshore: float) -> float:
	if x < RIVER_START_X - RIVER_BANK_DISTANCE or x > _river_end_x + RIVER_BANK_DISTANCE * 4.0:
		return h
	var level := river_level(x)
	var d := absf(z - river_centre(x))
	# Banks: on land, keep the ground at least bank height above the water beside the channel.
	var bank := level + RIVER_BANK_HEIGHT
	var on_land := 1.0 - smoothstep(-10.0, 0.0, offshore)
	var beside := 1.0 - smoothstep(RIVER_BANK_DISTANCE, RIVER_BANK_DISTANCE * 2.0, d)
	h = lerpf(h, maxf(h, bank), on_land * beside)
	var channel: float
	if d < RIVER_BANK_DISTANCE:
		channel = level + lerpf(-RIVER_DEPTH, RIVER_BANK_HEIGHT, smoothstep(RIVER_CHANNEL_HALF_WIDTH, RIVER_BANK_DISTANCE, d))
	else:
		channel = bank + (d - RIVER_BANK_DISTANCE) * RIVER_VALLEY_SLOPE
	# The channel starts at the pond's edge.
	var started := smoothstep(RIVER_START_X - RIVER_BANK_DISTANCE, RIVER_START_X - 2.0, x)
	return lerpf(h, _smooth_min(h, channel, CARVE_SMOOTHING), started)


## Smooth minimum (polynomial, blending over k metres): carved shapes meet the land without a crease.
static func _smooth_min(a: float, b: float, k: float) -> float:
	var t := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, t) - k * t * (1.0 - t)


## x of the east coastline at row z.
func _coast_x_at(z: float) -> float:
	var x := COAST_RADIUS
	for i in range(4):
		x = sqrt(maxf(coast_radius(Vector2(x, z).angle()) ** 2 - z * z, 0.0))
	return x
