# 0003 — Clip submerged geometry in materials, not in the reflection camera

Date: 2026-11-14
Status: Accepted.

## Context

Planar water reflections (`world/water/planar_reflection.gd`) render the scene from a camera mirrored
below the water plane. Anything partly under water (rocks, barrels, posts, the riverbed) sits between
that camera and the plane, so its submerged half shows up mirrored above the surface as a ghost.
Engines usually solve this with an oblique near clip plane on the mirror camera. Godot 4.7's `Camera3D`
has no oblique or custom projection. Height fog on the mirror camera was tried: it only recolours the
submerged part. It can't make it transparent, so the ghost stays.

## Decision

Every material on geometry that can be partly under water discards its fragments below the water level,
but only while the mirror camera renders. Shaders recognise that pass with `CAMERA_VISIBLE_LAYERS`: the
mirror camera is the only camera that excludes the water layer (`PlanarReflection.WATER_LAYER`).

- Shared code: `world/water/reflection_clip.gdshaderinc`; call `water_reflection_clip(world_position)`
  first thing in `fragment()`.
- Props: `WaterProp.material(color, roughness)` (`world/water/water_prop.gdshader`) replaces a plain
  `StandardMaterial3D` for anything that can be in water.
- The terrain shader uses the same include. It used to clip whenever the camera was below the water,
  which would also have hidden the riverbed from a swimming player's camera.

## Consequences

- Materials for things that can be in water must be our own shaders (or `WaterProp`), not a bare
  `StandardMaterial3D`. Imported models get our materials anyway (see section 7 of the architecture doc).
- If Godot gains oblique projection, the mirror camera can clip instead and this rule can go.
- Web has no planar reflection (it uses sky reflection), so nothing changes there.
