class_name WaterRipples
extends Node
## Waves and foam that objects make in the water: splashes, rings around bobbing things and the V-shaped
## wake behind a boat. A 2D wave equation on a grid centred on the camera (ripple_step.gdshader), run by
## two SubViewports that take turns, published as global shader values that every water shader reads
## (water_ripples.gdshaderinc). One per scene: the first water body creates it; others reuse it.
## Web / Compatibility: off (no float render targets to rely on there); water shaders then skip it.

const GROUP := &"water_ripples"
const STEP_SHADER := preload("res://world/water/ripples/ripple_step.gdshader")
const DEFAULT_QUALITY := preload("res://data/quality/water_high.tres")
const MAP_PARAM := &"water_ripple_map"
const RECT_PARAM := &"water_ripple_rect"
const ENABLED_PARAM := &"water_ripples_enabled"
## Must match MAX_SOURCES in ripple_step.gdshader.
const MAX_SOURCES := 16
## Wave speed of the simulated ripples. Half-metre waves travel at about 0.9 m/s; at 1 m/s a boat at
## 3 m/s leaves a V of 19.5 degrees each side, the angle of a real (Kelvin) wake.
const WAVE_SPEED := 1.0
## How fast ripples die out (1/s).
const DAMPING_RATE := 0.35
## Time for foam to fade to about a third (s).
const FOAM_LIFETIME := 2.5
## Above 0.5 the explicit wave equation blows up; long frames are clamped below it.
const MAX_COURANT2 := 0.45
const EDGE_ABSORB := 0.1

@export var quality: WaterQuality

var _viewports: Array[SubViewport] = []
var _materials: Array[ShaderMaterial] = []
var _current := 0
## Centre of the simulated area, snapped to whole texels so the pattern doesn't swim.
var _centre := Vector2.ZERO
var _sources := PackedVector4Array()
var _source_foam := PackedFloat32Array()
var _enabled := false
## The first drawn frame clears both state textures (their contents start out undefined).
var _clearing := true


## The scene's ripples, or null when no water body made one.
static func find(tree: SceneTree) -> WaterRipples:
	if tree == null:
		return null
	return tree.get_first_node_in_group(GROUP) as WaterRipples


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	if quality == null:
		quality = DEFAULT_QUALITY
	# Web / Compatibility: no ripple simulation.
	if OS.has_feature("web") or RenderingServer.get_current_rendering_method() == "gl_compatibility":
		RenderingServer.global_shader_parameter_set(ENABLED_PARAM, false)
		set_process(false)
		return
	for i in range(2):
		var viewport := SubViewport.new()
		viewport.size = Vector2i(quality.ripple_resolution, quality.ripple_resolution)
		viewport.use_hdr_2d = true
		viewport.disable_3d = true
		viewport.transparent_bg = false
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var rect := ColorRect.new()
		rect.size = Vector2(viewport.size)
		var material := ShaderMaterial.new()
		material.shader = STEP_SHADER
		material.set_shader_parameter("texel", Vector2.ONE / float(quality.ripple_resolution))
		material.set_shader_parameter("edge_absorb", EDGE_ABSORB)
		rect.material = material
		viewport.add_child(rect)
		add_child(viewport)
		_viewports.append(viewport)
		_materials.append(material)
	for i in range(2):
		_materials[i].set_shader_parameter("previous", _viewports[1 - i].get_texture())
		_materials[i].set_shader_parameter("reset", true)
		_viewports[i].render_target_update_mode = SubViewport.UPDATE_ONCE
	_enabled = true
	RenderingServer.global_shader_parameter_set(ENABLED_PARAM, true)


func _exit_tree() -> void:
	if _enabled:
		RenderingServer.global_shader_parameter_set(ENABLED_PARAM, false)


## Pushes the surface down by `push` metres over `radius` around `point` (world), leaving `foam` (0..1).
## Applied at the next simulation step; the strongest MAX_SOURCES of a step are kept.
func disturb(point: Vector3, radius: float, push: float, foam: float = 0.0) -> void:
	var source := Vector4(point.x, point.z, radius, push)
	if _sources.size() < MAX_SOURCES:
		_sources.append(source)
		_source_foam.append(foam)
		return
	var weakest := 0
	for i in range(_sources.size()):
		if absf(_sources[i].w) < absf(_sources[weakest].w):
			weakest = i
	if absf(push) > absf(_sources[weakest].w):
		_sources[weakest] = source
		_source_foam[weakest] = foam


## World rectangle the ripples cover: origin x, origin z, size x, size z.
func area() -> Vector4:
	var size := quality.ripple_area if quality != null else DEFAULT_QUALITY.ripple_area
	return Vector4(_centre.x - size * 0.5, _centre.y - size * 0.5, size, size)


func _process(delta: float) -> void:
	if not _enabled:
		return
	if _clearing:
		# Both viewports draw their reset this frame; the simulation starts on the next one.
		_clearing = false
		return
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("reset", false)
	var texel_size := quality.ripple_area / quality.ripple_resolution
	var cam := get_viewport().get_camera_3d()
	var shift := Vector2.ZERO
	if cam != null:
		var target := Vector2(snappedf(cam.global_position.x, texel_size), snappedf(cam.global_position.z, texel_size))
		shift = ((target - _centre) / texel_size).round()
		_centre = target
	var next := 1 - _current
	var material := _materials[next]
	material.set_shader_parameter("shift", shift)
	var step := WAVE_SPEED * delta / texel_size
	material.set_shader_parameter("courant2", minf(step * step, MAX_COURANT2))
	material.set_shader_parameter("damping", exp(-DAMPING_RATE * delta))
	material.set_shader_parameter("foam_decay", exp(-delta / FOAM_LIFETIME))
	_push_sources(material)
	_viewports[next].render_target_update_mode = SubViewport.UPDATE_ONCE
	_current = next
	RenderingServer.global_shader_parameter_set(MAP_PARAM, _viewports[next].get_texture())
	RenderingServer.global_shader_parameter_set(RECT_PARAM, area())


func _push_sources(material: ShaderMaterial) -> void:
	var rect := area()
	var uv_sources := PackedVector4Array()
	uv_sources.resize(MAX_SOURCES)
	var foam := PackedFloat32Array()
	foam.resize(MAX_SOURCES)
	for i in range(_sources.size()):
		var s := _sources[i]
		uv_sources[i] = Vector4((s.x - rect.x) / rect.z, (s.y - rect.y) / rect.w, s.z / rect.z, s.w)
		foam[i] = _source_foam[i]
	material.set_shader_parameter("source_count", _sources.size())
	material.set_shader_parameter("sources", uv_sources)
	material.set_shader_parameter("source_foam", foam)
	_sources.clear()
	_source_foam.clear()
