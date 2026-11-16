class_name OceanTunerColorRow
extends HBoxContainer
## One colour of the water's look, with a colour picker.

signal color_changed(color_name: StringName, color: Color)

const LABEL_WIDTH := 150.0
const PICKER_HEIGHT := 24.0

var color_name: StringName
var _picker := ColorPickerButton.new()


func _init(named: StringName, label_text: String) -> void:
	color_name = named
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = LABEL_WIDTH
	add_child(label)
	_picker.edit_alpha = false
	_picker.custom_minimum_size.y = PICKER_HEIGHT
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.focus_mode = Control.FOCUS_NONE
	_picker.color_changed.connect(_on_color_changed)
	add_child(_picker)


## Shows `color` without reporting it as a change.
func show_color(color: Color) -> void:
	_picker.color = color


func set_live(live: bool) -> void:
	_picker.disabled = not live


func _on_color_changed(color: Color) -> void:
	color_changed.emit(color_name, color)
