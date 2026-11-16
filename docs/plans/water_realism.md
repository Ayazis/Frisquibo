# Water realism plan

Status: in progress. Each step is committed on its own; the checklist below shows what is done.
Visual checks are left to a person on a desktop GPU. In the container every step is verified with the
headless import, the headless tests and the headless smoke test only (nothing is rendered there):

```
godot --headless --import
for t in water_shaders underwater_view water_ripples water_textures water_types shore_runup water_quality \
    island_terrain ocean_tuning ocean_parameters ocean_sea_systems ocean_rules ocean_height_field \
    beach_profile river_flow_field shore_waves water_mask planar_reflection; do
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

Wave refraction towards the shore and curling breakers were out of scope for this pass: both need a
separate near-shore wave model. The second pass below adds one (decision 0010).

## Second pass (decision 0010)

13. [x] **Shore waves.** A travel-time field over the seabed (eikonal equation, fast marching): crests
    turn to meet the beach, shorten and grow as the water shallows, lean forward and break at the depth
    limit, with white water on the front face and a fading foam band behind. Wave for wave the swash's
    timing and size, so each crest runs up the sand as far as the swash says. CPU twin for buoyancy.
14. [x] **Dry hulls.** `WaterMask`: an invisible lid over a boat's opening keeps the sea out of the hull.
15. [x] **Screen-space reflections** on all water, over the mirror or the sky: the river reflects its
    banks, and a boat on a crest reflects from the real surface, not the flat mirror plane.
16. [x] **Rough-water Fresnel and the horizon.** Fresnel averaged over the unresolved slopes (Bruneton
    et al. 2010); mirror samples and reflected rays never cross below the horizon.
17. [x] **Linear mirror.** The planar reflection renders linear HDR light without the main pass's tone
    mapping and glow (which it applied a second time before).

Out of scope still: plunging breakers that curl over (a mesh can't fold over itself here), foam left
lying on the sand after the backwash, and the shore waves in the underwater view's waterline and in
the caustics (both still read the FFT waves only).

## Desktop checks

Nothing here was rendered (no rendering in cloud containers). On a desktop GPU, open
`prototypes/water_demo/water_demo.tscn`, the island demo (keys 1-5 jump between the beach, the pond,
the river, the river mouth and the island from the sea). First look at the output panel for shader or
script errors, then check:

1. **Reflections** (1, 5): distant rough sea smears the island and the boats into vertical streaks.
   The **pond** (2) mirrors its trees sharply from its own mirror plane; that mirror only renders while
   the pond is on screen. The river reflects the sky only. Low tier: blockier streaks (4 taps).
2. **Pond and river** (2, 3): sun glint and colour look right with the ocean's optics (the sky
   reflection is the physical F0 = 0.02); no shimmer on distant ripples; the river flows from the pond
   to the sea, its surface following the falling water level, with no gap at the outlet or the mouth.
3. **Underwater** (Q to lower the camera, drag to look up), in the sea and in the pond: fog and colour
   by distance, blur, light shafts, the surface from below with Snell's window, and a wavy waterline with
   a dark meniscus when the camera is half in. The pond's underwater view only switches on over the pond.
4. **Ripples** (F to drop objects, the boats, the barrels off the beach): rings spread from splashes,
   bobbing objects make rings, foam appears and fades. If the rings only go one way (bumps, no troughs)
   the HDR viewport clamps negative values: encode the height with an offset in `ripple_step.gdshader`.
5. **Caustics** (1, shallow water off the beach): bright lines that move with the waves, with faint
   colour fringes; deep sand darker and bluer. The underwater view shows the same caustics.
6. **Gusts**: dark and light patches drifting downwind, most visible on a calm sea and on the pond.
7. **Close-up ripples**: fine ripples near the camera that fade into the glitter, with no visible tiling
   and no change in overall brightness with distance.
8. **Water types** (L): clear, coastal, murky on the sea and the pond; tune the colours by eye.
9. **Foam**: drifts slowly downwind, turquoise glow under fresh whitecaps, lumpy thick foam.
10. **Beach** (1, 4): the sea itself runs up the sand with each wave and slides back, each wave reaching
    its own height and neighbouring stretches of beach hit at different times; the sand stays damp up to
    where the waves reach and the backwash leaves a glossy film; foam rides the moving water's edge.
11. **Spray** (storm preset, C): droplets torn off breaking crests and carried downwind; none in a breeze.
    If droplets fly twice as fast as they should, the engine does not integrate VELOCITY for custom
    particle shaders: move them in `process()`.
12. **Sea-state changes** (C to cycle presets): the sea fades from one state to the next over about six
    seconds without a jump; floating barrels stay on the surface.
13. **Cost**: compare frame times with the previous main on High; each feature has a quality value.

Second pass:

14. **Shore waves** (1, 4, 5; C for the storm and calm presets): crests near the island run parallel
    to the beach all round it, also on the lee side (smaller there), and bend round the headlands; they
    get shorter and steeper towards the sand, lean forward, and break with white water on the front
    face and a fading band of foam behind. Each breaker should arrive just as the swash starts its
    run-up; a big one runs further. No seams or flicker where the shore waves fade in (around 4-8 m deep)
    or at the texels of the shore field (3 m). Barrels in the surf ride the breakers (CPU twin).
    If the breakers look too regular, raise `SWASH_PHASE_SPREAD` (now 0.5; the old swash used 1.5).
15. **Dry hulls** (5, then close to a boat; storm preset): no sea inside the open boats as they roll,
    and a crest between the camera and a boat still hides the boat. Set the mask's `debug_tint` to see
    the lid.
16. **Screen-space reflections**: the river (3) mirrors its banks and trees, with the sky where the rays
    find nothing; boats and the island reflect in the sea (1, 5) without seams where the march hands
    over to the mirror (screen edges, about 40-60 m away). Low: none.
17. **Fresnel and horizon** (5, looking out to sea; storm preset): the rough sea darkens towards the
    horizon instead of turning into a bright mirror; no bright line along the horizon.
18. **Linear mirror**: reflections are as bright as the things they reflect, times the Fresnel (they
    were washed out before), and the glow doesn't bloom twice in them.

Breaking waves, phase A (`docs/plans/breaking_waves.md`, decision 0011):

19. **Roller** (1, 4; calm and breeze presets): the upper front of each breaking wave carries dense,
    lumpy white water with a ragged lower edge. It travels with the crest, tumbles slowly down the
    face, looks different on each wave, and glows turquoise just under it. The face is slightly rounded
    at the top, with no crease where the bulge starts or at the crest.
20. **Lace** (1, 4): behind each breaker the foam opens into a lace of cells whose holes grow until
    thin threads are left, then fades before the next breaker. It never reads as scattered spots or
    cotton balls, at 10 m or at 60 m. From far away it fades smoothly into an even cover.
21. **Foam on the sand** (1): as each wave turns back, a lacy line stays where it stopped and a sheet
    of bubbles drains behind it, both gone before the next wave arrives. It lines up with the water's
    edge, with no gap and no overlap, and is brighter for bigger seas (they run further).
22. **Refraction** (5 and around the island): breakers are bigger on the points of the island and
    smaller in its bays. No stripes or blotches in wave height that follow the 3 m texels or small
    wiggles of the coast. If points look too violent, lower `ShoreField.REFRACTION_MAX` (2.0).
