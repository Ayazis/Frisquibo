class_name OceanTunerLinks
extends RefCounted
## Checkboxes that tie tunables together: surface waves keep their steepness, the water gets deeper
## when the sea rises. A tunable driven by a link follows its source and can't be moved by hand.
## Each box sits in the panel section of the tunables it ties (section_of()).
## Values that follow from the wind are not links: see the Auto box on their rows.

signal links_changed

enum Link { STEEPNESS, DEPTH_LEVEL }

## Links: id, label, the tunable it drives (none for the two-way steepness link), its panel section.
const LINKS: Array[Array] = [
	[Link.STEEPNESS, "Keep steepness: length follows height (and back)", &"", "Surface waves"],
	[Link.DEPTH_LEVEL, "Open sea depth follows sea level", &"depth", "Water depth"],
]
const MIN_SIZE_FOR_RATIO := 0.01

var _ocean: Ocean
var _boxes: Dictionary[Link, CheckBox] = {}
## Surface wave length / height when the steepness link was switched on.
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
		_boxes[id] = box


## The checkbox of `link`, for the panel to place.
func box(link: Link) -> CheckBox:
	return _boxes[link]


## The panel section (export group) `link` belongs in.
static func section_of(link: Link) -> String:
	for entry: Array in LINKS:
		var id: Link = entry[0]
		if id == link:
			return entry[3]
	return ""


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
		if changed == &"surface_length":
			_ocean.set_parameter(&"surface_height",
					_value(&"surface_length") / maxf(_steepness_ratio, MIN_SIZE_FOR_RATIO))
		else:
			_ocean.set_parameter(&"surface_length", _value(&"surface_height") * _steepness_ratio)
	if _boxes[Link.DEPTH_LEVEL].button_pressed:
		_ocean.set_parameter(&"depth", _value(&"level") + _depth_offset)


func _value(parameter: StringName) -> float:
	return _ocean.parameter_value(parameter)


func _on_toggled(on: bool, id: Link) -> void:
	if on:
		# Remember the current relation so switching a link on doesn't make the sea jump.
		match id:
			Link.STEEPNESS:
				_steepness_ratio = _value(&"surface_length") / maxf(_value(&"surface_height"), MIN_SIZE_FOR_RATIO)
			Link.DEPTH_LEVEL:
				_depth_offset = _value(&"depth") - _value(&"level")
	apply(&"")
	links_changed.emit()
