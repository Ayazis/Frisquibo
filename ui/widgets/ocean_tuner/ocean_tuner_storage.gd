class_name OceanTunerStorage
extends VBoxContainer
## Save and load buttons for the tuned sea state and look. They are written as text resources, so a
## sea worth keeping can be copied into the project and committed.

signal loaded(sea: OceanSpectrum, look: OceanLook)

const SEA_PATH := "user://ocean_sea.tres"
const LOOK_PATH := "user://ocean_look.tres"

var _ocean: Ocean
var _status := Label.new()


func _init(ocean: Ocean) -> void:
	_ocean = ocean
	var buttons := HBoxContainer.new()
	buttons.add_child(_button("Save", _save))
	buttons.add_child(_button("Load", _load))
	add_child(buttons)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(1, 1, 1, 0.7)
	add_child(_status)


func _save() -> void:
	var error := ResourceSaver.save(_ocean.spectrum, SEA_PATH)
	if error == OK:
		error = ResourceSaver.save(_ocean.look, LOOK_PATH)
	if error == OK:
		_status.text = "Saved to " + ProjectSettings.globalize_path(SEA_PATH).get_base_dir()
	else:
		_status.text = "Save failed (%s)" % error_string(error)


func _load() -> void:
	var sea := _read(SEA_PATH) as OceanSpectrum
	var look := _read(LOOK_PATH) as OceanLook
	if sea == null or look == null:
		_status.text = "Nothing saved yet"
		return
	_status.text = "Loaded"
	loaded.emit(sea, look)


## A private copy of a saved resource, or null when there is none.
static func _read(path: String) -> Resource:
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)


static func _button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(on_press)
	return button
