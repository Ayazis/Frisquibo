class_name PerfOverlay
extends Label
## Frame timings, to find what is slow on the machine itself: the frame rate, the CPU time of the
## scripts (process, and physics per step and steps per frame), and the GPU and render-thread CPU time
## of every viewport: the screen, the water's mirrors and the ripple simulation each render on their own.
## Averages over REFRESH seconds. Compute work outside a viewport (the ocean's FFT) shows in no row:
## it is the gap between the GPU rows and the frame time when the GPU is the limit.

## Seconds each reading averages over.
const REFRESH := 0.5
const MS_PER_SECOND := 1000.0
const BYTES_PER_MIB := 1048576.0
const FONT_SIZE := 14
const SHADOW_OFFSET := 1

var _frames := 0
var _physics_steps := 0
var _elapsed := 0.0
var _process_seconds := 0.0
var _physics_seconds := 0.0
## The viewports measured, found again at each reading (mirrors come and go).
var _viewports: Array[RID] = []
## Per viewport RID: the name shown, and the GPU and CPU milliseconds summed since the last reading.
var _names: Dictionary[RID, String] = {}
var _gpu_ms: Dictionary[RID, float] = {}
var _cpu_ms: Dictionary[RID, float] = {}


func _ready() -> void:
	add_theme_font_size_override("font_size", FONT_SIZE)
	add_theme_color_override("font_shadow_color", Color.BLACK)
	add_theme_constant_override("shadow_offset_x", SHADOW_OFFSET)
	add_theme_constant_override("shadow_offset_y", SHADOW_OFFSET)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().physics_frame.connect(_on_physics_frame)
	_find_viewports()


func _process(delta: float) -> void:
	_frames += 1
	_elapsed += delta
	_process_seconds += Performance.get_monitor(Performance.TIME_PROCESS)
	for rid: RID in _viewports:
		_gpu_ms[rid] += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		_cpu_ms[rid] += RenderingServer.viewport_get_measured_render_time_cpu(rid)
	if _elapsed >= REFRESH:
		text = _report()
		_frames = 0
		_physics_steps = 0
		_elapsed = 0.0
		_process_seconds = 0.0
		_physics_seconds = 0.0
		_find_viewports()


## Each physics step: the monitor then holds the step before it (physics engine and scripts).
func _on_physics_frame() -> void:
	_physics_steps += 1
	_physics_seconds += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)


## Lists the screen and every SubViewport, starts measuring new ones and zeroes the sums.
func _find_viewports() -> void:
	var found: Array[Viewport] = [get_tree().root]
	for node: Node in get_tree().root.find_children("*", "SubViewport", true, false):
		found.append(node as Viewport)
	var names: Dictionary[RID, String] = {}
	_viewports.clear()
	for viewport: Viewport in found:
		var rid := viewport.get_viewport_rid()
		if not _names.has(rid):
			RenderingServer.viewport_set_measure_render_time(rid, true)
		names[rid] = _names[rid] if _names.has(rid) else _viewport_name(viewport)
		_viewports.append(rid)
		_gpu_ms[rid] = 0.0
		_cpu_ms[rid] = 0.0
	_names = names
	for rid: RID in _gpu_ms.keys():
		if not _names.has(rid):
			_gpu_ms.erase(rid)
			_cpu_ms.erase(rid)


## "Screen", or the class of the node that owns a SubViewport (PlanarReflection, WaterRipples, ...).
func _viewport_name(viewport: Viewport) -> String:
	if viewport == get_tree().root:
		return "Screen"
	var user := viewport.get_parent()
	var script: Script = user.get_script() if user != null else null
	var label := String(script.get_global_name()) if script != null else ""
	if label == "" and user != null:
		label = user.get_class()
	return "%s %s" % [label, viewport.name]


func _report() -> String:
	var frames := maxi(_frames, 1)
	var frame_ms := _elapsed / frames * MS_PER_SECOND
	var steps := float(_physics_steps) / frames
	var per_step := _physics_seconds / maxi(_physics_steps, 1) * MS_PER_SECOND
	var lines := PackedStringArray()
	lines.append("FPS %d   frame %.1f ms" % [roundi(frames / maxf(_elapsed, 1e-6)), frame_ms])
	lines.append("CPU: process %.1f ms, physics %.1f ms per step x %.1f steps" % [
			_process_seconds / frames * MS_PER_SECOND, per_step, steps])
	lines.append("Render setup (CPU) %.1f ms" % RenderingServer.get_frame_setup_time_cpu())
	var gpu_total := 0.0
	for rid: RID in _viewports:
		var gpu := _gpu_ms[rid] / frames
		gpu_total += gpu
		lines.append("  %s: GPU %.2f ms, CPU %.2f ms" % [_names[rid], gpu, _cpu_ms[rid] / frames])
	lines.append("GPU viewports total %.1f ms" % gpu_total)
	lines.append("Draw calls %d, primitives %.1f M, video memory %d MiB" % [
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1.0e6,
			roundi(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / BYTES_PER_MIB)])
	return "\n".join(lines)
