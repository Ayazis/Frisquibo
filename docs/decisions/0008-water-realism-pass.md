# 0008 — Water realism pass: shared optics, underwater view, ripples, wave caustics

Date: 2026-11-16
Status: Accepted. Built and checked headless; the look and the GPU cost still need a desktop run
(see "Desktop checks" in `docs/plans/water_realism.md`).

## Context

The FFT ocean had good waves and optics, but much of what makes water read as real was missing:
rough water mirrored the world sharply at any distance, the camera could not go under water, nothing
disturbed the surface, caustics were a drifting texture unrelated to the waves, and lakes and rivers
(most of the game's water) used an older, simpler optical model than the sea.

## Decisions

1. **One optical model for all water.** `water_optics.gdshaderinc` holds pure functions (Schlick
   Fresnel, GGX glint, crest scattering, Snell's window). The ocean and `water_common` (lake, river) both
   use them. Uniforms stay in each shader, so `OceanLook` keeps one uniform per value. Lakes and rivers
   get their roughness from slopes a pixel can't show: specular anti-aliasing from slope derivatives,
   Toksvig on the mipmapped detail normals, and detail faded with distance.
2. **Rough reflections blur the planar mirror** by the same unresolved slope variance, as an upright
   ellipse (sideways tilt bends the reflected ray by only cos(view angle)). Taps come from the quality
   tier. No mip chain on the reflection viewport: SubViewport textures have none to rely on.
3. **The underwater view is the first transparent pass**, not a compositor effect: a full-screen quad
   (`UnderwaterView`) with a render priority below the water's. It reads the opaque scene from the
   screen copy and the surface, which shades itself from below, draws over it. Light shafts are
   ray-marched in its `light()` function, which knows the sun. This needs no compute shader and works on
   every renderer (no shafts on the web).
4. **Interaction ripples are a wave equation stepped by two SubViewports** with a canvas shader, not a
   compute shader: it compiles headless (so the container can check it) and needs no RenderingDevice
   code. One `WaterRipples` per scene, found through a group; bodies get a `RippleEmitter`. Off on the
   web (no float render targets to rely on there).
5. **Ocean caustics come from the wave curvature**: 1/|det(I + d(1 - 1/n)H)| per colour channel from the
   slope maps, blurred by the sun's disk through the mip chain. Light on the seabed also loses what the
   water absorbs on its way down.
6. **Close-up ripples carry the capillary roughness**, scaled by the measured variance of the detail
   maps (kept true by a headless test), and fade back into roughness as pixels grow.
7. **Foam drift stays in the surface shader.** Moving the persistent whitecap field in the compute
   shader would read and write the same image in place; only the bubble pattern drifts.
8. **Sea-state changes run two simulations side by side** while the new state fades in (only when the
   tiles change, after the values settle). Same-tile cascades blend linearly (shared phases), changed
   ones with square-root weights (unrelated fields, steady energy).
9. **Water types use measured optics**: absorption from Jerlov's water types; colours by eye.
10. **Beach swash uses Stockdon et al. (2006)** for the run-up, published as global shader values the
    ground reads.

## Consequences

- More shader work per water pixel on High: reflection taps, caustic samples (16 slope samples on the
  ocean), close-up ripple normals, ripple sampling. All of it scales with the quality tiers, and the
  costliest parts (spray, shafts) are off on Low.
- The ripple simulation relies on negative values in an HDR 2D viewport; if a driver clamps them, the
  ripples will be one-sided (see the desktop checks).
- `water_common` changed its interface (`WaterSurface`, more `water_light` inputs) and lake and river
  now draw back faces (`cull_disabled`) for the view from below.
- Headless runs exercise the ocean's Gerstner fallback only; the FFT path's new code (transitions,
  spray, underwater waves) is checked by reading and by the desktop checks.
