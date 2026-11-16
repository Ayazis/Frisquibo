class_name ShoreRays
extends RefCounted
## Wave rays: the paths waves take to the beach, traced seawards from every SPACING metres of each
## waterline over the ShoreField, and sampled every TIME_STEP seconds of travel time. Row r, column j
## holds where the wave that reaches waterline point r is j * TIME_STEP seconds before it gets there.
## Alongshore position (row) and travel time (column) make a grid that follows the crests, which is what
## the breaker ribbons (OceanBreakers) are built on.

## Metres between rays along the waterline.
const SPACING := 1.0
## Seconds of travel time between samples along a ray.
const TIME_STEP := 0.4
## Travel time the rays reach: breakers form well inside this (in water a few metres deep).
const MAX_TIME := 32.0
## Marks samples past the end of a ray (it left the field there and holds its last point).
const DEAD := -1.0
## Share of valid texels a sample's filter footprint must have to count as inside the field.
const INSIDE := 0.99
## Seconds one step's travel time may differ from TIME_STEP before the ray is cut off there.
const MAX_JUMP := 0.25

## RGBA float per ray (row) and step (column): world (x, z), the field's travel time there (DEAD once
## the ray has left the field), and the still water depth there. Times rise by about TIME_STEP per
## column from the ray's first one.
var image: Image
var columns := 0
var rows := 0
## Per waterline: first row, number of rows, and whether the line is closed (rows wrap around).
var line_starts := PackedInt32Array()
var line_lengths := PackedInt32Array()
var line_closed: Array[bool] = []


## `depth_at` (Vector2 -> float): still water depth at a world point, stored along the rays.
static func trace(field: ShoreField, depth_at: Callable) -> ShoreRays:
	var rays := ShoreRays.new()
	rays.columns = ceili(MAX_TIME / TIME_STEP) + 1
	var starts: Array[PackedVector2Array] = []
	for line: PackedVector2Array in field.waterlines:
		var closed := line.size() > 2 and line[0].distance_to(line[line.size() - 1]) < SPACING
		var points := resample(line, SPACING)
		if closed and points.size() > 1 and points[0].distance_to(points[points.size() - 1]) < SPACING * 0.5:
			points.resize(points.size() - 1)
		rays.line_starts.append(rays.rows)
		rays.line_lengths.append(points.size())
		rays.line_closed.append(closed)
		rays.rows += points.size()
		starts.append(points)
	rays.image = Image.create(rays.columns, maxi(rays.rows, 1), false, Image.FORMAT_RGBAF)
	var row := 0
	for points: PackedVector2Array in starts:
		for start: Vector2 in points:
			rays._trace_ray(field, depth_at, start, row)
			row += 1
	return rays


## Points every `spacing` metres along `line`, starting at its first point.
static func resample(line: PackedVector2Array, spacing: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	if line.is_empty():
		return result
	result.append(line[0])
	var carried := 0.0
	for i in range(1, line.size()):
		var a := line[i - 1]
		var b := line[i]
		var length := a.distance_to(b)
		var along := spacing - carried
		while along <= length:
			result.append(a.lerp(b, along / length))
			along += spacing
		carried = length - (along - spacing)
	return result


## World (x, z) of `row` where the field's travel time is `time`, linear between samples (as the GPU
## filters it). One correction step takes up the drift between the ray's clock and the field's. Past
## the end of the ray: its last point.
func position(row: int, time: float) -> Vector2:
	var c := column(row, time)
	return Vector2(_at(row, c).r, _at(row, c).g)


## Fractional column of `row` where the field's travel time is `time` (same as shore_ray_column()).
func column(row: int, time: float) -> float:
	var guess := clampf((time - start_time(row)) / TIME_STEP, 0.0, columns - 1.0)
	var there := _at(row, guess).b
	if there < 0.0:
		return guess
	return clampf(guess + (time - there) / TIME_STEP, 0.0, columns - 1.0)


## Sample of `row` at fractional `column`, linear between columns.
func _at(row: int, at_column: float) -> Color:
	var j := mini(floori(at_column), columns - 2)
	return image.get_pixel(j, row).lerp(image.get_pixel(j + 1, row), at_column - j)


## The field's travel time at the waterline end of `row`.
func start_time(row: int) -> float:
	return image.get_pixel(0, row).b


## Travel time of the last sample of `row` in water at least `depth` deep (its start time if none).
func time_to_depth(row: int, depth: float) -> float:
	var start := start_time(row)
	for j in range(columns):
		var sample := image.get_pixel(j, row)
		if sample.b < 0.0:
			break
		if sample.a >= depth:
			return sample.b
	return start + (columns - 1) * TIME_STEP


## Rows of the waterline `row` lies on, and its index along it: (line, index).
func line_of(row: int) -> Vector2i:
	for line in range(line_starts.size()):
		if row >= line_starts[line] and row < line_starts[line] + line_lengths[line]:
			return Vector2i(line, row - line_starts[line])
	return Vector2i(-1, -1)


## Follows the travel time's gradient seawards: dx/dT = grad T / |grad T|^2 (the wave speed squared
## along grad T), midpoint rule. Each sample records the field's own travel time there: right at the
## waterline the field's time is coarse (its first water texels), so a ray starts at the field's time of
## its waterline point, not at 0, and the two clocks are compared, never assumed equal. Where the field
## ends the ray holds its last point, marked DEAD.
func _trace_ray(field: ShoreField, depth_at: Callable, start: Vector2, row: int) -> void:
	var p := start
	var alive := field.sample(p).a >= 0.5
	var previous := 0.0
	for j in range(columns):
		if alive and j > 0:
			var k1 := _velocity(field, p)
			var k2 := Vector2.INF if k1 == Vector2.INF else _velocity(field, p + k1 * TIME_STEP * 0.5)
			# Fully inside valid texels: at the field's edge its filtered time mixes with the empty ones.
			alive = k2 != Vector2.INF and field.sample(p + k2 * TIME_STEP).a >= INSIDE
			if alive:
				p += k2 * TIME_STEP
		var time := field.sample(p).r
		# Where a step's time jumps away from the step's length (a river mouth, where waves come from both
		# banks), the ray stops: breakers there would sit off their crests.
		if alive and j > 0 and absf(time - previous - TIME_STEP) > MAX_JUMP:
			alive = false
		previous = time
		var depth: float = depth_at.call(p)
		image.set_pixel(j, row, Color(p.x, p.y, time if alive else DEAD, depth))


func _velocity(field: ShoreField, p: Vector2) -> Vector2:
	var f := field.sample(p)
	var gradient := Vector2(f.g, f.b)
	var slowness2 := gradient.length_squared()
	if f.a < 0.5 or slowness2 < 1e-8:
		return Vector2.INF
	return gradient / slowness2
