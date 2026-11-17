class_name ShoreRays
extends RefCounted
## Wave rays: the paths waves take to the beach, traced seawards from every SPACING metres of each
## waterline over the ShoreField, and sampled every TIME_STEP seconds of travel time. Row r, column j
## holds where the wave that reaches waterline point r is j * TIME_STEP seconds before it gets there.
## Alongshore position (row) and travel time (column) make a grid that follows the crests, which is what
## the breaker ribbons (OceanBreakers) are built on.
##
## Rays from neighbouring waterline points can fan far apart: the field's clock is coarse right at the
## waterline, and refraction gathers rays into bundles with empty water between them. A ribbon bends its
## curl only at its rays, so where two neighbours lie more than MAX_GAP apart in water a curl can form in,
## another ray is traced through the middle of the gap, back to the beach and out to sea, until all
## neighbours are close.

## Metres between rays along the waterline (before rays are added between neighbours that fan apart).
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
## Metres neighbouring rays may lie apart at equal travel time, in water a curl can form in (CURL_DEPTH),
## before a ray is traced between them.
const MAX_GAP := 1.5
## Still water depths (m) neighbours are kept within MAX_GAP in. Deeper, the shore waves are gone
## (ShoreField.MAX_DEPTH). Shallower, a breaker is at most 2 * 0.39 * 0.3 = 0.23 m high, and the field's
## clock is too coarse this near the waterline to trace rays through it.
const CURL_DEPTH := Vector2(0.3, ShoreField.MAX_DEPTH)
## Seconds two rays' clocks may differ where their positions are compared (a share of TIME_STEP).
const CLOCK_SLACK := 0.5 * TIME_STEP
## Times the gap between two neighbouring rays may be split by rays traced through it.
const MAX_SPLITS := 8

## RGBA float per ray (row) and step (column): world (x, z), the field's travel time there (DEAD once
## the ray has left the field), and the still water depth there. Times rise by about TIME_STEP per
## column from the ray's first one.
var image: Image
var columns := 0
var rows := 0
## Per waterline: first row, number of rows, whether the line is closed (rows wrap around), and its
## length in metres.
var line_starts := PackedInt32Array()
var line_lengths := PackedInt32Array()
var line_closed: Array[bool] = []
var line_metres := PackedFloat32Array()
## Per row: metres along its waterline its ray belongs to, rising along the line (past the line's length
## for rays traced between a closed line's last and first). A ray traced through a gap takes the middle
## of its neighbours'.
var along := PackedFloat32Array()
## Per row: the point on the waterline its ray belongs to (a ray traced through a gap: the point between
## its neighbours'). Smooth along the line, where the ray's own start need not be: a ray traced back
## from a gap ends a step or so off the waterline.
var shore_points := PackedVector2Array()
## Per row: the waterline point (world x, z) the field says the wave at the ray's start heads for. The
## timing and size of each wave are drawn there (ShoreField.origins), smooth along the shore.
var origins := PackedVector2Array()
## The rows of `image`, for reading on the CPU.
var _rays: Array[PackedColorArray] = []


## `depth_at` (Vector2 -> float): still water depth at a world point, stored along the rays.
static func trace(field: ShoreField, depth_at: Callable) -> ShoreRays:
	var rays := ShoreRays.new()
	rays.columns = ceili(MAX_TIME / TIME_STEP) + 1
	for line: PackedVector2Array in field.waterlines:
		var closed := line.size() > 2 and line[0].distance_to(line[line.size() - 1]) < SPACING
		var points := resample(line, SPACING)
		if closed and points.size() > 1 and points[0].distance_to(points[points.size() - 1]) < SPACING * 0.5:
			points.resize(points.size() - 1)
		# Rays that never leave their waterline point carry no crest: a ribbon row on one would fold its
		# neighbours' quads back onto the beach. The rays traced through the gaps take their place.
		var traced: Array[PackedColorArray] = []
		var metres := PackedFloat32Array()
		var on_shore := PackedVector2Array()
		for k in range(points.size()):
			var ray := rays._trace_ray(field, depth_at, points[k])
			if _leaves(ray):
				traced.append(ray)
				metres.append(k * SPACING)
				on_shore.append(points[k])
		if traced.is_empty():
			continue
		var length := points.size() * SPACING
		var first := rays._rays.size()
		for k in range(traced.size()):
			rays._rays.append(traced[k])
			rays.along.append(metres[k])
			rays.shore_points.append(on_shore[k])
			var next := k + 1
			var next_metres := metres[next] if next < traced.size() else metres[0] + length
			if next == traced.size():
				if not closed:
					break
				next = 0
			rays._fill(field, depth_at, traced[k], traced[next], Vector2(metres[k], next_metres),
					PackedVector2Array([on_shore[k], on_shore[next]]), 0)
		rays.line_starts.append(first)
		rays.line_lengths.append(rays._rays.size() - first)
		rays.line_closed.append(closed)
		rays.line_metres.append(length)
	rays.rows = rays._rays.size()
	rays.origins.resize(rays.rows)
	for row in range(rays.rows):
		rays.origins[row] = field.origin(Vector2(rays._rays[row][0].r, rays._rays[row][0].g))
	rays.image = Image.create(rays.columns, maxi(rays.rows, 1), false, Image.FORMAT_RGBAF)
	for row in range(rays.rows):
		for j in range(rays.columns):
			rays.image.set_pixel(j, row, rays._rays[row][j])
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
	var sample := _sample_on(_rays[row], column(row, time))
	return Vector2(sample.r, sample.g)


## Fractional column of `row` where the field's travel time is `time` (same as shore_ray_column()).
func column(row: int, time: float) -> float:
	return _column_on(_rays[row], time)


## The field's travel time at the waterline end of `row`.
func start_time(row: int) -> float:
	return _rays[row][0].b


## Travel time of the last sample of `row` in water at least `depth` deep (its start time if none).
func time_to_depth(row: int, depth: float) -> float:
	var ray := _rays[row]
	for sample: Color in ray:
		if sample.b < 0.0:
			break
		if sample.a >= depth:
			return sample.b
	return ray[0].b + (columns - 1) * TIME_STEP


## Rows of the waterline `row` lies on, and its index along it: (line, index).
func line_of(row: int) -> Vector2i:
	for line in range(line_starts.size()):
		if row >= line_starts[line] and row < line_starts[line] + line_lengths[line]:
			return Vector2i(line, row - line_starts[line])
	return Vector2i(-1, -1)


## How far apart rows `row` and `other` lie at equal travel time, at most, where both rays are alive and
## a curl can form (CURL_DEPTH).
func gap(row: int, other: int) -> float:
	return _widest(_rays[row], _rays[other]).x


static func _column_on(ray: PackedColorArray, time: float) -> float:
	var last := ray.size() - 1.0
	var guess := clampf((time - ray[0].b) / TIME_STEP, 0.0, last)
	var there := _sample_on(ray, guess).b
	if there < 0.0:
		return guess
	return clampf(guess + (time - there) / TIME_STEP, 0.0, last)


## Sample of `ray` at fractional `at_column`, linear between columns.
static func _sample_on(ray: PackedColorArray, at_column: float) -> Color:
	var j := mini(floori(at_column), ray.size() - 2)
	return ray[j].lerp(ray[j + 1], at_column - j)


## Follows the travel time's gradient seawards: dx/dT = grad T / |grad T|^2 (the wave speed squared
## along grad T), midpoint rule. Each sample records the field's own travel time there: right at the
## waterline the field's time is coarse (its first water texels), so a ray starts at the field's time of
## its waterline point, not at 0, and the two clocks are compared, never assumed equal. Where the field
## ends the ray holds its last point, marked DEAD.
func _trace_ray(field: ShoreField, depth_at: Callable, start: Vector2) -> PackedColorArray:
	var ray := PackedColorArray()
	ray.resize(columns)
	_march(field, depth_at, start, ray, 0)
	return ray


## The ray through `through`: traced back towards the beach while it stays inside the field, then out to sea,
## so it has the columns of a ray from the waterline. Tracing out from where it ends near the beach
## instead would miss `through` wherever rays fan out, which is where these rays are needed.
func _trace_through(field: ShoreField, depth_at: Callable, through: Vector2) -> PackedColorArray:
	var shoreward: Array[Color] = []
	var p := through
	var here := field.sample(p)
	if here.a < INSIDE:
		return PackedColorArray()
	while shoreward.size() < columns - 1:
		var next := _step(field, p, here, -TIME_STEP)
		if not next.is_finite():
			break
		var there := field.sample(next)
		var depth: float = depth_at.call(next)
		if there.a < INSIDE or depth <= 0.0 or absf(here.r - there.r - TIME_STEP) > MAX_JUMP:
			break
		p = next
		here = there
		shoreward.append(Color(p.x, p.y, here.r, depth))
	var ray := PackedColorArray()
	ray.resize(columns)
	for k in range(shoreward.size()):
		ray[k] = shoreward[shoreward.size() - 1 - k]
	_march(field, depth_at, through, ray, shoreward.size())
	return ray


## Fills `ray` from column `first`, which lies at `start`, out to sea (see _trace_ray()).
func _march(field: ShoreField, depth_at: Callable, start: Vector2, ray: PackedColorArray, first: int) -> void:
	var p := start
	# The field at p: each step's end is sampled once, for the check and as the next step's start.
	var here := field.sample(p)
	var alive := here.a >= 0.5
	var previous := here.r
	var depth: float = depth_at.call(p)
	for j in range(first, columns):
		if alive and j > first:
			var next := _step(field, p, here, TIME_STEP)
			var there := field.sample(next) if next.is_finite() else Color(0.0, 0.0, 0.0, 0.0)
			# Fully inside valid texels: at the field's edge its filtered time mixes with the empty ones.
			alive = there.a >= INSIDE
			if alive:
				p = next
				here = there
				depth = depth_at.call(p)
		var time := here.r
		# Where a step's time jumps away from the step's length (a river mouth, where waves come from both
		# banks), the ray stops: breakers there would sit off their crests.
		if alive and j > first and absf(time - previous - TIME_STEP) > MAX_JUMP:
			alive = false
		previous = time
		ray[j] = Color(p.x, p.y, time if alive else DEAD, depth)


## Where one midpoint step of `dt` seconds of travel time takes the wave at `p` (`here`: the field
## there); not finite where the field has no wave.
static func _step(field: ShoreField, p: Vector2, here: Color, dt: float) -> Vector2:
	var k1 := _velocity(here)
	if not k1.is_finite():
		return Vector2.INF
	var k2 := _velocity(field.sample(p + k1 * dt * 0.5))
	if not k2.is_finite():
		return Vector2.INF
	return p + k2 * dt


## Wave velocity from the field's sample `f`; INF where it has none.
static func _velocity(f: Color) -> Vector2:
	var gradient := Vector2(f.g, f.b)
	var slowness2 := gradient.length_squared()
	if f.a < 0.5 or slowness2 < 1e-8:
		return Vector2.INF
	return gradient / slowness2


## Appends the rays traced through the gap between neighbouring rays `a` and `b` (at `metres` along the
## waterline, from the waterline points `shore`), in order, until neighbours stay within MAX_GAP.
func _fill(field: ShoreField, depth_at: Callable, a: PackedColorArray, b: PackedColorArray, metres: Vector2,
		shore: PackedVector2Array, splits: int) -> void:
	if splits >= MAX_SPLITS:
		return
	var widest := _widest(a, b)
	if widest.x <= MAX_GAP:
		return
	var ray := _trace_through(field, depth_at, Vector2(widest.y, widest.z))
	if not _leaves(ray):
		return
	var middle := (metres.x + metres.y) * 0.5
	var shore_middle := shore[0].lerp(shore[1], 0.5)
	_fill(field, depth_at, a, ray, Vector2(metres.x, middle), PackedVector2Array([shore[0], shore_middle]), splits + 1)
	_rays.append(ray)
	along.append(middle)
	shore_points.append(shore_middle)
	_fill(field, depth_at, ray, b, Vector2(middle, metres.y), PackedVector2Array([shore_middle, shore[1]]), splits + 1)


## Whether `ray` gets away from where it starts.
static func _leaves(ray: PackedColorArray) -> bool:
	return ray.size() > 1 and ray[1].b >= 0.0


## How far apart rays `a` and `b` lie at equal travel time, at most, where both are alive and a curl can
## form (CURL_DEPTH), and the point midway between them there: (metres, x, z).
static func _widest(a: PackedColorArray, b: PackedColorArray) -> Vector3:
	var one := _widest_from(a, b)
	var other := _widest_from(b, a)
	return one if one.x >= other.x else other


## _widest() at the times of `ray`'s samples.
static func _widest_from(ray: PackedColorArray, other: PackedColorArray) -> Vector3:
	var widest := Vector3.ZERO
	for sample: Color in ray:
		if sample.b < 0.0:
			break
		if sample.a < CURL_DEPTH.x or sample.a > CURL_DEPTH.y:
			continue
		# Only where `other` is alive on both sides of that time and reaches it: a ray that has stopped
		# holds its last point while its neighbour runs on, and their clocks start and end apart.
		var at_column := _column_on(other, sample.b)
		var j := mini(floori(at_column), other.size() - 2)
		if other[j].b < 0.0 or other[j + 1].b < 0.0:
			continue
		var there := _sample_on(other, at_column)
		if absf(there.b - sample.b) > CLOCK_SLACK:
			continue
		var here := Vector2(sample.r, sample.g)
		var apart := here.distance_to(Vector2(there.r, there.g))
		if apart > widest.x:
			var middle := here.lerp(Vector2(there.r, there.g), 0.5)
			widest = Vector3(apart, middle.x, middle.y)
	return widest
