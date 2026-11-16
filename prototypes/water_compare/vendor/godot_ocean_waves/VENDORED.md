# GodotOceanWaves (vendored for evaluation)

- Source: https://github.com/2Retr0/GodotOceanWaves
- Commit: a171446f8174348895aaafc426576c26261058b9
- Licence: MIT (see LICENSE), Copyright (c) 2024 Ethan Truong
- Status: prototype only. Nothing outside `prototypes/` may depend on it.

## Local changes
- `res://assets/...` paths rewritten to this folder.
- Sea spray material reference removed from `water.gd` (spray particles not vendored).
- The ImGui debug UI, player, audio and skybox from the demo are not included.
- `render_context.gd`: push constants are no longer padded to 16 bytes; Godot 4.7 rejects the padded size.
- `wave_generator.gd`: spectrum_modulate gets its own descriptor set; Godot 4.7 checks read/write access per shader.
- `clipmap_*.obj.import`: LOD and shadow-mesh generation off (Godot 4.7 defaults to on, which cracks the clipmap).
- Excluded from our strict GDScript warnings via `debug/gdscript/warnings/directory_rules`.
