class_name OceanRuleEffect
extends Resource
## One "then" of an OceanRule, e.g. `foam_gain += 5`. `target` is any number parameter of the ocean or
## its spectrum, or a local output applied per point of the surface:
##   local_foam         foam cover (0 none, 1 fully white), added to whitecaps and surf
##   local_wave_size    multiplier on the wave height at that point (1 = unchanged)
##   local_water_level  metres of extra water at that point (surge, set-up), floods low ground

enum Operation { ADD, MULTIPLY, SET }

@export var target: StringName = &"local_foam"
@export var operation: Operation = Operation.ADD
@export var amount: float = 0.0


## `current` after this effect at rule weight `w` (0..1): partial weights blend towards the result.
func apply(current: float, w: float) -> float:
	return apply_operation(operation, amount, current, w)


## apply() for an effect given by its parts, without making one (OceanLocalRules runs this per point).
static func apply_operation(op: Operation, by: float, current: float, w: float) -> float:
	match op:
		Operation.ADD:
			return current + by * w
		Operation.MULTIPLY:
			return current * lerpf(1.0, by, w)
		_:
			return lerpf(current, by, w)
