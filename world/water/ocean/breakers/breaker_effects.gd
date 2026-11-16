class_name BreakerEffects
extends Node3D
## What plunging breakers throw into the air, and when they land: samples the crests the ribbons follow
## (OceanBreakers.active) on the CPU (ShoreBreakers) and feeds the spray off the lips and the splash-ups
## (BreakerSpray), the mist over the plunge lines (BreakerMist), and the `plunged` signal (for sound).

## A lip comes down here (where, how high the breaker was). For sound and gameplay effects.
signal plunged(position: Vector3, height: float)

## Metres between samples along a crest.
const STRIDE := 4.0
## Spray peels off the lip tip between these stages, and splashes up where it lands between these.
const TIP_STAGES := Vector2(0.25, 1.05)
const SPLASH_STAGES := Vector2(0.9, 1.5)
## Share of particle restarts a fully plunging sample takes, for the tip and for the splash-up.
const TIP_RATE := 0.6
const SPLASH_RATE := 1.0
## Splash droplets are this much bigger than tip droplets.
const SPLASH_SIZE := 1.6
## Mist hangs over a plunge line from the landing until the tube has collapsed.
const MIST_STAGES := Vector2(0.9, BreakerProfile.COLLAPSE.y)
## A sample counts as plunging (for sound) above this much plunge.
const PLUNGE_FOR_SOUND := 0.3

var _ribbons: OceanBreakers
var _rays: ShoreRays
var _query: ShoreBreakers
var _spray: BreakerSpray
var _mist: BreakerMist
## Last stage seen per (sample bucket, crest), to notice the moment a lip lands.
var _stages: Dictionary[Vector2i, float] = {}


## `spray_particles` 0: no spray; `mist` false: no mist.
func _init(ribbons: OceanBreakers, rays: ShoreRays, query: ShoreBreakers, spray_particles: int, mist: bool,
		bounds: AABB) -> void:
	_ribbons = ribbons
	_rays = rays
	_query = query
	if spray_particles > 0:
		_spray = BreakerSpray.new(spray_particles, bounds.grow(OceanBreakers.ROOM))
		add_child(_spray)
	if mist:
		_mist = BreakerMist.new(bounds.grow(OceanBreakers.ROOM))
		add_child(_mist)


func update(time: float, period: float, wind: Vector2) -> void:
	var stride := maxi(roundi(STRIDE / ShoreRays.SPACING), 1)
	var positions := PackedVector3Array()
	var rates := PackedFloat32Array()
	var velocities := PackedVector3Array()
	var sizes := PackedFloat32Array()
	var lines: Array[PackedVector3Array] = []
	var heights: Array[PackedFloat32Array] = []
	var strengths: Array[PackedFloat32Array] = []
	var seen: Dictionary[Vector2i, float] = {}
	for lay: Vector4 in _ribbons.active:
		var wave := lay.z
		var line := PackedVector3Array()
		var line_heights := PackedFloat32Array()
		var line_strengths := PackedFloat32Array()
		for k in range(0, int(lay.y), stride):
			var row := _ribbons.row_after(int(lay.x), k)
			var crest_rest := _rays.position(row, _ribbons.crest_time(row, wave, time, period))
			var state := _query.at_crest(crest_rest, wave)
			_emit(state, positions, rates, velocities, sizes)
			var key := Vector2i(row / stride, int(wave))
			seen[key] = state.stage
			if state.plunge >= PLUNGE_FOR_SOUND and _stages.get(key, -1.0) < 1.0 and state.stage >= 1.0:
				plunged.emit(state.landing, 2.0 * state.crest)
			var misty := state.fold > 0.0 and state.stage >= MIST_STAGES.x and state.stage <= MIST_STAGES.y
			if misty:
				line.append(state.landing)
				line_heights.append(state.crest)
				line_strengths.append(state.plunge * (1.0 - smoothstep(MIST_STAGES.x, MIST_STAGES.y, state.stage)))
			elif line.size() > 0:
				lines.append(line)
				heights.append(line_heights)
				strengths.append(line_strengths)
				line = PackedVector3Array()
				line_heights = PackedFloat32Array()
				line_strengths = PackedFloat32Array()
		if line.size() > 0:
			lines.append(line)
			heights.append(line_heights)
			strengths.append(line_strengths)
	_stages = seen
	if _spray != null:
		_spray.set_emitters(positions, rates, velocities, sizes)
		_spray.set_sea_level(_query.level)
	if _mist != null:
		_mist.set_lines(lines, heights, strengths, wind)


func _emit(state: BreakerState, positions: PackedVector3Array, rates: PackedFloat32Array,
		velocities: PackedVector3Array, sizes: PackedFloat32Array) -> void:
	if state.fold <= 0.0:
		return
	if state.stage >= TIP_STAGES.x and state.stage <= TIP_STAGES.y:
		positions.append(state.tip)
		rates.append(state.fold * TIP_RATE)
		velocities.append(state.tip_velocity)
		sizes.append(1.0)
	if state.splash > 0.0 and state.stage >= SPLASH_STAGES.x and state.stage <= SPLASH_STAGES.y:
		var along := Vector3(state.towards.x, 0.0, state.towards.y)
		positions.append(state.landing)
		rates.append(state.plunge * BreakerProfile.splash(state.stage) * SPLASH_RATE)
		# Thrown up as high as the splash-up, carried on with the crest.
		var crest_speed := state.tip_velocity.dot(along) * 0.5
		velocities.append(along * crest_speed + Vector3.UP * sqrt(2.0 * BreakerProfile.GRAVITY * state.splash))
		sizes.append(SPLASH_SIZE)
