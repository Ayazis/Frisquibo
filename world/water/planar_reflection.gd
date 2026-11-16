class_name PlanarReflection
extends Node
## Renders the scene mirrored in a horizontal water plane into a SubViewport and publishes it as a
## global shader texture that water shaders sample with the screen UV (Y flipped). Two planes can exist
## at once (`slot`): 0 is the sea's (`water_reflection`), 1 a second level such as a pond above the sea
## (`water_reflection_2`); each water material picks one with its reflection_slot.
## The water itself is on WATER_LAYER so mirror cameras don't see it. Desktop only: on the web this node
## disables itself and water falls back to the engine's sky reflection.

const WATER_LAYER := 20
## An otherwise empty layer that only the second mirror camera leaves out, so ground shaders know which
## clip height applies (reflection_clip.gdshaderinc). Put nothing on this layer.
const SECOND_MIRROR_LAYER := 19
const SLOT_COUNT := 2
## Per slot: the texture, whether it is drawn, and the height below which ground is clipped.
const TEXTURE_PARAMS: Array[StringName] = [&"water_reflection", &"water_reflection_2"]
const ENABLED_PARAMS: Array[StringName] = [&"water_reflection_enabled", &"water_reflection_2_enabled"]
const CLIP_PARAMS: Array[StringName] = [&"water_reflection_clip_height", &"water_reflection_2_clip_height"]
## Taps water shaders use to blur the reflection by unresolved ripples (water_reflection.gdshaderinc).
const BLUR_SAMPLES_PARAM := &"water_reflection_blur_samples"
## Used when no quality tier sets blur_samples (lakes and rivers): the High tier's value.
const DEFAULT_BLUR_SAMPLES := 12
## Seconds between copies of the main camera's environment into the mirror's (fog, sky, light changes).
const ENVIRONMENT_REFRESH := 0.5
## Post-processing the main camera applies to the whole picture, reflection included: the mirror must
## not apply it as well. The mirror image is linear scene light, like the screen copy water reads
## for refraction and screen-space reflections, so the two blend without a seam.
const MAIN_PASS_ONLY: Array[StringName] = [&"tonemap_mode", &"tonemap_exposure", &"tonemap_white",
		&"glow_enabled", &"adjustment_enabled"]

@export var plane_height := 0.0
## Fraction of the main viewport resolution; lower is cheaper and softer.
@export_range(0.25, 1.0) var resolution_scale := 0.6
## Taps of the rough-water blur; 1 gives a sharp mirror everywhere.
@export_range(1, 32) var blur_samples := DEFAULT_BLUR_SAMPLES
## Which mirror this is: 0 the sea's level, 1 a second level.
@export_range(0, 1) var slot := 0
## World box of the water this mirror serves. When set, the mirror only renders while that box is on
## screen (a pond seen from the beach costs nothing). Empty: always render.
@export var visibility_aabb := AABB()

var _viewport: SubViewport
var _camera: Camera3D
var _on_screen := true
var _environment := Environment.new()
var _environment_source: Environment
var _environment_age := 0.0


static func water_layer_mask() -> int:
	return 1 << (WATER_LAYER - 1)


static func second_mirror_mask() -> int:
	return 1 << (SECOND_MIRROR_LAYER - 1)


func _ready() -> void:
	slot = clampi(slot, 0, SLOT_COUNT - 1)
	if OS.has_feature("web") or RenderingServer.get_current_rendering_method() == "gl_compatibility":
		RenderingServer.global_shader_parameter_set(ENABLED_PARAMS[slot], false)
		set_process(false)
		return
	_viewport = SubViewport.new()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	# Linear, unclamped light: without HDR the image would be tone mapped and sRGB-encoded, then
	# tone mapped again as part of the water.
	_viewport.use_hdr_2d = true
	_viewport.positional_shadow_atlas_size = 0
	_camera = Camera3D.new()
	_camera.cull_mask = ~water_layer_mask()
	if slot == 1:
		_camera.cull_mask &= ~second_mirror_mask()
	_viewport.add_child(_camera)
	add_child(_viewport)
	if visibility_aabb.has_volume():
		var notifier := VisibleOnScreenNotifier3D.new()
		notifier.aabb = visibility_aabb
		notifier.screen_entered.connect(_set_on_screen.bind(true))
		notifier.screen_exited.connect(_set_on_screen.bind(false))
		add_child(notifier)
		_set_on_screen(false)
	RenderingServer.global_shader_parameter_set(CLIP_PARAMS[slot], plane_height)
	RenderingServer.global_shader_parameter_set(BLUR_SAMPLES_PARAM, blur_samples)
	RenderingServer.global_shader_parameter_set(TEXTURE_PARAMS[slot], _viewport.get_texture())
	RenderingServer.global_shader_parameter_set(ENABLED_PARAMS[slot], true)


func set_plane_height(value: float) -> void:
	plane_height = value
	if _viewport != null:
		RenderingServer.global_shader_parameter_set(CLIP_PARAMS[slot], value)


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set(ENABLED_PARAMS[slot], false)


func _set_on_screen(on_screen: bool) -> void:
	_on_screen = on_screen
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on_screen else SubViewport.UPDATE_DISABLED


func _process(delta: float) -> void:
	if not _on_screen:
		return
	var main := get_viewport().get_camera_3d()
	if main == null:
		return
	var size := Vector2i(Vector2(get_viewport().get_visible_rect().size) * resolution_scale)
	if _viewport.size != size:
		_viewport.size = size
	_camera.fov = main.fov
	_camera.near = main.near
	_camera.far = main.far
	# The camera's own environment, or else the scene's (WorldEnvironment), as the main pass uses.
	var source := main.environment if main.environment != null else main.get_world_3d().environment
	_camera.environment = _mirror_environment(source, delta)
	# Mirror across the plane, then flip the camera's local Y back so its basis is a proper rotation.
	# The image ends up upside down, which the shader undoes by sampling at (u, 1 - v).
	var mirror := Transform3D(Basis(Vector3.RIGHT, Vector3.DOWN, Vector3.BACK), Vector3(0, 2.0 * plane_height, 0))
	var t := mirror * main.global_transform
	t.basis = t.basis * Basis.from_scale(Vector3(1, -1, 1))
	_camera.global_transform = t


## The main environment without the post-processing the main pass applies to the whole picture.
## Copied when the main camera's environment changes and every ENVIRONMENT_REFRESH seconds after.
func _mirror_environment(source: Environment, delta: float) -> Environment:
	if source == null:
		return null
	_environment_age += delta
	if source == _environment_source and _environment_age < ENVIRONMENT_REFRESH:
		return _environment
	_environment_source = source
	_environment_age = 0.0
	copy_environment(source, _environment)
	return _environment


## Copies `source` into `target` as a mirror needs it: everything but the main pass's post-processing,
## and a linear tone map at exposure 1.
static func copy_environment(source: Environment, target: Environment) -> void:
	for property: Dictionary in source.get_property_list():
		var usage: int = property.usage
		var property_name: String = property.name
		if (usage & PROPERTY_USAGE_STORAGE) == 0 or StringName(property_name) in MAIN_PASS_ONLY:
			continue
		target.set(property_name, source.get(property_name))
	target.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	target.tonemap_exposure = 1.0
	target.glow_enabled = false
	target.adjustment_enabled = false

