class_name Ocean
extends Node3D
## Open sea with a GPU FFT wave simulation (desktop). Builds the camera-following surface, planar
## reflection and a CPU height field for floating objects.
## Web / Compatibility renderer: no compute shaders, so it falls back to the Gerstner `Sea`.

const SURFACE_SHADER := preload("res://world/water/ocean/ocean.gdshader")
const DEFAULT_QUALITY := preload("res://data/quality/ocean_high.tres")
const DEFAULT_SPECTRUM := preload("res://world/water/ocean/presets/fresh_breeze.tres")
const SEABED_RESOLUTION := 256
## The mesh moves with the camera in steps of this size so vertices don't swim over the waves.
const FOLLOW_SNAP := 0.5
## Depth-limited waves: crest height <= BREAKER_RATIO * water depth (waves break at H = 0.78 d).
const BREAKER_RATIO := 0.39
## How fast the measured wave amplitude follows the simulation (1/s); avoids pumping at the shore.
const AMPLITUDE_RESPONSE := 1.5
## Used until the first GPU readback has measured the real waves.
const DEFAULT_AMPLITUDE := 1.0

@export var spectrum: OceanSpectrum
@export var quality: OceanQuality
@export var level := 0.0
@export var planar_reflection := true
@export var min_shore_wave: float = 0.12

var material: ShaderMaterial
var _simulation: OceanSimulation
var _surface: MeshInstance3D
var _height_field: OceanHeightField
var _fallback: Sea
var _seabed: Image
var _seabed_area: Rect2
var _time := 0.0
var _frames_since_readback := 0
var _reflection: PlanarReflection
var _amplitude := DEFAULT_AMPLITUDE


func _ready() -> void:
	if spectrum == null:
		spectrum = DEFAULT_SPECTRUM
	if quality == null:
		quality = DEFAULT_QUALITY
	# Web / Compatibility: no RenderingDevice, so no compute shaders. Cheaper Gerstner fallback.
	if not OceanSimulation.is_supported():
		_fallback = Sea.new()
		_fallback.level = level
		_fallback.planar_reflection = planar_reflection
		add_child(_fallback)
		_apply_fallback_spectrum()
		return
	_simulation = OceanSimulation.new(quality.cascade_count, spectrum)
	_height_field = OceanHeightField.new(OceanSimulation.MAP_SIZE, _simulation.tile_lengths)
	material = ShaderMaterial.new()
	material.shader = SURFACE_SHADER
	material.set_shader_parameter("breaker_ratio", BREAKER_RATIO)
	material.set_shader_parameter("wave_amplitude", _amplitude)
	material.set_shader_parameter("min_shore_wave", min_shore_wave)
	material.set_shader_parameter("displacement_maps", _simulation.displacement)
	material.set_shader_parameter("slope_maps", _simulation.slope)
	material.set_shader_parameter("moment_maps", _simulation.moments)
	_apply_cascades()
	material.set_shader_parameter("map_size", float(OceanSimulation.MAP_SIZE))
	material.set_shader_parameter("mesh_angular_step", TAU / quality.radial_segments)
	material.set_shader_parameter("sea_level", level)
	material.set_shader_parameter("foam_texture", WaterTextures.foam())
	material.set_shader_parameter("caustic_texture", WaterTextures.caustics())
	_surface = MeshInstance3D.new()
	_surface.mesh = OceanSurfaceMesh.build(quality.radial_segments, quality.inner_radius, quality.far_radius)
	_surface.material_override = material
	_surface.layers = PlanarReflection.water_layer_mask()
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_surface)
	if planar_reflection:
		_reflection = PlanarReflection.new()
		_reflection.plane_height = level
		_reflection.resolution_scale = quality.reflection_resolution_scale
		add_child(_reflection)


func _exit_tree() -> void:
	if _simulation != null:
		# Release bindings before scheduling GPU destruction, after child meshes leave the tree.
		_surface.material_override = null
		material.set_shader_parameter("displacement_maps", null)
		material.set_shader_parameter("slope_maps", null)
		material.set_shader_parameter("moment_maps", null)
		# Queued on the render thread right away: a deferred call would never run when the game quits.
		_simulation.free_resources()
		_simulation = null


func set_spectrum(value: OceanSpectrum) -> void:
	spectrum = value
	if _fallback != null:
		_apply_fallback_spectrum()
	if _simulation != null:
		_simulation.set_spectrum(value)
		_height_field = OceanHeightField.new(OceanSimulation.MAP_SIZE, _simulation.tile_lengths)
		_height_field.damping_at = _damping_at
		_apply_cascades()


## Moves the rest level of the sea (tide, flooding). Shore damping follows the new depth.
func set_level(value: float) -> void:
	level = value
	if _fallback != null:
		_fallback.level = value
		_fallback.position.y = value
	if material != null:
		material.set_shader_parameter("sea_level", value)
	if _reflection != null:
		_reflection.set_plane_height(value)


## Bakes the ground height under the sea so waves calm down and surf forms in shallow water.
## `height` takes (x: float, z: float) and returns the ground height.
func set_seabed(height: Callable, area: Rect2) -> void:
	if material == null:
		return
	var img := Image.create(SEABED_RESOLUTION, SEABED_RESOLUTION, false, Image.FORMAT_RF)
	for y in range(SEABED_RESOLUTION):
		for x in range(SEABED_RESOLUTION):
			var p := area.position + area.size * Vector2(x + 0.5, y + 0.5) / SEABED_RESOLUTION
			var ground: float = height.call(p.x, p.y)
			img.set_pixel(x, y, Color(ground, 0.0, 0.0))
	_seabed = img
	_seabed_area = area
	_height_field.damping_at = _damping_at
	material.set_shader_parameter("seabed_height", ImageTexture.create_from_image(img))
	material.set_shader_parameter("seabed_rect", Vector4(area.position.x, area.position.y, area.size.x, area.size.y))


## World height of the water surface at `xz` (the rest level until the first GPU readback arrives).
func height_at(xz: Vector2) -> float:
	if _fallback != null:
		return _fallback.height_at(xz, _time)
	if _height_field == null or not _height_field.is_ready():
		return level
	return level + _height_field.height_at(xz)


func _process(delta: float) -> void:
	_time += delta
	if _fallback != null:
		_fallback.material.set_shader_parameter("wave_time", _time)
	if _simulation == null:
		return
	_simulation.update(_time, delta)
	if _height_field.is_ready():
		_amplitude = lerpf(_amplitude, _height_field.crest_amplitude(), 1.0 - exp(-AMPLITUDE_RESPONSE * delta))
		material.set_shader_parameter("wave_amplitude", _amplitude)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var p := cam.global_position
		_surface.global_position = Vector3(snappedf(p.x, FOLLOW_SNAP), level, snappedf(p.z, FOLLOW_SNAP))
	if quality.readback_interval > 0:
		_frames_since_readback += 1
		if _frames_since_readback >= quality.readback_interval:
			_frames_since_readback = 0
			for c in range(_simulation.cascade_count):
				var field := _height_field
				var cascade := c
				_simulation.request_displacement(c, func(bytes: PackedByteArray) -> void: field.set_cascade.call_deferred(cascade, bytes))


func _apply_cascades() -> void:
	var tiles := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
	for c in range(_simulation.cascade_count):
		tiles[c] = _simulation.tile_lengths[c]
	material.set_shader_parameter("tile_lengths", tiles)
	material.set_shader_parameter("cascade_count", _simulation.cascade_count)


func _damping_at(rest: Vector2) -> float:
	if _seabed == null or not _seabed_area.has_point(rest):
		return 1.0
	var uv: Vector2 = (rest - _seabed_area.position) / _seabed_area.size * SEABED_RESOLUTION - Vector2(0.5, 0.5)
	var x: int = floori(uv.x)
	var y: int = floori(uv.y)
	var x0: int = clampi(x, 0, SEABED_RESOLUTION - 1)
	var x1: int = clampi(x + 1, 0, SEABED_RESOLUTION - 1)
	var y0: int = clampi(y, 0, SEABED_RESOLUTION - 1)
	var y1: int = clampi(y + 1, 0, SEABED_RESOLUTION - 1)
	var a: float = lerpf(_seabed.get_pixel(x0, y0).r, _seabed.get_pixel(x1, y0).r, uv.x - x)
	var b: float = lerpf(_seabed.get_pixel(x0, y1).r, _seabed.get_pixel(x1, y1).r, uv.x - x)
	# Same rule as shore_damping() in ocean.gdshader.
	var depth := maxf(level - lerpf(a, b, uv.y - y), 0.0)
	var limited := BREAKER_RATIO * depth / maxf(_amplitude, 0.01)
	return clampf(maxf(limited, min_shore_wave * smoothstep(0.0, 0.5, depth)), 0.0, 1.0)


func _apply_fallback_spectrum() -> void:
	# Approximate sea states on Compatibility; this is not an FFT spectrum reconstruction.
	var wind_ratio: float = spectrum.wind_speed / DEFAULT_SPECTRUM.wind_speed
	_fallback.material.set_shader_parameter("wave_amplitude", 0.12 * wind_ratio * wind_ratio * spectrum.height_scale)
	_fallback.material.set_shader_parameter("wave_length", 9.0 * maxf(wind_ratio, 0.5))
	_fallback.material.set_shader_parameter("wave_steepness", minf(spectrum.choppiness, 0.95))
	var direction: float = deg_to_rad(spectrum.wind_direction)
	_fallback.material.set_shader_parameter("wind_direction", Vector2(cos(direction), sin(direction)))
