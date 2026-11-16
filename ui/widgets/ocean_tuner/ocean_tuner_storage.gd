class_name OceanTunerStorage
extends VBoxContainer
## Save / load and A/B for the tuned ocean (sea state, look, sea level and shore values).
## Save writes a text resource, so a sea worth keeping can be copied into the project and committed.
## Snapshot keeps the current values in memory; A/B swaps them with the live ones, back and forth.

## Emitted after the ocean got loaded or swapped values, so the controls can follow.
signal applied

const TUNING_PATH := "user://ocean_tuning.tres"
const SNAPSHOT_TEXT := "Snapshot"
const SWAP_TEXT := "A/B"
const SWAP_NOTE := "Swap the live values with the snapshot. Press again to swap back."

var _ocean: Ocean
var _status := Label.new()
var _swap: Button
## The other side of the A/B: the snapshot, or the live values while the snapshot is shown.
var _other: OceanTuning
var _showing_snapshot := false


func _init(ocean: Ocean) -> void:
	_ocean = ocean
	var buttons := HBoxContainer.new()
	buttons.add_child(_button("Save", _save))
	buttons.add_child(_button("Load", _load))
	buttons.add_child(_button(SNAPSHOT_TEXT, _take_snapshot))
	_swap = _button(SWAP_TEXT, _swap_with_snapshot)
	_swap.tooltip_text = SWAP_NOTE
	_swap.disabled = true
	buttons.add_child(_swap)
	add_child(buttons)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(1, 1, 1, 0.7)
	add_child(_status)


func _save() -> void:
	var error := ResourceSaver.save(OceanTuning.capture(_ocean), TUNING_PATH)
	if error == OK:
		_status.text = "Saved to " + ProjectSettings.globalize_path(TUNING_PATH)
	else:
		_status.text = "Save failed (%s)" % error_string(error)


func _load() -> void:
	if not ResourceLoader.exists(TUNING_PATH):
		_status.text = "Nothing saved yet"
		return
	var tuning := ResourceLoader.load(TUNING_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as OceanTuning
	if tuning == null:
		_status.text = "Could not read " + ProjectSettings.globalize_path(TUNING_PATH)
		return
	tuning.apply_to(_ocean)
	_status.text = "Loaded"
	applied.emit()


func _take_snapshot() -> void:
	_other = OceanTuning.capture(_ocean)
	_showing_snapshot = false
	_swap.disabled = false
	_status.text = "Snapshot taken. Change things, then press A/B to compare."


func _swap_with_snapshot() -> void:
	var live := OceanTuning.capture(_ocean)
	_other.apply_to(_ocean)
	_other = live
	_showing_snapshot = not _showing_snapshot
	_status.text = "Showing B: the snapshot" if _showing_snapshot else "Showing A: your edits"
	applied.emit()


static func _button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_press)
	return button
