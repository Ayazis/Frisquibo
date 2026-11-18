class_name BreakerSpray
extends GPUParticles3D
## Spray of plunging breakers: droplets off the lip tips and up from where the lips land, drawn as thin
## streaks along their motion (breaker_droplet.gdshader). Where and how much comes from the emitters
## BreakerEffects finds on the CPU each frame (breaker_spray.gdshader).

const PROCESS_SHADER := preload("res://world/water/ocean/breakers/breaker_spray.gdshader")
const DROPLET_SHADER := preload("res://world/water/ocean/breakers/breaker_droplet.gdshader")
## Most emitters listed per frame.
const MAX_EMITTERS := 128
## Seconds a droplet can fly.
const LIFETIME := 1.6

var process_shader_material: ShaderMaterial
var _emitters: Image
var _texture: ImageTexture


func _init(particle_count: int, bounds: AABB) -> void:
	amount = particle_count
	lifetime = LIFETIME
	explosiveness = 0.0
	randomness = 1.0
	local_coords = false
	visibility_aabb = bounds
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	layers = PlanarReflection.water_layer_mask()
	process_shader_material = ShaderMaterial.new()
	process_shader_material.shader = PROCESS_SHADER
	process_shader_material.set_shader_parameter("lifetime", LIFETIME)
	process_material = process_shader_material
	_emitters = Image.create(MAX_EMITTERS, 2, false, Image.FORMAT_RGBAF)
	_texture = ImageTexture.create_from_image(_emitters)
	process_shader_material.set_shader_parameter("emitters", _texture)
	var droplet := ShaderMaterial.new()
	droplet.shader = DROPLET_SHADER
	var quad := QuadMesh.new()
	quad.material = droplet
	draw_pass_1 = quad


## This frame's emitters: per emitter a position, a rate (0..1 share of restarts it takes), a velocity
## and a droplet size factor.
func set_emitters(positions: PackedVector3Array, rates: PackedFloat32Array, velocities: PackedVector3Array,
		sizes: PackedFloat32Array) -> void:
	var count := mini(positions.size(), MAX_EMITTERS)
	for i in range(count):
		var p := positions[i]
		var v := velocities[i]
		_emitters.set_pixel(i, 0, Color(p.x, p.y, p.z, rates[i]))
		_emitters.set_pixel(i, 1, Color(v.x, v.y, v.z, sizes[i]))
	_texture.update(_emitters)
	process_shader_material.set_shader_parameter("emitter_count", count)


func set_sea_level(value: float) -> void:
	process_shader_material.set_shader_parameter("sea_level", value)
