class_name OceanAutoValues
extends RefCounted
## Values that follow from the rest of the sea state, for controls set to "auto": whitecaps and
## crest sharpness grow with the wind. Pure logic.

## Fitted to the calm / breeze / storm presets (4, 9 and 24 m/s).
## Both grow with the square root of the wind: quickly in a breeze, slower once the sea is breaking.
const FOAM_BASE := 0.03
const FOAM_PER_ROOT_WIND := 0.17
const CHOP_BASE := 0.07
const CHOP_PER_ROOT_WIND := 0.27
const PARAMETERS: Array[StringName] = [&"foam_threshold", &"choppiness"]


## True when `parameter` can be derived from the rest of the sea state.
static func has(parameter: StringName) -> bool:
	return PARAMETERS.has(parameter)


## The derived value of `parameter` for `sea`; NAN when it has none.
static func value(parameter: StringName, sea: OceanSpectrum) -> float:
	match parameter:
		&"foam_threshold":
			return FOAM_BASE + FOAM_PER_ROOT_WIND * sqrt(sea.wind_speed)
		&"choppiness":
			return CHOP_BASE + CHOP_PER_ROOT_WIND * sqrt(sea.wind_speed)
	return NAN
