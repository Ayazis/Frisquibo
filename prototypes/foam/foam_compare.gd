extends Node3D
## Prototype: compares foam patterns on a gently rolling plane (see foam_compare.gdshader).

const PLANE_SIZE := 120.0
const PLANE_SUBDIVISIONS := 240
## ambientCG Foam00x (CC0), extracted locally into textures/ (not committed).
const SCAN_PATH := "res://build/foam_sources/ambientcg/Foam%s_8K-PNG_%s.png"

var _material: ShaderMaterial
var _sun: DirectionalLight3D
var _sky_material: ProceduralSkyMaterial


func _ready() -> void:
	WaterTextures.apply_foam_globals()
	_material = ShaderMaterial.new()
	_material.shader = load("res://prototypes/foam/foam_compare.gdshader") as Shader
	_material.set_shader_parameter("lace_tex", WaterTextures.lace())
	_material.set_shader_parameter("foam_tex", WaterTextures.foam())
	var plane := PlaneMesh.new()
	plane.size = Vector2(PLANE_SIZE, PLANE_SIZE)
	plane.subdivide_width = PLANE_SUBDIVISIONS
	plane.subdivide_depth = PLANE_SUBDIVISIONS
	var water := MeshInstance3D.new()
	water.mesh = plane
	water.material_override = _material
	add_child(water)

	_sun = DirectionalLight3D.new()
	var sun := _sun
	sun.rotation_degrees = Vector3(-35.0, 150.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)

	_sky_material = ProceduralSkyMaterial.new()
	var sky_material := _sky_material
	sky_material.sky_top_color = Color(0.35, 0.42, 0.5)
	sky_material.sky_horizon_color = Color(0.65, 0.68, 0.7)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func apply_visual_check_state(state: Dictionary) -> void:
	var variant: int = state.get("variant", 1)
	_material.set_shader_parameter("variant", variant)
	var scan: String = state.get("scan", "003")
	if variant == 3:
		_material.set_shader_parameter("tex_height", _scan(SCAN_PATH % [scan, "Displacement"]))
		_material.set_shader_parameter("tex_albedo", _scan(SCAN_PATH % [scan, "Color"]))
		_material.set_shader_parameter("tex_normal", _scan(SCAN_PATH % [scan, "NormalGL"]))
	if variant == 4:
		for i: int in range(1, 4):
			var id := "%03d" % i
			_material.set_shader_parameter("tex_height_%d" % i, _scan(SCAN_PATH % [id, "Displacement"]))
			_material.set_shader_parameter("tex_normal_%d" % i, _scan(SCAN_PATH % [id, "NormalGL"]))
	if variant == 5:
		var packed: String = state.get("packed", "")
		_material.set_shader_parameter("tex_packed", load(packed) as Texture2D)
	var fill: float = state.get("fill", 0.5)
	_material.set_shader_parameter("fixed_fill", fill)
	var overcast: bool = state.get("overcast", false)
	_sun.light_energy = 0.15 if overcast else 1.2
	_sky_material.sky_top_color = Color(0.4, 0.43, 0.47) if overcast else Color(0.35, 0.42, 0.5)


## The 8K ambientCG maps live in build/ (not imported): load them straight from disk.
func _scan(path: String) -> Texture2D:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
