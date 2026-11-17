class_name BreakerProfile
extends RefCounted
## The curl of a plunging breaker, as pure functions: the CPU twin of ocean_breakers.gdshaderinc (keep
## the two in step: same constants, same order of operations).
##
## A breaker's cross-section is one folded sheet of water in the frame of its crest (x: metres towards
## the shore from where the crest's water rests, y: metres above still water). From the crest the sheet
## runs out over the lip to its tip, turns back under the lip (the tube's ceiling), down the tube's back
## wall and on along the trough in front. The lip tip flies on a ballistic path: thrown forwards from
## the crest, it falls to the trough in the time a body falls one wave height, and lands. Then the water
## it lands on splashes up and the tube collapses into a foaming bore.
##
## Whether a wave plunges at all comes from the surf similarity (Iribarren) number (Battjes 1974):
## spilling below about 0.4, plunging up to about 2, surging above.

const GRAVITY := 9.81
## Surf similarity where spilling turns into plunging, and plunging into surging (ramps, not steps).
const SPILL_TO_PLUNGE := Vector2(0.3, 0.6)
const PLUNGE_TO_SURGE := Vector2(2.0, 3.3)
## Gentlest seabed slope used: flatter beaches all spill.
const MIN_SLOPE := 0.005
## A wave's unbroken height over the depth limit grows as h^-5/4 towards the beach (Green's law over a
## limit proportional to h): h_break = h * ratio^(4/5).
const BREAK_DEPTH_EXPONENT := 0.8
## How far ahead of the crest the lip lands, in breaking wave heights, in the crest's own frame.
const LIP_REACH := 0.55
## ...at most this share of the way from the crest to the trough ahead of it.
const MAX_REACH_SHARE := 0.8
## Stage (time since breaking, in lip flight times) over which the fold grows in...
const LIP_GROW := 0.25
## ...and over which the tube collapses into a bore after the lip has landed.
const COLLAPSE := Vector2(1.3, 2.4)
## Lip thickness at the crest and at the tip, in crest heights.
const ROOT_THICKNESS := 0.45
const TIP_THICKNESS := 0.08
## Where the tube's back wall meets the trough, as a share of the lip's reach.
const FACE_BASE := 0.3
## How far the tube's back wall bulges back under the crest, in crest heights.
const BACK_WALL := 0.35
## Handle length of the curves, as a share of the distance they span.
const HANDLE := 0.4
## The splash-up where the lip lands: height in crest heights, width in breaking heights, and the stages
## it rises from, is full at, starts to fall at and is gone by.
const SPLASH_HEIGHT := 0.8
const SPLASH_WIDTH := 0.35
const SPLASH := Vector4(0.9, 1.1, 1.25, 1.9)
## A breaker's stage and plunge are averaged along its crest, over PEEL_TAPS points PEEL_STEP metres
## apart (weights rising to the middle: 1 2 3 4 3 2 1), about a third of a wavelength either side: the
## lip peels along the crest instead of jumping ahead where the wave's height, size or depth changes
## within a few metres, and a curl runs along a long stretch of crest.
const PEEL_STEP := 3.0
const PEEL_TAPS := 7
## Along the crest the stage and plunge change smoothly, also where a point is still unbroken (its stage
## is negative, from the same formula, down to PEEL_BEFORE) and where the points reach the beach (they
## fade out over the last PEEL_SHORE metres of water).
const PEEL_BEFORE := -1.0
const PEEL_SHORE := 0.3
## From this share of the window the curl hands back to the wave's own surface, which it reaches at 1.
const END_BLEND := 0.85
## Parts of the sheet, as curve() reports them.
enum Part { OUTER_LIP, TIP, CEILING, BACK_WALL, TROUGH }


## Surf similarity xi = tan(beta) / sqrt(H / L0), L0 = g T^2 / 2 pi the deep-water wavelength.
static func surf_similarity(slope: float, height: float, period: float) -> float:
	var deep_wavelength := GRAVITY * period * period / TAU
	return maxf(slope, MIN_SLOPE) / sqrt(maxf(height, 1e-4) / deep_wavelength)


## How much of a breaker plunges (0: it spills or surges), times the artistic `strength` (1: physical).
static func plunge_share(xi: float, strength: float) -> float:
	return smoothstep(SPILL_TO_PLUNGE.x, SPILL_TO_PLUNGE.y, xi) \
			* (1.0 - smoothstep(PLUNGE_TO_SURGE.x, PLUNGE_TO_SURGE.y, xi)) * strength


## Depth where a crest, now in water `depth` deep at `ratio` times its depth limit, started to break.
static func breaking_depth(depth: float, ratio: float) -> float:
	return depth * pow(maxf(ratio, 1.0), BREAK_DEPTH_EXPONENT)


## stage() for averaging along a crest: also before the crest breaks, where it is negative and changes
## smoothly into the stage after breaking (down to PEEL_BEFORE).
static func peel_stage(depth: float, ratio: float, slope: float, breaker_ratio: float) -> float:
	var break_depth := depth * pow(maxf(ratio, 1e-3), BREAK_DEPTH_EXPONENT)
	var height := maxf(2.0 * breaker_ratio * break_depth, 1e-3)
	var run := (break_depth - depth) / maxf(slope, MIN_SLOPE)
	var flight := sqrt(2.0 * height / GRAVITY)
	return maxf(run / (sqrt(GRAVITY * maxf(break_depth, 1e-3)) * flight), PEEL_BEFORE)


## Time since the crest broke, in lip flight times (sqrt(2 H_b / g)): negative before it breaks.
## The crest has run (h_b - h) / slope metres since, at the breaking speed sqrt(g h_b).
static func stage(depth: float, ratio: float, slope: float, breaker_ratio: float) -> float:
	if ratio <= 1.0 or depth <= 0.0:
		return -1.0
	var break_depth := breaking_depth(depth, ratio)
	var height := 2.0 * breaker_ratio * break_depth
	var run := (break_depth - depth) / maxf(slope, MIN_SLOPE)
	var flight := sqrt(2.0 * height / GRAVITY)
	return run / (sqrt(GRAVITY * break_depth) * flight)


## How folded the breaker is (0: the plain wave surface, 1: the full curl).
static func fold(breaker_stage: float, plunge: float) -> float:
	return plunge * smoothstep(0.0, LIP_GROW, breaker_stage) \
			* (1.0 - smoothstep(COLLAPSE.x, COLLAPSE.y, breaker_stage))


## The sheet at share `phi` (0 at the crest, 1 at the trough ahead) of the front of a breaker at
## `breaker_stage`, whose crest stands `crest` metres above still water and whose trough lies
## `trough_distance` metres ahead of the crest: (x, y, part + share along that part), crest frame.
static func curve(phi: float, breaker_stage: float, crest: float, trough_distance: float) -> Vector3:
	var shape := _Shape.new(breaker_stage, crest, trough_distance)
	return shape.at(clampf(phi, 0.0, 1.0))


## Normal of the sheet at `phi` in the crest frame (x towards the shore, y up), pointing out of the water.
static func normal(phi: float, breaker_stage: float, crest: float, trough_distance: float) -> Vector2:
	var shape := _Shape.new(breaker_stage, crest, trough_distance)
	var a := shape.at(clampf(phi - NORMAL_STEP, 0.0, 1.0))
	var b := shape.at(clampf(phi + NORMAL_STEP, 0.0, 1.0))
	var tangent := Vector2(b.x - a.x, b.y - a.y)
	if tangent.length_squared() < 1e-12:
		return Vector2.UP
	tangent = tangent.normalized()
	return Vector2(-tangent.y, tangent.x)


## Share of phi either side used for the sheet's tangent.
const NORMAL_STEP := 0.004


## Splash-up height where the lip landed, as a share of SPLASH_HEIGHT.
static func splash(breaker_stage: float) -> float:
	return smoothstep(SPLASH.x, SPLASH.y, breaker_stage) * (1.0 - smoothstep(SPLASH.z, SPLASH.w, breaker_stage))


## Cubic Bezier.
static func bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var s := 1.0 - t
	return p0 * (s * s * s) + p1 * (3.0 * s * s * t) + p2 * (3.0 * s * t * t) + p3 * (t * t * t)


## Rough length of a cubic Bezier: halfway between its chord and its control polygon.
static func bezier_length(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2) -> float:
	return 0.5 * (p0.distance_to(p3) + p0.distance_to(p1) + p1.distance_to(p2) + p2.distance_to(p3))


## The sheet's control points for one stage, and its parts' lengths, so one sheet can be sampled often.
class _Shape:
	var points: Array[PackedVector2Array] = []
	var lengths := PackedFloat32Array()
	var total := 0.0
	var _splash_x := 0.0
	var _splash_height := 0.0
	var _splash_width := 1.0

	func _init(breaker_stage: float, crest: float, trough_distance: float) -> void:
		var flight := clampf(breaker_stage, 0.0, 1.0)
		var height := 2.0 * crest
		var reach := minf(LIP_REACH * height, MAX_REACH_SHARE * trough_distance)
		var top := Vector2(0.0, crest)
		# Ballistic tip: forwards at a steady speed, falling from the crest to the trough (2 crest heights).
		var tip := Vector2(reach * flight, crest - height * flight * flight)
		var heading := Vector2(reach, -2.0 * height * flight)
		heading = Vector2.RIGHT if heading.length_squared() < 1e-12 else heading.normalized()
		var inward := Vector2(heading.y, -heading.x)
		var tip_inside := tip + inward * TIP_THICKNESS * crest
		var ceiling := Vector2(0.0, crest - ROOT_THICKNESS * crest * sqrt(flight))
		var base := Vector2(FACE_BASE * reach * flight, -crest)
		var trough := Vector2(trough_distance, -crest)
		# The lip is the water thrown from the crest, so its outside follows the tip's path: the parabola
		# from the crest to the tip, one cubic exactly. Its underside is the parabola from the root of the
		# lip to the inside of the tip, level at the root and along the lip's heading at the tip.
		var thrown := Vector2(tip.x * 0.5, crest)
		var under := _corner(ceiling, tip_inside, heading)
		var wall := BACK_WALL * crest * flight
		var wall_handle := HANDLE * ceiling.distance_to(base)
		var run_handle := HANDLE * base.distance_to(trough)
		points = [
			PackedVector2Array([top, top.lerp(thrown, 2.0 / 3.0), tip.lerp(thrown, 2.0 / 3.0), tip]),
			PackedVector2Array([tip, tip.lerp(tip_inside, 1.0 / 3.0), tip.lerp(tip_inside, 2.0 / 3.0), tip_inside]),
			PackedVector2Array([tip_inside, tip_inside.lerp(under, 2.0 / 3.0), ceiling.lerp(under, 2.0 / 3.0), ceiling]),
			PackedVector2Array([ceiling, ceiling - Vector2(wall + wall_handle, 0.0), base - Vector2(wall_handle, 0.0), base]),
			PackedVector2Array([base, base + Vector2(run_handle, 0.0), trough - Vector2(run_handle, 0.0), trough]),
		]
		for part: PackedVector2Array in points:
			var length := BreakerProfile.bezier_length(part[0], part[1], part[2], part[3])
			lengths.append(length)
			total += length
		_splash_x = reach
		_splash_height = SPLASH_HEIGHT * crest * BreakerProfile.splash(breaker_stage)
		_splash_width = maxf(SPLASH_WIDTH * height, 1e-3)

	## Control point of the parabola that leaves `root` level and reaches `end` along `heading`: where
	## the two tangents meet (half way along when they hardly do).
	static func _corner(root: Vector2, end: Vector2, heading: Vector2) -> Vector2:
		var midway := Vector2((root.x + end.x) * 0.5, root.y)
		if heading.y > -1e-3:
			return midway
		var meet := end + heading * ((root.y - end.y) / heading.y)
		return meet if meet.x >= root.x and meet.x <= end.x else midway

	func at(phi: float) -> Vector3:
		if total <= 1e-9:
			return Vector3(0.0, points[0][0].y, float(Part.OUTER_LIP))
		var along := phi * total
		for part in range(points.size()):
			var length := lengths[part]
			if along <= length or part == points.size() - 1:
				var t := clampf(along / maxf(length, 1e-9), 0.0, 1.0)
				var c := points[part]
				var p := BreakerProfile.bezier(c[0], c[1], c[2], c[3], t)
				if part == Part.TROUGH:
					var off := (p.x - _splash_x) / _splash_width
					p.y += _splash_height * exp(-off * off)
				return Vector3(p.x, p.y, part + minf(t, 0.999))
			along -= length
		return Vector3.ZERO
