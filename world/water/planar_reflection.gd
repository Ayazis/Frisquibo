class_name PlanarReflection
extends Node
## Renders the scene mirrored in a horizontal water plane into a SubViewport and publishes it as the
## global shader texture `water_reflection`. Water shaders sample it with the screen UV (Y flipped).
## The water itself is on WATER_LAYER so the mirror camera doesn't see it. Desktop only: on the web
## this node disables itself and water falls back to the engine's sky reflection.

const WATER_LAYER := 20
## Terrain shaders discard fragments below this height while the mirror camera (below water) renders.
const CLIP_PARAM := &"water_reflection_clip_height"

@export var plane_height := 0.0
## Fraction of the main viewport resolution; lower is cheaper and softer.
@export_range(0.25, 1.0) var resolution_scale := 0.6

var _viewport: SubViewport
var _camera: Camera3D


static func water_layer_mask() -> int:
	return 1 << (WATER_LAYER - 1)


func _ready() -> void:
	if OS.has_feature("web") or RenderingServer.get_current_rendering_method() == "gl_compatibility":
		RenderingServer.global_shader_parameter_set(&"water_reflection_enabled", false)
		set_process(false)
		return
	_viewport = SubViewport.new()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.positional_shadow_atlas_size = 0
	_camera = Camera3D.new()
	_camera.cull_mask = ~water_layer_mask()
	_viewport.add_child(_camera)
	add_child(_viewport)
	RenderingServer.global_shader_parameter_set(CLIP_PARAM, plane_height)
	RenderingServer.global_shader_parameter_set(&"water_reflection", _viewport.get_texture())
	RenderingServer.global_shader_parameter_set(&"water_reflection_enabled", true)


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set(&"water_reflection_enabled", false)


func _process(_delta: float) -> void:
	var main := get_viewport().get_camera_3d()
	if main == null:
		return
	var size := Vector2i(Vector2(get_viewport().get_visible_rect().size) * resolution_scale)
	if _viewport.size != size:
		_viewport.size = size
	_camera.fov = main.fov
	_camera.near = main.near
	_camera.far = main.far
	_camera.environment = main.environment
	# Mirror across the plane, then flip the camera's local Y back so its basis is a proper rotation.
	# The image ends up upside down, which the shader undoes by sampling at (u, 1 - v).
	var mirror := Transform3D(Basis(Vector3.RIGHT, Vector3.DOWN, Vector3.BACK), Vector3(0, 2.0 * plane_height, 0))
	var t := mirror * main.global_transform
	t.basis = t.basis * Basis.from_scale(Vector3(1, -1, 1))
	_camera.global_transform = t
