extends SceneTree
## Packs the ambientCG sea foam scans (Foam001-003, CC0, https://ambientcg.com/view?id=Foam003) into the
## game's foam textures: one 2K RGB image each, R, G = normal x, y (OpenGL), B = height.
## Download the 8K-PNG sets, put their NormalGL and Displacement maps in SOURCE_DIR (build/, not committed), then:
##   godot --headless --path . --script res://tools/foam_scans/pack_foam_scans.gd

const SIZE := 2048
const SOURCE_DIR := "res://build/foam_sources/ambientcg/"
const SOURCE := SOURCE_DIR + "Foam%s_8K-PNG_%s.png"
const TARGET := "res://world/water/foam_scans/tex_foam_scan_%s.png"
const SCANS: Array[String] = ["001", "002", "003"]


func _init() -> void:
	for id: String in SCANS:
		var normal := Image.load_from_file(ProjectSettings.globalize_path(SOURCE % [id, "NormalGL"]))
		var height := Image.load_from_file(ProjectSettings.globalize_path(SOURCE % [id, "Displacement"]))
		normal.convert(Image.FORMAT_RGBF)
		height.convert(Image.FORMAT_RF)
		normal.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
		height.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
		var out := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
		for y: int in range(SIZE):
			for x: int in range(SIZE):
				var n := normal.get_pixel(x, y)
				out.set_pixel(x, y, Color(n.r, n.g, clampf(height.get_pixel(x, y).r, 0.0, 1.0)))
		out.save_png(ProjectSettings.globalize_path(TARGET % id))
		print("packed ", id)
	quit()
