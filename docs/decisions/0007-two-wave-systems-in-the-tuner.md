# 0007 — Main waves and surface waves as two systems in the tuner

Date: 2026-11-16
Status: Accepted.

## Context

Decision 0006 gave the ocean a separate swell, but the tuner still read as if the wind did everything:
the Wind section came first, every preset had `swell_height = 0`, and the wind slider ran to 80 m/s
(beyond any hurricane) with wave height growing with its square. The only way to a bigger sea was more
wind, so the wind felt far too strong. Several controls were also unclear:

- `swell` ("Crest alignment") sat in the Wind section, didn't add swell, and fought `spread` over the
  same property (how far wind-wave directions stray), in opposite directions.
- "Wave shape" mixed values for all waves (vertical size, choppiness) with one for the wind waves only
  (horizontal size).
- Foam was split over two sections, and the fold limit (a crest-shape value) sat with the look.

## Decision

- **Sections follow how a sea is described**, top to bottom: sea state readouts, *Main waves (swell)*,
  *Wind and surface waves*, *Crest shape*, *Foam*, *Depth and shore*, water colour, surface light,
  caustics, *Artistic overrides* (folded by default), links, save and load. The order lives in
  `OceanTunerPanel.SECTION_ORDER`; the export groups of `OceanSpectrum`, `OceanLook` and `Ocean` name
  the sections, and a test fails when a group is missing from the order.
- **`wind_spread` replaces `swell` and `spread`**: one width multiplier on the Donelan-Banner spreading
  (`beta / wind_spread`). 1 is a real wind sea, lower gives long aligned crests, higher a confused sea;
  as beta goes to 0 the spreading becomes uniform by itself, which covers what `spread` did. The
  spreading stays normalised, so the wave height doesn't change. Old resources still load:
  `OceanSpectrum._set()` turns `swell` into the matching `wind_spread` (`1 / (1 + 4 swell)`) and drops
  `spread`.
- **Wind speed runs to 40 m/s** (Beaufort 12 starts at 32.7). The readouts show the main waves and the
  surface waves separately (height, period, length), and the wind as Beaufort force and m/s.
- **Every preset has swell** with its own direction, so the main waves no longer come from the wind
  alone. The wind seas are unchanged.
- **Web / Compatibility**: the Gerstner fallback has one wave train. It now follows whichever system is
  bigger, in direction and length; heights add like energies. Swell sharpens it less.

Not done: a separate choppiness for the swell. Crest sharpening grows with choppiness times steepness
(k a, or pi times height / length), and real swell is gentle: 1.4 m at 12 s is 1/160 (k a = 0.02), so
choppiness 1.4 compresses it by about 3%. It stays rounded by itself. Only swell steeper than real
swell gets sharp, and the readouts now warn about that (height / length above 1/25).

## Consequences

The presets look different: each now has a long swell under its wind sea, and the wind sea's
directions follow `wind_spread` instead of the old alignment plus 15% uniform blend. Adding swell grows
the longest cascade's tile (decision 0006), so cascade 0 is coarser in all presets. Rules or shot
lists that named `swell` or `spread` must use `wind_spread`.
