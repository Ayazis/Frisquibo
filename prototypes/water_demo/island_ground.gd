class_name IslandGround
extends RefCounted
## Builds the island's ground: a radial mesh centred on the island (fine rings along the coast where
## the beach and surf need detail, coarser far out at sea) and a height-map collision over the island
## and its shallows.

const GROUND_SHADER := preload("res://world/terrain/terrain_ground.gdshader")
## Segments around the island.
const SEGMENTS := 768
## Web build: GDScript runs several times slower there, so the ground is built coarser (half the
## segments, rings WEB_RING_STRETCH times wider) to keep the load time reasonable. Desktop keeps it all.
const WEB_SEGMENTS := 384
const WEB_RING_STRETCH := 2.0
## Ring spacing (m): inland, across the coast band, and how fast it grows beyond the coast.
const INLAND_SPACING := 1.0
const COAST_SPACING := 0.5
const COAST_BAND := Vector2(115.0, 190.0)
const OFFSHORE_GROWTH := 0.015
## The mesh reaches this far out to sea; beyond it the seabed is too deep to see.
const OUTER_RADIUS := 1000.0
## Collision: cell size and how far from the centre it reaches (objects only matter near the island).
const COLLISION_CELL := 2.0
const COLLISION_RADIUS := 300.0


static func build_mesh(terrain: IslandTerrain) -> MeshInstance3D:
	var radii := ring_radii()
	var rings := radii.size()
	var segments := segment_count()
	var vertices := PackedVector3Array()
	vertices.resize(rings * segments + 1)
	var directions := PackedVector2Array()
	directions.resize(segments)
	for j in range(segments):
		var a := TAU * j / segments
		directions[j] = Vector2(cos(a), sin(a))
	for i in range(rings):
		for j in range(segments):
			var p := directions[j] * radii[i]
			vertices[i * segments + j] = Vector3(p.x, terrain.height(p.x, p.y), p.y)
	var centre := rings * segments
	vertices[centre] = Vector3(0.0, terrain.height(0.0, 0.0), 0.0)
	var indices := PackedInt32Array()
	for j in range(segments):
		var next := (j + 1) % segments
		indices.append_array([centre, j, next])
	for i in range(rings - 1):
		for j in range(segments):
			var next := (j + 1) % segments
			var a := i * segments + j
			var b := (i + 1) * segments + j
			var c := i * segments + next
			var d := (i + 1) * segments + next
			indices.append_array([a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals(vertices, rings, segments)
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := ShaderMaterial.new()
	material.shader = GROUND_SHADER
	material.set_shader_parameter("sea_level", IslandTerrain.SEA_LEVEL)
	material.set_shader_parameter("beach_top", IslandTerrain.BEACH_TOP)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	return instance


## Segments around the island (fewer on the web).
static func segment_count() -> int:
	return WEB_SEGMENTS if OS.has_feature("web") else SEGMENTS


## Radius of each ring, from the centre outwards.
static func ring_radii() -> PackedFloat32Array:
	var radii := PackedFloat32Array()
	var r := INLAND_SPACING
	while r < OUTER_RADIUS:
		radii.append(r)
		r += spacing(r) * (WEB_RING_STRETCH if OS.has_feature("web") else 1.0)
	radii.append(OUTER_RADIUS)
	return radii


## Distance to the next ring at radius r.
static func spacing(r: float) -> float:
	if r < COAST_BAND.x:
		return lerpf(INLAND_SPACING, COAST_SPACING, smoothstep(COAST_BAND.x - 15.0, COAST_BAND.x, r))
	if r < COAST_BAND.y:
		return COAST_SPACING
	return COAST_SPACING + (r - COAST_BAND.y) * OFFSHORE_GROWTH


static func build_collision(terrain: IslandTerrain) -> StaticBody3D:
	var size := int(2.0 * COLLISION_RADIUS / COLLISION_CELL) + 1
	var data := PackedFloat32Array()
	data.resize(size * size)
	for iz in range(size):
		for ix in range(size):
			var x := -COLLISION_RADIUS + ix * COLLISION_CELL
			var z := -COLLISION_RADIUS + iz * COLLISION_CELL
			# The shape is scaled uniformly by the cell size, so heights are stored in cells too.
			data[iz * size + ix] = terrain.height(x, z) / COLLISION_CELL
	var shape := HeightMapShape3D.new()
	shape.map_width = size
	shape.map_depth = size
	shape.map_data = data
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.scale = Vector3.ONE * COLLISION_CELL
	var body := StaticBody3D.new()
	body.add_child(collision)
	return body


## Per-vertex normals from the neighbouring vertices along the ring and across the rings.
static func _normals(vertices: PackedVector3Array, rings: int, segments: int) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for i in range(rings):
		var inner := maxi(i - 1, 0)
		var outer := mini(i + 1, rings - 1)
		for j in range(segments):
			var along := vertices[i * segments + (j + 1) % segments] - vertices[i * segments + (j + segments - 1) % segments]
			var across := vertices[outer * segments + j] - vertices[inner * segments + j]
			var n := along.cross(across).normalized()
			normals[i * segments + j] = n if n.y >= 0.0 else -n
	normals[vertices.size() - 1] = Vector3.UP
	return normals
