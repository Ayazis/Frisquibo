class_name OceanTuning
extends Resource
## Everything the tuner can change on an Ocean, as one text resource: the sea state, the look, and
## the ocean's own numbers (sea level, shore values). Used for save / load and the A/B snapshot.

@export var spectrum: OceanSpectrum
@export var look: OceanLook
## The ocean's own tunables by name (level, breaker_ratio, ...).
@export var ocean_values: Dictionary[StringName, float] = {}


## A private copy of the ocean's current authored values; later edits to the ocean don't change it.
static func capture(ocean: Ocean) -> OceanTuning:
	var tuning := OceanTuning.new()
	tuning.spectrum = ocean.spectrum.duplicate(true) as OceanSpectrum
	if ocean.look != null:
		tuning.look = ocean.look.duplicate(true) as OceanLook
	for parameter: OceanParameter in OceanParameterCatalog.of(ocean, ""):
		if parameter.has_range:
			tuning.ocean_values[parameter.name] = ocean.parameter_value(parameter.name)
	return tuning


## Puts these values on the ocean. The ocean gets copies, so tuning it afterwards leaves this intact.
## Values for names the ocean no longer has are skipped.
func apply_to(ocean: Ocean) -> void:
	if spectrum != null:
		ocean.set_spectrum(spectrum.duplicate(true) as OceanSpectrum)
	if look != null:
		ocean.set_look(look.duplicate(true) as OceanLook)
	for parameter: StringName in ocean_values:
		ocean.set_parameter(parameter, ocean_values[parameter])
