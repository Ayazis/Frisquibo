class_name ShoreField
extends RefCounted
## Where waves near a coast travel and when they arrive: the travel time T to the waterline over the
## baked seabed, and its gradient. Waves in shallow water run at c = sqrt(g h), so they slow down over
## the shallows and their crests swing round to meet the beach (refraction) and bunch up (shoaling).
## Wave crests are the lines of equal travel time: T solves the eikonal equation |grad T| = 1 / c(h),
## here with the fast marching method (Sethian 1996), outwards from the waterline.
## The shore waves (ShoreWaves on the CPU, ocean_shore_waves.gdshaderinc on the GPU) read it.

const GRAVITY := 9.81
## Metres per texel. The travel time is smooth, and its gradient is stored per texel, so a coarse grid
## is enough even for short waves at the waterline.
const DEFAULT_CELL := 3.0
## Deepest water the field covers. The shore waves fade in shallower than this, so nothing deeper reads it.
const MAX_DEPTH := 12.0
## The wave speed of this depth is used in shallower water, so the travel time stays finite at the waterline.
const MIN_DEPTH := 0.05

## RGBA float per texel: travel time to the waterline (s), its gradient along x and z (s/m), and 1
## where the field holds (water up to MAX_DEPTH, and land touching it); 0 elsewhere.
var image: Image
## RG float per texel: the point on the waterline (world x, z) the wave passing here will reach. Anything
## that varies along the coast (the timing and size of each wave) is drawn from it, so it stays the same
## along a wave's path and matches the swash where it lands.
var origins: Image
var area: Rect2
var width := 0
var height := 0
# Working state of the bake.
var _depths := PackedFloat32Array()
var _times := PackedFloat32Array()
var _ends := PackedVector2Array()
var _known := PackedByteArray()


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
				end = (_ends[ix] * px + _ends[iz] * pz) / maxf(px + pz, 1e-9)
	if t >= _times[i]:
		return false
	_times[i] = t
	_ends[i] = end
	return true


## Packs times, gradients and waterline points. Land next to the water gets the gradient of its water
## neighbours, so the filtered field still holds right up to the waterline.
func _encode() -> void:
	image = Image.create(width, height, false, Image.FORMAT_RGBAF)
	origins = Image.create(width, height, false, Image.FORMAT_RGF)
	var cell := _cell_size()
	var gradients := PackedVector2Array()
	gradients.resize(width * height)
	for i in range(width * height):
		if _solved_water(i):
			gradients[i] = Vector2(_derivative(i, 1, cell.x), _derivative(i, width, cell.y))
	for i in range(width * height):
		var x := i % width
		var y := i / width
		origins.set_pixel(x, y, Color(_ends[i].x, _ends[i].y, 0.0) if _known[i] == 1 or _solved_water(i)
				else Color(_centre(i).x, _centre(i).y, 0.0))
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
