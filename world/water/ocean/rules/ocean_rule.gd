class_name OceanRule
extends Resource
## "If all conditions hold, then apply all effects." Rules run in order and see the results of the
## rules before them, so one rule can raise the wind and the next can react to that wind.

@export var label: String = ""
@export var enabled: bool = true
## All must hold (AND). Make a second rule for OR. No conditions means always.
@export var conditions: Array[OceanRuleCondition] = []
@export var effects: Array[OceanRuleEffect] = []
