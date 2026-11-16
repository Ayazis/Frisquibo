class_name OceanTunerLinks
extends VBoxContainer
## Checkboxes that tie tunables together: the water gets deeper when the sea rises, wave steepness
## stays fixed. A tunable driven by a link follows its source and can't be moved by hand.
## Values that follow from the wind are not links: see the Auto box on their rows.

signal links_changed

enum Link { STEEPNESS, DEPTH_LEVEL }

## Links: id, label, the tunable it drives (none for the two-way steepness link).
const LINKS: Array[Array] = [
	[Link.STEEPNESS, "Keep steepness (horizontal follows vertical)", &""],
	[Link.DEPTH_LEVEL, "Water depth follows sea level", &"depth"],
]
const MIN_SIZE_FOR_RATIO := 0.01

var _ocean: Ocean
var _boxes: Dictionary[Link, CheckBox] = {}
## Horizontal / vertical size when the steepness link was switched on.
var _steepness_ratio := 1.0
## Water depth minus sea level when the depth link was switched on.
var _depth_offset := 0.0


func _init(ocean: Ocean) -> void:
	_ocean = ocean
	for link: Array in LINKS:
		var box := CheckBox.new()
		box.text = link[1]
		box.focus_mode = Control.FOCUS_NONE
		var id: Link = link[0]
		box.toggled.connect(_on_toggled.bind(id))
		add_child(box)
		_boxes[id] = box


func set_link(link: Link, on: bool) -> void:
	_boxes[link].button_pressed = on


## Tunables currently driven by a link.
func driven() -> Array[StringName]:
	var result: Array[StringName] = []
	for link: Array in LINKS:
		var id: Link = link[0]
		var target: StringName = link[2]
		if target != &"" and _boxes[id].button_pressed:
			result.append(target)
	return result


## Applies every active link. `changed` is the tunable the user just moved (for the two-way link).
func apply(changed: StringName) -> void:
	if _boxes[Link.STEEPNESS].button_pressed:
		if changed == &"wavelength_scale":
			_ocean.set_parameter(&"height_scale",
					_value(&"wavelength_scale") / maxf(_steepness_ratio, MIN_SIZE_FOR_RATIO))
		else:
			_ocean.set_parameter(&"wavelength_scale", _value(&"height_scale") * _steepness_ratio)
	if _boxes[Link.DEPTH_LEVEL].button_pressed:
		_ocean.set_parameter(&"depth", _value(&"level") + _depth_offset)


func _value(parameter: StringName) -> float:
	return _ocean.parameter_value(parameter)


func _on_toggled(on: bool, id: Link) -> void:
	if on:
		# Remember the current relation so switching a link on doesn't make the sea jump.
		match id:
			Link.STEEPNESS:
				_steepness_ratio = _value(&"wavelength_scale") / maxf(_value(&"height_scale"), MIN_SIZE_FOR_RATIO)
			Link.DEPTH_LEVEL:
				_depth_offset = _value(&"depth") - _value(&"level")
	apply(&"")
	links_changed.emit()
