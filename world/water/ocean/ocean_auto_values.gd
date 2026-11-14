class_name OceanAutoValues
extends RefCounted
## Values that follow from the rest of the sea state, for controls set to "auto": whitecaps and
## crest sharpness grow with the wind. Pure logic.

## Fitted to the calm / breeze / storm presets (4, 9 and 19 m/s).
const FOAM_BASE := 0.15
const FOAM_PER_WIND := 0.035
const CHOP_BASE := 0.45
const CHOP_PER_WIND := 0.04
const PARAMETERS: Array[StringName] = [&"foam_threshold", &"choppiness"]


## True when `parameter` can be derived from the rest of the sea state.
static func has(parameter: StringName) -> bool:
	return PARAMETERS.has(parameter)


## The derived value of `parameter` for `sea`; NAN when it has none.
static func value(parameter: StringName, sea: OceanSpectrum) -> float:
	match parameter:
		&"foam_threshold":
			return FOAM_BASE + FOAM_PER_WIND * sea.wind_speed
		&"choppiness":
			return CHOP_BASE + CHOP_PER_WIND * sea.wind_speed
	return NAN
