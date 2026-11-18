# Plan — water tuner: tweak water behaviour with UI controls

Started: 2026-11-14. Last updated: 2026-11-16 (third session: main waves and surface waves).
Branch: `ccr-2a9bff4d-nh0kdm` (contains `claude/fft-ocean-wave-behavior-dvqs3n`). No PR yet.
Status: steps 1 to 3 and the A/B part of step 4 built and pushed; the debug views, step 5 and the open
items below remain.

Goal: tweak every aspect of the water live through UI controls, with everything steering towards
water that is as realistic as possible. The tuner is a developer tool, not a player settings menu.

**Continuing in a new session: read "Desktop check" first, then pick from "Next up".**

## Desktop check (2026-11-15, RTX 4070)

All tests, the GPU wave-height test (measured within 0.01 m of expected) and the smoke test pass.
The scene was rendered and the panel was screenshotted and driven from a script:

- The panel is legible and works. Fixed: it covered the end of the button bar, and sliders on rows
  with an Auto box were shorter than the rest.
- The lower wave heights look plausible; the storm has less foam than before (expected, decision 0006).
- The `tests/visual/custom_ocean.tres` shots render the beach and shallows nearly white, on the base
  branch too, so that comes from the visual-check scene's lighting, not this work. In the normal
  scene the sand and water look right.

### Extremes and the storm (2026-11-15, after user feedback)

The user found the sliders work, but asked to push the extremes, said the storm didn't look like a
storm, and wanted the panel full height. Done:

- `tests/smoke/ocean_extremes.gd` (GPU): 94 cases, all pass. `tests/visual/ocean_extremes.tres`:
  18 shots, including boats for scale. Visual-check shots can now set any ocean value
  (`state.ocean`).
- Black frames in the first extreme renders were the camera **under water** (an 11 m hurricane sea,
  shore set-up above the camera), not NaN. Seen from below, the surface renders pitch black: there
  is no underwater look yet.
- Storm preset: 24 m/s, 600 km fetch, choppiness 1.4, foam threshold 0.85, 9 s foam. New look values
  `foam_streaks` and `streak_length`: foam blown into long lines along the wind from Beaufort 7.
  `OceanAutoValues` refitted to the square root of the wind; a test keeps it near the presets.
- `prototypes/water_demo/scale_boat.gd`: an 8 m boat with a mast, one off the beach and one in deep
  water at (-40, -1450).
- The panel now runs to the bottom of the screen.

Still odd at the extremes, left as they are:

- **Foam threshold is very steep** around 0.8-1.0: at 24 m/s, 0.85 gives whitecaps, 0.9 turns the
  sea mostly white. A control that maps to foam coverage would be easier to use.
- **Shortest horizontal size (0.1)** and **6x height with 4x choppiness** turn into a field of white
  spikes. Both are far steeper than real waves can be; the panel warns about it. Option: cap
  steepness by lowering height when the horizontal size shrinks.
- **Longest horizontal size (8x)** loses about a third of the wave height (1.72 -> 1.14 m): the
  longest waves probably no longer fit in the largest cascade.
- **Storm at the beach**: the whole surf zone and the low beach go white (set-up pushes foamy water
  up the flat beach). Possibly right for a storm, but worth a look.
- The sky stays sunny blue; a storm also needs an overcast sky, which the comparison scene owns.

Still a matter of taste for the user: `OceanAutoValues` against the new heights, and the jump when
swell is switched on.

On 2026-11-15 the user allowed checks to be run, including renders. On 2026-11-16 they limited that: no renders or GPU smoke tests in a cloud container (see below).

## Main waves and surface waves (2026-11-16, after user feedback)

The user found the wind had too much effect and asked for clear sections: one for the main waves, one
for the surface waves, since big waves can run one way while the wind blows another. Done (decision
`0007-two-wave-systems-in-the-tuner.md`):

- Panel sections in a fixed order: sea state, Main waves (swell), Wind and surface waves, Crest
  shape, Foam, Depth and shore, look sections, Artistic overrides (folded), links, save and load.
  Since replaced by numbered steps and surface waves with their own sliders (decision
  `0016-waves-independent-of-wind.md`).
- `wind_spread` replaces `swell` ("Crest alignment") and `spread`; old resources convert on load.
- Wind speed slider ends at 40 m/s. Readouts show main and surface waves separately; a warning
  when swell is steeper than real swell.
- Every preset has swell with its own direction. The Gerstner fallback follows the bigger system.
- No separate swell choppiness: swell is too gentle for choppiness to sharpen it (see the decision).

Checked with the headless import, all headless tests and the headless smoke test. **Not checked on a
GPU**: the spectrum shader change (`wind_spread`), the new presets, and how the panel looks.

**The user asked not to run visual checks or the GPU (software Vulkan) smoke tests in a cloud
container**: 1600x900 renders take about 17 minutes per shot there. Run them on a desktop machine.

## Done

| Step | What | Where |
|---|---|---|
| 1 | Parameter catalogue: every exported number with range, unit, group, label, description | `world/water/ocean/ocean_parameter.gd`, `ocean_parameter_catalog.gd` |
| 1 | `Ocean.parameters()`, `parameter_value()`, `set_parameter()`, `is_parameter_live()` | `world/water/ocean/ocean.gd` |
| 1 | Panel generated from the catalogue: sections, reset, tooltips, links | `ui/widgets/ocean_tuner/` |
| 1 | Physical readouts and warnings | `world/water/ocean/ocean_sea_stats.gd`, `ocean_tuner_readouts.gd` |
| 2 | Look resource (colour, clarity, foam, caustics, fold limit), sliders and colour pickers | `ocean_look.gd`, `ocean_look_binding.gd`, `ocean_tuner_color_row.gd` |
| 3 | Separate swell: height, period, direction, spread | `ocean_spectrum.gd`, `compute/ocean_spectrum.glsl`, `presets/breeze_over_swell.tres` |
| 3 | Wave height normalisation fixed; fixed energy per wave with random phase | `compute/ocean_spectrum.glsl` |
| 3 | Auto boxes for foam amount and choppiness | `ocean_auto_values.gd`, `ocean_tuner_row.gd` |
| 4 (part) | `OceanTuning`: sea state, look and the ocean's own values (level, shore) as one resource | `ocean_tuning.gd`, `tests/headless/ocean_tuning_test.gd` |
| 4 (part) | Save / load (one `user://ocean_tuning.tres`), Snapshot and A/B swap | `ocean_tuner_storage.gd` |

Decisions: `docs/decisions/0005-ocean-parameter-catalogue-and-look.md`,
`0006-swell-and-wave-height.md`. The panel is shown in `prototypes/water_demo/island_scene.gd`.

## Next up, in order

1. **Step 4: debug views.** Per-cascade tint, foam and fold (jacobian) map, water depth, rule
   weights: a `debug_view` integer uniform in `ocean.gdshader` with a dropdown in the panel. Pause
   and time scale: `Ocean._time` advances in `_process`; add a `time_scale` export (it then appears
   in the panel by itself).
2. **Step 5: shore and quality controls.** The beach profile values are constants in
   `custom_ocean_station.gd` feeding `BeachProfile`; changing one means rebuilding the beach mesh and
   calling `Ocean.set_seabed()` again. Quality values are in `data/quality/ocean_*.tres`
   (`OceanQuality`); changing cascade count or mesh density means re-creating the simulation and mesh.
3. **Make the overlay usable outside the prototype.** The plan's "toggled by a key, usable in any
   scene with an `Ocean`" is not done: the panel only appears as a tab in the water comparison scene.

## Open items that need eyes on a desktop GPU

- **Water-type presets**: written in `world/water/ocean/looks/` (absorption from Jerlov's water types);
  their colours still need judging on a desktop GPU.
- **Blended transitions between sea states**: done in the water realism pass (`Ocean.transition_time`):
  a change of tiles waits for the values to settle, then runs the old simulation beside the new one and
  cross-fades them. Needs a look on a desktop GPU.
- **Auto values showing how far a manual value is from physical.** The Auto box exists; the
  deviation display from the original design does not.
- **The steepness and depth links** are still hard-coded in `ocean_tuner_links.gd`.

## How to verify (no desktop GPU needed)

Godot 4.7-stable, as in CI (`.github/scripts/install-godot.sh`). In a fresh container, install it
and the software Vulkan driver first (`apt-get update` is needed before the install works):

```
apt-get update && apt-get install -y --no-install-recommends mesa-vulkan-drivers libvulkan1
```

Then, from the project root (the two `xvfb-run` lines render: run them on a desktop only, never in a
cloud container):

```
godot --headless --import
for t in ocean_tuning ocean_parameters ocean_sea_systems ocean_rules ocean_height_field beach_profile river_flow_field; do
  timeout 120 godot --headless --path . --script res://tests/headless/${t}_test.gd; done
timeout 200 godot --headless --path . --script res://tests/smoke/ocean_smoke.gd
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json
timeout 500 xvfb-run -a godot --path . --rendering-driver vulkan --resolution 320x180 --script res://tests/smoke/ocean_wave_height.gd
timeout 500 xvfb-run -a godot --path . --rendering-driver vulkan --resolution 320x180 --script res://tests/smoke/ocean_smoke.gd
```

Things that cost time in the first session:

- **Always wrap test runs in `timeout`.** A script error in a `--script` test leaves Godot running
  forever instead of exiting.
- **`--headless --import` does not compile test scripts**, so a parse error in a test only shows when
  the test runs. Read the log for `SCRIPT ERROR`, not only the exit code.
- **`--headless` has no RenderingDevice**: the ocean runs its Gerstner fallback, and
  `RenderingServer.shader_get_parameter_default()` returns null. The software Vulkan runs above are
  the only way here to exercise the compute shaders.
- **The Windows and Web exports were not run locally** (they need the export templates); CI runs them
  on a PR.

## How things fit together

- A new `@export_range` number on `OceanSpectrum`, `OceanLook` or `Ocean` appears in the panel and in
  the rule editor by itself. Add its label and tooltip to `OceanParameterCatalog.LABELS` and
  `DESCRIPTIONS`; `ocean_parameters_test.gd` fails when a description is missing.
- A new `OceanLook` number needs a float uniform of the same name in `ocean.gdshader` with the same
  default; the same test checks both.
- Anything in the spectrum compute shader that changes wave energy should be checked with
  `tests/smoke/ocean_wave_height.gd`, which compares simulated against expected significant height.
- On Web/Compatibility only the values in `Ocean.FALLBACK_PARAMETERS` do anything; the panel greys
  out the rest.

## Original design, for reference

A water tuner overlay, toggled by a key, usable in any scene with an `Ocean`:

- Grouped, collapsible sections with units, per-row reset and a short explanation per control.
- Auto or manual per control. Auto is the physically derived value; manual overrides it and shows
  how far it is from physical.
- Live readouts: significant wave height, peak period, dominant wavelength, steepness, Beaufort
  number, with a warning when a setting is not physically possible.
- Presets: save, load, and A/B against a snapshot, as text `.tres`.
- Debug views: per-cascade tint, foam and fold map, water depth, rule weights, pause and time scale.

Each step gets a decision record where it changes structure, plus headless tests for the pure logic.
