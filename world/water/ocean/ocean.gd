class_name Ocean
extends Node3D
## Open sea with a GPU FFT wave simulation (desktop). Builds the camera-following surface, planar
## reflection and a CPU height field for floating objects.
## Web / Compatibility renderer: no compute shaders, so it falls back to the Gerstner `Sea`.
## `spectrum` and the exported values are the authored sea state; `rules` (OceanRuleSet) change them
## at runtime ("if local_depth < 1 and wind_speed > 12 then local_foam += 5").

## A plunging breaker's lip came down at `position`; the breaker was `height` metres high. For sound.
signal breaker_plunged(position: Vector3, height: float)

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
## Foam drifts downwind at about this share of the wind speed (the wind-driven surface current).
const FOAM_DRIFT_SHARE := 0.03
## The foam drift wraps after this many foam pattern tiles: whole tiles of both pattern layers
## (2.71 times apart in ocean.gdshader), so the wrap never shows.
const FOAM_WRAP_TILES := 100.0
## A tile change waits until the sea state has stopped changing this long (a slider being dragged),
## so one drag makes one transition, not one per frame.
const TRANSITION_SETTLE := 0.3
## Global shader values the ground reads for the swash on the beach (terrain_ground.gdshader).
const SWASH_RUNUP_PARAM := &"water_swash_runup"
const SWASH_PERIOD_PARAM := &"water_swash_period"
## The wave clock the swash and the shore waves run on, so the CPU heights match what is drawn.
const WAVE_TIME_PARAM := &"water_wave_time"
## Cell texture foam ages into, on the sea and on the sand (foam_lace.gdshaderinc).
## Ray-march steps of the screen-space reflections on all water, from the quality tier.
const SSR_STEPS_PARAM := &"water_ssr_steps"
## Metres over which the slope of the shore waves and swash at the camera is measured, for the waterline
## across the lens.
const LENS_SLOPE_STEP := 0.25
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
## Slope of the beach face at the waterline (rise over run): with the waves it sets how far the swash
## runs up the sand (ShoreRunup). 0.08 is a medium-sand beach, as BeachProfile builds by default.
@export_range(0.01, 0.3, 0.005) var foreshore_slope := 0.08
## Water shallower than this (m) turns the waves towards the beach, where they steepen and break
## (ShoreWaves). Real waves feel the bottom deeper still; the shore waves take over where it shows.
@export_range(1.0, 12.0, 0.5, "suffix:m") var shore_wave_depth := 8.0
## Share of the open sea's wave energy that the shore waves carry inside that depth; the rest stays
## as the simulated, many-directional sea on top of them.
@export_range(0.0, 1.0, 0.01) var shore_wave_share := 0.7
## Shore waves left on a coast facing away from the open sea's main waves (refraction still bends
## some round to it).
@export_range(0.0, 1.0, 0.01) var shore_lee_share := 0.3
## How hard breakers plunge where the beach makes them (BreakerProfile): 1 is physical, 0 makes every
## breaker spill. Curls are drawn near the camera only, as far as the quality tier's breaker_reach.
@export_range(0.0, 2.0, 0.01) var curl_strength := 1.0
@export_group("Sea state changes")
## Seconds a new sea state takes to fade in when it changes the longest waves' tile (a preset, a big
## wind change). 0 switches at once and rearranges every long wave in one frame.
@export_range(0.0, 30.0, 0.5, "suffix:s") var transition_time := 6.0
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
var _shore := ShoreWaves.new()
## The swash's run-up (m) as last published, for the CPU twin of the swash (SwashEdge).
var _runup := 0.0
var _breakers: BreakerSystem
var _time := 0.0
var _frames_since_readback := 0
var _reflection: PlanarReflection
var _underwater: UnderwaterView
var _spray: OceanSpray
## During a sea-state change: the old simulation and its height field, fading out.
var _outgoing: OceanSimulation
var _outgoing_field: OceanHeightField
## 0: all old, 1: all new.
var _transition := 1.0
## A sea state with new tiles, waiting to settle before it starts its transition.
var _pending: OceanSpectrum
var _pending_age := 0.0
var _foam_offset := Vector2.ZERO
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
	RenderingServer.global_shader_parameter_set(SSR_STEPS_PARAM, quality.reflection_march_steps)
	# Both renderers: the beach draws the swash's foam from them too (terrain_ground).
	WaterTextures.apply_foam_globals()
	for tunable: Object in _tunables():
		_limits.merge(OceanRuleEngine.limits(tunable))
	_effective = spectrum.duplicate() as OceanSpectrum
	# Web / Compatibility: no RenderingDevice, so no compute shaders. Cheaper Gerstner fallback.
	if not OceanSimulation.is_supported():
		_fallback = Sea.new()
		_fallback.level = level
		_fallback.planar_reflection = planar_reflection
		_fallback.interaction_ripples = interaction_ripples
		# Open sea to the horizon, following the camera like the FFT surface.
		_fallback.follow_camera = true
		_fallback.far_radius = quality.far_radius
		_fallback.radial_segments = quality.radial_segments
		add_child(_fallback)
		_update_rules(true)
		return
	_simulation = OceanSimulation.new(quality.cascade_count, _effective)
	_height_field = OceanHeightField.new(OceanSimulation.MAP_SIZE, _simulation.tile_lengths)
	material = ShaderMaterial.new()
	material.shader = SURFACE_SHADER
	material.set_shader_parameter("wave_amplitude", _amplitude)
	_bind_maps()
	_underwater = UnderwaterView.new()
	_underwater.shaft_steps = quality.underwater_shaft_steps
	add_child(_underwater)
	if quality.spray_particles > 0:
		_spray = OceanSpray.new(quality.spray_particles, quality.spray_area)
		add_child(_spray)
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
	RenderingServer.global_shader_parameter_set(SWASH_RUNUP_PARAM, 0.0)
	if _simulation != null:
		# Release bindings before scheduling GPU destruction, after child meshes leave the tree.
		_surface.material_override = null
		material.set_shader_parameter("displacement_maps", null)
		material.set_shader_parameter("slope_maps", null)
		material.set_shader_parameter("moment_maps", null)
		_underwater.set_waves(null, null, PackedFloat32Array(), 0, OceanSimulation.MAP_SIZE)
		if _spray != null:
			_spray.set_waves(null, null, PackedFloat32Array(), 0)
		_end_transition()
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
## The plunging breaker at world `xz`: its stage, its lip, and whether `xz` is inside its tube. An empty
## state (stage < 0) where nothing is breaking or the ocean has no seabed or no curls.
func breaker_at(xz: Vector2) -> BreakerState:
	if _breakers == null:
		return BreakerState.new()
	return _breakers.query.at(xz)


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
	# The coast at the current level: a tide moves the waterline, but the crests still follow the depths.
	_shore.field = ShoreField.bake(_depth_at, area)
	material.set_shader_parameter("shore_field", ImageTexture.create_from_image(_shore.field.image))
	material.set_shader_parameter("shore_origin", ImageTexture.create_from_image(_shore.field.origins))
	_make_breakers(area)


## World height of the water surface at `xz` (the rest level until the first GPU readback arrives).
func height_at(xz: Vector2) -> float:
	if _fallback != null:
		return _fallback.height_at(xz, _time)
	var rest_level := _level() + _local_lift(xz) + _near_shore_lift(xz)
	var current := _height_field != null and _height_field.is_ready()
	var outgoing := _outgoing_field != null and _outgoing_field.is_ready()
	if outgoing and not current:
		return rest_level + _outgoing_field.height_at(xz)
	if not current:
		return rest_level
	if not outgoing:
		return rest_level + _height_field.height_at(xz)
	# The longest waves change in a transition: unrelated fields, blended to keep their energy.
	var w := smoothstep(0.0, 1.0, _transition)
	return rest_level + _height_field.height_at(xz) * sqrt(w) + _outgoing_field.height_at(xz) * sqrt(1.0 - w)


func _process(delta: float) -> void:
	_time += delta
	_shore.time = _time
	RenderingServer.global_shader_parameter_set(WAVE_TIME_PARAM, _time)
	_publish_swash()
	if _fallback != null:
		_fallback.material.set_shader_parameter("wave_time", _time)
	if _simulation == null:
		_update_rules(false)
		return
	if _height_field.is_ready():
		_amplitude = lerpf(_amplitude, _height_field.crest_amplitude(), 1.0 - exp(-AMPLITUDE_RESPONSE * delta))
		material.set_shader_parameter("wave_amplitude", _amplitude)
		_shore.amplitude = _amplitude
	_update_rules(false)
	_advance_transition(delta)
	_simulation.update(_time, delta)
	_drift_foam(delta)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var p := cam.global_position
		_surface.global_position = Vector3(snappedf(p.x, FOLLOW_SNAP), _level(), snappedf(p.z, FOLLOW_SNAP))
		var xz := Vector2(p.x, p.z)
		var surface := height_at(xz)
		# Back faces of the surface mean "seen from below" only when the camera really is under water;
		# otherwise they are the far side of a steep crest and get drawn like the top.
		material.set_shader_parameter("camera_underwater", p.y < surface)
		var near_shore := _near_shore_lift(xz)
		var slope := Vector2(_near_shore_lift(xz + Vector2(LENS_SLOPE_STEP, 0.0)) - near_shore,
				_near_shore_lift(xz + Vector2(0.0, LENS_SLOPE_STEP)) - near_shore) / LENS_SLOPE_STEP
		_underwater.follow(cam, surface, _level() + _local_lift(xz) + near_shore, _damping_at(xz),
				wave_height() + UNDERWATER_REACH_MARGIN, slope)
		if _spray != null:
			_spray.follow(p)
		if _breakers != null:
			_breakers.update(xz, _time, _shore.period, _wind())
	else:
		_underwater.follow(null, 0.0, 0.0, 0.0, 0.0)
	if quality.readback_interval > 0:
		_frames_since_readback += 1
		if _frames_since_readback >= quality.readback_interval:
			_frames_since_readback = 0
			_request_readback(_simulation, _height_field)
			if _outgoing != null:
				_request_readback(_outgoing, _outgoing_field)


static func _request_readback(simulation: OceanSimulation, field: OceanHeightField) -> void:
	for c in range(simulation.cascade_count):
		var cascade := c
		simulation.request_displacement(c, func(bytes: PackedByteArray) -> void: field.set_cascade.call_deferred(cascade, bytes))


## Runs a sea-state change: starts it once a new state with new tiles has settled, runs the old
## simulation alongside the new one, and ends it when the new one has fully faded in.
func _advance_transition(delta: float) -> void:
	if _pending != null:
		_pending_age += delta
		if _pending_age >= TRANSITION_SETTLE:
			_start_transition()
	if _outgoing == null:
		return
	_transition = minf(_transition + delta / maxf(transition_time, 0.001), 1.0)
	material.set_shader_parameter("transition", _transition)
	_outgoing.update(_time, delta)
	if _transition >= 1.0:
		_end_transition()


func _start_transition() -> void:
	var incoming := _pending
	_pending = null
	# A change during a change: the oldest state goes, the one fading in becomes the one fading out.
	_end_transition()
	_outgoing = _simulation
	_outgoing_field = _height_field
	_simulation = OceanSimulation.new(quality.cascade_count, incoming)
	_height_field = OceanHeightField.new(OceanSimulation.MAP_SIZE, _simulation.tile_lengths)
	_height_field.damping_at = _damping_at
	_bind_maps()
	material.set_shader_parameter("prev_displacement_maps", _outgoing.displacement)
	material.set_shader_parameter("prev_slope_maps", _outgoing.slope)
	material.set_shader_parameter("prev_moment_maps", _outgoing.moments)
	material.set_shader_parameter("prev_tile_lengths", _tiles_of(_outgoing))
	material.set_shader_parameter("prev_cascade_count", _outgoing.cascade_count)
	_transition = 0.0
	material.set_shader_parameter("transition", _transition)
	_apply_cascades()


## Drops the fading-out simulation, if any: unbinds its maps first, then frees it on the render thread.
func _end_transition() -> void:
	_transition = 1.0
	if material != null:
		material.set_shader_parameter("transition", _transition)
		material.set_shader_parameter("prev_cascade_count", 0)
		material.set_shader_parameter("prev_displacement_maps", null)
		material.set_shader_parameter("prev_slope_maps", null)
		material.set_shader_parameter("prev_moment_maps", null)
	if _outgoing != null:
		_outgoing.free_resources()
	_outgoing = null
	_outgoing_field = null


func _bind_maps() -> void:
	material.set_shader_parameter("displacement_maps", _simulation.displacement)
	material.set_shader_parameter("slope_maps", _simulation.slope)
	material.set_shader_parameter("moment_maps", _simulation.moments)


static func _tiles_of(simulation: OceanSimulation) -> PackedFloat32Array:
	var tiles := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
	for c in range(simulation.cascade_count):
		tiles[c] = simulation.tile_lengths[c]
	return tiles


## How far up the beach the waves run now, and how often, for the ground's swash.
func _publish_swash() -> void:
	var height := wave_height() if _height_field != null and _height_field.is_ready() \
			else OceanSeaStats.expected_wave_height(_effective)
	var period := OceanSeaStats.dominant_period(_effective)
	_runup = ShoreRunup.stockdon(height, period, _value(&"foreshore_slope"))
	RenderingServer.global_shader_parameter_set(SWASH_RUNUP_PARAM, _runup)
	RenderingServer.global_shader_parameter_set(SWASH_PERIOD_PARAM, period)
	_shore.period = period


func _drift_foam(delta: float) -> void:
	var angle := deg_to_rad(_effective.wind_direction)
	var drift := Vector2(cos(angle), sin(angle)) * _effective.wind_speed * FOAM_DRIFT_SHARE * delta
	var period := FOAM_WRAP_TILES / maxf(_look_value(&"foam_scale"), 0.001)
	_foam_offset = Vector2(fposmod(_foam_offset.x + drift.x, period), fposmod(_foam_offset.y + drift.y, period))
	material.set_shader_parameter("foam_offset", _foam_offset)


func _apply_cascades() -> void:
	var tiles := _tiles_of(_simulation)
	material.set_shader_parameter("tile_lengths", tiles)
	material.set_shader_parameter("cascade_count", _simulation.cascade_count)
	_underwater.set_waves(_simulation.displacement, _simulation.slope, tiles, _simulation.cascade_count,
			OceanSimulation.MAP_SIZE)
	if _spray != null:
		_spray.set_waves(_simulation.displacement, _simulation.moments, tiles, _simulation.cascade_count)


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
	if spectrum_changed:
		_change_spectrum()
	if _height_field.damping_at.is_null():
		_height_field.damping_at = _damping_at
	material.set_shader_parameter("sea_level", sea_level)
	var wind := _wind()
	material.set_shader_parameter("wind", wind)
	material.set_shader_parameter("white_water_height", _effective.white_water_height)
	if _spray != null:
		_spray.set_sea(wind, sea_level, _look_value(&"foam_cascade_falloff"), _effective.spray_amount)
	material.set_shader_parameter("breaker_ratio", _value(&"breaker_ratio"))
	material.set_shader_parameter("min_shore_wave", _value(&"min_shore_wave"))
	material.set_shader_parameter("wave_setup", _value(&"wave_setup"))
	_apply_shore_waves()
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


## New tiles fade in over transition_time (once the values settle); anything else applies at once.
func _change_spectrum() -> void:
	var new_tiles := OceanSimulation.tiles_for(_effective, _simulation.cascade_count) != _simulation.tile_lengths
	if new_tiles and transition_time > 0.0:
		_pending = _effective.duplicate() as OceanSpectrum
		_pending_age = 0.0
		return
	_pending = null
	if _simulation.set_spectrum(_effective):
		_height_field = OceanHeightField.new(OceanSimulation.MAP_SIZE, _simulation.tile_lengths)
		_height_field.damping_at = _damping_at
		_apply_cascades()


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


## Same rule as shore_damping() in ocean.gdshader, with local rules and set-up, times the share the
## shore waves leave to the open sea's.
func _damping_at(rest: Vector2) -> float:
	var raw := _depth_at(rest)
	if raw >= OPEN_SEA_DEPTH and _local.count() == 0:
		return 1.0
	var rule := _local.evaluate(raw)
	var still := raw + _setup_lift(raw) + rule.z
	var depth := maxf(still, 0.0)
	var limited := _value(&"breaker_ratio") * depth / maxf(_amplitude, 0.01)
	var shore := clampf(maxf(limited, _value(&"min_shore_wave") * smoothstep(0.0, 0.5, depth)), 0.0, 1.0)
	return shore * rule.y * _shore.open_sea_share(still)


## Height the shore waves and the swash add at world `xz` (m).
func _near_shore_lift(xz: Vector2) -> float:
	return _shore.height_at(xz, _still_depth) + _swash_lift(xz)


## Same as swash_lift() in ocean.gdshader: near the waterline the sea rises to the swash edge.
func _swash_lift(p: Vector2) -> float:
	var depth := _depth_at(p)
	if depth >= OPEN_SEA_DEPTH:
		return 0.0
	var zone := _amplitude / maxf(_value(&"breaker_ratio"), 0.01)
	var near_shore := 1.0 - smoothstep(0.0, zone, depth)
	var edge := SwashEdge.state(p, _time, _runup, _shore.period).x
	return maxf(edge * near_shore - _setup_lift(depth), 0.0)


## Still water depth at rest point `p` with set-up and rule water: what the shore waves see
## (v_still_depth in ocean.gdshader).
func _still_depth(p: Vector2) -> float:
	var raw := _depth_at(p)
	return raw + _setup_lift(raw) + _local.evaluate(raw).z


## The shore waves' settings after the rules, on the CPU twin and the surface.
func _apply_shore_waves() -> void:
	_shore.breaker_ratio = _value(&"breaker_ratio")
	_shore.zone_depth = _value(&"shore_wave_depth")
	_shore.share = _value(&"shore_wave_share")
	_shore.lee_share = _value(&"shore_lee_share")
	_shore.direction = _main_wave_direction()
	material.set_shader_parameter("shore_wave_depth", _shore.zone_depth)
	material.set_shader_parameter("shore_wave_share", _shore.share)
	material.set_shader_parameter("shore_lee_share", _shore.lee_share)
	material.set_shader_parameter("shore_wave_direction", _shore.direction)
	material.set_shader_parameter("curl_strength", _value(&"curl_strength"))
	if _breakers != null:
		_breakers.set_sea(_level(), _value(&"curl_strength"))


## The wind over the sea after the rules (direction * m/s).
func _wind() -> Vector2:
	var angle := deg_to_rad(_effective.wind_direction)
	return Vector2(cos(angle), sin(angle)) * _effective.wind_speed


## Plunging breakers along the baked seabed, when the quality tier asks for curls.
func _make_breakers(area: Rect2) -> void:
	if _breakers != null:
		_breakers.queue_free()
		_breakers = null
	if quality.breaker_reach <= 0.0 or _shore.field.waterlines.is_empty():
		return
	_breakers = BreakerSystem.new(_shore, material, quality, area, _level(), _depth_at, _still_depth)
	_breakers.plunged.connect(func(at: Vector3, height: float) -> void: breaker_plunged.emit(at, height))
	_breakers.set_sea(_level(), _value(&"curl_strength"))
	add_child(_breakers)


## Direction the bigger wave system travels in: the swell when it is higher than the wind sea.
func _main_wave_direction() -> Vector2:
	var heading := _effective.wind_direction
	if OceanSeaStats.swell_wave_height(_effective) > OceanSeaStats.surface_wave_height(_effective):
		heading = _effective.swell_direction
	var angle := deg_to_rad(heading)
	return Vector2(cos(angle), sin(angle))


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
