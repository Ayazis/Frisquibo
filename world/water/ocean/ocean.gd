class_name Ocean
extends Node3D
## Open sea with a GPU FFT wave simulation (desktop). Builds the camera-following surface, planar
## reflection and a CPU height field for floating objects.
## Web / Compatibility renderer: no compute shaders, so it falls back to the Gerstner `Sea`.
## `spectrum` and the exported values are the authored sea state; `rules` (OceanRuleSet) change them
## at runtime ("if local_depth < 1 and wind_speed > 12 then local_foam += 5").

const SURFACE_SHADER := preload("res://world/water/ocean/ocean.gdshader")
const DEFAULT_QUALITY := preload("res://data/quality/ocean_high.tres")
const DEFAULT_SPECTRUM := preload("res://world/water/ocean/presets/fresh_breeze.tres")
const SEABED_RESOLUTION := 256
## The mesh moves with the camera in steps of this size so vertices don't swim over the waves.
const FOLLOW_SNAP := 0.5
## How fast the measured wave amplitude follows the simulation (1/s); avoids pumping at the shore.
const AMPLITUDE_RESPONSE := 1.5
## Used until the first GPU readback has measured the real waves.
const DEFAULT_AMPLITUDE := 1.0
## Matches the 1e4 that seabed_depth() in ocean.gdshader returns outside the baked seabed.
const OPEN_SEA_DEPTH := 1.0e4

@export var spectrum: OceanSpectrum
@export var quality: OceanQuality
@export var level := 0.0
@export var planar_reflection := true
@export var min_shore_wave: float = 0.12
## Depth-limited waves: crest height <= breaker_ratio * water depth. Real waves break at H = 0.78 d,
## a crest of 0.39 d.
@export_range(0.05, 2.0) var breaker_ratio := 0.39
## Extra water level at the waterline from breaking waves, as a fraction of the crest height
## (real set-up is about 0.2 of the breaking wave height). Higher seas reach further up the beach.
@export_range(0.0, 2.0) var wave_setup := 0.3
@export var rules: OceanRuleSet

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
## The sea state after the rules: spectrum and ocean values actually simulated and drawn.
var _effective: OceanSpectrum
var _values: Dictionary[StringName, float] = {}
var _local := OceanLocalRules.new()
var _limits: Dictionary[StringName, Vector2] = {}
var _problems := PackedStringArray()


func _ready() -> void:
	if spectrum == null:
		spectrum = DEFAULT_SPECTRUM
	if quality == null:
		quality = DEFAULT_QUALITY
	_limits = OceanRuleEngine.limits(spectrum)
	_limits.merge(OceanRuleEngine.limits(self))
	_effective = spectrum.duplicate() as OceanSpectrum
	# Web / Compatibility: no RenderingDevice, so no compute shaders. Cheaper Gerstner fallback.
	if not OceanSimulation.is_supported():
		_fallback = Sea.new()
		_fallback.level = level
		_fallback.planar_reflection = planar_reflection
		add_child(_fallback)
		_update_rules(true)
		return
	_simulation = OceanSimulation.new(quality.cascade_count, _effective)
	_height_field = OceanHeightField.new(OceanSimulation.MAP_SIZE, _simulation.tile_lengths)
	material = ShaderMaterial.new()
	material.shader = SURFACE_SHADER
	material.set_shader_parameter("wave_amplitude", _amplitude)
	material.set_shader_parameter("displacement_maps", _simulation.displacement)
	material.set_shader_parameter("slope_maps", _simulation.slope)
	material.set_shader_parameter("moment_maps", _simulation.moments)
	_apply_cascades()
	material.set_shader_parameter("map_size", float(OceanSimulation.MAP_SIZE))
	material.set_shader_parameter("mesh_angular_step", TAU / quality.radial_segments)
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
	_update_rules(true)


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
	_update_rules(true)


## Moves the authored rest level of the sea (tide, flooding). Shore damping follows the new depth.
func set_level(value: float) -> void:
	level = value
	_update_rules(true)


func set_breaker_ratio(value: float) -> void:
	breaker_ratio = value
	_update_rules(true)


func set_wave_setup(value: float) -> void:
	wave_setup = value
	_update_rules(true)


func set_rules(value: OceanRuleSet) -> void:
	rules = value
	_update_rules(true)


## Current value of a parameter after the rules (e.g. &"wind_speed", &"level", &"wave_height").
func effective_value(parameter: StringName) -> float:
	var value: float = _values.get(parameter, NAN)
	return value


## Measured significant wave height of the open sea (twice the typical crest height), in metres.
func wave_height() -> float:
	return 2.0 * _amplitude


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
	var rest_level := _level() + _local_lift(xz)
	if _height_field == null or not _height_field.is_ready():
		return rest_level
	return rest_level + _height_field.height_at(xz)


func _process(delta: float) -> void:
	_time += delta
	if _fallback != null:
		_fallback.material.set_shader_parameter("wave_time", _time)
	if _simulation == null:
		_update_rules(false)
		return
	if _height_field.is_ready():
		_amplitude = lerpf(_amplitude, _height_field.crest_amplitude(), 1.0 - exp(-AMPLITUDE_RESPONSE * delta))
		material.set_shader_parameter("wave_amplitude", _amplitude)
	_update_rules(false)
	_simulation.update(_time, delta)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var p := cam.global_position
		_surface.global_position = Vector3(snappedf(p.x, FOLLOW_SNAP), _level(), snappedf(p.z, FOLLOW_SNAP))
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


## Re-applies the rules to the authored state. Without `force`, only pushes what actually changed,
## so rules that read the measured wave height can run every frame.
func _update_rules(force: bool) -> void:
	if _effective == null or (not force and rules == null):
		return
	var inputs := OceanRuleEngine.parameters(spectrum)
	inputs.merge(OceanRuleEngine.parameters(self))
	inputs[OceanRuleEngine.WAVE_HEIGHT] = wave_height()
	var result := OceanRuleEngine.evaluate(rules, inputs, _limits)
	if result.problems != _problems:
		_problems = result.problems
		for problem in _problems:
			push_warning("Ocean rules: " + problem)
	var local_changed := (result.local.depth_ranges != _local.depth_ranges
			or result.local.effects != _local.effects)
	_local = result.local
	if not force and result.values == _values and not local_changed:
		return
	var spectrum_changed := force
	if force:
		_effective = spectrum.duplicate() as OceanSpectrum
	for key: StringName in result.values:
		if key in _effective and _effective.get(key) != result.values[key]:
			_effective.set(key, result.values[key])
			spectrum_changed = true
	_values = result.values
	_apply_state(spectrum_changed)


func _apply_state(spectrum_changed: bool) -> void:
	var sea_level := _level()
	if _fallback != null:
		_fallback.level = sea_level
		_fallback.position.y = sea_level
		if spectrum_changed:
			_apply_fallback_spectrum()
		return
	if _simulation == null:
		return
	if spectrum_changed and _simulation.set_spectrum(_effective):
		_height_field = OceanHeightField.new(OceanSimulation.MAP_SIZE, _simulation.tile_lengths)
		_height_field.damping_at = _damping_at
		_apply_cascades()
	if _height_field.damping_at.is_null():
		_height_field.damping_at = _damping_at
	material.set_shader_parameter("sea_level", sea_level)
	material.set_shader_parameter("breaker_ratio", _value(&"breaker_ratio"))
	material.set_shader_parameter("min_shore_wave", _value(&"min_shore_wave"))
	material.set_shader_parameter("wave_setup", _value(&"wave_setup"))
	material.set_shader_parameter("local_rule_count", _local.count())
	if _local.count() > 0:
		material.set_shader_parameter("local_rule_depth", _local.depth_ranges)
		material.set_shader_parameter("local_rule_effect", _local.effects)
	if _reflection != null:
		_reflection.set_plane_height(sea_level)


func _value(parameter: StringName) -> float:
	if _values.has(parameter):
		return _values[parameter]
	var authored: float = get(parameter)
	return authored


func _level() -> float:
	return _value(&"level")


## Seabed depth below the sea level at `p`; a large value outside the baked seabed (open sea).
func _depth_at(p: Vector2) -> float:
	if _seabed == null or not _seabed_area.has_point(p):
		return OPEN_SEA_DEPTH
	var uv: Vector2 = (p - _seabed_area.position) / _seabed_area.size * SEABED_RESOLUTION - Vector2(0.5, 0.5)
	var x: int = floori(uv.x)
	var y: int = floori(uv.y)
	var x0: int = clampi(x, 0, SEABED_RESOLUTION - 1)
	var x1: int = clampi(x + 1, 0, SEABED_RESOLUTION - 1)
	var y0: int = clampi(y, 0, SEABED_RESOLUTION - 1)
	var y1: int = clampi(y + 1, 0, SEABED_RESOLUTION - 1)
	var a: float = lerpf(_seabed.get_pixel(x0, y0).r, _seabed.get_pixel(x1, y0).r, uv.x - x)
	var b: float = lerpf(_seabed.get_pixel(x0, y1).r, _seabed.get_pixel(x1, y1).r, uv.x - x)
	return _level() - lerpf(a, b, uv.y - y)


## Extra water level at `p` from wave set-up and local rules. Same as the vertex shader.
func _local_lift(p: Vector2) -> float:
	var depth := _depth_at(p)
	return _setup_lift(depth) + _local.evaluate(depth).z


func _setup_lift(depth: float) -> float:
	if depth >= OPEN_SEA_DEPTH:
		return 0.0
	var zone := _amplitude / maxf(_value(&"breaker_ratio"), 0.01)
	return _value(&"wave_setup") * _amplitude * (1.0 - smoothstep(0.0, zone, depth))


## Same rule as shore_damping() in ocean.gdshader, with local rules and set-up.
func _damping_at(rest: Vector2) -> float:
	var raw := _depth_at(rest)
	if raw >= OPEN_SEA_DEPTH and _local.count() == 0:
		return 1.0
	var rule := _local.evaluate(raw)
	var depth := maxf(raw + _setup_lift(raw) + rule.z, 0.0)
	var limited := _value(&"breaker_ratio") * depth / maxf(_amplitude, 0.01)
	var shore := clampf(maxf(limited, _value(&"min_shore_wave") * smoothstep(0.0, 0.5, depth)), 0.0, 1.0)
	return shore * rule.y


func _apply_fallback_spectrum() -> void:
	# Approximate sea states on Compatibility; this is not an FFT spectrum reconstruction.
	var sea := _effective
	var wind_ratio: float = sea.wind_speed / DEFAULT_SPECTRUM.wind_speed
	_fallback.material.set_shader_parameter("wave_amplitude", 0.12 * wind_ratio * wind_ratio * sea.height_scale)
	_fallback.material.set_shader_parameter("wave_length", 9.0 * maxf(wind_ratio, 0.5) * sea.wavelength_scale)
	_fallback.material.set_shader_parameter("wave_steepness", minf(sea.choppiness, 0.95))
	var direction: float = deg_to_rad(sea.wind_direction)
	_fallback.material.set_shader_parameter("wind_direction", Vector2(cos(direction), sin(direction)))
