class_name SwashEdge
extends RefCounted
## The swash on the CPU: the twin of water_swash_state() in swash.gdshaderinc (keep the two in step), so
## the water height gameplay reads (Ocean.height_at) runs up the beach with each wave like the surface.

## Same as SWASH_UPRUSH_SHARE in swash.gdshaderinc. The other numbers are ShoreWaves' SWASH_* ones.
const UPRUSH_SHARE := 0.3


## At world `p` and wave clock `time`, for a run-up of `runup` metres and waves `period` seconds apart:
## (height of the swash edge now, highest point this wave reaches, share of the swash cycle gone by,
## number of the wave), heights in metres above still water.
static func state(p: Vector2, time: float, runup: float, period: float) -> Vector4:
	if runup <= 0.0:
		return Vector4.ZERO
	var along := p / ShoreWaves.SWASH_ALONGSHORE
	var phase := time / maxf(period, 0.1) + ShoreWaves.noise(along) * ShoreWaves.SWASH_PHASE_SPREAD
	var wave := floorf(phase)
	var cycle := phase - wave
	var reach := runup * lerpf(ShoreWaves.SWASH_SMALLEST, 1.0,
			ShoreWaves.noise(along + Vector2.ONE * wave * ShoreWaves.SWASH_WAVE_STEP))
	var rush := smoothstep(0.0, UPRUSH_SHARE, cycle) if cycle < UPRUSH_SHARE \
			else 1.0 - smoothstep(UPRUSH_SHARE, 1.0, cycle)
	return Vector4(reach * rush, reach, cycle, wave)
