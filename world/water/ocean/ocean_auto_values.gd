class_name OceanAutoValues
extends RefCounted
## Values that follow from the rest of the sea state, for controls set to "auto": whitecaps grow
## with the wind. The waves themselves never follow the wind; they have their own sliders. Pure logic.

## Fitted to the calm / breeze / storm presets (4, 9 and 24 m/s).
## Grows with the square root of the wind: quickly in a breeze, slower once the sea is breaking.
const FOAM_BASE := 0.03
const FOAM_PER_ROOT_WIND := 0.17
const PARAMETERS: Array[StringName] = [&"foam_threshold"]


## True when `parameter` can be derived from the rest of the sea state.
static func has(parameter: StringName) -> bool:
	return PARAMETERS.has(parameter)


## The derived value of `parameter` for `sea`; NAN when it has none.
static func value(parameter: StringName, sea: OceanSpectrum) -> float:
	match parameter:
		&"foam_threshold":
			return FOAM_BASE + FOAM_PER_ROOT_WIND * sqrt(sea.wind_speed)
	return NAN
