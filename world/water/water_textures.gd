class_name WaterTextures
extends RefCounted
## Shared, seamless noise textures for water shaders: two detail normal maps, foam and caustics.
## Generated once (in Godot's noise thread) and reused by every water material.

const SIZE := 512
const NORMAL_BUMP := 6.0

static var _normal_a: NoiseTexture2D
static var _normal_b: NoiseTexture2D
static var _foam: NoiseTexture2D
static var _caustics: NoiseTexture2D


static func apply(mat: ShaderMaterial) -> void:
	if _normal_a == null:
		_build()
	mat.set_shader_parameter("normal_map_a", _normal_a)
	mat.set_shader_parameter("normal_map_b", _normal_b)
	mat.set_shader_parameter("foam_texture", _foam)
	mat.set_shader_parameter("caustic_texture", _caustics)


static func foam() -> NoiseTexture2D:
	if _foam == null:
		_build()
	return _foam


static func caustics() -> NoiseTexture2D:
	if _caustics == null:
		_build()
	return _caustics


static func _build() -> void:
	_normal_a = _noise_texture(_simplex(101, 0.012, 5), true)
	_normal_b = _noise_texture(_simplex(202, 0.02, 4), true)
	var foam_noise := _simplex(303, 0.03, 4)
	foam_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_foam = _noise_texture(foam_noise, false)
	var cells := FastNoiseLite.new()
	cells.seed = 404
	cells.noise_type = FastNoiseLite.TYPE_CELLULAR
	cells.frequency = 0.03
	cells.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	cells.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	cells.fractal_type = FastNoiseLite.FRACTAL_NONE
	_caustics = _noise_texture(cells, false)
	_caustics.invert = true


static func _simplex(seed_value: int, frequency: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = frequency
	n.fractal_octaves = octaves
	return n


static func _noise_texture(noise: FastNoiseLite, as_normal: bool) -> NoiseTexture2D:
	var t := NoiseTexture2D.new()
	t.width = SIZE
	t.height = SIZE
	t.seamless = true
	t.generate_mipmaps = true
	t.noise = noise
	t.as_normal_map = as_normal
	if as_normal:
		t.bump_strength = NORMAL_BUMP
	return t
