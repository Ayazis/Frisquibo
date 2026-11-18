# 0013 — Storm crests: wave direction, crest lean, breaking white water, spindrift

Date: 2026-11-16
Status: Proposed. Checked headless and with rendered A/B shots on a desktop GPU; the look still needs
the user's judgement against the reference photos.

## Context

The FFT ocean's storm seas looked too smooth and regular. Real storm seas (the user's reference
photos) have lopsided crests (steep front, leaning downwind), crests that collapse into a ragged,
tumbling mass of white water, and spray blown off the crests. Only long swell looks like smooth,
sine-like waves. More choppiness is not the answer: the storm preset is already near folding.

## Decisions

- **Waves travel along the wind.** The evolve pass used h0(k) e^(+iwt), which with the inverse
  transform's e^(+ik.x) sent the wind sea upwind and the swell against its own direction (measured: a
  pattern shift of -3 m in 0.5 s along the wind). It now uses e^(-iwt). The Gerstner fallback already
  moved downwind. Every rendered baseline changes with this (the waves have other phases at the
  capture time).
- **Crest lean** (`OceanSpectrum.crest_lean`, default 1.2, faded in from 7 to 18 m/s wind). The unpack
  pass pushes each point along the wind by crest_lean times its height. That squeezes the face in front
  of a crest and stretches the back by crest_lean times the slope: steep wind waves turn lopsided at
  every wave length, gentle swell (slope ~0.03) hardly changes. Its derivatives follow from the slope
  and go into the jacobian terms, so normals and the fold limit see it. Where it would compress the
  surface below a jacobian of 0.3 (or below what the wave already had) it is scaled back: it never
  folds the surface. Foam is still injected from the waves' own jacobian, so the lean doesn't change
  how much of the sea is white.
- **Breaking white water** (`OceanSpectrum.white_water_height`, default 0.45). The unpack pass keeps a
  short-lived copy of the foam injection (1.2 s, moments.w) that marks crests breaking now. The surface
  vertex shader raises separate lumps of churning noise (ocean_white_water.gdshaderinc) on those
  crests, a share of each cascade's breaking crest height, spilling a little downwind; the fragment
  shader tilts the normal by the same lumps. Octaves the mesh or the pixel can't carry fade out. Not
  mirrored in OceanHeightField: aerated white water carries little weight, so floating objects ride
  the wave under it, and the lumps depend on maps the CPU doesn't read back.
- **Spindrift** (`OceanSpectrum.spray_amount`, default 1). Spray particles now look for crests breaking
  now (white water, up to 8 random tries per particle) instead of any old foam, and 60% of them are
  wisps of mist that the wind smears out and carries downwind, growing and thinning. High and Ultra
  draw spray over a wider area with more particles (12000 over 200 m, 24000 over 300 m), so storm
  crests further than 60 m from the camera get spray too.

## Consequences

- The lean and lumps are strongest on the storm and hurricane presets and invisible in calm seas.
  The lumps' silhouette is limited by the surface mesh: from 100 m away only lumps of a few metres
  show.
- The visual-check storm shots set the sea state while the scene starts, which starts the 6 s fade
  from the default sea; the shots capture after 4 s, so they show a part-faded storm.
  `tests/visual/storm_crests.tres` sets `transition_time` to 0 to show the full storm.
