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
	var end := field.origin(crest_rest)
	var lee := lerpf(waves.lee_share, 1.0,
			smoothstep(ShoreWaves.LEE_FROM, ShoreWaves.LEE_TO, state.towards.dot(waves.direction)))
	var gain := waves.amplitude * sqrt(waves.share) * lee * field.refraction(crest_rest)
	var free_crest := gain * ShoreWaves.wave_size(end, wave) \
			* pow(minf(waves.zone_depth, ShoreField.MAX_DEPTH) / maxf(still, ShoreField.MIN_DEPTH), 0.25)
	var limit := waves.breaker_ratio * still
	var ratio := free_crest / maxf(limit, 1e-4)
	state.crest = minf(free_crest, limit) * weight
	var ahead: float = depth_at.call(crest_rest + state.towards * SLOPE_STEP)
	var behind: float = depth_at.call(crest_rest - state.towards * SLOPE_STEP)
	var slope := maxf((behind - ahead) / (2.0 * SLOPE_STEP), BreakerProfile.MIN_SLOPE)
	state.stage = BreakerProfile.stage(still, ratio, slope, waves.breaker_ratio)
	if state.stage < 0.0:
		return state
	var height := 2.0 * waves.breaker_ratio * BreakerProfile.breaking_depth(still, ratio)
	state.plunge = BreakerProfile.plunge_share(BreakerProfile.surf_similarity(slope, height, waves.period), curl_strength)
	state.fold = BreakerProfile.fold(state.stage, state.plunge) * weight
	_lip(state, still, height)
	return state


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
	state.splash = BreakerProfile.SPLASH_HEIGHT * crest * BreakerProfile.splash(state.stage)
