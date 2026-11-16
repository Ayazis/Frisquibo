# 0006 — Separate swell, and wave heights that match the sea state

Date: 2026-11-14
Status: Accepted. Verified on the FFT path with Mesa's software Vulkan driver
(`tests/smoke/ocean_wave_height.gd`); how it looks is not yet judged on a desktop machine.

## Context

The sea was one wind sea. Real seas are almost always a local wind sea plus swell from elsewhere, with
its own direction and a much longer period; that mix is a large part of what makes water read as real.
Measuring the simulation also showed its wave height did not follow from the wind: a fresh breeze
(9 m/s, 80 km fetch) is 1.72 m by its own JONSWAP spectrum and was simulated at 2.0 to 2.4 m.

## Decision

- `OceanSpectrum` gets `swell_height` (significant height in metres), `swell_period`,
  `swell_direction` and `swell_spread`. The swell is a Gaussian around its wave vector in the longest
  cascade, holding the variance (height / 4)^2. It is at least 0.7 spectrum texels wide so the grid
  samples all of its energy; the longest tile grows to hold four swell wavelengths. The swell's
  wavenumber uses the finite-depth dispersion relation, so swell slows and shortens in shallow seas.
  Default height is 0: existing presets are unchanged. `presets/breeze_over_swell.tres` shows it.
- Amplitude normalisation corrected: |h0|^2 = S(k) dk^2 / 2 (was S(k) dk^2, waves 1.41 times too high).
- Waves get a random phase but a fixed share of the energy, instead of a Gaussian-random amplitude.
  A tile holds few long waves, so random amplitudes made the height depend on the seed (measured:
  wind sea 17% high, swells 30 to 40% low). Many random-phase waves still give a Gaussian surface.
- `OceanSeaStats.wind_wave_height()` computes the height the spectrum describes; the tuner shows it
  next to the measured one.
- Web/Compatibility: the Gerstner fallback ignores the swell (its controls are disabled there).

## Consequences

Every existing preset is now lower: about 0.7 of its former height, the height its wind really gives.
Foam and choppiness react to steepness, so whitecaps are sparser at the same settings. `height_scale`
1.41 restores the old height where that look was wanted. Switching swell on grows the longest tile
(233 m to about 900 m for a 12 s swell), which coarsens that cascade and makes the pattern jump once.
Wave groups are slightly more regular than with random amplitudes.
