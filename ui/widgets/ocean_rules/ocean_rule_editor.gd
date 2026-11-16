class_name OceanRuleEditor
extends VBoxContainer
## Live editor for an OceanRuleSet: add, remove, reorder and tune rules, save and load them.
## Works on its own deep copy; listen to `rules_changed` and hand `rule_set` to the Ocean.

signal rules_changed(rule_set: OceanRuleSet)

const SAVE_PATH := "user://ocean_rules.tres"
const PROBLEM_COLOR := Color(1.0, 0.55, 0.45)
const HELP := ("Rules run top to bottom; each sees the results of the ones above.\n"
		+ "local_depth: water depth at each point. local_*: per-point foam, wave size, water level.\n"
		+ "wave_height: measured, read-only. Avoid rules that read it and change the waves.")

var rule_set: OceanRuleSet
var _preset: OceanRuleSet
var _parameters: PackedStringArray
var _targets: PackedStringArray
var _cards: VBoxContainer
var _problems: Label
var _status: Label


func _init(preset: OceanRuleSet, parameters: PackedStringArray, targets: PackedStringArray) -> void:
	_preset = preset
	_parameters = parameters
	_targets = targets
	var help := Label.new()
	help.text = HELP
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.modulate = Color(1, 1, 1, 0.7)
	add_child(help)
	_problems = Label.new()
	_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_problems.add_theme_color_override("font_color", PROBLEM_COLOR)
	add_child(_problems)
	_cards = VBoxContainer.new()
	add_child(_cards)
	var buttons := HBoxContainer.new()
	buttons.add_child(_button("+ Add rule", _add_rule))
	buttons.add_child(_button("Save", _save))
	buttons.add_child(_button("Load", _load))
	buttons.add_child(_button("Reset", _reset))
	add_child(buttons)
	_status = Label.new()
	_status.modulate = Color(1, 1, 1, 0.7)
	add_child(_status)
	_use(_copy(preset))


## Shows the problems the Ocean found in the current rules (empty: none).
func show_problems(problems: PackedStringArray) -> void:
	_problems.text = "\n".join(problems)
	_problems.visible = not problems.is_empty()


func _use(rules: OceanRuleSet) -> void:
	rule_set = rules
	_rebuild()
	rules_changed.emit(rule_set)


func _rebuild() -> void:
	for child in _cards.get_children():
		child.queue_free()
	for rule: OceanRule in rule_set.rules:
		if rule == null:
			continue
		var card := OceanRuleCard.new(rule, _parameters, _targets)
		card.edited.connect(func() -> void: rules_changed.emit(rule_set))
		card.move_requested.connect(_move.bind(rule))
		card.delete_requested.connect(_delete.bind(rule))
		_cards.add_child(card)


func _add_rule() -> void:
	var rule := OceanRule.new()
	rule.label = "New rule"
	rule.effects.append(OceanRuleEffect.new())
	rule_set.rules.append(rule)
	_use(rule_set)


func _move(step: int, rule: OceanRule) -> void:
	var from := rule_set.rules.find(rule)
	var to := clampi(from + step, 0, rule_set.rules.size() - 1)
	if from < 0 or to == from:
		return
	rule_set.rules.remove_at(from)
	rule_set.rules.insert(to, rule)
	_use(rule_set)


func _delete(rule: OceanRule) -> void:
	rule_set.rules.erase(rule)
	_use(rule_set)


func _save() -> void:
	var error := ResourceSaver.save(rule_set, SAVE_PATH)
	_status.text = ("Saved to " + ProjectSettings.globalize_path(SAVE_PATH)) if error == OK else "Save failed (%s)" % error_string(error)


func _load() -> void:
	var loaded := ResourceLoader.load(SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as OceanRuleSet
	if loaded == null:
		_status.text = "Nothing saved yet"
		return
	_status.text = "Loaded"
	_use(_copy(loaded))


func _reset() -> void:
	_status.text = "Back to the preset"
	_use(_copy(_preset))


static func _copy(rules: OceanRuleSet) -> OceanRuleSet:
	if rules == null:
		return OceanRuleSet.new()
	return rules.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as OceanRuleSet


static func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	return b
