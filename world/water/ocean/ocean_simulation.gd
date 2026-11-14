class_name OceanSimulation
extends RefCounted
## Runs the FFT ocean on the GPU with compute shaders (desktop renderers only) and exposes the result
## as three mipmapped texture arrays, one layer per cascade. See compute/*.glsl for the maths.
## Uses the main RenderingDevice so the textures can be sampled directly by the surface shader.

## Must match N in the compute shaders.
const MAP_SIZE := 256
const MAX_CASCADES := 4
const MIP_LEVELS := 9
## Wave frequencies are snapped so the whole sea repeats after this many seconds (time can wrap safely).
const REPEAT_PERIOD := 600.0
## Cascade bands meet at this many wavelengths of the next cascade's tile.
const BAND_SPLIT := 6.0
const GROUP_2D := 16
const GROUP_MIP := 8
const BYTES_PER_TEXEL := 8
const SIGNALS_PER_TEXEL := 2
const VEC4_BYTES := 16

const SPECTRUM_SHADER := "res://world/water/ocean/compute/ocean_spectrum.glsl"
const EVOLVE_SHADER := "res://world/water/ocean/compute/ocean_evolve.glsl"
const FFT_SHADER := "res://world/water/ocean/compute/ocean_fft.glsl"
const UNPACK_SHADER := "res://world/water/ocean/compute/ocean_unpack.glsl"
const MIPMAP_SHADER := "res://world/water/ocean/compute/ocean_mipmap.glsl"

var displacement := Texture2DArrayRD.new()
var slope := Texture2DArrayRD.new()
var moments := Texture2DArrayRD.new()
var cascade_count: int
var tile_lengths := PackedFloat32Array()

var _rd: RenderingDevice
var _gpu_tile_lengths: PackedFloat32Array
var _spectrum: OceanSpectrum
var _spectrum_dirty := true
var _rids: Array[RID] = []
var _shaders: Dictionary[StringName, RID] = {}
var _pipelines: Dictionary[StringName, RID] = {}
var _sets: Dictionary[StringName, RID] = {}
var _mip_sets: Array[RID] = []
var _unpack_sets: Array[RID] = []
var _textures: Array[RID] = []


static func is_supported() -> bool:
	return RenderingServer.get_rendering_device() != null


func _init(cascades: int, spectrum: OceanSpectrum) -> void:
	cascade_count = clampi(mini(cascades, spectrum.cascade_tile_lengths.size()), 1, MAX_CASCADES)
	set_spectrum(spectrum)
	RenderingServer.call_on_render_thread(_initialize_gpu)


func _initialize_gpu() -> void:
	_rd = RenderingServer.get_rendering_device()
	for key: StringName in [&"spectrum", &"evolve", &"fft", &"unpack", &"mipmap"]:
		var path: String = {
			&"spectrum": SPECTRUM_SHADER, &"evolve": EVOLVE_SHADER, &"fft": FFT_SHADER,
			&"unpack": UNPACK_SHADER, &"mipmap": MIPMAP_SHADER}[key]
		var file: RDShaderFile = load(path)
		_shaders[key] = _keep(_rd.shader_create_from_spirv(file.get_spirv()))
		_pipelines[key] = _keep(_rd.compute_pipeline_create(_shaders[key]))
	_create_resources()


func set_spectrum(spectrum: OceanSpectrum) -> void:
	assert(spectrum.cascade_tile_lengths.size() >= cascade_count, "Spectrum needs one tile per active cascade")
	tile_lengths = spectrum.cascade_tile_lengths.slice(0, cascade_count)
	var snapshot: OceanSpectrum = spectrum.duplicate() as OceanSpectrum
	RenderingServer.call_on_render_thread(_set_spectrum_gpu.bind(snapshot))


func _set_spectrum_gpu(spectrum: OceanSpectrum) -> void:
	_spectrum = spectrum
	_gpu_tile_lengths = spectrum.cascade_tile_lengths.slice(0, cascade_count)
	_spectrum_dirty = true


## Simulates the sea at `time` seconds. `delta` drives foam decay.
func update(time: float, delta: float) -> void:
	RenderingServer.call_on_render_thread(_update_gpu.bind(time, delta))


func _update_gpu(time: float, delta: float) -> void:
	var list := _rd.compute_list_begin()
	var groups := MAP_SIZE / GROUP_2D
	if _spectrum_dirty:
		_spectrum_dirty = false
		for c in range(cascade_count):
			_dispatch(list, &"spectrum", _sets[&"spectrum"], _spectrum_push(c), Vector3i(groups, groups, 1))
		_rd.compute_list_add_barrier(list)
	var tiles := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	for c in range(cascade_count):
		tiles[c] = _physical_tile(c)
	# Stretched waves are longer, so they travel slower than the stretch alone would show: c ~ sqrt(length).
	var wave_time := time / sqrt(_spectrum.wavelength_scale)
	var evolve := tiles.to_byte_array()
	evolve.append_array(PackedFloat32Array([fmod(wave_time, REPEAT_PERIOD), _spectrum.depth, REPEAT_PERIOD, 0.0]).to_byte_array())
	_dispatch(list, &"evolve", _sets[&"evolve"], evolve, Vector3i(groups, groups, cascade_count))
	_rd.compute_list_add_barrier(list)
	for vertical: int in [0, 1]:
		var fft := PackedInt32Array([vertical, 0, 0, 0]).to_byte_array()
		_dispatch(list, &"fft", _sets[&"fft"], fft, Vector3i(MAP_SIZE, cascade_count, 1))
		_rd.compute_list_add_barrier(list)
	var decay := exp(-delta / _spectrum.foam_lifetime)
	var unpack := PackedFloat32Array([_spectrum.height_scale, _spectrum.choppiness, _spectrum.foam_threshold,
			_spectrum.foam_gain, decay, 0.0, _spectrum.wavelength_scale, 0.0]).to_byte_array()
	for c in range(cascade_count):
		unpack.encode_float(20, float(c))
		_dispatch(list, &"unpack", _unpack_sets[c], unpack, Vector3i(groups, groups, 1))
	for level in range(1, MIP_LEVELS):
		_rd.compute_list_add_barrier(list)
		var size := MAP_SIZE >> level
		var mip_groups := ceili(float(size) / GROUP_MIP)
		var push := PackedInt32Array([size, 0, 0, 0]).to_byte_array()
		for c in range(cascade_count):
			_dispatch(list, &"mipmap", _mip_sets[c * (MIP_LEVELS - 1) + level - 1], push, Vector3i(mip_groups, mip_groups, 1))
	_rd.compute_list_end()


## Asks for the displacement of one cascade (mip 0 first in the returned bytes, rgba16f per texel).
func request_displacement(cascade: int, callback: Callable) -> void:
	RenderingServer.call_on_render_thread(_request_displacement_gpu.bind(cascade, callback))


func _request_displacement_gpu(cascade: int, callback: Callable) -> void:
	_rd.texture_get_data_async(_textures[0], cascade, callback)


func free_resources() -> void:
	RenderingServer.call_on_render_thread(_free_gpu)


func _free_gpu() -> void:
	displacement.texture_rd_rid = RID()
	slope.texture_rd_rid = RID()
	moments.texture_rd_rid = RID()
	for i in range(_rids.size() - 1, -1, -1):
		if _rids[i].is_valid():
			_rd.free_rid(_rids[i])
	_rids.clear()





func _create_resources() -> void:
	var texel_count := MAP_SIZE * MAP_SIZE * cascade_count
	var spectrum_buffer := _keep(_rd.storage_buffer_create(texel_count * VEC4_BYTES))
	var signal_buffer := _keep(_rd.storage_buffer_create(texel_count * SIGNALS_PER_TEXEL * VEC4_BYTES))
	var format := RDTextureFormat.new()
	format.texture_type = RenderingDevice.TEXTURE_TYPE_2D_ARRAY
	format.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	format.width = MAP_SIZE
	format.height = MAP_SIZE
	format.array_layers = cascade_count
	format.mipmaps = MIP_LEVELS
	format.usage_bits = (RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
			| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT)
	# Zeroed start so the foam accumulation reads defined values on the first frame.
	var zero := PackedByteArray()
	var mip_bytes := 0
	for level in range(MIP_LEVELS):
		mip_bytes += (MAP_SIZE >> level) * (MAP_SIZE >> level) * BYTES_PER_TEXEL
	zero.resize(mip_bytes)
	var layers: Array[PackedByteArray] = []
	for c in range(cascade_count):
		layers.append(zero)
	for i in range(3):
		_textures.append(_keep(_rd.texture_create(format, RDTextureView.new(), layers)))
	displacement.texture_rd_rid = _textures[0]
	slope.texture_rd_rid = _textures[1]
	moments.texture_rd_rid = _textures[2]

	var buffer := RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	var image := RenderingDevice.UNIFORM_TYPE_IMAGE
	_sets[&"spectrum"] = _uniform_set(&"spectrum", [buffer], [spectrum_buffer])
	_sets[&"evolve"] = _uniform_set(&"evolve", [buffer, buffer], [spectrum_buffer, signal_buffer])
	_sets[&"fft"] = _uniform_set(&"fft", [buffer], [signal_buffer])
	# Bind individual 2D layers: the installed engine cannot slice an entire array mip.
	for c in range(cascade_count):
		var previous: Array[RID] = []
		for level in range(MIP_LEVELS):
			var views: Array[RID] = []
			for tex in _textures:
				views.append(_keep(_rd.texture_create_shared_from_slice(RDTextureView.new(), tex, c, level)))
			if level == 0:
				_unpack_sets.append(_uniform_set(&"unpack", [buffer, image, image, image],
						[signal_buffer, views[0], views[1], views[2]]))
			else:
				var rids: Array[RID] = []
				rids.assign(previous + views)
				_mip_sets.append(_uniform_set(&"mipmap", [image, image, image, image, image, image], rids))
			previous = views


func _uniform_set(shader: StringName, types: Array[RenderingDevice.UniformType], rids: Array[RID]) -> RID:
	var uniforms: Array[RDUniform] = []
	for i in range(rids.size()):
		var u := RDUniform.new()
		u.uniform_type = types[i]
		u.binding = i
		u.add_id(rids[i])
		uniforms.append(u)
	return _keep(_rd.uniform_set_create(uniforms, _shaders[shader], 0))


func _dispatch(list: int, pipeline: StringName, uniform_set: RID, push: PackedByteArray, groups: Vector3i) -> void:
	_rd.compute_list_bind_compute_pipeline(list, _pipelines[pipeline])
	_rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	_rd.compute_list_set_push_constant(list, push, push.size())
	_rd.compute_list_dispatch(list, groups.x, groups.y, groups.z)


func _spectrum_push(cascade: int) -> PackedByteArray:
	var tile := _physical_tile(cascade)
	var k_min := 0.0 if cascade == 0 else TAU / tile * BAND_SPLIT
	var k_max := PI * MAP_SIZE / tile
	if cascade < cascade_count - 1:
		k_max = TAU / _physical_tile(cascade + 1) * BAND_SPLIT
	var bytes := PackedFloat32Array([tile, _spectrum.wind_speed, deg_to_rad(_spectrum.wind_direction),
			_spectrum.fetch * 1000.0, _spectrum.depth, _spectrum.swell, _spectrum.spread,
			_spectrum.short_wave_cutoff, k_min, k_max]).to_byte_array()
	bytes.append_array(PackedInt32Array([cascade, _spectrum.seed]).to_byte_array())
	return bytes


## The tile the spectrum is computed for. With a horizontal stretch w, a world tile of length L shows
## the waves of a physical tile L / w, stretched out w times (same heights, longer waves).
func _physical_tile(cascade: int) -> float:
	return _gpu_tile_lengths[cascade] / _spectrum.wavelength_scale


func _keep(rid: RID) -> RID:
	_rids.append(rid)
	return rid
