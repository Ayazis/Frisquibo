# 0004 — Ocean rules, physical wave length and shore set-up

Date: 2026-11-14
Status: Accepted. Text checks only; GPU path not yet verified on a desktop machine.

## Context

The ocean's "horizontal size" stretched the whole simulated sea sideways, ripples included. A random sea
looks much the same zoomed in, so the control appeared to do nothing. Big seas also brought no extra water
to the beach, and sea parameters could not react to each other ("if the water is shallow and the wind is
strong, add foam").

## Decision

- `OceanSpectrum.wavelength_scale` moves the JONSWAP spectral peak (peak frequency / sqrt(scale)) and
  divides out the energy gain, so it changes the length of the dominant waves only. Ripples keep their
  physical size; longer waves travel faster through normal dispersion. The longest cascade tile grows to
  hold at least four dominant waves (`OceanSimulation.tiles_for`).
- `Ocean.wave_setup`: breaking waves raise the mean water level towards the waterline (wave set-up), in
  proportion to the measured crest height, so higher seas run further up the beach. Shader and CPU height
  query use the same rule.
- Rules (`world/water/ocean/rules/`): an `OceanRuleSet` of `OceanRule`s, each "all conditions → all
  effects". Conditions and effects name any exported number of `Ocean` or `OceanSpectrum`, plus the
  measured `wave_height` (read-only) and per-point `local_depth`. Local outputs (`local_foam`,
  `local_wave_size`, `local_water_level`) are compiled into shader uniforms (max 8) and evaluated the same
  way on the CPU. Rules run in order and see earlier results; soft thresholds blend effects in.
  Evaluation is pure logic in `OceanRuleEngine` / `OceanLocalRules`, tested in `tests/headless/ocean_rules_test.gd`.
- Web/Compatibility: global rules apply to the Gerstner fallback; local rules and set-up are a no-op there.

## Consequences

Rules reading `wave_height` while changing wave size form a feedback loop; the measured height is
smoothed, but such rules should be avoided. Global changes regenerate the spectrum only when a value
actually changes. Local rule results are evaluated at the rest position on the CPU, so floating objects
can differ slightly from the drawn surface inside steep rule gradients.
