class_name ShoreBreakers
extends RefCounted
## Plunging breakers on the CPU: the twin of breaker_at() in ocean_breakers.gdshaderinc, for what the GPU
## can't tell the game: where the lips fly (spray, mist), when they land (sound), and whether a spot is
## inside a tube. Built on the CPU shore waves (ShoreWaves) and the breaker profile (BreakerProfile).

## Metres either side of the crest the seabed slope is measured over (BREAKER_SLOPE_STEP).
const SLOPE_STEP := 2.0

var waves: ShoreWaves
## Seabed depth below the still sea at a rest point (Vector2 -> float), and the still water depth with
## set-up and rule water (Ocean._depth_at, Ocean._still_depth).
var depth_at: Callable
var still_at: Callable
## Rest level of the sea (m).
var level := 0.0
## How hard waves plunge (1: physical).
var curl_strength := 1.0


## The breaker of crest number `wave` whose water rests at `crest_rest`.
func at_crest(crest_rest: Vector2, wave: float) -> BreakerState:
	var state := BreakerState.new()
	state.crest_rest = crest_rest
	state.sampled_at = waves.time
	var field := waves.field
	if field == null or curl_strength <= 0.0:
		return state
	var f := field.sample(crest_rest)
	var gradient := Vector2(f.g, f.b)
	if f.a < 0.5 or gradient.length_squared() < 1e-12:
		return state
	state.towards = -gradient.normalized()
	var still: float = still_at.call(crest_rest)
	var raw: float = depth_at.call(crest_rest)
	state.level = level + still - raw
	var weight := waves.weight(still)
	if weight <= 0.0:
		return state
	var free_crest := _free_crest(crest_rest, state.towards, still, wave)
	var limit := waves.breaker_ratio * still
	state.crest = minf(free_crest, limit) * weight
	# Stage, plunge and fold averaged along the crest (the fold itself, as breaker_at() does).
	var along := Vector2(-state.towards.y, state.towards.x)
	var stage := 0.0
	var plunge := 0.0
	var fold := 0.0
	var total := 0.0
	for k in range(BreakerProfile.PEEL_TAPS):
		var offset := float(k - BreakerProfile.PEEL_TAPS / 2)
		var tap := _stage_plunge(crest_rest + along * offset * BreakerProfile.PEEL_STEP, state.towards, wave)
		var tap_weight := (float(BreakerProfile.PEEL_TAPS / 2 + 1) - absf(offset)) * tap.z
		stage += tap.x * tap_weight
		plunge += tap.y * tap_weight
		fold += BreakerProfile.fold(tap.x, tap.y) * tap_weight
		total += tap_weight
	if total <= 0.0:
		return state
	state.stage = stage / total
	state.plunge = plunge / total
	state.fold = fold / total * weight
	var height := 2.0 * waves.breaker_ratio * BreakerProfile.breaking_depth(still, free_crest / maxf(limit, 1e-4))
	_lip(state, still, height)
	return state


## Open-sea crest height this coast gives crest number `wave` at `p` (travelling `towards`, still water
## `still` deep), before the depth limit: refraction and the per-wave size read at `p`.
func _free_crest(p: Vector2, towards: Vector2, still: float, wave: float) -> float:
	var field := waves.field
	var lee := lerpf(waves.lee_share, 1.0, smoothstep(ShoreWaves.LEE_FROM, ShoreWaves.LEE_TO, towards.dot(waves.direction)))
	var gain := waves.amplitude * sqrt(waves.share) * lee * field.refraction(p)
	return gain * ShoreWaves.wave_size(field.origin(p), wave) \
			* pow(minf(waves.zone_depth, ShoreField.MAX_DEPTH) / maxf(still, ShoreField.MIN_DEPTH), 0.25)


## Stage and plunge share of crest number `wave` with its crest water at `p`, travelling `towards`:
## (stage, plunge share, weight), weight 0 where there is no shore wave (breaker_stage_plunge()).
func _stage_plunge(p: Vector2, towards: Vector2, wave: float) -> Vector3:
	var still: float = still_at.call(p)
	var weight := waves.weight(still) * smoothstep(0.0, BreakerProfile.PEEL_SHORE, still)
	if weight <= 0.0 or not waves.field.area.has_point(p):
		return Vector3(BreakerProfile.PEEL_BEFORE, 0.0, 0.0)
	var ratio := _free_crest(p, towards, still, wave) / maxf(waves.breaker_ratio * still, 1e-4)
	var ahead: float = depth_at.call(p + towards * SLOPE_STEP)
	var behind: float = depth_at.call(p - towards * SLOPE_STEP)
	var slope := maxf((behind - ahead) / (2.0 * SLOPE_STEP), BreakerProfile.MIN_SLOPE)
	var stage := BreakerProfile.peel_stage(still, ratio, slope, waves.breaker_ratio)
	var height := maxf(2.0 * waves.breaker_ratio * still * pow(maxf(ratio, 1e-3), BreakerProfile.BREAK_DEPTH_EXPONENT), 1e-3)
	var plunge := BreakerProfile.plunge_share(BreakerProfile.surf_similarity(slope, height, waves.period), curl_strength)
	return Vector3(stage, plunge, weight)


## The breaker at world `xz` as a point on the water: the crest it belongs to, and whether `xz` lies
## under that crest's flying lip.
func at(xz: Vector2) -> BreakerState:
	var field := waves.field
	if field == null:
		return BreakerState.new()
	var f := field.sample(xz)
	var gradient := Vector2(f.g, f.b)
	var slowness := gradient.length()
	if f.a < 0.5 or slowness <= 0.0:
		return BreakerState.new()
	var towards := -gradient / slowness
	var end := field.origin(xz)
	var cycle := maxf(waves.period, 0.1)
	var phase := (waves.time + f.r) / cycle + ShoreWaves.noise(end / ShoreWaves.SWASH_ALONGSHORE) * ShoreWaves.SWASH_PHASE_SPREAD
	var u := phase - floorf(phase)
	# Metres ahead of the crest that follows: the crest is this far back along the direction of travel.
	var ahead := (1.0 - u) * cycle / slowness
	var state := at_crest(xz - towards * ahead, floorf(phase) + 1.0)
	var under_lip := ahead < state.tip.distance_to(Vector3(state.crest_rest.x, state.tip.y, state.crest_rest.y))
	state.inside_tube = state.fold > 0.5 and state.stage < 1.0 and under_lip
	return state


## Where the lip's tip is and how it moves, and where it lands (BreakerProfile's ballistic lip).
func _lip(state: BreakerState, still: float, height: float) -> void:
	var flight := clampf(state.stage, 0.0, 1.0)
	var crest := state.crest
	var reach := BreakerProfile.LIP_REACH * 2.0 * crest
	var along := Vector3(state.towards.x, 0.0, state.towards.y)
	var base := Vector3(state.crest_rest.x, state.level, state.crest_rest.y)
	state.tip = base + along * reach * flight + Vector3.UP * (crest - 2.0 * crest * flight * flight)
	state.landing = base + along * reach + Vector3.UP * -crest
	# The crest runs at the shallow-water speed; in its frame the tip moves on at reach per flight time
	# and falls 2 crest heights in one flight time.
	var flight_time := sqrt(2.0 * height / BreakerProfile.GRAVITY)
	var crest_speed := sqrt(BreakerProfile.GRAVITY * maxf(still, ShoreField.MIN_DEPTH))
	var forwards := crest_speed + reach / maxf(flight_time, 1e-3)
	var down := 4.0 * crest * flight / maxf(flight_time, 1e-3)
	state.tip_velocity = along * forwards + Vector3.DOWN * down
	state.crest_speed = crest_speed
	state.splash = BreakerProfile.SPLASH_HEIGHT * crest * BreakerProfile.splash(state.stage)
