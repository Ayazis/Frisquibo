class_name WaterTextures
extends RefCounted
## Shared, seamless noise textures for water shaders: two detail normal maps, foam, foam lace, caustics
## and the smooth field that wind gusts follow.
## Generated once (in Godot's noise thread) and reused by every water material.

const SIZE := 512
const NORMAL_BUMP := 6.0
const LACE_SEED := 606
## Foam textures (world/water/foam_scans/SOURCE.txt), packed: R, G = normal x, y (OpenGL), B = height.
## Three per foam density; foam_surface.gdshaderinc picks between them across the sea.
const FOAM_TEXTURES: Dictionary[StringName, Texture2D] = {
	&"water_foam_dense_a": preload("res://world/water/foam_scans/tex_foam_photo_engstrom_aerial.png"),
	&"water_foam_dense_b": preload("res://world/water/foam_scans/tex_foam_photo_morning_seafoam.png"),
	&"water_foam_dense_c": preload("res://world/water/foam_scans/tex_foam_photo_gischt_stiller.png"),
	&"water_foam_middle_a": preload("res://world/water/foam_scans/tex_foam_photo_foamy_ocean.png"),
	&"water_foam_middle_b": preload("res://world/water/foam_scans/tex_foam_photo_anna_popovic.png"),
	&"water_foam_middle_c": preload("res://world/water/foam_scans/tex_foam_scan_003.png"),
	&"water_foam_sparse_a": preload("res://world/water/foam_scans/tex_foam_photo_croatia_pasman.png"),
	&"water_foam_sparse_b": preload("res://world/water/foam_scans/tex_foam_photo_dench_dark_whitecap.png"),
	&"water_foam_sparse_c": preload("res://world/water/foam_scans/tex_foam_scan_002.png"),
	&"water_foam_specks": preload("res://world/water/foam_scans/tex_foam_synth_spatter.png"),
}

static var _normal_a: NoiseTexture2D
static var _normal_b: NoiseTexture2D
static var _foam: NoiseTexture2D
static var _caustics: NoiseTexture2D
static var _lace: NoiseTexture2D
static var _gusts: NoiseTexture2D


static func apply(mat: ShaderMaterial) -> void:
	if _normal_a == null:
		_build()
	mat.set_shader_parameter("normal_map_a", _normal_a)
	mat.set_shader_parameter("normal_map_b", _normal_b)
	mat.set_shader_parameter("foam_texture", _foam)
	mat.set_shader_parameter("caustic_texture", _caustics)
	mat.set_shader_parameter("gust_texture", _gusts)


## Only the two detail normal maps (normal_map_a, normal_map_b).
static func apply_detail_normals(mat: ShaderMaterial) -> void:
	if _normal_a == null:
		_build()
	mat.set_shader_parameter("normal_map_a", _normal_a)
	mat.set_shader_parameter("normal_map_b", _normal_b)


static func foam() -> NoiseTexture2D:
	if _foam == null:
		_build()
	return _foam


## Distance to the nearest cell edge (cellular F2 - F1, 0 on the edges): the network foam ages into
## (foam_lace.gdshaderinc).
static func lace() -> NoiseTexture2D:
	if _lace == null:
		_build()
	return _lace


## Sets the global shader parameters every foam shader reads (foam_surface.gdshaderinc).
static func apply_foam_globals() -> void:
	if _lace == null:
		_build()
	RenderingServer.global_shader_parameter_set(&"water_foam_lace", _lace)
	RenderingServer.global_shader_parameter_set(&"water_foam_noise", _foam)
	for param: StringName in FOAM_TEXTURES:
		RenderingServer.global_shader_parameter_set(param, FOAM_TEXTURES[param])


static func caustics() -> NoiseTexture2D:
	if _caustics == null:
		_build()
	return _caustics


static func gusts() -> NoiseTexture2D:
	if _gusts == null:
		_build()
	return _gusts


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
	var lace_cells := cells.duplicate() as FastNoiseLite
	lace_cells.seed = LACE_SEED
	_lace = _noise_texture(lace_cells, false)
	# Few octaves: gusts are broad patches, not detail.
	_gusts = _noise_texture(_simplex(505, 0.006, 2), false)


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
