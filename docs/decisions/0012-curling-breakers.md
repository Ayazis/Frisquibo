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

## Fix: seabed showing beside the curls (2026-11-17)

At the ends of some curling sections a slanted strip of seabed showed next to a pale patch. The cause
was the wave rays, not the ocean surface: neighbouring rays often fan far apart (the field's clock is
coarse at the waterline, so rays leave it in bundles), in the demo island 1 m apart at the beach and
11 m or more apart at the crest. A ribbon bends its curl only at its rays, so across such a gap one
quad stretched flat between two curled edges, while the ocean's hole followed the real curl pixel by
pixel. Where the hole lay outside the stretched quad, nothing drew the water.

- `ShoreRays` now traces another ray wherever two neighbours lie more than 1.5 m apart, at equal travel
  time, in water 0.3 to 12 m deep. The ray is seeded midway between them where they are furthest apart
  and traced back to the beach and out to sea, so it lands in the gap however sensitive the start
  point is. Up to 8 such splits per pair. Rays that die at their first step are dropped (their rows
  folded the ribbon back onto the beach); the rays traced through the gaps take their place.
- `OceanBreakers` sizes the ribbon mesh to the densest stretch of rows, and a stretch longer than one
  ribbon is split into ribbons that share their end row (before, the quad between two ribbons was missing).
- Cost on the demo island: 3,181 rays instead of 1,084, tracing in about 3.2 s instead of 1.0 s (the
  tracer itself got faster: each step's end is sampled once); ribbons of 788 rows instead of 221, so the
  ribbons' vertex work is about 3.5 times what it was. The look is not traded away; if the load time
  matters, tracing the rays on a thread is the next step.

## Fix: spiky lips and paper-flat undersides (2026-11-17)

With the ribbons following the curl closely, two faults showed that the stretched quads had hidden:

- **Spikes.** A breaker's stage follows its unbroken height very closely (a tenth more height and the
  lip is thrown a whole flight time earlier). Along a crest that height changed within a metre or two:
  the field's refraction coefficient comes out striped from cell to cell, and the waterline point that
  sets each wave's size moves fast where rays bunch. The shader also read refraction and size at each
  pixel's rest point instead of at its crest, so one cross-section mixed several stages. Now the stage
  and plunge are read at the crest, the same on the GPU and the CPU (`ShoreBreakers`), and averaged over
  five points 2.5 m apart along the crest (weights 1 2 3 2 1): the lip peels along the crest. Each point
  changes smoothly so the average has no seams of its own: before breaking its stage comes from the same
  formula (negative, down to -1), and near the beach it fades out over the last 0.3 m of water. (A first
  try without that drew thin slivers along the lines where a point crossed the waterline.)
  Smoothing the refraction coefficient itself was tried and left out. It is far from the ideal even
  around a round island (0.5 to 1.6 where 1.41 is right), so it needs its own fix, which would change
  the shore wave heights everywhere.
- **Paper lips.** Ripples, foam and whitecaps were looked up at the rest position, and the lip is a
  narrow band of rest positions stretched over metres of sheet, so they were magnified until flat. They
  are now looked up along the sheet (metres of sheet towards the shore, `breaker_surface_position()`).
  And the lip's tip and underside reflect downwards, where the mirror and the sky only had sky to give:
  that part of the reflection now shows the water ahead, its sky by the water's Fresnel and otherwise
  its body colour. The underside reads as the dark inside of the tube.
- Cost: five breaker samples instead of one per pixel near the shore, and the sheet's length once per
  curling pixel.

## Fix: short, boxy tubes (2026-11-17)

After the peel fix the curls came as short tubes with a squared-off lip and a dark rectangular opening.

- The lip's outside was a cubic with handles of 0.4 times its chord: level from the crest, then nearly
  straight down to the tip, a box corner. The lip is the water thrown from the crest, so its outside is
  now the tip's own ballistic path: the parabola from the crest to the tip, which one cubic gives
  exactly. Its underside is a parabola too, level at the root of the lip and along the lip's heading at
  the tip. The opening is now rounded.
- The stage and plunge are averaged over seven points 3 m apart (±9 m, about a third of a wavelength
  either side) instead of five points 2.5 m apart: a curl now runs along a longer stretch of crest. Cost:
  seven breaker samples per pixel near the shore instead of five.
