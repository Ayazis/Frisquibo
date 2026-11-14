class_name OceanTunerPanel
extends VBoxContainer
## Live controls for an Ocean, generated from its parameter catalogue: one foldable section per
## group, a slider per tunable, physical readouts on top and the links below.

const READOUTS_TITLE := "Sea state"
const LINKS_TITLE := "Links"

var _ocean: Ocean
var _rows: Dictionary[StringName, OceanTunerRow] = {}
var _links: OceanTunerLinks
var _readouts: OceanTunerReadouts


func _init(ocean: Ocean) -> void:
	_ocean = ocean
	_readouts = OceanTunerReadouts.new(ocean)
	_add_section(READOUTS_TITLE).add_child(_readouts)
	var sections: Dictionary[String, VBoxContainer] = {}
	for parameter: OceanParameter in ocean.parameters():
		if not parameter.has_range:
			continue
		if not sections.has(parameter.group):
			sections[parameter.group] = _add_section(parameter.group)
		var row := OceanTunerRow.new(parameter)
		row.set_live(ocean.is_parameter_live(parameter.name))
		row.value_changed.connect(_on_value_changed)
		sections[parameter.group].add_child(row)
		_rows[parameter.name] = row
	_links = OceanTunerLinks.new(ocean)
	_links.links_changed.connect(_sync)
	_add_section(LINKS_TITLE).add_child(_links)
	mark_defaults()


## Call after the ocean got a new sea state (a preset): its values become what Reset returns to,
## and the links apply on top of it.
func mark_defaults() -> void:
	for key: StringName in _rows:
		_rows[key].set_default(_ocean.parameter_value(key))
	_links.apply(&"")
	_sync()


func set_link(link: OceanTunerLinks.Link, on: bool) -> void:
	_links.set_link(link, on)


func _add_section(title: String) -> VBoxContainer:
	var section := FoldableContainer.new()
	section.title = title
	section.focus_mode = Control.FOCUS_NONE
	var content := VBoxContainer.new()
	section.add_child(content)
	add_child(section)
	return content


func _on_value_changed(parameter: StringName, value: float) -> void:
	_ocean.set_parameter(parameter, value)
	_links.apply(parameter)
	_sync()


func _sync() -> void:
	var driven := _links.driven()
	for key: StringName in _rows:
		_rows[key].show_value(_ocean.parameter_value(key))
		_rows[key].set_driven(driven.has(key))
	_readouts.refresh()
