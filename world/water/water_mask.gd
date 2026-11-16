class_name WaterMask
extends MeshInstance3D
## Keeps water out of a dry space that is open to the sky, such as the inside of an open boat. The mesh
## covers the opening (a lid along the gunwale) and is drawn invisibly, before any water, writing only
## depth: water seen through the opening is behind it and doesn't draw, water in front of it still does.
## Add it as a child of the hull so it moves with it.

const SHADER := preload("res://world/water/water_mask.gdshader")
## Before the water surfaces (render priority 0), after the underwater view (UnderwaterView).
const RENDER_PRIORITY := -5

static var _material: ShaderMaterial


func _init(opening: Mesh = null) -> void:
	mesh = opening
	material_override = shared_material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# On the water's layer, which the mirror cameras leave out: the mask has nothing to hide there.
	layers = PlanarReflection.water_layer_mask()


static func shared_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.render_priority = RENDER_PRIORITY
	return _material


## A lid between two rims of an opening, such as the port and starboard gunwales of a hull from bow
## to stern. The rims are joined point by point, so give both the same number of points.
static func lid(port: PackedVector3Array, starboard: PackedVector3Array) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_normal(Vector3.UP)
	for i in range(mini(port.size(), starboard.size()) - 1):
		for v: Vector3 in [port[i], port[i + 1], starboard[i + 1], port[i], starboard[i + 1], starboard[i]]:
			surface.add_vertex(v)
	return surface.commit()
