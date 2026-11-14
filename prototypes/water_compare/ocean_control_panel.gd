class_name OceanControlPanel
extends PanelContainer
## Sliders for the custom FFT ocean, plus "links": checkboxes that tie sliders together with a
## physical rule (foam and choppiness grow with the wind, deeper water when the sea rises, a fixed
## wave steepness). A slider driven by a link is greyed out and follows its source.

enum Target { SPECTRUM, OCEAN }

## Rows: property, label, min, max, step, where the property lives.
const ROWS: Array[Array] = [
	[&"wind_speed", "Wind (m/s)", 1.0, 60.0, 0.5, Target.SPECTRUM],
	[&"height_scale", "Vertical size", 0.0, 5.0, 0.05, Target.SPECTRUM],
	[&"wavelength_scale", "Horizontal size", 0.2, 4.0, 0.05, Target.SPECTRUM],
	[&"choppiness", "Choppiness", 0.0, 3.2, 0.05, Target.SPECTRUM],
	[&"short_wave_cutoff", "Smoothness", 0.0, 5.0, 0.05, Target.SPECTRUM],
	[&"swell", "Swell", 0.0, 2.0, 0.05, Target.SPECTRUM],
	[&"wind_direction", "Wind direction", -180.0, 180.0, 5.0, Target.SPECTRUM],
	[&"foam_threshold", "Foam amount", 0.0, 2.4, 0.02, Target.SPECTRUM],
	[&"foam_lifetime", "Foam lifetime (s)", 0.5, 24.0, 0.25, Target.SPECTRUM],
	[&"depth", "Water depth (m)", 2.0, 400.0, 1.0, Target.SPECTRUM],
	[&"level", "Sea level (m)", -6.0, 6.0, 0.1, Target.OCEAN],
	[&"breaker_ratio", "Max wave per depth", 0.05, 1.5, 0.01, Target.OCEAN],
]

enum Link { STEEPNESS, FOAM_WIND, CHOP_WIND, DEPTH_LEVEL }
## Links: id, label, the slider it drives (greyed out while on; none for the two-way steepness link).
const LINKS: Array[Array] = [
	[Link.STEEPNESS, "Keep steepness (horizontal follows vertical)", &""],
	[Link.FOAM_WIND, "Foam follows wind", &"foam_threshold"],
	[Link.CHOP_WIND, "Choppiness follows wind", &"choppiness"],
	[Link.DEPTH_LEVEL, "Water depth follows sea level", &"depth"],
]
## Fitted to the calm / breeze / storm presets (4, 9 and 19 m/s).
const FOAM_BASE := 0.15
const FOAM_PER_WIND := 0.035
const CHOP_BASE := 0.45
const CHOP_PER_WIND := 0.04
const MIN_SIZE_FOR_RATIO := 0.01

const PANEL_WIDTH := 360.0
const LABEL_WIDTH := 140.0
const VALUE_WIDTH := 52.0

var _ocean: Ocean
var _live: OceanSpectrum
var _sliders: Dictionary[StringName, HSlider] = {}
var _values: Dictionary[StringName, Label] = {}
var _targets: Dictionary[StringName, Target] = {}
var _links: Dictionary[Link, CheckBox] = {}
## Horizontal / vertical size when the steepness link was switched on.
var _steepness_ratio := 1.0
## Water depth minus sea level when the depth link was switched on.
var _depth_offset := 0.0


func _init(ocean: Ocean, live: OceanSpectrum) -> void:
	_ocean = ocean
	_live = live
	custom_minimum_size.x = PANEL_WIDTH
	var rows := VBoxContainer.new()
	add_child(rows)
	var heading := Label.new()
	heading.text = "Sea state (C cycles presets)"
	rows.add_child(heading)
	for row: Array in ROWS:
		_add_slider(rows, row)
	var links_heading := Label.new()
	links_heading.text = "Links"
	rows.add_child(links_heading)
	for link: Array in LINKS:
		var box := CheckBox.new()
		box.text = link[1]
		box.focus_mode = Control.FOCUS_NONE
		var id: Link = link[0]
		box.toggled.connect(_on_link_toggled.bind(id))
		rows.add_child(box)
		_links[id] = box
	_sync()


## A new preset was loaded: links still apply on top of it.
func set_spectrum(live: OceanSpectrum) -> void:
	_live = live
	_apply_links(&"")
	_sync()


func _add_slider(rows: VBoxContainer, row: Array) -> void:
	var key: StringName = row[0]
	var line := HBoxContainer.new()
	var label := Label.new()
	label.text = row[1]
	label.custom_minimum_size.x = LABEL_WIDTH
	line.add_child(label)
	var slider := HSlider.new()
	slider.min_value = row[2]
	slider.max_value = row[3]
	slider.step = row[4]
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(_on_slider_changed.bind(key))
	line.add_child(slider)
	var value := Label.new()
	value.custom_minimum_size.x = VALUE_WIDTH
	line.add_child(value)
	rows.add_child(line)
	_sliders[key] = slider
	_values[key] = value
	_targets[key] = row[5]


func _get_value(key: StringName) -> float:
	return _ocean.get(key) if _targets[key] == Target.OCEAN else _live.get(key)


func _set_value(key: StringName, value: float) -> void:
	if _targets[key] == Target.SPECTRUM:
		_live.set(key, value)
	elif key == &"level":
		_ocean.set_level(value)
	elif key == &"breaker_ratio":
		_ocean.set_breaker_ratio(value)


func _on_slider_changed(value: float, key: StringName) -> void:
	_set_value(key, value)
	_apply_links(key)
	_ocean.set_spectrum(_live)
	_sync()


func _on_link_toggled(on: bool, id: Link) -> void:
	if on:
		# Remember the current relation so switching a link on doesn't make the sea jump.
		match id:
			Link.STEEPNESS:
				_steepness_ratio = _live.wavelength_scale / maxf(_live.height_scale, MIN_SIZE_FOR_RATIO)
			Link.DEPTH_LEVEL:
				_depth_offset = _live.depth - _ocean.level
	_apply_links(&"")
	_ocean.set_spectrum(_live)
	_sync()


## Applies every active link. `changed` is the slider the user just moved (for the two-way link).
func _apply_links(changed: StringName) -> void:
	if _links.is_empty():
		return
	if _links[Link.STEEPNESS].button_pressed:
		if changed == &"wavelength_scale":
			_live.height_scale = clampf(_live.wavelength_scale / maxf(_steepness_ratio, MIN_SIZE_FOR_RATIO),
					_sliders[&"height_scale"].min_value, _sliders[&"height_scale"].max_value)
		else:
			_live.wavelength_scale = clampf(_live.height_scale * _steepness_ratio,
					_sliders[&"wavelength_scale"].min_value, _sliders[&"wavelength_scale"].max_value)
	if _links[Link.FOAM_WIND].button_pressed:
		_live.foam_threshold = clampf(FOAM_BASE + FOAM_PER_WIND * _live.wind_speed,
				_sliders[&"foam_threshold"].min_value, _sliders[&"foam_threshold"].max_value)
	if _links[Link.CHOP_WIND].button_pressed:
		_live.choppiness = clampf(CHOP_BASE + CHOP_PER_WIND * _live.wind_speed,
				_sliders[&"choppiness"].min_value, _sliders[&"choppiness"].max_value)
	if _links[Link.DEPTH_LEVEL].button_pressed:
		_live.depth = clampf(_ocean.level + _depth_offset, _sliders[&"depth"].min_value, _sliders[&"depth"].max_value)


func _sync() -> void:
	for key: StringName in _sliders:
		var v := _get_value(key)
		_sliders[key].set_value_no_signal(v)
		_values[key].text = "%.2f" % v
		_sliders[key].editable = true
	for link: Array in LINKS:
		var driven: StringName = link[2]
		var id: Link = link[0]
		if driven != &"" and _links.has(id) and _links[id].button_pressed:
			_sliders[driven].editable = false
