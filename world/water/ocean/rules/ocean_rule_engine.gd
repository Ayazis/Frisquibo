class_name OceanRuleEngine
extends RefCounted
## Applies an OceanRuleSet to a set of named parameters. Pure logic: the Ocean gathers the parameters
## (its own, its spectrum's and the measured ones), and writes the results back.

## Measured from the simulation; conditions can read it, effects can't write it.
const WAVE_HEIGHT := &"wave_height"

## Rule results of one evaluation.
class Result:
	extends RefCounted
	var values: Dictionary[StringName, float] = {}
	var local := OceanLocalRules.new()
	## Human-readable problems with the rules (unknown parameters, too many local rules, ...).
	var problems := PackedStringArray()


## Number parameters of `object` exported in the inspector, by name.
static func parameters(object: Object) -> Dictionary[StringName, float]:
	var result: Dictionary[StringName, float] = {}
	for parameter_name: String in OceanParameterCatalog.names_of(object):
		var value: float = object.get(parameter_name)
		result[StringName(parameter_name)] = value
	return result


## Allowed (min, max) of each ranged number parameter of `object`, from its export hints.
static func limits(object: Object) -> Dictionary[StringName, Vector2]:
	var result: Dictionary[StringName, Vector2] = {}
	for parameter: OceanParameter in OceanParameterCatalog.of(object, ""):
		if parameter.has_range:
			result[parameter.name] = parameter.limits()
	return result


static func evaluate(rule_set: OceanRuleSet, values: Dictionary[StringName, float],
		value_limits: Dictionary[StringName, Vector2]) -> Result:
	var result := Result.new()
	result.values = values.duplicate()
	if rule_set == null:
		return result
	for rule: OceanRule in rule_set.rules:
		if rule != null and rule.enabled:
			_apply(rule, result, value_limits)
	return result


static func _apply(rule: OceanRule, result: Result, value_limits: Dictionary[StringName, Vector2]) -> void:
	var weight := 1.0
	var depth_range := OceanLocalRules.full_range()
	var rule_name := rule.label if rule.label != "" else rule.resource_path
	for condition: OceanRuleCondition in rule.conditions:
		if condition == null:
			continue
		if condition.parameter == OceanLocalRules.DEPTH:
			if condition.comparison == OceanRuleCondition.Comparison.GREATER:
				depth_range.x = maxf(depth_range.x, condition.threshold)
				depth_range.z = condition.softness
			else:
				depth_range.y = minf(depth_range.y, condition.threshold)
				depth_range.w = condition.softness
		elif result.values.has(condition.parameter):
			weight *= condition.weight(result.values[condition.parameter])
		else:
			result.problems.append("Rule '%s': unknown parameter '%s'" % [rule_name, condition.parameter])
			weight = 0.0
	var is_local := depth_range != OceanLocalRules.full_range()
	for effect: OceanRuleEffect in rule.effects:
		if effect == null:
			continue
		var target := effect.target
		if OceanLocalRules.is_local_target(target):
			if not result.local.add(depth_range, target, effect, weight):
				result.problems.append("Rule '%s': more than %d local effects" % [rule_name, OceanLocalRules.MAX_RULES])
		elif is_local:
			result.problems.append("Rule '%s': '%s' is one value for the whole sea and can't depend on local_depth; use a local_ output" % [rule_name, target])
		elif target == WAVE_HEIGHT or not result.values.has(target):
			result.problems.append("Rule '%s': can't change '%s'" % [rule_name, target])
		elif weight > 0.0:
			var value := effect.apply(result.values[target], weight)
			if value_limits.has(target):
				value = clampf(value, value_limits[target].x, value_limits[target].y)
			result.values[target] = value

