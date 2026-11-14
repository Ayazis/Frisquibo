class_name OceanTunerRow
extends HBoxContainer
## One tunable: name, slider, value with unit, and a button back to the starting value. A tunable
## that follows from the rest of the sea state also gets an Auto box, which hands it to that rule.

signal value_changed(parameter: StringName, value: float)
signal auto_toggled(parameter: StringName, on: bool)

const LABEL_WIDTH := 150.0
const VALUE_WIDTH := 76.0
const RESET_TEXT := "Reset"
const AUTO_TEXT := "Auto"
const AUTO_NOTE := "Auto: follows from the wind. Untick to set it by hand."
const DRIVEN_NOTE := "Follows another control."
const NOT_LIVE_NOTE := "No effect here: needs the FFT ocean (desktop)."

var parameter: OceanParameter
var _slider := HSlider.new()
var _value := Label.new()
var _reset := Button.new()
var _auto: CheckBox
var _default := 0.0
var _driven := false
var _live := true


func _init(described: OceanParameter, can_be_auto: bool = false) -> void:
	parameter = described
	var label := Label.new()
	label.text = parameter.label
	label.custom_minimum_size.x = LABEL_WIDTH
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(label)
	_slider.min_value = parameter.minimum
	_slider.max_value = parameter.maximum
	_slider.step = parameter.step
	_slider.allow_lesser = parameter.allow_less
	_slider.allow_greater = parameter.allow_greater
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.value_changed.connect(_on_slider_changed)
	add_child(_slider)
	_value.custom_minimum_size.x = VALUE_WIDTH
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_value)
	if can_be_auto:
		_auto = CheckBox.new()
		_auto.text = AUTO_TEXT
		_auto.focus_mode = Control.FOCUS_NONE
		_auto.toggled.connect(_on_auto_toggled)
		add_child(_auto)
	_reset.text = RESET_TEXT
	_reset.flat = true
	_reset.focus_mode = Control.FOCUS_NONE
	_reset.pressed.connect(_on_reset_pressed)
	add_child(_reset)
	_update_state()


## Shows `value` without reporting it as a change.
func show_value(value: float) -> void:
	_slider.set_value_no_signal(value)
	_value.text = ("%s %s" % [_format(value), parameter.unit]).strip_edges()
	_update_state()


## The value the reset button returns to.
func set_default(value: float) -> void:
	_default = value
	_update_state()


## A driven row follows another control and can't be moved by hand.
func set_driven(driven: bool) -> void:
	_driven = driven
	_update_state()


## A row that is not live has no effect in the active renderer.
func set_live(live: bool) -> void:
	_live = live
	_update_state()


func _update_state() -> void:
	var usable := _live and not _driven
	_slider.editable = usable
	_reset.disabled = not usable or is_equal_approx(_slider.value, _default)
	if _auto != null:
		_auto.disabled = not _live
	var note := ""
	if not _live:
		note = NOT_LIVE_NOTE
	elif _auto != null and _auto.button_pressed:
		note = AUTO_NOTE
	elif _driven:
		note = DRIVEN_NOTE
	tooltip_text = "\n".join(PackedStringArray([parameter.description, note])).strip_edges()
	for child: Node in get_children():
		var control := child as Control
		if control != null:
			control.tooltip_text = tooltip_text


## As many decimals as the step needs, so a 0.005 step doesn't show as 0.01.
func _format(value: float) -> String:
	var decimals := clampi(ceili(-log(maxf(parameter.step, 1.0e-6)) / log(10.0) - 1.0e-6), 0, 4)
	return String.num(value, decimals).pad_decimals(decimals)


func _on_slider_changed(value: float) -> void:
	value_changed.emit(parameter.name, value)


func _on_auto_toggled(on: bool) -> void:
	auto_toggled.emit(parameter.name, on)


func _on_reset_pressed() -> void:
	value_changed.emit(parameter.name, _default)
