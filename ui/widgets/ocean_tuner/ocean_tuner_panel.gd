class_name OceanTunerPanel
extends VBoxContainer
## Live controls for an Ocean, generated from its parameter catalogue, as numbered steps in the order
## a sea is built: shape the waves, add the surface waves and wind, then the foam, the coast and
## beach, and last the look of the water. One step is open at a time. A step holds the sections
## (export groups) it lists, a slider per tunable and a picker per colour, and keeps the values few
## people need in a folded "Fine-tuning" part. Sea state readouts stay on top, save and load below.

const READOUTS_TITLE := "Sea state"
const STORAGE_TITLE := "Save and load"
const FINE_TUNING_TITLE := "Fine-tuning"
## Steps: title, a one-line hint, and the sections in it (export groups of OceanSpectrum, OceanLook and
## Ocean, in order). Every export group must be in a step (ocean_sea_systems_test).
const STEPS: Array[Array] = [
	["1  Wave shape", "The big waves and the shape of every crest. The wind doesn't change any of this.",
		["Main waves (swell)", "Crest shape", "Sea state changes"]],
	["2  Surface waves and wind",
		"Shorter waves on top of the swell, with their own size. Then the wind: ripples, gusts, spray, foam drift.",
		["Surface waves", "Wind"]],
	["3  Foam", "Whitecaps on breaking crests: how easily they form, how long they last, how they look.",
		["Foam"]],
	["4  Coast and beach", "How deep the water is, how waves break on the shore, and the beach itself.",
		["Water depth", "Shore waves", "Beach"]],
	["5  Water look", "Colour and clarity of the water, reflections and sun, light on the seabed.",
		["Water colour", "Surface light", "Caustics"]],
]
## The step that starts open.
const OPEN_STEP := 0
## Values few people need: in the folded fine-tuning part of their step.
const FINE_TUNING: Array[StringName] = [&"short_wave_cutoff", &"min_jacobian", &"transition_time",
	&"capillary_tile", &"capillary_speed", &"gust_size", &"foam_gain", &"foam_softness",
	&"foam_cascade_falloff", &"foam_far_distance", &"streak_length", &"foam_relief", &"wave_setup",
	&"min_shore_wave", &"shore_wave_depth", &"shore_wave_share", &"shore_lee_share",
	&"refraction_full_distance", &"reflection_distortion", &"base_slope_variance", &"murk_blur",
	&"caustic_fade", &"seabed_light_loss"]
## The section each colour of the look belongs to (an export group of OceanLook).
const COLOR_GROUPS: Dictionary[StringName, String] = {
	&"scatter_color": "Water colour",
	&"sss_color": "Water colour",
	&"deep_color": "Water colour",
	&"foam_color": "Foam",
}
const HINT_COLOR := Color(1.0, 1.0, 1.0, 0.6)
const SECTION_COLOR := Color(0.62, 0.8, 1.0)
const SECTION_GAP := 6.0

var _ocean: Ocean
var _rows: Dictionary[StringName, OceanTunerRow] = {}
## Tunables currently set to follow from the rest of the sea state.
var _auto: Array[StringName] = []
var _colors: Dictionary[StringName, OceanTunerColorRow] = {}
## Content of each section, by export group.
var _sections: Dictionary[String, VBoxContainer] = {}
## Header of each section a step lists, by export group; hidden while the section is empty.
var _headers: Dictionary[String, Control] = {}
## Fine-tuning part of each step, by step index, and the fold around it.
var _fine: Array[VBoxContainer] = []
var _fine_folds: Array[FoldableContainer] = []
var _step_folds: Array[FoldableContainer] = []
var _links: OceanTunerLinks
var _readouts: OceanTunerReadouts


func _init(ocean: Ocean) -> void:
	_ocean = ocean
	_readouts = OceanTunerReadouts.new(ocean)
	_add_fold(READOUTS_TITLE, false).add_child(_readouts)
	_add_steps()
	for parameter: OceanParameter in ocean.parameters():
		if not parameter.has_range:
			continue
		var row := OceanTunerRow.new(parameter, OceanAutoValues.has(parameter.name))
		row.set_live(ocean.is_parameter_live(parameter.name))
		row.value_changed.connect(_on_value_changed)
		row.auto_toggled.connect(_on_auto_toggled)
		_container_for(parameter.name, parameter.group).add_child(row)
		_rows[parameter.name] = row
	for color_name: StringName in OceanLookBinding.COLORS:
		var picker := OceanTunerColorRow.new(color_name, OceanLookBinding.COLOR_LABELS[color_name])
		picker.set_live(ocean.is_parameter_live(color_name))
		picker.color_changed.connect(_on_color_changed)
		_section(COLOR_GROUPS[color_name]).add_child(picker)
		_colors[color_name] = picker
	_links = OceanTunerLinks.new(ocean)
	_links.links_changed.connect(_sync)
	for entry: Array in OceanTunerLinks.LINKS:
		var link: OceanTunerLinks.Link = entry[0]
		_section(OceanTunerLinks.section_of(link)).add_child(_links.box(link))
	_hide_empty_parts()
	var storage := OceanTunerStorage.new(ocean)
	storage.applied.connect(_on_applied)
	_add_fold(STORAGE_TITLE, false).add_child(storage)
	mark_defaults()


## Index of the step that holds section `group`; -1 when no step lists it.
static func step_of(group: String) -> int:
	for index: int in range(STEPS.size()):
		var groups: Array = STEPS[index][2]
		if groups.has(group):
			return index
	return -1


## Call after the ocean got a new sea state (a preset): its values become what Reset returns to,
## and the links apply on top of it.
func mark_defaults() -> void:
	for key: StringName in _rows:
		_rows[key].set_default(_ocean.parameter_value(key))
	_apply_derived(&"")
	_sync()


## Opens step `index` and folds the others, showing values set on the ocean meanwhile.
func open_step(index: int) -> void:
	for i: int in range(_step_folds.size()):
		_step_folds[i].folded = i != index
	_sync()


func set_link(link: OceanTunerLinks.Link, on: bool) -> void:
	_links.set_link(link, on)


## One fold per step, of which one is open at a time, each with its sections and fine-tuning part.
func _add_steps() -> void:
	var accordion := FoldableGroup.new()
	accordion.allow_folding_all = true
	for index: int in range(STEPS.size()):
		var step: Array = STEPS[index]
		var title: String = step[0]
		var hint_text: String = step[1]
		var content := _add_fold(title, index != OPEN_STEP)
		var step_fold := content.get_parent() as FoldableContainer
		step_fold.foldable_group = accordion
		_step_folds.append(step_fold)
		var hint := Label.new()
		hint.text = hint_text
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_color_override(&"font_color", HINT_COLOR)
		content.add_child(hint)
		var groups: Array = step[2]
		for group: String in groups:
			_headers[group] = _section_header(group)
			content.add_child(_headers[group])
			var section := VBoxContainer.new()
			content.add_child(section)
			_sections[group] = section
		var fine := FoldableContainer.new()
		fine.title = FINE_TUNING_TITLE
		fine.folded = true
		fine.focus_mode = Control.FOCUS_NONE
		var fine_rows := VBoxContainer.new()
		fine.add_child(fine_rows)
		content.add_child(fine)
		_fine.append(fine_rows)
		_fine_folds.append(fine)


## Sections whose values all went to fine-tuning lose their header; steps with nothing to fine-tune
## lose that fold.
func _hide_empty_parts() -> void:
	for group: String in _headers:
		_headers[group].visible = _sections[group].get_child_count() > 0
	for index: int in range(_fine.size()):
		_fine_folds[index].visible = _fine[index].get_child_count() > 0


## Where the row of `parameter` goes: its section, or its step's fine-tuning part.
func _container_for(parameter: StringName, group: String) -> VBoxContainer:
	var step := step_of(group)
	if step >= 0 and FINE_TUNING.has(parameter):
		return _fine[step]
	return _section(group)


## The content of section `group`. A group no step lists gets a fold of its own at the end, so a new
## export group still shows up before it is given a step.
func _section(group: String) -> VBoxContainer:
	if not _sections.has(group):
		_sections[group] = _add_fold(group, true)
	return _sections[group]


func _section_header(title: String) -> Control:
	var box := VBoxContainer.new()
	var gap := Control.new()
	gap.custom_minimum_size.y = SECTION_GAP
	box.add_child(gap)
	var label := Label.new()
	label.text = title
	label.add_theme_color_override(&"font_color", SECTION_COLOR)
	box.add_child(label)
	return box


func _add_fold(title: String, folded: bool) -> VBoxContainer:
	var fold := FoldableContainer.new()
	fold.title = title
	fold.focus_mode = Control.FOCUS_NONE
	fold.folded = folded
	var content := VBoxContainer.new()
	fold.add_child(content)
	add_child(fold)
	return content


func _on_value_changed(parameter: StringName, value: float) -> void:
	_ocean.set_parameter(parameter, value)
	_apply_derived(parameter)
	_sync()


func _on_auto_toggled(parameter: StringName, on: bool) -> void:
	if on and not _auto.has(parameter):
		_auto.append(parameter)
	elif not on:
		_auto.erase(parameter)
	_apply_derived(&"")
	_sync()


## Applies the links, then every auto value. `changed` is the tunable the user just moved.
func _apply_derived(changed: StringName) -> void:
	_links.apply(changed)
	for parameter: StringName in _auto:
		_ocean.set_parameter(parameter, OceanAutoValues.value(parameter, _ocean.spectrum))


func _on_color_changed(color_name: StringName, color: Color) -> void:
	_ocean.look.set(color_name, color)
	_ocean.set_look(_ocean.look)


## Loaded or A/B-swapped values are shown as they are; links and Auto apply again on the next edit.
func _on_applied() -> void:
	_sync()


func _sync() -> void:
	for color_name: StringName in _colors:
		var color: Color = _ocean.look.get(color_name)
		_colors[color_name].show_color(color)
	var driven := _links.driven()
	driven.append_array(_auto)
	for key: StringName in _rows:
		_rows[key].show_value(_ocean.parameter_value(key))
		_rows[key].set_driven(driven.has(key))
	_readouts.refresh()
