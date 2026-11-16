# 0012 — Curling breakers: ribbons along the crests, a folded sheet, white water as foam and streaks

Date: 2026-11-16
Status: Built and checked headless. The look and the cost are not judged yet: the plan's phase B
pass/fail judgement was meant to come first, but on request phases B and C were built together. If the
bench fails, set `curl_strength` to 0 or the tier's `breaker_reach` to 0; the shore then keeps phase A's
spilling breakers (0011).

## Context

Plunging breakers need a surface that folds over itself, which the camera-centred radial ocean mesh
can't carry. It is too coarse beyond about 10 m, its grid doesn't follow the crests, and its normals
come from a height map. The plan (`docs/plans/breaking_waves.md`) chose strips of fine mesh along the
breaking crests near the camera.

## Decisions

1. **Wave rays** (`ShoreRays`). Rays are traced seawards from every metre of each waterline: marching
   squares on the shore field's depths (`WaterlineTracer`), then dx/dT = grad T / |grad T|^2 by the
   midpoint rule, sampled every 0.4 s of travel time.
   - Each sample keeps the field's own travel time. Near the waterline the field's clock is coarse
     (its first water texels sit at about 1.5 s), and pulling samples onto a ray clock threw them back
     onto land.
   - Lookups take one correction step against that time.
   - A ray stops where one step's time jumps (river mouths) or it leaves the field.
   - Each sample also stores the still depth.
2. **Ribbons are the ocean's own material on another mesh.** Two instance uniforms set the ribbon's
   rows and its crest number. The vertex stage finds the rest position on the rays and then runs the
   ocean's usual vertex code, so a ribbon matches the surface exactly wherever there is no curl.
   - A ribbon draws where the curl is at least 0.01. The ocean leaves a hole where the curl is above
     0.05, but only for the crest numbers the ribbons cover now (`breaker_waves`), so a crest without a
     ribbon never becomes a hole. Between the two thresholds both draw the same water.
   - Ribbons cover the stretches of coast whose rays start within reach + 30 m of the camera, and every
     crest out to where the biggest possible wave starts breaking.
   - `OceanBreakers` manages a pool of 16 ribbons. Mesh size comes from the tier (80 m reach and 64
     segments across on High).
3. **The curl is one folded sheet in the crest's frame** (`BreakerProfile` with a GDScript twin, and
   `ocean_breakers.gdshaderinc` on the GPU):
   - Five cubic Beziers: the outer lip, the tip, the tube's ceiling, its back wall, and the trough. The
     water ahead of the crest is spread over them by arc length.
   - The lip tip is ballistic. It lands in the trough after the time a body takes to fall one wave
     height, about half a breaking wave height ahead of the crest.
   - The stage comes from how far the crest has run into shallower water since it reached the depth
     limit: h_break = h * ratio^(4/5). The breaker type comes from the surf similarity number (Battjes
     1974).
   - Normals come from the sheet's tangent. The water is blended onto the sheet by the fold, which is 0
     before breaking and after the tube collapses.
4. **White water without particles where it can be avoided:**
   - Lip aeration, the plunge burst and the foam-over after the plunge are lace foam on the surface
     (`ocean_breaker_foam`).
   - Spray is GPU particles drawn as thin streaks along their motion, never round dots. They are fed by
     an emitter texture the CPU writes (`BreakerSpray`).
   - Mist is one faint sheet per plunge line, rebuilt each update (`BreakerMist`).
5. **CPU twin and game hooks** (`ShoreBreakers`, `BreakerState`):
   - `Ocean.breaker_at(xz)` gives the stage, the lip, and whether a spot is inside a tube.
   - `Ocean.breaker_plunged(position, height)` fires when a lip lands, for sound.
   - `Ocean.height_at` stays the uncurled surface, so floating things ride the face and the bore and
     never get caught in the tube.
6. **The lip and tube are shaded from the water's own light.** The screen copy is taken before any
   water is drawn, so it can't show the wave behind the lip. The lip and tube drop the refracted screen
   for the scattered in-water colour, and the tube loses part of the sky light.

## Consequences

- Cost on High: up to 16 ribbons of about 220 x 65 vertices, mostly fewer (2 to 6 in use). The ocean
  fragment shader does a breaker evaluation per pixel near the shore. The CPU samples the crests for spray, mist and landings every 6 m. Each frame it re-samples a sixth of
  them and carries the others' lips on along their velocity: about 0.6 ms per frame, up to 1.5 ms in
  the frame new crests come within reach.
- Load time: the waterline and the rays add about 0.5 s to the seabed bake (the demo island: 1,084 rays).
- About a fifth of the island's rays stop before 15 s of travel time, mostly in the river mouth and in
  bays where rays from two sides meet. Waves there keep spilling, which is right for a river mouth.
- The CPU noise now really matches the GPU. The previous `hash()` resolved to Godot's global hash(), so
  until this change floating objects in the shore waves rode wave timings and sizes the screen didn't
  show.
- Since then, the shore waves focus caustics on the seabed, and the underwater lens waterline and
  `Ocean.height_at` include the shore waves and the swash. The curls themselves don't do any of this.
  Underwater caustics still come from the FFT waves only.
- Not done: A camera inside a tube sees no tube from inside. The screen copy limitation from decision 6
  stays.
