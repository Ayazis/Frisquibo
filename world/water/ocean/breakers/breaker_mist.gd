class_name BreakerMist
extends MeshInstance3D
## Mist over plunging breakers: one faint, rising sheet along each line where lips are landing, rebuilt
## from BreakerEffects' points each frame (breaker_mist.gdshader).

const SHADER := preload("res://world/water/ocean/breakers/breaker_mist.gdshader")
## Mist rises to this many breaking crest heights...
const HEIGHT := 3.0
## ...and leans downwind by this share of its height.
const LEAN := 0.3

var _immediate := ImmediateMesh.new()
var _material := ShaderMaterial.new()


func _init(bounds: AABB) -> void:
	mesh = _immediate
	_material.shader = SHADER
	_material.set_shader_parameter("pattern", WaterTextures.foam())
	material_override = _material
	custom_aabb = bounds
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	layers = PlanarReflection.water_layer_mask()


## Rebuilds the sheets. `lines`: per breaking crest, its points along the coast (landing points), and
## per point the crest height and how hard it is plunging (0..1). `wind`: direction * m/s.
func set_lines(lines: Array[PackedVector3Array], heights: Array[PackedFloat32Array],
		strengths: Array[PackedFloat32Array], wind: Vector2) -> void:
	_immediate.clear_surfaces()
	_material.set_shader_parameter("drift", wind * 0.3)
	var lean := Vector3(wind.x, 0.0, wind.y).normalized() * LEAN if wind.length_squared() > 0.0 else Vector3.ZERO
	var drawn := false
	for i in range(lines.size()):
		var points := lines[i]
		if points.size() < 2:
			continue
		if not drawn:
			_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			drawn = true
		for k in range(points.size() - 1):
			_quad(points[k], points[k + 1], heights[i][k], heights[i][k + 1], strengths[i][k], strengths[i][k + 1], lean)
	if drawn:
		_immediate.surface_end()


func _quad(a: Vector3, b: Vector3, ha: float, hb: float, sa: float, sb: float, lean: Vector3) -> void:
	var top_a := a + (Vector3.UP + lean) * ha * HEIGHT
	var top_b := b + (Vector3.UP + lean) * hb * HEIGHT
	for corner: Array in [[a, 0.0, sa], [b, 0.0, sb], [top_b, 1.0, sb], [a, 0.0, sa], [top_b, 1.0, sb], [top_a, 1.0, sa]]:
		var strength: float = corner[2]
		var height: float = corner[1]
		var at: Vector3 = corner[0]
		_immediate.surface_set_color(Color(1.0, 1.0, 1.0, strength))
		_immediate.surface_set_uv(Vector2(0.0, height))
		_immediate.surface_set_normal(Vector3.UP)
		_immediate.surface_add_vertex(at)
