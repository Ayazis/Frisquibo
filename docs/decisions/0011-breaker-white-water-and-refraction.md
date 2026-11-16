# 0011 — Breaker white water as surface foam; refraction from ray divergence; curls behind prototypes

Date: 2026-11-16
Status: Accepted. Built and checked headless; the look needs a desktop run (checks 19-22 in
`docs/plans/water_realism.md`).

## Context

The shore waves (0010) break, but their white water was the generic foam pattern thresholded by a
breaking amount, which thins into scattered spots. Curling (plunging) breakers were considered next
(`docs/plans/breaking_waves.md`). The curl geometry is a known technique, but the white water of a
plunge is where real-time breakers usually look fake, and on this game's coasts most breakers spill
anyway.

## Decisions

1. **Spilling white water first, curls only after two pass/fail prototypes** (the plan's phases B
   and C). Nothing production-side is built for curls until a person has judged the prototypes on a
   desktop GPU against real footage.
2. **All breaker white water is foam on the water surface, not particles.**
   - The roller is a dense, ragged band on the upper front face, its pattern in a frame that rides
     the crest and tumbles down the face, with a different pattern per wave and a small bulge in the
     surface (twinned on the CPU).
   - The foam behind a breaker ages into lace: cellular F2 - F1 edges at two sizes, thresholded by a
     width that shrinks with age, worn unevenly by a broad noise.
   - The same lace (`foam_lace.gdshaderinc`, global texture `water_foam_lace`) draws the foam the
     backwash leaves on the sand, timed by the swash (`water_swash_state`).
3. **The refraction coefficient comes from the divergence of the travel direction**,
   d(ln b)/ds = div(d), added up along the rays the fast marching already followed (each cell
   remembers its upwind neighbours). The value at each ray's offshore end is then carried back along
   it. No separate ray tracing is needed. The divergence is smoothed over about a wavelength
   (diffraction) and Kr clamped to 0.4..2. It is stored with the waterline points (RGB float), so the
   shader reads it with no extra texture fetch.

## Consequences

- Kr is relative to the field's offshore edge (12 m deep), not to where the shore waves fade in.
  Waves inside the zone are a little bigger on points and a little smaller in bays than the open sea's
  share would make them. On the demo island about 8 % of the field is at or near the 2.0 clamp, mostly on
  points of the wiggly coast. Close to the shore the depth limit caps them anyway, so the effect
  there is breaking further out.
- The bake takes about 1.3 s for the demo island, up from 0.9 s.
- The lace on the sand needs the global texture, which Ocean publishes on both renderers. Ground
  without an ocean has no swash, so it draws no lace.
