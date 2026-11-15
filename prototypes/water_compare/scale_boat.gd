class_name ScaleBoat
extends RigidBody3D
## An 8 m medieval fishing boat with a mast and a square sail, built from code, floating on the
## ocean: something of known size to judge wave height by. Prototype only.

const LENGTH := 8.0
const BEAM := 2.4
## Keel to gunwale amidships; the ends rise by SHEER_RISE.
const HULL_DEPTH := 1.2
const SHEER_RISE := 0.45
## Sharpness of bow and stern: lower makes fuller ends.
const END_FULLNESS := 0.6
const STATIONS := 24
const SECTION_POINTS := 12
const MAST_HEIGHT := 7.0
const MAST_RADIUS := 0.1
const SAIL_SIZE := Vector3(0.04, 3.2, 3.6)
const SAIL_BOTTOM := 2.0
const BOAT_MASS := 1500.0
## Buoyancy probes along the bottom: STATIONS_PROBED along the keel, on both sides of it.
const PROBE_STATIONS := 4
const PROBE_SIDE := 0.8
const PROBE_HEIGHT := -0.45
## Volume that sinks the boat to about its waterline (mass / water density, doubled because the
## probes are only half under water at rest).
const DISPLACED_VOLUME := 3.0
const IMMERSION_DEPTH := 1.0
const HULL_COLOR := Color(0.24, 0.15, 0.08)
const MAST_COLOR := Color(0.3, 0.2, 0.1)
const SAIL_COLOR := Color(0.78, 0.72, 0.6)
const WOOD_ROUGHNESS := 0.85
const SAIL_ROUGHNESS := 0.95


func _init(water_height: Callable) -> void:
	mass = BOAT_MASS
	var hull := MeshInstance3D.new()
	hull.mesh = _hull_mesh()
	hull.material_override = WaterProp.material(HULL_COLOR, WOOD_ROUGHNESS)
	add_child(hull)
	var mast := MeshInstance3D.new()
	var mast_mesh := CylinderMesh.new()
	mast_mesh.top_radius = MAST_RADIUS * 0.6
	mast_mesh.bottom_radius = MAST_RADIUS
	mast_mesh.height = MAST_HEIGHT
	mast_mesh.material = WaterProp.material(MAST_COLOR, WOOD_ROUGHNESS)
	mast.mesh = mast_mesh
	mast.position.y = MAST_HEIGHT / 2.0 - HULL_DEPTH / 2.0
	add_child(mast)
	var sail := MeshInstance3D.new()
	var sail_mesh := BoxMesh.new()
	sail_mesh.size = SAIL_SIZE
	sail_mesh.material = WaterProp.material(SAIL_COLOR, SAIL_ROUGHNESS)
	sail.mesh = sail_mesh
	sail.position = Vector3(MAST_RADIUS * 2.0, SAIL_BOTTOM + SAIL_SIZE.y / 2.0, 0.0)
	add_child(sail)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(LENGTH * 0.9, HULL_DEPTH, BEAM * 0.9)
	collision.shape = box
	add_child(collision)
	var buoyancy := Buoyancy.new()
	buoyancy.body = self
	buoyancy.water_height = water_height
	buoyancy.displaced_volume = DISPLACED_VOLUME
	buoyancy.immersion_depth = IMMERSION_DEPTH
	var probes := PackedVector3Array()
	for i: int in range(PROBE_STATIONS):
		var x := (float(i) / (PROBE_STATIONS - 1) - 0.5) * LENGTH * 0.7
		probes.append(Vector3(x, PROBE_HEIGHT, -PROBE_SIDE))
		probes.append(Vector3(x, PROBE_HEIGHT, PROBE_SIDE))
	buoyancy.probes = probes
	add_child(buoyancy)


## The hull lofted through cross-sections along x: U-shaped, pointed at both ends, open on top,
## drawn from both sides so its inside shows too.
static func _hull_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	for s: int in range(STATIONS + 1):
		var t := float(s) / STATIONS
		var x := (t - 0.5) * LENGTH
		var fullness := pow(sin(PI * t), END_FULLNESS)
		var half_width := BEAM / 2.0 * fullness
		var top := HULL_DEPTH / 2.0 + SHEER_RISE * pow(2.0 * t - 1.0, 2.0)
		var bottom := -HULL_DEPTH / 2.0 * sqrt(fullness)
		var ring := PackedVector3Array()
		for p: int in range(SECTION_POINTS + 1):
			var a := PI * float(p) / SECTION_POINTS
			ring.append(Vector3(x, top - (top - bottom) * pow(sin(a), 0.7), half_width * cos(a)))
		rings.append(ring)
	for s: int in range(STATIONS):
		for p: int in range(SECTION_POINTS):
			var a := rings[s][p]
			var b := rings[s + 1][p]
			var c := rings[s + 1][p + 1]
			var d := rings[s][p + 1]
			for triangle: PackedVector3Array in [PackedVector3Array([a, b, c]), PackedVector3Array([a, c, d]),
					PackedVector3Array([a, c, b]), PackedVector3Array([a, d, c])]:
				# Flat normals: averaging would cancel out between the outside and the inside face.
				surface.set_normal((triangle[2] - triangle[0]).cross(triangle[1] - triangle[0]).normalized())
				for v: Vector3 in triangle:
					surface.add_vertex(v)
	return surface.commit()
