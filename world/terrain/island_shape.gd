class_name IslandShape
extends RefCounted
## Height field of the demo island: rolling noise hills inland that fall off into the sea near the edges,
## leaving a sandy beach band around sea level.

const SEA_LEVEL := 0.0
## Height above sea level where sand gives way to grass.
const BEACH_TOP := 0.9
const HILL_AMPLITUDE := 4.0
## Inland base height, so the hills sit above the sea.
const INLAND_LIFT := 2.2
const SEABED_DEPTH := -3.5
## Radial distance (0 = centre, 1 = edge of the square) where land starts and stops falling to the seabed.
const SHORE_START := 0.45
const SHORE_END := 0.92
const NOISE_FREQUENCY := 0.02
const NOISE_OCTAVES := 3

var _noise := FastNoiseLite.new()
var _half_size: float


func _init(size: float, seed_value: int) -> void:
	_half_size = size / 2.0
	_noise.seed = seed_value
	_noise.frequency = NOISE_FREQUENCY
	_noise.fractal_octaves = NOISE_OCTAVES


func height(x: float, z: float) -> float:
	var r := Vector2(x, z).length() / _half_size
	var land := 1.0 - smoothstep(SHORE_START, SHORE_END, r)
	var inland := _noise.get_noise_2d(x, z) * HILL_AMPLITUDE + INLAND_LIFT
	return lerpf(SEABED_DEPTH, inland, land)


func is_beach(x: float, z: float) -> bool:
	return height(x, z) < SEA_LEVEL + BEACH_TOP
