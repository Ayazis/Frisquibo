class_name OceanBreakers
extends Node3D
## Ribbons for plunging breakers: strips of the ocean's own surface laid along the crests near the camera,
## fine across each crest where its curl needs the detail (ocean_breakers.gdshaderinc). Each frame this
## finds the stretches of coast within reach of the camera and the crests on them that could be breaking,
## and gives each (stretch, crest) a ribbon from a pool. The ribbons share the ocean's material: what
## differs per ribbon are two instance uniforms.

## Metres beyond the curls' reach that a waterline point may lie and still get a ribbon: its crests run
## out to sea from there.
const RAY_MARGIN := 30.0
## Seconds of travel time added beyond where the biggest wave starts to break, so a ribbon covers its
## whole window.
const BREAK_MARGIN := 2.0
## Ribbons in the pool: stretches of coast times crests on them.
const MAX_RIBBONS := 16
## Metres above and below the sea the ribbons' bounds reach.
const ROOM := 30.0

## The ribbons laid this frame: (first row, rows, crest number, waterline), for the breaker effects.
var active: Array[Vector4] = []
## Crest numbers every stretch near the camera has a ribbon for (from, to): the ocean surface leaves holes
## for the curls of these crests only, so a crest without a ribbon is never left as a hole.
var covered := Vector2i(1, 0)

var _rays: ShoreRays
var _pool: Array[MeshInstance3D] = []
var _rows := 0
var _reach := 0.0
var _starts := PackedVector2Array()
var _timing := PackedFloat32Array()
var _start_times := PackedFloat32Array()


## `reach`: metres from the camera curls are drawn within; `segments`: quads across each ribbon;
## `bounds`: world box the ribbons stay in (the seabed area).
func _init(rays: ShoreRays, material: ShaderMaterial, reach: float, segments: int, bounds: AABB) -> void:
	_rays = rays
	_reach = reach
	_rows = ceili(2.0 * (reach + RAY_MARGIN) / ShoreRays.SPACING) + 1
	var mesh := ribbon_mesh(_rows, segments)
	var room := bounds.grow(ROOM)
	for i in range(MAX_RIBBONS):
		var ribbon := MeshInstance3D.new()
		ribbon.mesh = mesh
		ribbon.material_override = material
		ribbon.custom_aabb = room
		ribbon.layers = PlanarReflection.water_layer_mask()
		ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ribbon.visible = false
		add_child(ribbon)
		_pool.append(ribbon)
	_starts.resize(rays.rows)
	_timing.resize(rays.rows)
	_start_times.resize(rays.rows)
	for row in range(rays.rows):
		var start := rays.image.get_pixel(0, row)
		_starts[row] = Vector2(start.r, start.g)
		_start_times[row] = start.b
		_timing[row] = ShoreWaves.noise(_starts[row] / ShoreWaves.SWASH_ALONGSHORE) * ShoreWaves.SWASH_PHASE_SPREAD


## A grid of `rows` by `segments` quads whose vertices carry (row, 0, share across) for the shader.
static func ribbon_mesh(rows: int, segments: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for row in range(rows):
		for k in range(segments + 1):
			vertices.append(Vector3(row, 0.0, float(k) / segments))
	for row in range(rows - 1):
		for k in range(segments):
			var a := row * (segments + 1) + k
			var b := a + segments + 1
			indices.append_array(PackedInt32Array([a, b, a + 1, a + 1, b, b + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Lays the ribbons for a camera at `camera_xz`, at wave clock `time`, with crests `period` apart, for
## crests that may break in water up to `break_depth` deep.
func update(camera_xz: Vector2, time: float, period: float, break_depth: float) -> void:
	active.clear()
	var cycle := maxf(period, 0.1)
	var runs := _runs(camera_xz)
	covered = Vector2i(-2147483648, 2147483647) if not runs.is_empty() else Vector2i(1, 0)
	for run: Vector3i in runs:
		var line := run.x
		var first := run.y
		var count := run.z
		var lo := INF
		var hi := -INF
		var earliest := INF
		for k in range(count):
			var row := _row(line, first + k)
			lo = minf(lo, _timing[row])
			hi = maxf(hi, _timing[row])
			earliest = minf(earliest, _start_times[row])
		var middle := _row(line, first + count / 2)
		var latest := _rays.time_to_depth(middle, break_depth) + BREAK_MARGIN
		# Crest n is at travel time (n - timing) * period - time: from just behind the waterline out to
		# where the biggest wave starts to break.
		var n_from := ceili((time + earliest) / cycle + lo - 0.5)
		var n_to := floori((time + latest) / cycle + hi)
		var laid_to := n_from - 1
		for n in range(n_from, n_to + 1):
			if active.size() >= MAX_RIBBONS:
				break
			active.append(Vector4(_row(line, first), count, n, line))
			laid_to = n
		covered = Vector2i(maxi(covered.x, n_from), mini(covered.y, laid_to))
	for i in range(_pool.size()):
		var ribbon := _pool[i]
		ribbon.visible = i < active.size()
		if not ribbon.visible:
			continue
		var lay := active[i]
		var line := int(lay.w)
		ribbon.set_instance_shader_parameter(&"breaker_ribbon", Vector4(lay.x, _rays.line_starts[line],
				_rays.line_lengths[line], 1.0 if _rays.line_closed[line] else 0.0))
		ribbon.set_instance_shader_parameter(&"breaker_span", Vector2(lay.z, lay.y))


## Travel time where crest number `wave` stands on `row` at wave clock `time` (ocean_shore_waves: crest n
## is where (time + T) / period + timing = n).
func crest_time(row: int, wave: float, time: float, period: float) -> float:
	return (wave - _timing[row]) * maxf(period, 0.1) - time


## Global row `steps` rows on from global row `first` along its waterline (wrapping round a closed line).
func row_after(first: int, steps: int) -> int:
	var line := _rays.line_of(first).x
	return _row(line, first - _rays.line_starts[line] + steps)


## Global row of index `index` along waterline `line` (wrapping round a closed line).
func _row(line: int, index: int) -> int:
	var length := _rays.line_lengths[line]
	var local := posmod(index, length) if _rays.line_closed[line] else clampi(index, 0, length - 1)
	return _rays.line_starts[line] + local


## Stretches of waterline near the camera: (line, first index along it, rows), each at most a ribbon long.
func _runs(camera_xz: Vector2) -> Array[Vector3i]:
	var runs: Array[Vector3i] = []
	var limit := _reach + RAY_MARGIN
	for line in range(_rays.line_starts.size()):
		var start := _rays.line_starts[line]
		var length := _rays.line_lengths[line]
		var near := PackedByteArray()
		near.resize(length)
		for k in range(length):
			near[k] = 1 if _starts[start + k].distance_to(camera_xz) <= limit else 0
		var k := 0
		var stretches: Array[Vector2i] = []
		while k < length:
			if near[k] == 0:
				k += 1
				continue
			var from := k
			while k < length and near[k] == 1:
				k += 1
			stretches.append(Vector2i(from, k - from))
		# On a closed line a stretch through the end continues at the start.
		if _rays.line_closed[line] and stretches.size() > 1 and stretches[0].x == 0 \
				and stretches[-1].x + stretches[-1].y == length:
			var tail: Vector2i = stretches.pop_back()
			stretches[0] = Vector2i(tail.x, tail.y + stretches[0].y)
		for stretch: Vector2i in stretches:
			var offset := 0
			while offset < stretch.y:
				var count := mini(_rows, stretch.y - offset)
				runs.append(Vector3i(line, stretch.x + offset, count))
				offset += count
	return runs
