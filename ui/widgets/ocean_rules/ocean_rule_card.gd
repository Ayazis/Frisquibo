class_name OceanRuleCard
extends PanelContainer
## Edits one OceanRule in place: enabled, name, its "if" conditions and "then" effects.
## Value edits emit `edited`; adding or removing rows rebuilds the card itself; moving or deleting the
## whole rule is asked of the owner through the other signals.

signal edited
signal move_requested(step: int)
signal delete_requested

const COMPARISONS: Array[String] = ["<", ">"]
const OPERATIONS: Array[String] = ["+=", "×=", "="]
const NUMBER_STEP := 0.01
const NUMBER_WIDTH := 72.0
const NAME_WIDTH := 150.0
const SOFTNESS_TOOLTIP := "Fade: width of the blend around the threshold (0 switches hard)"

var rule: OceanRule
var _parameters: PackedStringArray
var _targets: PackedStringArray
var _body: VBoxContainer


## `parameters`: what conditions can read. `targets`: what effects can change.
func _init(edited_rule: OceanRule, parameters: PackedStringArray, targets: PackedStringArray) -> void:
	rule = edited_rule
	_parameters = parameters
	_targets = targets
	_body = VBoxContainer.new()
	add_child(_body)
	_build()


func _build() -> void:
	for child in _body.get_children():
		child.queue_free()
	_body.add_child(_header())
	_body.add_child(_caption("If (all of)" if not rule.conditions.is_empty() else "If: always"))
	for condition: OceanRuleCondition in rule.conditions:
		if condition != null:
			_body.add_child(_condition_row(condition))
	_body.add_child(_add_button("+ condition", _add_condition))
	_body.add_child(_caption("Then"))
	for effect: OceanRuleEffect in rule.effects:
		if effect != null:
			_body.add_child(_effect_row(effect))
	_body.add_child(_add_button("+ effect", _add_effect))


func _header() -> HBoxContainer:
	var row := HBoxContainer.new()
	var on := CheckBox.new()
	on.button_pressed = rule.enabled
	on.tooltip_text = "Rule on/off"
	on.focus_mode = Control.FOCUS_NONE
	on.toggled.connect(func(value: bool) -> void:
		rule.enabled = value
		edited.emit())
	row.add_child(on)
	var title := LineEdit.new()
	title.text = rule.label
	title.placeholder_text = "Rule name"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_changed.connect(func(value: String) -> void: rule.label = value)
	row.add_child(title)
	row.add_child(_icon_button("↑", "Earlier (rules run top to bottom)", func() -> void: move_requested.emit(-1)))
	row.add_child(_icon_button("↓", "Later", func() -> void: move_requested.emit(1)))
	row.add_child(_icon_button("✕", "Delete rule", func() -> void: delete_requested.emit()))
	return row


func _condition_row(condition: OceanRuleCondition) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_child(_choice(_parameters, String(condition.parameter), NAME_WIDTH, func(value: String) -> void:
		condition.parameter = StringName(value)))
	row.add_child(_choice(PackedStringArray(COMPARISONS), COMPARISONS[condition.comparison], 0.0, func(value: String) -> void:
		condition.comparison = COMPARISONS.find(value) as OceanRuleCondition.Comparison))
	row.add_child(_number(condition.threshold, "Threshold", func(value: float) -> void: condition.threshold = value))
	row.add_child(_number(condition.softness, SOFTNESS_TOOLTIP, func(value: float) -> void: condition.softness = value, 0.0))
	row.add_child(_icon_button("✕", "Remove condition", func() -> void:
		rule.conditions.erase(condition)
		_changed_structure()))
	return row


func _effect_row(effect: OceanRuleEffect) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_child(_choice(_targets, String(effect.target), NAME_WIDTH, func(value: String) -> void:
		effect.target = StringName(value)))
	row.add_child(_choice(PackedStringArray(OPERATIONS), OPERATIONS[effect.operation], 0.0, func(value: String) -> void:
		effect.operation = OPERATIONS.find(value) as OceanRuleEffect.Operation))
	row.add_child(_number(effect.amount, "Amount", func(value: float) -> void: effect.amount = value))
	row.add_child(_icon_button("✕", "Remove effect", func() -> void:
		rule.effects.erase(effect)
		_changed_structure()))
	return row


func _add_condition() -> void:
	var condition := OceanRuleCondition.new()
	rule.conditions.append(condition)
	_changed_structure()


func _add_effect() -> void:
	var effect := OceanRuleEffect.new()
	rule.effects.append(effect)
	_changed_structure()


func _changed_structure() -> void:
	_build()
	edited.emit()


func _choice(options: PackedStringArray, current: String, width: float, on_pick: Callable) -> OptionButton:
	var box := OptionButton.new()
	box.focus_mode = Control.FOCUS_NONE
	box.custom_minimum_size.x = width
	box.fit_to_longest_item = false
	var items := options.duplicate()
	if not items.has(current):
		items.append(current)
	for item in items:
		box.add_item(item)
	box.select(items.find(current))
	box.item_selected.connect(func(index: int) -> void:
		on_pick.call(box.get_item_text(index))
		edited.emit())
	return box


func _number(value: float, tooltip: String, on_change: Callable, minimum := -INF) -> SpinBox:
	var box := SpinBox.new()
	box.step = NUMBER_STEP
	box.allow_greater = true
	box.allow_lesser = minimum == -INF
	box.min_value = 0.0 if minimum != -INF else -1.0
	box.max_value = 1.0
	box.custom_minimum_size.x = NUMBER_WIDTH
	box.tooltip_text = tooltip
	box.set_value_no_signal(value)
	box.value_changed.connect(func(v: float) -> void:
		on_change.call(v)
		edited.emit())
	return box


func _icon_button(text: String, tooltip: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	return b


func _add_button(text: String, on_press: Callable) -> Button:
	var b := _icon_button(text, "", on_press)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return b


static func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = Color(1, 1, 1, 0.7)
	return label
