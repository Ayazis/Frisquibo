class_name OceanHeightField
extends RefCounted
## CPU copy of the ocean displacement for gameplay (buoyancy, splashes, AI). Holds the raw rgba16f
## readback of each cascade and answers "how high is the water at this exact spot". Because the waves
## also move water sideways, the point that ends up above a spot started somewhere else; height_at()
## finds that start point by fixed-point iteration, as the surface shader does implicitly.
## Each readback is unpacked to 32-bit floats once (in C++), so the many lookups per query are plain
## array reads instead of half-float decodes.

const BYTES_PER_TEXEL := 8
const BYTES_PER_CHANNEL := 2
const CHANNELS := 4
const INVERSE_ITERATIONS := 4
## Texel stride for estimating each cascade's height variance (32 x 32 samples of a 256 map).
const VARIANCE_STRIDE := 8

var _map_size: int
var _tile_lengths: PackedFloat32Array
## Per cascade: RGBA floats, row by row (empty until its first readback).
var _data: Array[PackedFloat32Array] = []
var damping_at: Callable
var _variances := PackedFloat32Array()


func _init(map_size: int, tile_lengths: PackedFloat32Array) -> void:
	_map_size = map_size
	_tile_lengths = tile_lengths
	_data.resize(tile_lengths.size())
	_variances.resize(tile_lengths.size())


func set_cascade(cascade: int, bytes: PackedByteArray) -> void:
	var size := _map_size * _map_size * BYTES_PER_TEXEL
	if cascade < 0 or cascade >= _data.size() or bytes.size() < size:
		return
	var image := Image.create_from_data(_map_size, _map_size, false, Image.FORMAT_RGBAH,
			bytes if bytes.size() == size else bytes.slice(0, size))
	image.convert(Image.FORMAT_RGBAF)
	_data[cascade] = image.get_data().to_float32_array()
	_variances[cascade] = _height_variance(bytes)


func is_ready() -> bool:
	for floats in _data:
		if floats.size() < _map_size * _map_size * CHANNELS:
			return false
	return true


## Typical wave crest height above the rest level (half the significant wave height, 2 sigma),
## measured from the simulation itself, before any shore damping.
func crest_amplitude() -> float:
	var total := 0.0
	for v in _variances:
		total += v
	return 2.0 * sqrt(total)


## Summed displacement of all cascades for the water that started at rest position `rest`.
func displacement_at(rest: Vector2) -> Vector3:
	var total := Vector3.ZERO
	for c in range(_data.size()):
		var data := _data[c]
		if data.is_empty():
			continue
		total += _sample(data, rest / _tile_lengths[c] * _map_size)
	if damping_at.is_valid():
		var damping: float = damping_at.call(rest)
		total *= damping
	return total


## Water surface height above the rest level at world position `xz`.
func height_at(xz: Vector2) -> float:
	var rest := xz
	for i in range(INVERSE_ITERATIONS):
		var d := displacement_at(rest)
		rest = xz - Vector2(d.x, d.z)
	return displacement_at(rest).y


## Bilinear sample in texel units, matching the GPU (texel centres at +0.5, wrapping tiles). Written
## out in full: this runs several times per probe of every floating object, each physics frame.
func _sample(data: PackedFloat32Array, texel: Vector2) -> Vector3:
	var p := texel - Vector2(0.5, 0.5)
	var x0 := floori(p.x)
	var y0 := floori(p.y)
	var fx := p.x - x0
	var fy := p.y - y0
	var xa := posmod(x0, _map_size)
	var xb := posmod(x0 + 1, _map_size)
	var row_a := posmod(y0, _map_size) * _map_size
	var row_b := posmod(y0 + 1, _map_size) * _map_size
	var i := (row_a + xa) * CHANNELS
	var t00 := Vector3(data[i], data[i + 1], data[i + 2])
	i = (row_a + xb) * CHANNELS
	var t10 := Vector3(data[i], data[i + 1], data[i + 2])
	i = (row_b + xa) * CHANNELS
	var t01 := Vector3(data[i], data[i + 1], data[i + 2])
	i = (row_b + xb) * CHANNELS
	var t11 := Vector3(data[i], data[i + 1], data[i + 2])
	return t00.lerp(t10, fx).lerp(t01.lerp(t11, fx), fy)


func _height_variance(bytes: PackedByteArray) -> float:
	var sum := 0.0
	var sum_sq := 0.0
	var count := 0
	for y in range(0, _map_size, VARIANCE_STRIDE):
		for x in range(0, _map_size, VARIANCE_STRIDE):
			var h := bytes.decode_half((y * _map_size + x) * BYTES_PER_TEXEL + BYTES_PER_CHANNEL)
			sum += h
			sum_sq += h * h
			count += 1
	var mean := sum / count
	return maxf(sum_sq / count - mean * mean, 0.0)
