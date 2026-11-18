# 0015 — Foam brightness: half the light, darker hollows, greyer as it ages

Date: 2026-11-18
Status: Proposed. Checked headless (import, shader compile, tests). Not rendered: the look needs the
user's judgement on a desktop GPU against the reference photos.

## Context

The user found the foam too white and not photorealistic. Three things made it so:
- **Too bright.** Thick foam had an albedo of 0.86–0.9 (sRGB), about 0.75 in linear light. Measured fresh
  sea foam reflects about half the visible light (Whitlock et al. 1982: ~55 %), and older foam much
  less.
- **Evenly white.** Once foam was thick, every pixel had exactly `foam_color`. Real foam has bright
  bubble tops and darker hollows between them, so even a closed sheet shows a texture of tones.
- **Aged foam as white as fresh foam.** Sparse, old threads were as bright as a new whitecap.

## Decisions

- **`foam_color` is (0.76, 0.79, 0.79)** in the ocean, the rivers and lakes (`water_common`) and the
  foam the swash leaves on the sand (`terrain_ground`), about 0.55–0.6 in linear light.
- **`FoamSurface.shade`**: the brightness of the foam itself, from the foam textures' own height.
  - Hollows are 0.55 as bright as the tops (`FOAM_CAVITY_SHADE`). Foam is fully lit 0.45 in eroded
    height above where it wears through (`FOAM_CAVITY_RANGE`).
  - Foam at the lowest fill (old, drained, sparse) is 0.7 as bright as a fresh sheet (`FOAM_AGED_SHADE`).
  - The breaker roller, the lace the breakers leave, the plunging breakers' foam and the beach residue
    carry their own shade (`water_lace_shaded`), mixed by cover (`water_foam_shade`).
- **Thin foam shows more of the water**: it is 35 % white over the bubble colour, not 50 %
  (`FOAM_THIN_WHITE`).

## Consequences

- A few ALU per foam pixel; no extra texture samples.
- Every rendered baseline with foam in it changes.
- The ocean tuner and `OceanLook.foam_color` still set the base colour, so the look can be pushed back
  towards white if the user prefers.
