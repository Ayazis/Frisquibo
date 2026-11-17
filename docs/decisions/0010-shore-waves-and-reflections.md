# 0010 — Shore waves from a travel-time field, dry hulls, screen-space water reflections

Date: 2026-11-16
Status: Accepted. Built and checked headless; the look and the GPU cost need a desktop run
(see "Desktop checks", items 14-18, in `docs/plans/water_realism.md`).

## Context

After the realism pass (0008) the beach was the weakest part of the water: waves only got smaller in
shallow water and never turned, steepened or broke. Open boats showed the sea inside their hulls. The
river had no reflections except the sky, the flat mirror put reflections at the wrong height under big
waves, and rough water at the horizon reflected like a mirror. The planar reflection also rendered through
the main environment, so it was tone mapped and sRGB-encoded before the water drew it, then tone mapped
again.

## Decisions

1. **Shore waves come from a travel-time field over the seabed.** `ShoreField` solves the eikonal
   equation |grad T| = 1 / sqrt(g h) outwards from the waterline with fast marching (trapezoid slowness,
   4-neighbour Godunov update) on a 3 m grid, only in water up to 12 m deep. Crests are lines of equal T,
   so they refract round headlands and meet the beach; |grad T| sets the wavelength, so waves shorten as
   they slow. It bakes at load in GDScript: about 0.9 s for the demo island (a 1200 m square).
   Shallow-water speed is used throughout: about 10 % fast at the zone's outer edge for an 8 s wave,
   exact where it matters most (near the beach).
2. **A share of the sea's energy becomes shore waves inside the zone** (`shore_wave_share`, 0.7); the
   FFT waves keep the rest (amplitude sqrt(1 - share)), so the total stays the same. They grow by
   Green's law (h^-1/4) until the depth limit (crest <= breaker_ratio * h), lean forward with a short
   front as they near it, and break: white water on the front face, a foam band behind that fades over
   a third of a period. A coast facing away from the main waves keeps `shore_lee_share` of them.
3. **The shore waves are the swash's waves.** Their phase at the waterline is the swash's, and each
   wave's size is the swash's draw for its reach. Both are drawn at the waterline point the wave heads
   for (carried along by the fast marching), so they stay fixed along a wave's path: drawn at the
   wave's own position, the timing noise could reverse the phase gradient in deeper water and make
   crests run out to sea. The swash noise became an integer hash so the CPU twin (`ShoreWaves`, used by
   `Ocean.height_at`) matches the GPU bit for bit, and everything runs on one published clock
   (`water_wave_time`) instead of the shader's TIME. `SWASH_PHASE_SPREAD` fell from 1.5 to 0.5 periods:
   it now also sets how far crests turn from parallel to the beach.
4. **Dry hulls by depth, not stencil.** `WaterMask` draws an invisible lid over the opening after the
   underwater view and before the water (render priority -5), writing depth only. Water behind the lid
   fails the depth test; a crest in front of the boat still draws. Works on every renderer.
5. **Screen-space reflections in the water shaders**, not the engine's SSR (which skips transparent
   surfaces). The ray off the displaced surface is marched against the depth buffer (steps growing
   quadratically, jittered, bisection refinement), kept above the horizon and blurred by the same slope
   spread as the mirror. It blends over the mirror or the sky by a confidence that fades at the screen
   edges, past 40 m and for rays turning back to the camera. Steps per tier
   (`OceanQuality.reflection_march_steps`: 0 / 12 / 24 / 40; the project default is High's). Off on
   Compatibility.
6. **Mean Fresnel** (Bruneton, Neyret & Holzschuch 2010) over the unresolved slope variance along the
   view replaces Schlick times an ad-hoc roughness factor, on sea, lake and river. Mirror samples are
   clamped to the water's side of the horizon line.
7. **The mirror renders linear light.** The reflection viewport is HDR (`use_hdr_2d`) and its camera
   uses a copy of the main environment with a linear tone map at exposure 1, no glow and no
   adjustments (refreshed twice a second), so it matches the screen copy that refraction and the march
   read.

## Consequences

- Reflections change brightness: physically right now, but every water look tuned by eye against the
  old double-tone-mapped mirror needs another look on a desktop.
- More work per water pixel on High: up to 24 march steps plus 5 refinement samples, two more shore-field
  samples, and the shore wave per vertex and per pixel. The march is the costliest part and scales with
  the tier.
- The shore field is baked at the sea level of `set_seabed`. A tide moves the waterline but not the
  field: crests keep following the depths, and the waves near the new waterline fade with the depth
  limit as before. Rebake (call `set_seabed` again) for big level changes.
- The underwater view's waterline and the caustics still read only the FFT waves; in the surf the lens
  waterline can miss a breaker.
- Plunging breakers don't curl over: the forward lean is a horizontal displacement held back by the fold
  limit.
- Headless runs can't exercise the FFT path, so the shore waves' GPU half, the march and the mask are
  checked by compiling, by the CPU twin's tests and by reading; the look by the desktop checks.

## Since then: crests run at the speed of high waves (2026-11-17)

The beach waves looked like slow motion. Their crests ran at the small-wave shallow-water speed
sqrt(g h), but high waves in shallow water run faster, at about sqrt(g (h + H)) (solitary waves and
bores), and in the surf zone every wave is depth-limited at H = 0.78 h: about a third faster.
`ShoreField` now bakes the travel time with that speed (`crest_speed()`), H the depth-limited height,
at most the sea's expected wave height (`Ocean` passes it when it bakes the seabed). The swash, the rays
and the breakers all follow the field, so they keep in step. The field is baked once, so a much rougher
or calmer sea later keeps the speeds of the sea it was baked for beyond the surf zone; inside it they
are right for any sea.
