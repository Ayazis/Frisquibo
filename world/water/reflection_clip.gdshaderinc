// Planar water reflections (planar_reflection.gd) render the scene from mirror cameras below the water.
// Godot has no oblique clip plane, so anything below the water would show up mirrored above the surface.
// Every material on objects that can be partly under water includes this file and calls
// water_reflection_clip(world_position) at the start of fragment().
//
// Mirror cameras are recognised by their cull mask: they are the only cameras that exclude the water
// layer. The second mirror (water above the sea, such as a pond) also excludes SECOND_MIRROR_LAYER, an
// otherwise empty layer, so each mirror clips at its own height.
// Keep the bits in sync with PlanarReflection.WATER_LAYER (20 = bit 19) and SECOND_MIRROR_LAYER (19 = bit 18).

const uint WATER_LAYER_BIT = 1u << 19u;
const uint SECOND_MIRROR_BIT = 1u << 18u;

global uniform float water_reflection_clip_height;
global uniform float water_reflection_2_clip_height;

bool water_reflection_pass(uint camera_layers) {
	return (camera_layers & WATER_LAYER_BIT) == 0u;
}

float water_reflection_clip_level(uint camera_layers) {
	return (camera_layers & SECOND_MIRROR_BIT) == 0u ? water_reflection_2_clip_height : water_reflection_clip_height;
}

#define water_reflection_clip(world_position) \
	if (water_reflection_pass(CAMERA_VISIBLE_LAYERS) && (world_position).y < water_reflection_clip_level(CAMERA_VISIBLE_LAYERS)) { discard; }
