class_name OceanSurfaceMesh
extends RefCounted
## Camera-centred polar grid for the ocean surface: rings whose radius grows by (1 + TAU / segments)
## each step, so every cell stays square and covers roughly the same screen area out to the horizon.
## No LOD seams, no T-junctions, no popping. The ocean keeps it centred under the camera.

## Vertical room in the bounding box for waves, so the mesh is never culled while it is displaced.
const WAVE_HEADROOM := 50.0


static func build(segments: int, inner_radius: float, far_radius: float) -> ArrayMesh:
	var growth := 1.0 + TAU / segments
	var radii := PackedFloat32Array()
	var r := inner_radius
	while r < far_radius:
		radii.append(r)
		r *= growth
	radii.append(far_radius)

	var vertices := PackedVector3Array()
	vertices.resize(1 + radii.size() * segments)
	vertices[0] = Vector3.ZERO
	for ring in range(radii.size()):
		for s in range(segments):
			var angle := TAU * s / segments
			vertices[1 + ring * segments + s] = Vector3(cos(angle), 0.0, sin(angle)) * radii[ring]

	# Clockwise seen from above, so the top side is the front face.
	var indices := PackedInt32Array()
	indices.resize(segments * 3 + (radii.size() - 1) * segments * 6)
	var n := 0
	for s in range(segments):
		indices[n] = 0
		indices[n + 1] = 1 + s
		indices[n + 2] = 1 + (s + 1) % segments
		n += 3
	for ring in range(radii.size() - 1):
		var inner := 1 + ring * segments
		var outer := inner + segments
		for s in range(segments):
			var s1 := (s + 1) % segments
			indices[n] = inner + s
			indices[n + 1] = outer + s
			indices[n + 2] = inner + s1
			indices[n + 3] = inner + s1
			indices[n + 4] = outer + s
			indices[n + 5] = outer + s1
			n += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.custom_aabb = AABB(Vector3(-far_radius, -WAVE_HEADROOM, -far_radius),
			Vector3(far_radius * 2.0, WAVE_HEADROOM * 2.0, far_radius * 2.0))
	return mesh
