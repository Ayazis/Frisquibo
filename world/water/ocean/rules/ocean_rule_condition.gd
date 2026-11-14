class_name OceanRuleCondition
extends Resource
## One "if" of an OceanRule: compares a parameter with a threshold, e.g. `wind_speed > 12`.
## `parameter` is any number parameter of the ocean or its spectrum (wind_speed, depth, level, foam_gain,
## ...), the measured `wave_height`, or `local_depth`: the water depth at each point of the surface.

enum Comparison { LESS, GREATER }

@export var parameter: StringName = &"wind_speed"
@export var comparison: Comparison = Comparison.GREATER
@export var threshold: float = 0.0
## Width of the fade around the threshold, in the parameter's units. 0 switches hard; a few units
## blend the effect in, so foam and waves never pop.
@export_range(0.0, 100.0, 0.01, "or_greater") var softness: float = 0.0


## How strongly the condition holds for `value`, from 0 (false) to 1 (true).
func weight(value: float) -> float:
	var half := softness * 0.5
	var above: float = 1.0 if value > threshold else 0.0
	if half > 0.0:
		above = smoothstep(threshold - half, threshold + half, value)
	return above if comparison == Comparison.GREATER else 1.0 - above
