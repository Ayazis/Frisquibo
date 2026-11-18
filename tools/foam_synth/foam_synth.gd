extends SceneTree
## Generates seamless foam textures of several kinds on the GPU, in the game's packed layout
## (R, G = normal x, y in OpenGL convention, B = height). Needs a GPU, so run it with a window:
##   godot --path . --script res://tools/foam_synth/foam_synth.gd
## Output: OUTPUT_DIR/tex_foam_synth_<kind>.png

const SIZE := 2048
const OUTPUT_DIR := "res://prototypes/foam/synth/"
const SYNTH := preload("res://tools/foam_synth/foam_synth.gdshader")
const SMEAR := preload("res://tools/foam_synth/foam_smear.gdshader")
const PACK := preload("res://tools/foam_synth/foam_pack.gdshader")
## Kind name -> [kind index in foam_synth.gdshader, smear amount, smear length (px), relief, seed].
const KINDS: Dictionary[String, Array] = {
	"surf_sheet": [0, 0.15, 24.0, 5.0, 1.0],
	"streaks": [1, 0.8, 60.0, 4.0, 2.0],
	"spatter": [2, 0.0, 0.0, 6.0, 3.0],
	"old_lace": [3, 0.25, 30.0, 5.0, 4.0],
	"churn": [4, 0.1, 20.0, 7.0, 5.0],
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	for kind_name: String in KINDS:
		var k: Array = KINDS[kind_name]
		var height := await _render(SYNTH, {"kind": k[0], "seed": k[4]}, null, "")
		var smeared := await _render(SMEAR, {"amount": k[1], "length_px": k[2], "texture_size": float(SIZE)}, height, "source")
		var packed := await _render(PACK, {"relief": k[3], "texture_size": float(SIZE)}, smeared, "height_map")
		var img := packed.get_image()
		img.convert(Image.FORMAT_RGB8)
		img.save_png(ProjectSettings.globalize_path(OUTPUT_DIR + "tex_foam_synth_%s.png" % kind_name))
		print("generated ", kind_name)
	quit()


## Renders one full-screen pass into a float target and returns a standalone copy of the result.
func _render(shader: Shader, params: Dictionary, input: Texture2D, input_name: String) -> ImageTexture:
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
	if input != null:
		material.set_shader_parameter(input_name, input)
	rect.material = material
	viewport.add_child(rect)
	root.add_child(viewport)
	await process_frame
	await process_frame
	var copy := ImageTexture.create_from_image(viewport.get_texture().get_image())
	viewport.queue_free()
	return copy
