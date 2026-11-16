class_name OceanTunerPanel
extends VBoxContainer
## Live controls for an Ocean, generated from its parameter catalogue: one foldable section per
## group, a slider per tunable and a picker per colour, physical readouts on top, links and
## save / load below. Sections run in SECTION_ORDER, whichever object their values live on.

const READOUTS_TITLE := "Sea state"
const LINKS_TITLE := "Links"
const STORAGE_TITLE := "Save and load"
const ARTISTIC_TITLE := "Artistic overrides"
## Top to bottom, the way a sea is described: the big waves, the wind on top of them, how the crests
## look and foam, the depth and shore, then the look. Values that leave physics behind come last.
## Every export group of OceanSpectrum, OceanLook and Ocean must be listed (ocean_parameters_test).
const SECTION_ORDER: Array[String] = [READOUTS_TITLE, "Main waves (swell)", "Wind and surface waves",
	"Crest shape", "Foam", "Depth and shore", "Water colour", "Surface light", "Caustics", ARTISTIC_TITLE,
	LINKS_TITLE, STORAGE_TITLE]
## Sections that start folded: rarely needed, and they make the sea less physical.
const FOLDED_SECTIONS: Array[String] = [ARTISTIC_TITLE]
## The section each colour of the look belongs to (an export group of OceanLook).
const COLOR_GROUPS: Dictionary[StringName, String] = {
	&"scatter_color": "Water colour",
	&"sss_color": "Water colour",
	&"deep_color": "Water colour",
	&"foam_color": "Foam",
}

var _ocean: Ocean
var _rows: Dictionary[StringName, OceanTunerRow] = {}
## Tunables currently set to follow from the rest of the sea state.
var _auto: Array[StringName] = []
var _colors: Dictionary[StringName, OceanTunerColorRow] = {}
var _sections: Dictionary[String, VBoxContainer] = {}
var _folds: Dictionary[String, FoldableContainer] = {}
var _links: OceanTunerLinks
var _readouts: OceanTunerReadouts


func _init(ocean: Ocean) -> void:
	_ocean = ocean
	_readouts = OceanTunerReadouts.new(ocean)
	_add_section(READOUTS_TITLE).add_child(_readouts)
	for parameter: OceanParameter in ocean.parameters():
		if not parameter.has_range:
			continue
		var row := OceanTunerRow.new(parameter, OceanAutoValues.has(parameter.name))
		row.set_live(ocean.is_parameter_live(parameter.name))
		row.value_changed.connect(_on_value_changed)
		row.auto_toggled.connect(_on_auto_toggled)
		_section(parameter.group).add_child(row)
		_rows[parameter.name] = row
	for color_name: StringName in OceanLookBinding.COLORS:
		var picker := OceanTunerColorRow.new(color_name, OceanLookBinding.COLOR_LABELS[color_name])
		picker.set_live(ocean.is_parameter_live(color_name))
		picker.color_changed.connect(_on_color_changed)
		_section(COLOR_GROUPS[color_name]).add_child(picker)
		_colors[color_name] = picker
	_links = OceanTunerLinks.new(ocean)
	_links.links_changed.connect(_sync)
	_add_section(LINKS_TITLE).add_child(_links)
	var storage := OceanTunerStorage.new(ocean)
	storage.applied.connect(_on_applied)
	_add_section(STORAGE_TITLE).add_child(storage)
	_order_sections()
	mark_defaults()


## Call after the ocean got a new sea state (a preset): its values become what Reset returns to,
## and the links apply on top of it.
func mark_defaults() -> void:
	for key: StringName in _rows:
		_rows[key].set_default(_ocean.parameter_value(key))
	_apply_derived(&"")
	_sync()


func set_link(link: OceanTunerLinks.Link, on: bool) -> void:
	_links.set_link(link, on)


## The section of a group, made on first use.
func _section(group: String) -> VBoxContainer:
	if not _sections.has(group):
		_add_section(group)
	return _sections[group]


func _add_section(title: String) -> VBoxContainer:
	var section := FoldableContainer.new()
	section.title = title
	section.focus_mode = Control.FOCUS_NONE
	section.folded = FOLDED_SECTIONS.has(title)
	var content := VBoxContainer.new()
	section.add_child(content)
	add_child(section)
	_sections[title] = content
	_folds[title] = section
	return content


## Puts the known sections in SECTION_ORDER; any other group follows them in the order it came.
func _order_sections() -> void:
	var index := 0
	for title: String in SECTION_ORDER:
		if _folds.has(title):
			move_child(_folds[title], index)
			index += 1


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
