class_name OceanParameter
extends RefCounted
## One tunable number of the ocean: what a slider, a rule or a preset needs to know about it.

const SUFFIX_PREFIX := "suffix:"
const DEGREES_HINT := "degrees"
const DEGREES_UNIT := "°"
const OR_LESS := "or_less"
const OR_GREATER := "or_greater"
## Slider steps across the range when the export hint names no step.
const DEFAULT_STEPS := 200.0

var name: StringName
var label := ""
var group := ""
var description := ""
var unit := ""
## False when the export has no range: the value can be read and set, but has no slider.
var has_range := false
var minimum := 0.0
var maximum := 0.0
var step := 0.0
## The range is a slider suggestion only; values beyond that side are allowed.
var allow_less := false
var allow_greater := false


## Reads the range, step and unit from an `@export_range` hint string such as "0.5,80,0.1,suffix:m/s".
func read_range_hint(hint: String) -> void:
	var parts := hint.split(",")
	if parts.size() < 2:
		return
	has_range = true
	minimum = parts[0].to_float()
	maximum = parts[1].to_float()
	step = (maximum - minimum) / DEFAULT_STEPS
	for i: int in range(2, parts.size()):
		var part := parts[i].strip_edges()
		if part.is_valid_float():
			step = part.to_float()
		elif part == OR_LESS:
			allow_less = true
		elif part == OR_GREATER:
			allow_greater = true
		elif part == DEGREES_HINT:
			unit = DEGREES_UNIT
		elif part.begins_with(SUFFIX_PREFIX):
			unit = part.trim_prefix(SUFFIX_PREFIX)


## Allowed (min, max); infinite on a side the hint leaves open.
func limits() -> Vector2:
	return Vector2(-INF if allow_less else minimum, INF if allow_greater else maximum)


func clamp_value(value: float) -> float:
	if not has_range:
		return value
	var allowed := limits()
	return clampf(value, allowed.x, allowed.y)
