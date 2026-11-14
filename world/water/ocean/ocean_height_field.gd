class_name OceanHeightField
extends RefCounted
## CPU copy of the ocean displacement for gameplay (buoyancy, splashes, AI). Holds the raw rgba16f
## readback of each cascade and answers "how high is the water at this exact spot". Because the waves
## also move water sideways, the point that ends up above a spot started somewhere else; height_at()
## finds that start point by fixed-point iteration, as the surface shader does implicitly.

const BYTES_PER_TEXEL := 8
const BYTES_PER_CHANNEL := 2
const INVERSE_ITERATIONS := 4

var _map_size: int
var _tile_lengths: PackedFloat32Array
var _data: Array[PackedByteArray] = []
var damping_at: Callable


func _init(map_size: int, tile_lengths: PackedFloat32Array) -> void:
	_map_size = map_size
	_tile_lengths = tile_lengths
	_data.resize(tile_lengths.size())


func set_cascade(cascade: int, bytes: PackedByteArray) -> void:
	if cascade < 0 or cascade >= _data.size() or bytes.size() < _map_size * _map_size * BYTES_PER_TEXEL:
		return
	_data[cascade] = bytes


func is_ready() -> bool:
	for bytes in _data:
		if bytes.size() < _map_size * _map_size * BYTES_PER_TEXEL:
			return false
	return true


## Summed displacement of all cascades for the water that started at rest position `rest`.
func displacement_at(rest: Vector2) -> Vector3:
	var total := Vector3.ZERO
	for c in range(_data.size()):
		if _data[c].is_empty():
			continue
		total += _sample(c, rest / _tile_lengths[c] * _map_size)
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


## Bilinear sample in texel units, matching the GPU (texel centres at +0.5, wrapping tiles).
func _sample(cascade: int, texel: Vector2) -> Vector3:
	var p := texel - Vector2(0.5, 0.5)
	var x0 := floori(p.x)
	var y0 := floori(p.y)
	var fx := p.x - x0
	var fy := p.y - y0
	var a := _texel(cascade, x0, y0).lerp(_texel(cascade, x0 + 1, y0), fx)
	var b := _texel(cascade, x0, y0 + 1).lerp(_texel(cascade, x0 + 1, y0 + 1), fx)
	return a.lerp(b, fy)


func _texel(cascade: int, x: int, y: int) -> Vector3:
	var bytes := _data[cascade]
	var offset := (posmod(y, _map_size) * _map_size + posmod(x, _map_size)) * BYTES_PER_TEXEL
	return Vector3(bytes.decode_half(offset), bytes.decode_half(offset + BYTES_PER_CHANNEL),
			bytes.decode_half(offset + 2 * BYTES_PER_CHANNEL))
