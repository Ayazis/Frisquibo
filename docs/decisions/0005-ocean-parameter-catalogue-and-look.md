# 0005 — Ocean parameter catalogue, look resource and the tuner panel

Date: 2026-11-14
Status: Accepted. Text checks only (headless import, headless tests, headless smoke test on the
Gerstner fallback); the GPU path and how the panel looks are not yet verified on a desktop machine.

## Context

The sea could only be tuned through a hand-listed slider panel in `prototypes/`, about 25 values of
the surface shader had no control, and a tuned sea could not be saved. See `docs/plans/water_tuner.md`.

## Decision

- `OceanParameterCatalog` describes every exported number of an object (range, step, unit, group,
  label, description) from its `@export` hints. `Ocean.parameters()`, `parameter_value()` and
  `set_parameter()` are the one way to list, read and change a tunable; they replace the per-value
  setters. The rule engine reads the same catalogue, so sliders and rules never disagree on a range.
- Labels and descriptions live in the catalogue, because doc comments do not exist in an exported game.
- `OceanLook` (Resource) holds colour, clarity, foam, caustics and fold limiting. Each value has the
  name of the shader uniform it drives; `OceanLookBinding` pushes them. Its defaults equal the shader's
  (checked by `tests/headless/ocean_parameters_test.gd`), so nothing changes visually until a value is
  moved. Absorption is three numbers so it gets ordinary sliders. Look values are rule-addressable.
- `ui/widgets/ocean_tuner/` is the panel, generated from the catalogue: foldable sections per export
  group, reset per row, tooltips, colour pickers, physical readouts (`OceanSeaStats`), the existing
  links, and save / load of sea state and look as text resources in `user://`.
- Web/Compatibility: controls the Gerstner fallback ignores are disabled (`Ocean.is_parameter_live`).

## Consequences

A new `@export_range` number on `OceanSpectrum`, `OceanLook` or `Ocean` appears in the panel and in
the rules without further work; a number exported without a range is rule-addressable but gets no
slider. A new look value needs a shader uniform of the same name. Ocean-level values (sea level,
shore values) are not part of a saved sea yet. The links are still hard-coded in the panel; the plan
replaces them with per-control auto values.
