extends SceneTree
## Turns top-down foam photos into tileable foam textures in the game's packed layout (R, G = normal x, y
## in OpenGL convention, B = height). Needs a GPU, so run it with a window:
##   godot --path . --script res://tools/foam_synth/foam_photo.gd
## Photos are local working copies in PHOTO_DIR (build/, not committed); sources and licences in their .txt files.

const SIZE := 2048
const LOWPASS_SIZE := 12
const LEVEL_SAMPLE := 256
const PHOTO_DIR := "res://build/foam_sources/photos/"
const OUTPUT_DIR := "res://prototypes/foam/photo/"
const PHOTO := preload("res://tools/foam_synth/foam_photo.gdshader")
const PACK := preload("res://tools/foam_synth/foam_pack.gdshader")
## Photo -> [crop centre x, y (0..1 of the image), crop side (share of the shorter side), low and high
## percentile of brightness that become height 0 and 1, relief].
var jobs: Dictionary[String, PackedFloat32Array] = {
	"anna_popovic": PackedFloat32Array([0.5, 0.5, 1.0, 0.35, 0.995, 5.0]),
	"neonbrand_whitewater": PackedFloat32Array([0.55, 0.5, 0.8, 0.2, 0.99, 5.0]),
	"dench_dark_whitecap": PackedFloat32Array([0.5, 0.75, 0.5, 0.3, 0.995, 5.0]),
	"morning_seafoam": PackedFloat32Array([0.5, 0.6, 0.7, 0.1, 0.98, 5.0]),
	"foamy_ocean": PackedFloat32Array([0.5, 0.55, 0.8, 0.3, 0.995, 5.0]),
	"engstrom_aerial": PackedFloat32Array([0.5, 0.5, 0.9, 0.15, 0.99, 5.0]),
	"croatia_pasman": PackedFloat32Array([0.5, 0.5, 0.9, 0.5, 0.998, 5.0]),
	"gischt_stiller": PackedFloat32Array([0.4, 0.5, 0.8, 0.15, 0.99, 6.0]),
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	for photo_name: String in jobs:
		var job: PackedFloat32Array = jobs[photo_name]
		var crop := _crop(Image.load_from_file(ProjectSettings.globalize_path(PHOTO_DIR + photo_name + ".jpg")), job)
		var small := crop.duplicate() as Image
		small.resize(LEVEL_SAMPLE, LEVEL_SAMPLE, Image.INTERPOLATE_BILINEAR)
		var lumas := PackedFloat32Array()
		for y: int in range(LEVEL_SAMPLE):
			for x: int in range(LEVEL_SAMPLE):
				lumas.append(small.get_pixel(x, y).get_luminance())
		lumas.sort()
		var mean := 0.0
		for l: float in lumas:
			mean += l
		mean /= lumas.size()
		var lowpass := crop.duplicate() as Image
		lowpass.resize(LOWPASS_SIZE, LOWPASS_SIZE, Image.INTERPOLATE_LANCZOS)
		var params := {
			"photo": ImageTexture.create_from_image(crop),
			"lowpass": ImageTexture.create_from_image(lowpass),
			"mean_luma": mean,
			"levels": Vector2(_percentile(lumas, job[3]), _percentile(lumas, job[4])),
		}
		var height := await _render(PHOTO, params)
		var packed := await _render(PACK, {"height_map": height, "relief": job[5], "texture_size": float(SIZE)})
		var img := packed.get_image()
		img.convert(Image.FORMAT_RGB8)
		img.save_png(ProjectSettings.globalize_path(OUTPUT_DIR + "tex_foam_photo_%s.png" % photo_name))
		print("converted ", photo_name)
	quit()


func _crop(img: Image, job: PackedFloat32Array) -> Image:
	var side := int(minf(img.get_width(), img.get_height()) * job[2])
	var centre := Vector2(img.get_width() * job[0], img.get_height() * job[1])
	var origin := Vector2i(clampi(int(centre.x) - side / 2, 0, img.get_width() - side),
			clampi(int(centre.y) - side / 2, 0, img.get_height() - side))
	var crop := img.get_region(Rect2i(origin, Vector2i(side, side)))
	crop.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	return crop


func _percentile(sorted: PackedFloat32Array, share: float) -> float:
	return sorted[clampi(int(share * (sorted.size() - 1)), 0, sorted.size() - 1)]


func _render(shader: Shader, params: Dictionary) -> ImageTexture:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(SIZE, SIZE)
	viewport.use_hdr_2d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(SIZE, SIZE)
	var material := ShaderMaterial.new()
	material.shader = shader
	for key: String in params:
		material.set_shader_parameter(key, params[key])
	rect.material = material
	viewport.add_child(rect)
	root.add_child(viewport)
	await process_frame
	await process_frame
	var copy := ImageTexture.create_from_image(viewport.get_texture().get_image())
	viewport.queue_free()
	return copy
