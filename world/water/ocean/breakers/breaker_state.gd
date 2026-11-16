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
## For a point query (ShoreBreakers.at()): whether the point is inside the tube, under the flying lip.
var inside_tube := false


## True while the lip is in the air or the water it hit is splashing up.
func is_plunging() -> bool:
	return fold > 0.0 and stage >= 0.0 and stage < BreakerProfile.SPLASH.w
