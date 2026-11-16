# Water realism plan

Status: in progress. Each step is committed on its own; the checklist below shows what is done.
Visual checks are left to a person on a desktop GPU. In the container every step is verified with the
headless import, the headless tests and the headless smoke test only (nothing is rendered there):

```
godot --headless --import
for t in water_shaders underwater_view water_ripples water_textures water_types shore_runup water_quality ocean_tuning ocean_parameters ocean_sea_systems ocean_rules ocean_height_field \
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
3. [x] **Underwater view.** A full-screen pass when the camera is below the surface: absorption and
   in-scatter over distance, blur, a waterline where the surface crosses the lens, and light shafts.
4. [x] **Interaction ripples and wakes.** A camera-centred ripple simulation (wave equation on the GPU)
   that floating and moving objects disturb, added to the water normals and foam; boat wakes; splash
   foam where `Buoyancy.entered_water` fires.
5. [x] **Caustics from the waves.** Caustics derived from the simulated slopes (light bunching under
   focusing waves) instead of a drifting noise texture, with slight colour dispersion.
6. [x] **Gust patches.** Large, slow, wind-driven patches of rougher and calmer water ("cat's paws").
7. [x] **Close-up ripple detail.** Fine scrolling detail normals near the camera, below the smallest
   simulated waves, on the ocean as well.
8. [x] **Water types.** `OceanLook` presets for clear ocean, coastal and murky (moat, harbour) water.
9. [x] **Floating foam.** Foam drifts with the wind, fresh foam glows turquoise from bubbles below it,
   foam has surface relief. (The bubble pattern drifts; the whitecap cover itself stays where the
   compute shader made it: moving it there would read and write the same image in place.)
10. [x] **Shoreline.** Wet sand that follows the swash (how far each wave runs up the beach).
11. [x] **Spray** blown off breaking crests in strong wind.
12. [x] **Sea-state transitions.** Cross-fade the longest cascade when its tile length changes.

Wave refraction towards the shore and curling breakers are out of scope for this pass: both need a
separate near-shore wave model (see the notes at the end once written).

## Desktop checks

Nothing here was rendered (no rendering in cloud containers). On a desktop GPU, in
`prototypes/water_compare/water_compare.tscn`, first look at the output panel for shader or script
errors, then check:

1. **Reflections** (stations 1 and 4): distant rough water smears trees and boats into vertical streaks;
   a calm lake close by stays a sharp mirror. Low tier: blockier streaks (4 taps).
2. **Lake and river**: sun glint and colour still look right after the move to the ocean's optics
   (the sky reflection is now physical F0 = 0.02, half of before); no shimmer on distant ripples.
3. **Underwater** (Q to lower the camera, drag to look up): fog and colour by distance, blur, light
   shafts from the sun, the surface from below with Snell's window, and a wavy waterline with a dark
   meniscus when the camera is half in. Check the quad never shows in the planar reflection.
4. **Ripples** (F to drop objects, the boats): rings spread from splashes, bobbing objects make rings,
   foam appears and fades. If the rings only go one way (bumps, no troughs) the HDR viewport clamps
   negative values: encode the height with an offset in `ripple_step.gdshader`.
5. **Caustics** (station 4, shallow water by the beach): bright lines that move with the waves, with
   faint colour fringes; deep sand darker and bluer. The underwater view shows the same caustics.
6. **Gusts**: dark and light patches drifting downwind, most visible on the calm sea and the lake.
7. **Close-up ripples**: fine ripples near the camera that fade into the glitter, with no visible tiling
   and no change in overall brightness with distance.
8. **Water types** (L): clear, coastal, murky on the ocean and the lake; tune the colours by eye.
9. **Foam**: drifts slowly downwind, turquoise glow under fresh whitecaps, lumpy thick foam.
10. **Beach**: damp sand up to where waves reach, a glossy film with a foam edge rushing up and back.
11. **Spray** (storm preset, C): droplets torn off breaking crests and carried downwind; none in a breeze.
    If droplets fly twice as fast as they should, the engine does not integrate VELOCITY for custom
    particle shaders: move them in `process()`.
12. **Sea-state changes** (C to cycle presets): the sea fades from one state to the next over about six
    seconds without a jump; floating barrels stay on the surface.
13. **Cost**: compare frame times with the previous main on High; each feature has a quality value.
