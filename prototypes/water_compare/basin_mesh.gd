class_name BasinMesh
extends RefCounted
## Builds a ground grid mesh plus matching collision-free MeshInstance3D from a height function.

const GROUND_SHADER := preload("res://world/terrain/terrain_ground.gdshader")


## `height` takes (x: float, z: float) and returns float. `cells` is the grid resolution per axis.
static func build(size: Vector2, cells: Vector2i, height: Callable) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := size / Vector2(cells)
	var origin := -size / 2.0
	for iz in range(cells.y + 1):
		for ix in range(cells.x + 1):
			var x := origin.x + ix * step.x
			var z := origin.y + iz * step.y
			var y: float = height.call(x, z)
			st.add_vertex(Vector3(x, y, z))
	var row := cells.x + 1
	for iz in range(cells.y):
		for ix in range(cells.x):
			var i := iz * row + ix
			st.add_index(i); st.add_index(i + 1); st.add_index(i + row)
			st.add_index(i + 1); st.add_index(i + row + 1); st.add_index(i + row)
	st.generate_normals()
	var mat := ShaderMaterial.new()
	mat.shader = GROUND_SHADER
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	return mi
