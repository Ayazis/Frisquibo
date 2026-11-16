class_name UnderwaterView
extends Node
## Draws what the camera sees while its lens is under water: absorption and in-scatter over distance,
## blur, the waterline across the lens and light shafts (underwater.gdshader on a full-screen quad).
## The water body that owns it calls follow() every frame with the surface at the camera.

const SHADER := preload("res://world/water/underwater/underwater.gdshader")
## Below the water surface's own priority (0), so the screen copy it reads holds only the opaque scene
## and the surface, which shades itself from below, draws over it.
const RENDER_PRIORITY := -10
## The vertex shader spans the quad's -1..1 over the whole screen.
const QUAD_SIZE := Vector2(2.0, 2.0)
## The quad moves with the camera, but frustum culling must never drop it.
const CULL_MARGIN := 16384.0
## Lakes and rivers have no quality tier: they use the High tier's value.
const DEFAULT_SHAFT_STEPS := 16
## Metres above the surface height at the camera where the lens may still touch a wave.
const DEFAULT_REACH := 1.0

## Ray-march steps of the light shafts; 0 turns them off.
@export_range(0, 64) var shaft_steps := DEFAULT_SHAFT_STEPS

var material: ShaderMaterial
var _quad: MeshInstance3D


func _init() -> void:
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.render_priority = RENDER_PRIORITY


func _ready() -> void:
	material.set_shader_parameter("caustic_texture", WaterTextures.caustics())
	# Web / Compatibility: no shafts (a ray march per pixel is too much for the web build).
	var steps := 0 if OS.has_feature("web") else shaft_steps
	material.set_shader_parameter("shaft_steps", steps)
	var mesh := QuadMesh.new()
	mesh.size = QUAD_SIZE
	_quad = MeshInstance3D.new()
	_quad.mesh = mesh
	_quad.material_override = material
	_quad.extra_cull_margin = CULL_MARGIN
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# On the water layer, so the planar reflection's mirror camera doesn't see it.
	_quad.layers = PlanarReflection.water_layer_mask()
	_quad.visible = false
	add_child(_quad)


## Colour of the water: light lost per metre per channel, and the radiance of deep water.
func set_optics(absorption: Vector3, deep_color: Color) -> void:
	material.set_shader_parameter("absorption", absorption)
	material.set_shader_parameter("deep_color", deep_color)


## Light on the seabed: caustic brightness (1 physical), extra fade per metre, and the share of the
## light the water absorbs on the way down (1 physical).
func set_seabed_light(caustic_strength: float, caustic_fade: float, light_loss: float) -> void:
	material.set_shader_parameter("caustic_strength", caustic_strength)
	material.set_shader_parameter("caustic_fade", caustic_fade)
	material.set_shader_parameter("seabed_light_loss", light_loss)


## FFT ocean only: the displacement and slope cascades, so the waterline on the lens follows the waves
## and the seabed gets their caustics.
func set_waves(displacement: Texture, slopes: Texture, tile_lengths: PackedFloat32Array, cascade_count: int,
		map_size: int) -> void:
	material.set_shader_parameter("displacement_maps", displacement)
	material.set_shader_parameter("slope_maps", slopes)
	material.set_shader_parameter("map_size", float(map_size))
	material.set_shader_parameter("tile_lengths", tile_lengths)
	material.set_shader_parameter("cascade_count", cascade_count)


## Places the effect on `camera`. surface_height: the water height at the camera, waves included;
## rest_level: the surface without waves; wave_scale: share of the cascade waves there (shore damping);
## reach: how far above surface_height the lens can still touch a wave.
func follow(camera: Camera3D, surface_height: float, rest_level: float, wave_scale: float, reach: float) -> void:
	if _quad == null:
		return
	if camera == null:
		_quad.visible = false
		return
	_quad.visible = camera.global_position.y < surface_height + reach
	if not _quad.visible:
		return
	_quad.global_position = camera.global_position
	material.set_shader_parameter("surface_level", rest_level)
	material.set_shader_parameter("wave_scale", wave_scale)


## True while the effect is drawn (the lens is at or below the water).
func is_active() -> bool:
	return _quad != null and _quad.visible
