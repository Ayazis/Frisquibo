# Water realism plan

Status: in progress. Each step is committed on its own; the checklist below shows what is done.
Visual checks are left to a person on a desktop GPU. In the container every step is verified with the
headless import, the headless tests and the headless smoke test only (nothing is rendered there):

```
godot --headless --import
for t in water_shaders ocean_tuning ocean_parameters ocean_sea_systems ocean_rules ocean_height_field \
    beach_profile river_flow_field; do
  timeout 120 godot --headless --path . --script res://tests/headless/${t}_test.gd; done
timeout 200 godot --headless --path . --script res://tests/smoke/ocean_smoke.gd
```

`water_shaders_test.gd` compiles every water and terrain shader: headless Godot renders nothing, but
its dummy renderer still runs the shader compiler. Compute shaders (`.glsl`) are not compiled there;
they only show errors on a desktop run.

## Steps, in order

1. [x] **Rough reflections.** The planar reflection is sampled sharp everywhere. Rough water (the LEAN
   roughness the sun glint already uses) should blur it, stretched vertically the way real wave slopes
   smear reflections into streaks. The reflection viewport gets a mip chain to blur from.
2. [x] **Shared optics for lake and river.** `water_common.gdshaderinc` moves to the ocean's model:
   Schlick Fresnel, GGX sun glint with a roughness from the detail-normal strength and distance,
   blur through murky water, the rough-reflection blur from step 1, and Snell's window from below.
3. [ ] **Underwater view.** A full-screen pass when the camera is below the surface: absorption and
   in-scatter over distance, blur, a waterline where the surface crosses the lens, and light shafts.
4. [ ] **Interaction ripples and wakes.** A camera-centred ripple simulation (wave equation on the GPU)
   that floating and moving objects disturb, added to the water normals and foam; boat wakes; splash
   foam where `Buoyancy.entered_water` fires.
5. [ ] **Caustics from the waves.** Caustics derived from the simulated slopes (light bunching under
   focusing waves) instead of a drifting noise texture, with slight colour dispersion.
6. [ ] **Gust patches.** Large, slow, wind-driven patches of rougher and calmer water ("cat's paws").
7. [ ] **Close-up ripple detail.** Fine scrolling detail normals near the camera, below the smallest
   simulated waves, on the ocean as well.
8. [ ] **Water types.** `OceanLook` presets for clear ocean, coastal and murky (moat, harbour) water.
9. [ ] **Floating foam.** Foam drifts with the wind, fresh foam glows turquoise from bubbles below it,
   foam has surface relief.
10. [ ] **Shoreline.** Wet sand that follows the swash (how far each wave runs up the beach).
11. [ ] **Spray** blown off breaking crests in strong wind.
12. [ ] **Sea-state transitions.** Cross-fade the longest cascade when its tile length changes.

Wave refraction towards the shore and curling breakers are out of scope for this pass: both need a
separate near-shore wave model (see the notes at the end once written).
