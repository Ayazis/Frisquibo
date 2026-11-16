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
const DEFAULT_SEABED_RESOLUTION := 256
## The mesh moves with the camera in steps of this size so vertices don't swim over the waves.
const FOLLOW_SNAP := 0.5
## How fast the measured wave amplitude follows the simulation (1/s); avoids pumping at the shore.
const AMPLITUDE_RESPONSE := 1.5
## Used until the first GPU readback has measured the real waves.
const DEFAULT_AMPLITUDE := 1.0
## Matches the 1e4 that seabed_depth() in ocean.gdshader returns outside the baked seabed.
const OPEN_SEA_DEPTH := 1.0e4
## Group names for tunables declared outside an export group.
const WAVES_GROUP := "Waves"
const SEA_GROUP := "Sea"
const LOOK_GROUP := "Look"
## The only values the Gerstner fallback (web / Compatibility) reacts to.
const FALLBACK_PARAMETERS: Array[StringName] = [&"wind_speed", &"wind_direction", &"swell_height",
		&"swell_period", &"swell_direction", &"height_scale", &"wavelength_scale", &"choppiness", &"level"]
## Gerstner fallback: wave amplitude and length it gives the default sea (DEFAULT_SPECTRUM's wind sea).
const FALLBACK_AMPLITUDE := 0.12
const FALLBACK_WAVELENGTH := 9.0
## Lightest wind, relative to the default sea's, whose wave length the fallback still shortens.
const FALLBACK_MIN_WIND_RATIO := 0.5
## Above this the Gerstner waves loop over themselves.
const FALLBACK_MAX_STEEPNESS := 0.95
## Metres above the local wave height where the camera lens can still dip into a crest.
const UNDERWATER_REACH_MARGIN := 0.5

@export var spectrum: OceanSpectrum
@export var quality: OceanQuality
## Colour, clarity, foam and caustics. Null: the shader defaults.
@export var look: OceanLook
@export var planar_reflection := true
## Waves, wakes and foam from objects in the water, near the camera (WaterRipples).
@export var interaction_ripples := true
@export_group("Depth and shore")
@export_range(-20.0, 20.0, 0.05, "or_less", "or_greater", "suffix:m") var level := 0.0
## Share of the open-sea wave that still reaches the waterline, so the shore keeps a lapping wave.
@export_range(0.0, 1.0, 0.01) var min_shore_wave: float = 0.12
## Depth-limited waves: crest height <= breaker_ratio * water depth. Real waves break at H = 0.78 d,
## a crest of 0.39 d.
@export_range(0.05, 2.0) var breaker_ratio := 0.39
## Extra water level at the waterline from breaking waves, as a fraction of the crest height
## (real set-up is about 0.2 of the breaking wave height). Higher seas reach further up the beach.
@export_range(0.0, 2.0) var wave_setup := 0.3
@export_group("")
@export var rules: OceanRuleSet

var material: ShaderMaterial
var _simulation: OceanSimulation
var _surface: MeshInstance3D
var _height_field: OceanHeightField
var _fallback: Sea
var _seabed: Image
var _seabed_area: Rect2
var _seabed_resolution := DEFAULT_SEABED_RESOLUTION
var _time := 0.0
var _frames_since_readback := 0
var _reflection: PlanarReflection
var _underwater: UnderwaterView
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
	for tunable: Object in _tunables():
		_limits.merge(OceanRuleEngine.limits(tunable))
	_effective = spectrum.duplicate() as OceanSpectrum
	# Web / Compatibility: no RenderingDevice, so no compute shaders. Cheaper Gerstner fallback.
	if not OceanSimulation.is_supported():
		_fallback = Sea.new()
		_fallback.level = level
		_fallback.planar_reflection = planar_reflection
		_fallback.interaction_ripples = interaction_ripples
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
	_underwater = UnderwaterView.new()
	_underwater.shaft_steps = quality.underwater_shaft_steps
	add_child(_underwater)
	_apply_cascades()
	material.set_shader_parameter("map_size", float(OceanSimulation.MAP_SIZE))
	material.set_shader_parameter("mesh_angular_step", TAU / quality.radial_segments)
	material.set_shader_parameter("foam_texture", WaterTextures.foam())
	material.set_shader_parameter("gust_texture", WaterTextures.gusts())
	WaterTextures.apply_detail_normals(material)
	_surface = MeshInstance3D.new()
	_surface.mesh = OceanSurfaceMesh.build(quality.radial_segments, quality.inner_radius, quality.far_radius)
	_surface.material_override = material
	_surface.layers = PlanarReflection.water_layer_mask()
	_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_surface)
	if interaction_ripples and WaterRipples.find(get_tree()) == null:
		add_child(WaterRipples.new())
	if planar_reflection:
		_reflection = PlanarReflection.new()
		_reflection.plane_height = level
		_reflection.resolution_scale = quality.reflection_resolution_scale
		_reflection.blur_samples = quality.reflection_blur_samples
		add_child(_reflection)
	_update_rules(true)


func _exit_tree() -> void:
	if _simulation != null:
		# Release bindings before scheduling GPU destruction, after child meshes leave the tree.
		_surface.material_override = null
		material.set_shader_parameter("displacement_maps", null)
		material.set_shader_parameter("slope_maps", null)
		material.set_shader_parameter("moment_maps", null)
		_underwater.set_waves(null, null, PackedFloat32Array(), 0, OceanSimulation.MAP_SIZE)
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


## Every tunable number of the sea state and of this ocean, in display order.
func parameters() -> Array[OceanParameter]:
	var result := OceanParameterCatalog.of(_authored_spectrum(), WAVES_GROUP)
	result.append_array(OceanParameterCatalog.of(_authored_look(), LOOK_GROUP))
	result.append_array(OceanParameterCatalog.of(self, SEA_GROUP))
	return result


## Authored value of a tunable (before the rules); NAN for an unknown name.
func parameter_value(parameter: StringName) -> float:
	var owner_object := _owner_of(parameter)
	if owner_object == null:
		return NAN
	var value: float = owner_object.get(parameter)
	return value


## Sets the authored value of a tunable, kept inside its allowed range, and applies it.
## Returns false for an unknown name.
func set_parameter(parameter: StringName, value: float) -> bool:
	var owner_object := _owner_of(parameter)
	if owner_object == null:
		return false
	owner_object.set(parameter, _described(owner_object, parameter).clamp_value(value))
	_update_rules(true)
	return true


## False when the active renderer ignores this tunable (the Gerstner fallback has far fewer).
func is_parameter_live(parameter: StringName) -> bool:
	return _fallback == null or FALLBACK_PARAMETERS.has(parameter)


func _authored_spectrum() -> OceanSpectrum:
	return spectrum if spectrum != null else DEFAULT_SPECTRUM


func _authored_look() -> OceanLook:
	if look == null:
		look = OceanLook.new()
	return look


## Everything that holds tunable numbers: the sea state, the look and this ocean.
func _tunables() -> Array[Object]:
	return [_authored_spectrum(), _authored_look(), self]


## The object holding a tunable: the spectrum, this ocean, or null.
func _owner_of(parameter: StringName) -> Object:
	for candidate: Object in _tunables():
		if _described(candidate, parameter) != null:
			return candidate
	return null


static func _described(object: Object, parameter: StringName) -> OceanParameter:
	for known: OceanParameter in OceanParameterCatalog.of(object, ""):
		if known.name == parameter:
			return known
	return null


## Replaces the look, or re-applies it after its colours were changed in place.
func set_look(value: OceanLook) -> void:
	look = value
	_update_rules(true)


func set_rules(value: OceanRuleSet) -> void:
	rules = value
	_update_rules(true)


## Current value of a parameter after the rules (e.g. &"wind_speed", &"level", &"wave_height").
func effective_value(parameter: StringName) -> float:
	var value: float = _values.get(parameter, NAN)
	return value


## Names rule conditions can read: every number of the ocean and its spectrum, plus the measured
## wave height and the per-point water depth.
func rule_parameters() -> PackedStringArray:
	var names := _number_names()
	names.append(String(OceanRuleEngine.WAVE_HEIGHT))
	names.append(String(OceanLocalRules.DEPTH))
	return names


## Names rule effects can change: every number of the ocean and its spectrum, plus the local outputs.
func rule_targets() -> PackedStringArray:
	var names := PackedStringArray([String(OceanLocalRules.FOAM), String(OceanLocalRules.WAVE_SIZE),
			String(OceanLocalRules.WATER_LEVEL)])
	names.append_array(_number_names())
	return names


func _number_names() -> PackedStringArray:
	var names := PackedStringArray()
	for tunable: Object in _tunables():
		for key: StringName in OceanRuleEngine.parameters(tunable):
			names.append(String(key))
	return names


## Problems found in the rules at their last evaluation (unknown parameters, too many local rules, ...).
func rule_problems() -> PackedStringArray:
	return _problems


## Measured significant wave height of the open sea (twice the typical crest height), in metres.
func wave_height() -> float:
	return 2.0 * _amplitude


## Bakes the ground height under the sea so waves calm down and surf forms in shallow water.
## `height` takes (x: float, z: float) and returns the ground height.
## `resolution` texels per side; raise it for large areas so the shoreline stays sharp.
func set_seabed(height: Callable, area: Rect2, resolution: int = DEFAULT_SEABED_RESOLUTION) -> void:
	if material == null:
		return
	_seabed_resolution = resolution
	var img := Image.create(resolution, resolution, false, Image.FORMAT_RF)
	for y in range(resolution):
		for x in range(resolution):
			var p := area.position + area.size * Vector2(x + 0.5, y + 0.5) / resolution
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
		var xz := Vector2(p.x, p.z)
		var surface := height_at(xz)
		# Back faces of the surface mean "seen from below" only when the camera really is under water;
		# otherwise they are the far side of a steep crest and get drawn like the top.
		material.set_shader_parameter("camera_underwater", p.y < surface)
		_underwater.follow(cam, surface, _level() + _local_lift(xz), _damping_at(xz), wave_height() + UNDERWATER_REACH_MARGIN)
	else:
		_underwater.follow(null, 0.0, 0.0, 0.0, 0.0)
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
	_underwater.set_waves(_simulation.displacement, _simulation.slope, tiles, _simulation.cascade_count,
			OceanSimulation.MAP_SIZE)


## Re-applies the rules to the authored state. Without `force`, only pushes what actually changed,
## so rules that read the measured wave height can run every frame.
func _update_rules(force: bool) -> void:
	if _effective == null or (not force and rules == null):
		return
	var inputs: Dictionary[StringName, float] = {}
	for tunable: Object in _tunables():
		inputs.merge(OceanRuleEngine.parameters(tunable))
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
	var wind_angle := deg_to_rad(_effective.wind_direction)
	material.set_shader_parameter("wind", Vector2(cos(wind_angle), sin(wind_angle)) * _effective.wind_speed)
	material.set_shader_parameter("breaker_ratio", _value(&"breaker_ratio"))
	material.set_shader_parameter("min_shore_wave", _value(&"min_shore_wave"))
	material.set_shader_parameter("wave_setup", _value(&"wave_setup"))
	OceanLookBinding.apply(_authored_look(), material, _values)
	var look_now := _authored_look()
	_underwater.set_optics(OceanLookBinding.absorption(look_now, _values), look_now.deep_color)
	_underwater.set_seabed_light(_look_value(&"caustic_strength"), _look_value(&"caustic_fade"),
			_look_value(&"seabed_light_loss"))
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


## A look value after the rules.
func _look_value(parameter: StringName) -> float:
	if _values.has(parameter):
		return _values[parameter]
	var authored: float = _authored_look().get(parameter)
	return authored


func _level() -> float:
	return _value(&"level")


## Seabed depth below the sea level at `p`; a large value outside the baked seabed (open sea).
func _depth_at(p: Vector2) -> float:
	if _seabed == null or not _seabed_area.has_point(p):
		return OPEN_SEA_DEPTH
	var last := _seabed_resolution - 1
	var uv: Vector2 = (p - _seabed_area.position) / _seabed_area.size * _seabed_resolution - Vector2(0.5, 0.5)
	var x: int = floori(uv.x)
	var y: int = floori(uv.y)
	var x0: int = clampi(x, 0, last)
	var x1: int = clampi(x + 1, 0, last)
	var y0: int = clampi(y, 0, last)
	var y1: int = clampi(y + 1, 0, last)
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


## Approximate sea states on Compatibility; this is not an FFT spectrum reconstruction. The Gerstner
## sea has one wave train, so it takes the direction and length of the bigger system, swell or wind sea,
## on the default sea's scale. Heights add like energies; gentle swell sharpens the crests less.
func _apply_fallback_spectrum() -> void:
	var sea := _effective
	var wind_ratio: float = sea.wind_speed / DEFAULT_SPECTRUM.wind_speed
	var wind_amplitude := FALLBACK_AMPLITUDE * wind_ratio * wind_ratio
	var swell_amplitude := FALLBACK_AMPLITUDE * sea.swell_height / OceanSeaStats.wind_wave_height(DEFAULT_SPECTRUM)
	var wavelength := FALLBACK_WAVELENGTH * maxf(wind_ratio, FALLBACK_MIN_WIND_RATIO) * sea.wavelength_scale
	var heading := sea.wind_direction
	var steepness := minf(sea.choppiness, FALLBACK_MAX_STEEPNESS)
	if swell_amplitude > wind_amplitude:
		wavelength = FALLBACK_WAVELENGTH * sea.swell_wavelength() / DEFAULT_SPECTRUM.peak_wavelength()
		heading = sea.swell_direction
		steepness *= wind_amplitude / swell_amplitude
	var amplitude := sqrt(wind_amplitude * wind_amplitude + swell_amplitude * swell_amplitude) * sea.height_scale
	_fallback.material.set_shader_parameter("wave_amplitude", amplitude)
	_fallback.material.set_shader_parameter("wave_length", wavelength)
	_fallback.material.set_shader_parameter("wave_steepness", steepness)
	var direction: float = deg_to_rad(heading)
	_fallback.material.set_shader_parameter("wind_direction", Vector2(cos(direction), sin(direction)))
