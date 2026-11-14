// Planar water reflections (planar_reflection.gd) render the scene from a mirror camera below the water.
// Godot has no oblique clip plane, so anything below the water would show up mirrored above the surface.
// Every material on objects that can be partly under water includes this file and calls
// water_reflection_clip(world_position) at the start of fragment().
//
// The mirror camera is recognised by its cull mask: it is the only camera that excludes the water layer.
// Keep WATER_LAYER_BIT in sync with PlanarReflection.WATER_LAYER (layer 20 = bit 19).

const uint WATER_LAYER_BIT = 1u << 19u;

global uniform float water_reflection_clip_height;

bool water_reflection_pass(uint camera_layers) {
	return (camera_layers & WATER_LAYER_BIT) == 0u;
}

#define water_reflection_clip(world_position) \
	if (water_reflection_pass(CAMERA_VISIBLE_LAYERS) && (world_position).y < water_reflection_clip_height) { discard; }
