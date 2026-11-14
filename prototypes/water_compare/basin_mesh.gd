class_name BasinMesh
extends RefCounted
## Builds a ground grid mesh plus matching collision-free MeshInstance3D from a height function.

const GROUND_SHADER := preload("res://world/terrain/terrain_ground.gdshader")


## `height` takes (x: float, z: float) and returns float. `cells` is the grid resolution per axis.
## `center` moves the grid. `z_spacing`, if valid, maps a row fraction (0..1) to a z fraction (0..1),
## to put more rows where detail matters (e.g. near a shoreline).
static func build(size: Vector2, cells: Vector2i, height: Callable, center := Vector2.ZERO,
		z_spacing := Callable()) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := size / Vector2(cells)
	var origin := center - size / 2.0
	for iz in range(cells.y + 1):
		var row := float(iz) / cells.y
		var z_fraction: float = z_spacing.call(row) if z_spacing.is_valid() else row
		var z := origin.y + z_fraction * size.y
		for ix in range(cells.x + 1):
			var x := origin.x + ix * step.x
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
