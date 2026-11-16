extends SceneTree
## No GUT dependency: godot --headless --path . --script res://tests/headless/water_shaders_test.gd
## Compiles every shader under the water folders. Headless Godot renders nothing, but its dummy
## renderer still runs the shader compiler: a shader that fails to compile has no uniforms.

const FOLDERS: Array[String] = ["res://world/water", "res://world/terrain"]
const EXTENSION := "gdshader"
var _failures: int = 0
var _count: int = 0


func _initialize() -> void:
	for folder: String in FOLDERS:
		_check_folder(folder)
	_check(_count > 0, "Found shaders to compile")
	print("Water shaders: ", "PASS" if _failures == 0 else "FAIL", " (", _count, " shaders, ", _failures, " failures)")
	quit(_failures)


func _check_folder(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		_check(false, "Open " + path)
		return
	for sub: String in dir.get_directories():
		_check_folder(path.path_join(sub))
	for file: String in dir.get_files():
		if file.get_extension() == EXTENSION:
			_compile(path.path_join(file))


func _compile(path: String) -> void:
	_count += 1
	var shader := load(path) as Shader
	_check(shader != null and not shader.get_shader_uniform_list().is_empty(), "Compiles: " + path)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		print("  FAIL: ", label)
