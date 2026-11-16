class_name OceanSpray
extends GPUParticles3D
## Spray blown off breaking crests in strong wind, droplets and veils of spindrift, around the camera (ocean_spray.gdshader decides where
## and when from the FFT ocean's own foam and displacement). Desktop only: the Ocean makes one when its
## quality tier asks for spray particles.

const PROCESS_SHADER := preload("res://world/water/ocean/ocean_spray.gdshader")
## Seconds a droplet can fly before it is reused.
const LIFETIME := 2.5
## Texture of one droplet: a soft round dot.
const DOT_SIZE := 32
const DROPLET_COLOR := Color(0.92, 0.95, 0.96, 0.8)
const DROPLET_ROUGHNESS := 0.4
## Room above the sea the droplets may fly in, for culling.
const FLIGHT_HEIGHT := 20.0

var process_shader_material: ShaderMaterial


func _init(particle_count: int, area: float) -> void:
	amount = particle_count
	lifetime = LIFETIME
	explosiveness = 0.0
	randomness = 1.0
	# Particles live in world space: moving the emitter with the camera leaves flying spray alone.
	local_coords = false
	visibility_aabb = AABB(Vector3(-area, -FLIGHT_HEIGHT, -area), Vector3(area, FLIGHT_HEIGHT, area) * 2.0)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	process_shader_material = ShaderMaterial.new()
	process_shader_material.shader = PROCESS_SHADER
	process_shader_material.set_shader_parameter("area_size", area)
	process_material = process_shader_material
	draw_pass_1 = _droplet_mesh()


## The FFT ocean's maps the spray reads to find breaking crests.
func set_waves(displacement: Texture, moments: Texture, tile_lengths: PackedFloat32Array, cascade_count: int) -> void:
	process_shader_material.set_shader_parameter("displacement_maps", displacement)
	process_shader_material.set_shader_parameter("moment_maps", moments)
	process_shader_material.set_shader_parameter("tile_lengths", tile_lengths)
	process_shader_material.set_shader_parameter("cascade_count", cascade_count)


## Wind (direction * m/s), the sea's rest level, how much the smaller waves' breaking counts, and
## the amount of spray relative to the natural one.
func set_sea(wind: Vector2, sea_level: float, foam_falloff: float, amount: float) -> void:
	process_shader_material.set_shader_parameter("wind", wind)
	process_shader_material.set_shader_parameter("sea_level", sea_level)
	process_shader_material.set_shader_parameter("foam_falloff", foam_falloff)
	process_shader_material.set_shader_parameter("spray_amount", amount)


## Centres the spray area on the camera.
func follow(camera_position: Vector3) -> void:
	global_position = camera_position
	process_shader_material.set_shader_parameter("area_centre", Vector2(camera_position.x, camera_position.z))


static func _droplet_mesh() -> QuadMesh:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var dot := GradientTexture2D.new()
	dot.gradient = gradient
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.width = DOT_SIZE
	dot.height = DOT_SIZE
	var material := StandardMaterial3D.new()
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.albedo_color = DROPLET_COLOR
	material.albedo_texture = dot
	material.roughness = DROPLET_ROUGHNESS
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	var mesh := QuadMesh.new()
	mesh.material = material
	return mesh
