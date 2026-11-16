# 0002 — Own the desktop FFT ocean

Date: 2026-11-13
Status: Accepted for prototype integration; visual acceptance and profiling pending.

## Context

The water comparison prototype evaluates our Gerstner lake/river water and the pinned MIT GodotOceanWaves implementation. Desktop realism is the priority: directional waves over multiple scales, persistent whitecaps, shallow-water attenuation, planar reflections, refraction, and a CPU height query for gameplay must work together. Web cannot run compute shaders.

## Decision

Keep the production ocean in world/water/ocean. Use a cascaded JONSWAP spectrum, GPU inverse FFT, displacement/slope textures and mipmapped slope moments. Bind individual 2D layer/mip views because the installed Godot 4.7.2 build does not expose TEXTURE_SLICE_2D_ARRAY. RenderingDevice work and disposal run on the render thread. Deliver asynchronous displacement readbacks to the main thread before physics samples them.

Keep GodotOceanWaves in prototypes/water_compare/vendor as a comparison reference, not a production dependency. The fourth station demonstrates our ocean, three sea states, beach damping and rigid-body barrels. Buoyancy receives a height callable rather than depending on one renderer.

On Web/Compatibility use Sea's Gerstner surface with matching CPU sampling and approximate sea-state parameters. Shared buoyancy logic stays unchanged. The fallback does not reproduce the FFT spectrum or its shoreline attenuation.

## Consequences

We own spectral correctness, resource lifetime, GPU performance and optical tuning. LEAN-style slope variance and procedural caustics are approximations, not a full fluid or light-transport simulation. Readbacks lag rendering by several frames, and the CPU height query samples full-resolution displacement while distant mesh vertices use mip levels. Floating objects should stay near the camera. Breaking/folding waves can make the inverse height lookup ambiguous.

## Validation

Run the standalone height-field checks and the rendered comparison smoke test documented in tests/smoke/README.md. Check logs as well as process status: Godot can exit successfully after reporting script errors. A clean import/export alone does not verify the compute pipeline. Visual acceptance, performance budgets, actual browser behavior and an exported Windows runtime require separate verification.
