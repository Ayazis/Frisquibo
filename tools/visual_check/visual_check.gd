extends Node
## Renders the fixed camera shots of a VisualShotList to PNG and compares them with a local baseline.
## Baselines are per machine (renders differ between GPUs), so they live in build/ and are never committed.
## Start it through tools/visual_check/run.sh; see tools/visual_check/README.md.

enum Mode { CAPTURE, COMPARE, BASELINE }

const MODES := {"capture": Mode.CAPTURE, "compare": Mode.COMPARE, "baseline": Mode.BASELINE}
const EXIT_PASS := 0
const EXIT_DIFFERENT := 1
const EXIT_ERROR := 2
const OUTPUT_DIR := "res://build/visual_check"
## Optional method on the scene root that puts the scene in a fixed state for a shot.
const STATE_METHOD := &"apply_visual_check_state"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var exit_code: int = await _execute()
	get_tree().quit(exit_code)


func _execute() -> int:
	var args := _parse_args()
	var list_path: String = args.get("shots", "")
	var mode_name: String = args.get("mode", "compare")
	if not MODES.has(mode_name):
		printerr("Unknown --mode=%s (use baseline, compare or capture)." % mode_name)
		return EXIT_ERROR
	var mode: Mode = MODES[mode_name]

	var list := load(list_path) as VisualShotList if ResourceLoader.exists(list_path) else null
	if list == null:
		printerr("No shot list at --shots=%s" % list_path)
		return EXIT_ERROR
	if not ResourceLoader.exists(list.scene_path):
		printerr("Shot list scene not found: %s" % list.scene_path)
		return EXIT_ERROR

	var list_name := list_path.get_file().get_basename()
	var output_dir := _prepare_output_dir(list_name)
	var baseline_dir := output_dir.path_join("baseline")
	get_window().size = list.resolution

	var failures := 0
	for shot in list.shots:
		var image: Image = await _render(list, shot)
		var render_path := output_dir.path_join(shot.name + ".png")
		image.save_png(render_path)
		match mode:
			Mode.CAPTURE:
				print("CAPTURED %s -> %s" % [shot.name, render_path])
			Mode.BASELINE:
				DirAccess.make_dir_recursive_absolute(baseline_dir)
				image.save_png(baseline_dir.path_join(shot.name + ".png"))
				print("BASELINE %s" % shot.name)
			Mode.COMPARE:
				if not _compare_shot(list, shot, image, baseline_dir, output_dir):
					failures += 1

	if mode == Mode.COMPARE:
		print("%d of %d shots match the baseline. Renders: %s" % [list.shots.size() - failures, list.shots.size(), output_dir])
	return EXIT_DIFFERENT if failures > 0 else EXIT_PASS


## Builds the scene fresh for every shot, so shots don't influence each other.
func _render(list: VisualShotList, shot: VisualShot) -> Image:
	seed(list.random_seed)
	var scene := (load(list.scene_path) as PackedScene).instantiate()
	add_child(scene)
	if scene.has_method(STATE_METHOD):
		scene.call(STATE_METHOD, shot.state)

	var camera := _make_camera(get_viewport().get_camera_3d())
	camera.fov = shot.fov
	camera.global_position = shot.camera_position
	camera.look_at(shot.look_at_target)

	for _frame in range(list.settle_frames):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image.get_size() != list.resolution:
		image.resize(list.resolution.x, list.resolution.y, Image.INTERPOLATE_BILINEAR)

	scene.queue_free()
	camera.queue_free()
	await get_tree().process_frame
	return image


## A camera that takes over the scene camera's look (environment, exposure, clipping) but not its position.
func _make_camera(scene_camera: Camera3D) -> Camera3D:
	var camera := Camera3D.new()
	if scene_camera != null:
		camera.environment = scene_camera.environment
		camera.attributes = scene_camera.attributes
		camera.near = scene_camera.near
		camera.far = scene_camera.far
		camera.cull_mask = scene_camera.cull_mask
	add_child(camera)
	camera.make_current()
	return camera


func _compare_shot(list: VisualShotList, shot: VisualShot, image: Image, baseline_dir: String, output_dir: String) -> bool:
	var baseline_path := baseline_dir.path_join(shot.name + ".png")
	var baseline := Image.load_from_file(baseline_path) if FileAccess.file_exists(baseline_path) else null
	if baseline == null:
		print("MISSING  %s: no baseline on this machine (run with --mode=baseline before changing anything)" % shot.name)
		return false
	var result := ImageDiff.compare(baseline, image, list.pixel_threshold)
	var compare_path := output_dir.path_join(shot.name + ".compare.png")
	result.composite.save_png(compare_path)
	var passed := result.changed_ratio <= list.max_changed_ratio
	print("%s %s: %.3f%% of pixels changed (limit %.3f%%), max difference %.3f. Baseline | render | diff: %s" % [
		"PASS    " if passed else "FAIL    ", shot.name, result.changed_ratio * 100.0,
		list.max_changed_ratio * 100.0, result.max_difference, compare_path])
	return passed


func _prepare_output_dir(list_name: String) -> String:
	var root := ProjectSettings.globalize_path(OUTPUT_DIR)
	var dir := root.path_join(list_name)
	DirAccess.make_dir_recursive_absolute(dir)
	# Keeps Godot from importing the renders as project assets.
	var marker := root.get_base_dir().path_join(".gdignore")
	if not FileAccess.file_exists(marker):
		FileAccess.open(marker, FileAccess.WRITE).close()
	return dir


func _parse_args() -> Dictionary:
	var args := {}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			var parts := arg.trim_prefix("--").split("=", true, 1)
			args[parts[0]] = parts[1]
	return args
