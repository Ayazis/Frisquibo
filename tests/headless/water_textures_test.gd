extends SceneTree
## No GUT dependency: godot --headless --path . --script res://tests/headless/water_textures_test.gd
## Shaders scale the detail normal maps by their measured slope variance; this keeps that number true.

## CAPILLARY_MAP_VARIANCE in ocean.gdshader.
const MAP_VARIANCE := 0.0269
const TOLERANCE := 0.15
const STRIDE := 2
## Edge distance below which a texel counts as a thread of old lace (about LACE_THREAD in foam_lace).
const LACE_THREAD_TEST := 0.08
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var mat := ShaderMaterial.new()
	WaterTextures.apply_detail_normals(mat)
	var total := 0.0
	for key: String in ["normal_map_a", "normal_map_b"]:
		var tex: NoiseTexture2D = mat.get_shader_parameter(key)
		if tex.get_image() == null:
			await tex.changed
		total += _variance_per_axis(tex.get_image())
	_check(absf(total - MAP_VARIANCE) <= MAP_VARIANCE * TOLERANCE,
			"Detail maps' slope variance %.4f matches the shader's %.4f" % [total, MAP_VARIANCE])
	var shader := load("res://world/water/ocean/ocean.gdshader") as Shader
	_check(shader.code.contains("CAPILLARY_MAP_VARIANCE = %s;" % MAP_VARIANCE), "The shader uses the same number")
	_check(WaterTextures.gusts() != null, "Gust field exists")
	# Foam lace: distance to cell edges, 0 on the edges, so a threshold draws a network of threads.
	var lace := WaterTextures.lace()
	if lace.get_image() == null:
		await lace.changed
	var cells := lace.get_image()
	var lowest := 1.0
	var highest := 0.0
	var on_edges := 0
	var samples := 0
	for y in range(0, cells.get_height(), STRIDE * 4):
		for x in range(0, cells.get_width(), STRIDE * 4):
			var v := cells.get_pixel(x, y).r
			lowest = minf(lowest, v)
			highest = maxf(highest, v)
			on_edges += 1 if v < LACE_THREAD_TEST else 0
			samples += 1
	_check(lowest < 0.05 and highest > 0.8, "Lace spans edges to cell centres (%.2f..%.2f)" % [lowest, highest])
	var share := float(on_edges) / samples
	_check(share > 0.03 and share < 0.4, "Thin threads cover a small share of the lace (%.2f)" % share)
	print("Water textures: ", "PASS" if _failures == 0 else "FAIL", " (", _failures, " failures)")
	quit(_failures)


func _variance_per_axis(img: Image) -> float:
	var sum := 0.0
	var n := 0
	for y in range(0, img.get_height(), STRIDE):
		for x in range(0, img.get_width(), STRIDE):
			var c := img.get_pixel(x, y)
			var nx := c.r * 2.0 - 1.0
			var ny := c.g * 2.0 - 1.0
			sum += nx * nx + ny * ny
			n += 1
	return sum / n / 2.0


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		print("  FAIL: ", label)
