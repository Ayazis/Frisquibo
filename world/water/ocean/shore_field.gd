class_name ShoreField
extends RefCounted
## Where waves near a coast travel and when they arrive: the travel time T to the waterline over the
## baked seabed, and its gradient. Waves in shallow water run at c = sqrt(g h), so they slow down over
## the shallows and their crests swing round to meet the beach (refraction) and bunch up (shoaling).
## Wave crests are the lines of equal travel time: T solves the eikonal equation |grad T| = 1 / c(h),
## here with the fast marching method (Sethian 1996), outwards from the waterline.
## Along the same rays it measures how they spread or gather (the refraction coefficient): waves
## heading for a headland bunch their energy up, waves heading into a bay spread it out.
## The shore waves (ShoreWaves on the CPU, ocean_shore_waves.gdshaderinc on the GPU) read it.

const GRAVITY := 9.81
## Metres per texel. The travel time is smooth, and its gradient is stored per texel, so a coarse grid
## is enough even for short waves at the waterline.
const DEFAULT_CELL := 3.0
## Deepest water the field covers. The shore waves fade in shallower than this, so nothing deeper reads it.
const MAX_DEPTH := 12.0
## The wave speed of this depth is used in shallower water, so the travel time stays finite at the waterline.
const MIN_DEPTH := 0.05
## Limits of the refraction coefficient. Where rays cross (behind an island, at a sharp headland) ray
## theory predicts infinite focusing; real waves diffract and spread it out.
const REFRACTION_MIN := 0.4
const REFRACTION_MAX := 2.0
## 3 x 3 smoothing passes over the rays' divergence: real waves diffract, so they don't follow bends of
## the coast smaller than about a wavelength (several cells); the passes average over about 2 * passes
## + 1 cells.
const DIVERGENCE_SMOOTHING := 3

## RGBA float per texel: travel time to the waterline (s), its gradient along x and z (s/m), and 1
## where the field holds (water up to MAX_DEPTH, and land touching it); 0 elsewhere.
var image: Image
## RGB float per texel: the point on the waterline (world x, z) the wave passing here will reach, and the
## refraction coefficient Kr = sqrt(b0 / b) here (b: spacing of neighbouring rays, b0: their spacing at
## the field's offshore edge). Anything that varies along the coast (the timing and size of each wave) is
## drawn from the waterline point, so it stays the same along a wave's path and matches the swash where
## it lands.
var origins: Image
var area: Rect2
var width := 0
var height := 0
# Working state of the bake.
var _depths := PackedFloat32Array()
var _times := PackedFloat32Array()
var _ends := PackedVector2Array()
var _known := PackedByteArray()
## Per cell, the neighbours the wave came from (-1: none) and the share of the x one.
var _up_x := PackedInt32Array()
var _up_z := PackedInt32Array()
var _up_share := PackedFloat32Array()
## Water cells in the order the march accepted them (rising travel time).
var _order := PackedInt32Array()


## Bakes the field over `area`. `depth_at` takes a world (x, z) as a Vector2 and returns the still
## water depth there in metres (negative or zero on land).
static func bake(depth_at: Callable, bake_area: Rect2, cell: float = DEFAULT_CELL) -> ShoreField:
	var field := ShoreField.new()
	field.area = bake_area
	field.width = maxi(ceili(bake_area.size.x / cell), 2)
	field.height = maxi(ceili(bake_area.size.y / cell), 2)
	field._sample_depths(depth_at)
	field._march()
	field._encode()
	field._depths = PackedFloat32Array()
	field._times = PackedFloat32Array()
	field._ends = PackedVector2Array()
	field._known = PackedByteArray()
	field._up_x = PackedInt32Array()
	field._up_z = PackedInt32Array()
	field._up_share = PackedFloat32Array()
	field._order = PackedInt32Array()
	return field


## Wave speed in water of depth `depth` (shallow-water waves, limited to the field's depth range).
static func wave_speed(depth: float) -> float:
	return sqrt(GRAVITY * clampf(depth, MIN_DEPTH, MAX_DEPTH))


## The field at world `p`, filtered like the GPU texture (bilinear, texel centres at +0.5, clamped at
## the border): (travel time, gradient x, gradient z, validity). Zero outside the area.
func sample(p: Vector2) -> Color:
	return _filtered(image, p)


## The waterline point the wave at `p` is heading for, filtered like the GPU texture; `p` outside the area.
func origin(p: Vector2) -> Vector2:
	if origins == null or not area.has_point(p):
		return p
	var c := _filtered(origins, p)
	return Vector2(c.r, c.g)


## Refraction coefficient at `p`, filtered like the GPU texture: 1 outside the area.
func refraction(p: Vector2) -> float:
	if origins == null or not area.has_point(p):
		return 1.0
	return _filtered(origins, p).b


func _filtered(img: Image, p: Vector2) -> Color:
	if img == null or not area.has_point(p):
		return Color(0.0, 0.0, 0.0, 0.0)
	var texel := (p - area.position) / area.size * Vector2(width, height) - Vector2(0.5, 0.5)
	var x0 := floori(texel.x)
	var y0 := floori(texel.y)
	var fx := texel.x - x0
	var fy := texel.y - y0
	var a := _texel(img, x0, y0).lerp(_texel(img, x0 + 1, y0), fx)
	var b := _texel(img, x0, y0 + 1).lerp(_texel(img, x0 + 1, y0 + 1), fx)
	return a.lerp(b, fy)


func _texel(img: Image, x: int, y: int) -> Color:
	return img.get_pixel(clampi(x, 0, width - 1), clampi(y, 0, height - 1))


func _cell_size() -> Vector2:
	return area.size / Vector2(width, height)


func _centre(i: int) -> Vector2:
	return area.position + _cell_size() * Vector2(i % width + 0.5, i / width + 0.5)


func _sample_depths(depth_at: Callable) -> void:
	_depths.resize(width * height)
	for i in range(width * height):
		var depth: float = depth_at.call(_centre(i))
		_depths[i] = depth


## Fast marching: land is known at T = 0; water cells are accepted in order of arrival time, each
## solved from its accepted neighbours with the upwind (Godunov) update. Water deeper than MAX_DEPTH
## is solved but not expanded from, which bounds the work to the band along the coast.
func _march() -> void:
	var count := width * height
	_times.resize(count)
	_times.fill(INF)
	_ends.resize(count)
	_known.resize(count)
	_up_x.resize(count)
	_up_x.fill(-1)
	_up_z.resize(count)
	_up_z.fill(-1)
	_up_share.resize(count)
	var heap := _MinHeap.new()
	for i in range(count):
		if _depths[i] <= 0.0:
			_times[i] = 0.0
			_ends[i] = _centre(i)
			_known[i] = 1
	for i in range(count):
		if _known[i] == 0 and _touches_known(i):
			_update(i)
			heap.push(_times[i], i)
	while not heap.is_empty():
		var i := heap.pop()
		if _known[i] == 1:
			continue
		_known[i] = 1
		_order.append(i)
		if _depths[i] > MAX_DEPTH:
			continue
		for j: int in _neighbours(i):
			if _known[j] == 0 and _update(j):
				heap.push(_times[j], j)


func _neighbours(i: int) -> PackedInt32Array:
	var x := i % width
	var y := i / width
	var result := PackedInt32Array()
	if x > 0:
		result.append(i - 1)
	if x < width - 1:
		result.append(i + 1)
	if y > 0:
		result.append(i - width)
	if y < height - 1:
		result.append(i + width)
	return result


func _touches_known(i: int) -> bool:
	for j: int in _neighbours(i):
		if _known[j] == 1:
			return true
	return false


## Accepted neighbour of `i` with the smallest time along one axis (`step` 1: x, width: z); -1 if none.
func _upwind(i: int, step: int) -> int:
	var x := i % width
	var y := i / width
	var best := -1
	var low_ok := x > 0 if step == 1 else y > 0
	var high_ok := x < width - 1 if step == 1 else y < height - 1
	if low_ok and _known[i - step] == 1:
		best = i - step
	if high_ok and _known[i + step] == 1 and (best < 0 or _times[i + step] < _times[best]):
		best = i + step
	return best


## Arrival time at cell `i` from its accepted neighbours: solves (T - a)^2 / dx^2 + (T - b)^2 / dz^2
## = f^2, falling back to a single direction where the two disagree too much. f is the slowness
## averaged over the step from the upwind neighbour (trapezoid rule): the speed changes fastest right at
## the waterline, where taking it at one end alone would make the waves arrive early.
## The waterline point is carried along from the neighbours the wave came from. Returns true when
## the time improved.
func _update(i: int) -> bool:
	var cell := _cell_size()
	var here := 1.0 / wave_speed(_depths[i])
	var ix := _upwind(i, 1)
	var iz := _upwind(i, width)
	if ix < 0 and iz < 0:
		return false
	var a := INF if ix < 0 else _times[ix]
	var b := INF if iz < 0 else _times[iz]
	var fx := INF if ix < 0 else 0.5 * (here + 1.0 / wave_speed(_depths[ix]))
	var fz := INF if iz < 0 else 0.5 * (here + 1.0 / wave_speed(_depths[iz]))
	var along_x := a + fx * cell.x
	var along_z := b + fz * cell.y
	var t := minf(along_x, along_z)
	var end := _ends[ix] if along_x <= along_z else _ends[iz]
	var share := 1.0 if along_x <= along_z else 0.0
	if ix >= 0 and iz >= 0:
		var wx := 1.0 / (cell.x * cell.x)
		var wz := 1.0 / (cell.y * cell.y)
		var slowness := 0.5 * (fx + fz)
		var qa := wx + wz
		var qb := -2.0 * (a * wx + b * wz)
		var qc := a * a * wx + b * b * wz - slowness * slowness
		var disc := qb * qb - 4.0 * qa * qc
		if disc >= 0.0:
			var both := (-qb + sqrt(disc)) / (2.0 * qa)
			if both >= maxf(a, b):
				t = both
				# Each neighbour weighs in as much as the wave travels along its axis.
				var px := (t - a) * wx
				var pz := (t - b) * wz
				share = px / maxf(px + pz, 1e-9)
				end = _ends[ix] * share + _ends[iz] * (1.0 - share)
	if t >= _times[i]:
		return false
	_times[i] = t
	_ends[i] = end
	_up_x[i] = ix if share > 0.0 else -1
	_up_z[i] = iz if share < 1.0 else -1
	_up_share[i] = share
	return true


## Packs times, gradients and waterline points. Land next to the water gets the gradient of its water
## neighbours, so the filtered field still holds right up to the waterline.
func _encode() -> void:
	image = Image.create(width, height, false, Image.FORMAT_RGBAF)
	origins = Image.create(width, height, false, Image.FORMAT_RGBF)
	var cell := _cell_size()
	var gradients := PackedVector2Array()
	gradients.resize(width * height)
	for i in range(width * height):
		if _solved_water(i):
			gradients[i] = Vector2(_derivative(i, 1, cell.x), _derivative(i, width, cell.y))
	var kr := _refraction(gradients)
	for i in range(width * height):
		var x := i % width
		var y := i / width
		var end := _ends[i] if _known[i] == 1 or _solved_water(i) else _centre(i)
		origins.set_pixel(x, y, Color(end.x, end.y, kr[i]))
		if _solved_water(i):
			image.set_pixel(x, y, Color(_times[i], gradients[i].x, gradients[i].y, 1.0))
			continue
		if _depths[i] > 0.0:
			continue
		var shore := Vector2.ZERO
		var wet := 0
		for j: int in _neighbours(i):
			if _solved_water(j):
				shore += gradients[j]
				wet += 1
		if wet > 0:
			image.set_pixel(x, y, Color(0.0, shore.x / wet, shore.y / wet, 1.0))


## Refraction coefficient per cell. Rays spread at the rate the wave direction diverges:
## d(ln b)/ds = div(d), d the unit direction of travel. Integrated seawards along the rays the march
## followed (ln b, from 0 at the waterline), then the value at each ray's offshore end carried back
## along it: Kr = sqrt(b0 / b) = exp((ln b0 - ln b) / 2). Land touching the water takes its neighbours'.
func _refraction(gradients: PackedVector2Array) -> PackedFloat32Array:
	var count := width * height
	var divergence := _direction_divergence(gradients)
	for pass_index in range(DIVERGENCE_SMOOTHING):
		divergence = _smoothed(divergence)
	var spread := PackedFloat32Array()
	spread.resize(count)
	for i: int in _order:
		if _depths[i] <= 0.0:
			continue
		var share := _up_share[i]
		var before := _upstream(_up_x[i], share, _up_z[i], spread)
		var t_before := _upstream(_up_x[i], share, _up_z[i], _times)
		spread[i] = before + divergence[i] * (_times[i] - t_before) * wave_speed(_depths[i])
	var end_sum := PackedFloat32Array()
	end_sum.resize(count)
	var end_weight := PackedFloat32Array()
	end_weight.resize(count)
	var kr := PackedFloat32Array()
	kr.resize(count)
	kr.fill(1.0)
	for k in range(_order.size() - 1, -1, -1):
		var i := _order[k]
		if _depths[i] <= 0.0:
			continue
		var offshore := end_sum[i] / end_weight[i] if end_weight[i] > 0.0 else spread[i]
		kr[i] = clampf(exp(0.5 * (offshore - spread[i])), REFRACTION_MIN, REFRACTION_MAX)
		var share := _up_share[i]
		if _up_x[i] >= 0 and share > 0.0:
			end_sum[_up_x[i]] += offshore * share
			end_weight[_up_x[i]] += share
		if _up_z[i] >= 0 and share < 1.0:
			end_sum[_up_z[i]] += offshore * (1.0 - share)
			end_weight[_up_z[i]] += 1.0 - share
	for i in range(count):
		if _depths[i] > 0.0:
			continue
		var total := 0.0
		var wet := 0
		for j: int in _neighbours(i):
			if _solved_water(j):
				total += kr[j]
				wet += 1
		if wet > 0:
			kr[i] = total / wet
	return kr


## Weighted value of the upwind neighbours (0 for land, where rays start).
func _upstream(ix: int, share: float, iz: int, values: PackedFloat32Array) -> float:
	var total := 0.0
	if ix >= 0 and _depths[ix] > 0.0:
		total += values[ix] * share
	if iz >= 0 and _depths[iz] > 0.0:
		total += values[iz] * (1.0 - share)
	return total


## Divergence of the unit direction of travel (seawards), per solved water cell.
func _direction_divergence(gradients: PackedVector2Array) -> PackedFloat32Array:
	var count := width * height
	var cell := _cell_size()
	var directions := PackedVector2Array()
	directions.resize(count)
	for i in range(count):
		if _solved_water(i):
			directions[i] = gradients[i].normalized()
	var divergence := PackedFloat32Array()
	divergence.resize(count)
	for i in range(count):
		if _solved_water(i):
			divergence[i] = _direction_derivative(i, 1, cell.x, directions, true) \
					+ _direction_derivative(i, width, cell.y, directions, false)
	return divergence


## Derivative of one component of the directions along one axis, over solved water only.
func _direction_derivative(i: int, step: int, spacing: float, directions: PackedVector2Array,
		along_x: bool) -> float:
	var x := i % width
	var y := i / width
	var low_ok := (x > 0 if step == 1 else y > 0) and _solved_water(i - step)
	var high_ok := (x < width - 1 if step == 1 else y < height - 1) and _solved_water(i + step)
	var here := directions[i].x if along_x else directions[i].y
	var low := 0.0
	var high := 0.0
	if low_ok:
		low = directions[i - step].x if along_x else directions[i - step].y
	if high_ok:
		high = directions[i + step].x if along_x else directions[i + step].y
	if low_ok and high_ok:
		return (high - low) / (2.0 * spacing)
	if high_ok:
		return (high - here) / spacing
	if low_ok:
		return (here - low) / spacing
	return 0.0


## 3 x 3 average over solved water.
func _smoothed(values: PackedFloat32Array) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(values.size())
	for i in range(values.size()):
		if not _solved_water(i):
			continue
		var x := i % width
		var y := i / width
		var total := 0.0
		var n := 0
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx := x + dx
				var ny := y + dy
				if nx < 0 or ny < 0 or nx >= width or ny >= height:
					continue
				var j := ny * width + nx
				if _solved_water(j):
					total += values[j]
					n += 1
		result[i] = total / n
	return result


func _solved_water(i: int) -> bool:
	return _depths[i] > 0.0 and not is_inf(_times[i])


## Central difference of the times along one axis; one-sided where a neighbour is missing or unsolved.
func _derivative(i: int, step: int, spacing: float) -> float:
	var x := i % width
	var y := i / width
	var low_ok := (x > 0 if step == 1 else y > 0) and not is_inf(_times[i - step])
	var high_ok := (x < width - 1 if step == 1 else y < height - 1) and not is_inf(_times[i + step])
	if low_ok and high_ok:
		return (_times[i + step] - _times[i - step]) / (2.0 * spacing)
	if high_ok:
		return (_times[i + step] - _times[i]) / spacing
	if low_ok:
		return (_times[i] - _times[i - step]) / spacing
	return 0.0


## Binary min-heap of (time, cell). Entries are never updated in place: a better time is pushed again
## and the stale entry skipped when it comes out (the cell is already known by then).
class _MinHeap:
	var _keys := PackedFloat32Array()
	var _values := PackedInt32Array()

	func is_empty() -> bool:
		return _keys.is_empty()

	func push(key: float, value: int) -> void:
		_keys.append(key)
		_values.append(value)
		var i := _keys.size() - 1
		while i > 0:
			var parent := (i - 1) / 2
			if _keys[parent] <= key:
				break
			_keys[i] = _keys[parent]
			_values[i] = _values[parent]
			i = parent
		_keys[i] = key
		_values[i] = value

	## Removes and returns the value with the smallest key.
	func pop() -> int:
		var top := _values[0]
		var last := _keys.size() - 1
		var key := _keys[last]
		var value := _values[last]
		_keys.resize(last)
		_values.resize(last)
		if last == 0:
			return top
		var i := 0
		while true:
			var child := 2 * i + 1
			if child >= last:
				break
			if child + 1 < last and _keys[child + 1] < _keys[child]:
				child += 1
			if _keys[child] >= key:
				break
			_keys[i] = _keys[child]
			_values[i] = _values[child]
			i = child
		_keys[i] = key
		_values[i] = value
		return top
