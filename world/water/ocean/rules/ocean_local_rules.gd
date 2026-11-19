class_name OceanLocalRules
extends RefCounted
## Rules whose condition or effect depends on the point of the surface, compiled for the shader
## (ocean.gdshader, local_rules()) and evaluated the same way on the CPU for floating objects.
## Global conditions are already folded into each rule's weight.

## Must match MAX_LOCAL_RULES in ocean.gdshader.
const MAX_RULES := 8
const FOAM := &"local_foam"
const WAVE_SIZE := &"local_wave_size"
const WATER_LEVEL := &"local_water_level"
const DEPTH := &"local_depth"
## Stands in for an open-ended depth range in the shader.
const UNBOUNDED := 1.0e6

enum Output { FOAM, WAVE_SIZE, WATER_LEVEL }

## Per rule: (min depth, max depth, softness at min, softness at max).
var depth_ranges := PackedVector4Array()
## Per rule: (output, operation, amount, weight from the global conditions).
var effects := PackedVector4Array()


static func is_local_target(target: StringName) -> bool:
	return target == FOAM or target == WAVE_SIZE or target == WATER_LEVEL


func count() -> int:
	return effects.size()


## Adds one local effect of a rule. Returns false when the shader's rule limit is reached.
func add(depth_range: Vector4, target: StringName, effect: OceanRuleEffect, weight: float) -> bool:
	if count() >= MAX_RULES:
		return false
	var output: Output = Output.FOAM
	if target == WAVE_SIZE:
		output = Output.WAVE_SIZE
	elif target == WATER_LEVEL:
		output = Output.WATER_LEVEL
	depth_ranges.append(depth_range)
	effects.append(Vector4(output, effect.operation, effect.amount, weight))
	return true


## (foam, wave size, water level) at a point with water depth `depth` (negative on dry land).
func evaluate(depth: float) -> Vector3:
	var result := Vector3(0.0, 1.0, 0.0)
	for i in range(count()):
		var r := depth_ranges[i]
		var e := effects[i]
		var w: float = e.w * _inside(depth, r)
		var axis := int(e.x)
		var operation := int(e.y) as OceanRuleEffect.Operation
		result[axis] = OceanRuleEffect.apply_operation(operation, e.z, result[axis], w)
	result.y = maxf(result.y, 0.0)
	return result


static func full_range() -> Vector4:
	return Vector4(-UNBOUNDED, UNBOUNDED, 0.0, 0.0)


static func _inside(depth: float, r: Vector4) -> float:
	return _soft_step(r.x, r.z, depth) * (1.0 - _soft_step(r.y, r.w, depth))


## Same as soft_step() in ocean.gdshader.
static func _soft_step(edge: float, softness: float, x: float) -> float:
	if softness <= 0.0:
		return 1.0 if x > edge else 0.0
	return smoothstep(edge - softness * 0.5, edge + softness * 0.5, x)
