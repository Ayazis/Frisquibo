class_name IslandRiver
extends Node3D
## The island's river: from the pond east to the sea, its surface following the falling water level.
## A baked RiverFlowField gives the current, foam and standing waves around boulders; floating objects
## ride the same field. Reflects the sky only (sloping water has no mirror plane).

const RIVER_SHADER := preload("res://world/water/river/river.gdshader")
const FLOW_SPEED := 1.4
const FLOW_TEXELS_PER_METRE := 3.0
## Room either side of the meander for the flow field.
const SIDE_MARGIN := 9.0
## Surface vertices per metre, so bow and standing waves have geometry to bend.
const SURFACE_DENSITY := 2.0
const ROCK_COUNT := 7
const ROCK_COLOR := Color(0.32, 0.31, 0.29)
const ROCK_RADIUS := Vector2(0.45, 0.9)
## Boulders are ellipsoids this many radii tall, sunk this many radii into the bed.
const ROCK_HEIGHT_RADII := 3.0
const ROCK_SINK_RADII := 0.4
const ROCK_TILT := 0.15
## Keep boulders out of the first and last stretch, so the outlet and the mouth stay open.
const ROCK_CLEAR_ENDS := 15.0

var _terrain: IslandTerrain
var _field: RiverFlowField


func _init(terrain: IslandTerrain) -> void:
	_terrain = terrain


func _ready() -> void:
	var area := _area()
	var rocks := _make_rocks()
	_field = RiverFlowField.new(area, FLOW_TEXELS_PER_METRE, _terrain.river_centre, IslandTerrain.RIVER_HALF_WIDTH,
			FLOW_SPEED, rocks)
	_make_surface(area)


## Water surface height at `xz`, inside the river.
func height_at(xz: Vector2) -> float:
	return _terrain.river_level(xz.x) + _field.height_at(xz)


## Current at `xz` (m/s), inside the river.
func velocity_at(xz: Vector2) -> Vector3:
	return _field.velocity_at(xz)


func _area() -> Rect2:
	var start := IslandTerrain.RIVER_START_X
	var end := _terrain.river_end_x()
	var centre := IslandTerrain.POND_CENTRE.y
	var half := IslandTerrain.RIVER_MEANDER + IslandTerrain.RIVER_BANK_DISTANCE + SIDE_MARGIN
	return Rect2(start, centre - half, end - start, half * 2.0)


func _make_surface(area: Rect2) -> void:
	# A ribbon along the meander, reaching under the banks on both sides, at the falling water level.
	var along := ceili(area.size.x * SURFACE_DENSITY)
	var across := ceili(IslandTerrain.RIVER_BANK_DISTANCE * 2.0 * SURFACE_DENSITY)
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for iz in range(across + 1):
		var offset := (float(iz) / across - 0.5) * 2.0 * IslandTerrain.RIVER_BANK_DISTANCE
		for ix in range(along + 1):
			var x := area.position.x + area.size.x * ix / along
			vertices.append(Vector3(x, _terrain.river_level(x), _terrain.river_centre(x) + offset))
	var row := along + 1
	for iz in range(across):
		for ix in range(along):
			var i := iz * row + ix
			indices.append_array([i, i + 1, i + row, i + 1, i + row + 1, i + row])
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = RIVER_SHADER
	mat.set_shader_parameter("flow_map", _field.texture())
	mat.set_shader_parameter("flow_rect", Vector4(area.position.x, area.position.y, area.size.x, area.size.y))
	mat.set_shader_parameter("max_speed", FLOW_SPEED * 2.0)
	# Sloping water: no mirror plane, the sky reflection only.
	mat.set_shader_parameter("reflection_slot", -1)
	# Clear stream water, slightly green; foam comes from the flow field, not from shoreline bands.
	mat.set_shader_parameter("absorption", Vector3(0.95, 0.38, 0.5))
	mat.set_shader_parameter("scatter_color", Color(0.03, 0.1, 0.07))
	mat.set_shader_parameter("caustic_strength", 1.2)
	mat.set_shader_parameter("foam_amount", 0.9)
	mat.set_shader_parameter("foam_breakup", 0.0)
	mat.set_shader_parameter("crest_foam_strength", 1.0)
	mat.set_shader_parameter("shore_foam_strength", 0.2)
	mat.set_shader_parameter("shore_foam_width", 0.25)
	WaterTextures.apply(mat)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.layers = PlanarReflection.water_layer_mask()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


## Boulders in the channel (with collision); returns those that break the surface as
## (x, z, radius at the waterline) for the flow field.
func _make_rocks() -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var mat := WaterProp.material(ROCK_COLOR, 0.9)
	var breaking: Array[Vector3] = []
	var start := IslandTerrain.RIVER_START_X + ROCK_CLEAR_ENDS
	var end := _terrain.river_end_x() - ROCK_CLEAR_ENDS
	for i in range(ROCK_COUNT):
		var x := rng.randf_range(start, end)
		var z := _terrain.river_centre(x) + rng.randf_range(-1.0, 1.0) * IslandTerrain.RIVER_CHANNEL_HALF_WIDTH * 0.8
		var r := rng.randf_range(ROCK_RADIUS.x, ROCK_RADIUS.y)
		var half_height := r * ROCK_HEIGHT_RADII / 2.0
		var centre_y := _terrain.height(x, z) + half_height - r * ROCK_SINK_RADII
		var body := StaticBody3D.new()
		body.position = Vector3(x, centre_y, z)
		body.rotation = Vector3(rng.randf() - 0.5, rng.randf() * TAU, rng.randf() - 0.5) * ROCK_TILT
		var sphere := SphereMesh.new()
		sphere.radius = r
		sphere.height = half_height * 2.0
		sphere.material = mat
		var instance := MeshInstance3D.new()
		instance.mesh = sphere
		body.add_child(instance)
		var shape := CylinderShape3D.new()
		shape.radius = r
		shape.height = half_height * 2.0
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		add_child(body)
		# Ellipsoid cross-section at the water level here.
		var t := (_terrain.river_level(x) - centre_y) / half_height
		if absf(t) < 1.0:
			breaking.append(Vector3(x, z, r * sqrt(1.0 - t * t)))
	return breaking
