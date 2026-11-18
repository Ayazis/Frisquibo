class_name BreakerState
extends RefCounted
## One breaking crest at one spot along the coast, as ShoreBreakers finds it on the CPU: for spray, mist,
## sound and gameplay. All positions are world space.

## Time since the crest broke, in lip flight times (negative: not breaking).
var stage := -1.0
## How much it plunges (0: it spills or surges), with the curl strength applied.
var plunge := 0.0
## How folded it is now (BreakerProfile.fold()).
var fold := 0.0
## Crest height above still water (m).
var crest := 0.0
## Direction of travel, towards the shore.
var towards := Vector2.RIGHT
## Where the crest's water rests, and the still water level there.
var crest_rest := Vector2.ZERO
var level := 0.0
## The lip's tip and how fast it moves; where it comes down.
var tip := Vector3.ZERO
var tip_velocity := Vector3.ZERO
var landing := Vector3.ZERO
## Height of the splash-up where the lip lands (m).
var splash := 0.0
## How fast the crest runs towards the shore (m/s), and the wave clock when this state was sampled.
var crest_speed := 0.0
var sampled_at := 0.0
## For a point query (ShoreBreakers.at()): whether the point is inside the tube, under the flying lip.
var inside_tube := false


## The lip's tip `time` (wave clock) after this state was sampled: carried on along its velocity.
func tip_at(time: float) -> Vector3:
	return tip + tip_velocity * (time - sampled_at)


## Where the lip comes down, `time` after sampling: carried on with the crest.
func landing_at(time: float) -> Vector3:
	return landing + Vector3(towards.x, 0.0, towards.y) * crest_speed * (time - sampled_at)


## True while the lip is in the air or the water it hit is splashing up.
func is_plunging() -> bool:
	return fold > 0.0 and stage >= 0.0 and stage < BreakerProfile.SPLASH.w
