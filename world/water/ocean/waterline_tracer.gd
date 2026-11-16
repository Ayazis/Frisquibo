class_name WaterlineTracer
extends RefCounted
## The waterline (depth 0) of a grid of depths, as polylines: marching squares over the cell centres,
## with the segments chained into lines. Closed lines (an island) end on the point they start from.

## Waterlines shorter than this (a rock, a puddle in the seabed grid) are left out.
const MIN_LENGTH := 20.0


## `depths`: width * height values at cell centres of `area`, positive in water.
static func trace(depths: PackedFloat32Array, width: int, height: int, area: Rect2) -> Array[PackedVector2Array]:
	var cell := area.size / Vector2(width, height)
	# Crossing points on grid edges, keyed by edge: 2 * (y * width + x) for the edge from (x, y) to
	# (x + 1, y), + 1 for the edge from (x, y) to (x, y + 1).
	var points: Dictionary[int, Vector2] = {}
	var links: Dictionary[int, PackedInt32Array] = {}
	for y in range(height - 1):
		for x in range(width - 1):
			var i := y * width + x
			var corners := PackedFloat32Array([depths[i], depths[i + 1], depths[i + width + 1], depths[i + width]])
			# Square edges: bottom (x, y)-(x+1, y), right (x+1, y)-(x+1, y+1), top (x, y+1)-(x+1, y+1),
			# left (x, y)-(x, y+1).
			var edges := PackedInt32Array([2 * i, 2 * (i + 1) + 1, 2 * (i + width), 2 * i + 1])
			var crossed := PackedInt32Array()
			for e in range(4):
				var a := corners[e]
				var b := corners[(e + 1) % 4]
				if (a > 0.0) != (b > 0.0):
					crossed.append(e)
					var key := edges[e]
					if not points.has(key):
						points[key] = _crossing(x, y, e, a, b, cell, area.position)
			if crossed.size() == 2:
				_link(links, edges[crossed[0]], edges[crossed[1]])
			elif crossed.size() == 4:
				# Saddle: the average of the corners decides which way the water connects.
				var centre := (corners[0] + corners[1] + corners[2] + corners[3]) * 0.25
				var wet_first := corners[0] > 0.0
				if (centre > 0.0) == wet_first:
					_link(links, edges[0], edges[1])
					_link(links, edges[2], edges[3])
				else:
					_link(links, edges[0], edges[3])
					_link(links, edges[1], edges[2])
	return _chain(points, links)


static func _crossing(x: int, y: int, edge: int, a: float, b: float, cell: Vector2, origin: Vector2) -> Vector2:
	var corners: Array[Vector2] = [Vector2(x, y), Vector2(x + 1, y), Vector2(x + 1, y + 1), Vector2(x, y + 1)]
	var t := a / (a - b)
	var grid := corners[edge].lerp(corners[(edge + 1) % 4], t)
	return origin + (grid + Vector2(0.5, 0.5)) * cell


static func _link(links: Dictionary[int, PackedInt32Array], a: int, b: int) -> void:
	if not links.has(a):
		links[a] = PackedInt32Array()
	if not links.has(b):
		links[b] = PackedInt32Array()
	links[a].append(b)
	links[b].append(a)


## Walks the links into polylines: open ones from an end (a point with one link), then closed loops.
static func _chain(points: Dictionary[int, Vector2], links: Dictionary[int, PackedInt32Array]) -> Array[PackedVector2Array]:
	var lines: Array[PackedVector2Array] = []
	var used: Dictionary[int, bool] = {}
	var starts: Array[int] = []
	for key: int in links:
		if links[key].size() == 1:
			starts.append(key)
	for key: int in links:
		if links[key].size() != 1:
			starts.append(key)
	for start: int in starts:
		if used.has(start):
			continue
		var line := PackedVector2Array()
		var current := start
		var previous := -1
		while true:
			used[current] = true
			line.append(points[current])
			var next := -1
			for candidate: int in links[current]:
				if candidate != previous and not used.has(candidate):
					next = candidate
					break
			if next < 0:
				# Closed loop: back at the start.
				if links[current].has(start) and line.size() > 2:
					line.append(points[start])
				break
			previous = current
			current = next
		if _length(line) >= MIN_LENGTH:
			lines.append(line)
	return lines


static func _length(line: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, line.size()):
		total += line[i - 1].distance_to(line[i])
	return total
