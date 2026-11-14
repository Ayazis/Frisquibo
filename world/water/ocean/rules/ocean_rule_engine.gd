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
	for property: Dictionary in object.get_property_list():
		if _is_exported_float(property):
			var key: StringName = property.name
			var value: float = object.get(key)
			result[key] = value
	return result


## Allowed (min, max) of each ranged number parameter of `object`, from its export hints.
static func limits(object: Object) -> Dictionary[StringName, Vector2]:
	var result: Dictionary[StringName, Vector2] = {}
	for property: Dictionary in object.get_property_list():
		var hint_type: int = property.hint
		if not _is_exported_float(property) or hint_type != PROPERTY_HINT_RANGE:
			continue
		var hint: String = property.hint_string
		var parts: PackedStringArray = hint.split(",")
		if parts.size() < 2:
			continue
		var low: float = -INF if parts.has("or_less") else parts[0].to_float()
		var high: float = INF if parts.has("or_greater") else parts[1].to_float()
		var key: StringName = property.name
		result[key] = Vector2(low, high)
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


static func _is_exported_float(property: Dictionary) -> bool:
	var type: int = property.type
	var usage: int = property.usage
	return (type == TYPE_FLOAT and (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0
			and (usage & PROPERTY_USAGE_EDITOR) != 0)
