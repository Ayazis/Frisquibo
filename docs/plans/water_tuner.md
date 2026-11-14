# Plan — water tuner: tweak water behaviour with UI controls

Started: 2026-11-14. Last updated: 2026-11-14.
Branch: `ccr-2a9bff4d-nh0kdm` (contains `claude/fft-ocean-wave-behavior-dvqs3n`). No PR yet.
Status: steps 1 to 3 built and pushed; steps 4 and 5 and the open items below remain.

Goal: tweak every aspect of the water live through UI controls, with everything steering towards
water that is as realistic as possible. The tuner is a developer tool, not a player settings menu.

**Continuing in a new session: read "Waiting on the user" first, then pick from "Next up".**

## Waiting on the user

Nobody has looked at any of this on a desktop GPU yet. The user said they would check later. Ask for
their findings before building further on the look; these are the things most likely to need a change:

- Every preset is now about 0.7 of its former wave height, with sparser whitecaps (decision 0006).
  It is the height the wind really gives. `height_scale` 1.41 restores the old look.
- `OceanAutoValues` (foam amount and choppiness from wind) was fitted to the old, taller presets and
  probably wants retuning against the new heights.
- Switching swell on makes the long waves jump once (the longest tile grows from 233 m to about
  900 m for a 12 s swell).
- The panel layout itself (`ui/widgets/ocean_tuner/`) has never been seen: widths, the foldable
  sections, the Auto and Reset buttons, the colour pickers.
- The `OceanLook` defaults equal the shader's, so the water should look unchanged until a look
  control is moved. Worth confirming.

The user chose **no visual checks** (`tools/visual_check/`) for this work. Ask again before doing any.

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
| 4 (part) | Save and load of sea state and look to `user://` | `ocean_tuner_storage.gd` |

Decisions: `docs/decisions/0005-ocean-parameter-catalogue-and-look.md`,
`0006-swell-and-wave-height.md`. The panel is shown in `prototypes/water_compare/custom_ocean_station.gd`.

## Next up, in order

1. **Step 4: A/B snapshot.** A button that stores the current sea state, look and ocean values, and
   a toggle that flips between the snapshot and the live values. Fits in `ocean_tuner_storage.gd`
   or a sibling widget.
2. **Save the ocean-level values too.** Sea level and the shore values (`level`, `breaker_ratio`,
   `wave_setup`, `min_shore_wave`) live on the `Ocean` node, so save and load skip them. One
   `OceanTuning` resource holding spectrum, look and those values would also serve the A/B snapshot.
3. **Step 4: debug views.** Per-cascade tint, foam and fold (jacobian) map, water depth, rule
   weights: a `debug_view` integer uniform in `ocean.gdshader` with a dropdown in the panel. Pause
   and time scale: `Ocean._time` advances in `_process`; add a `time_scale` export (it then appears
   in the panel by itself).
4. **Step 5: shore and quality controls.** The beach profile values are constants in
   `custom_ocean_station.gd` feeding `BeachProfile`; changing one means rebuilding the beach mesh and
   calling `Ocean.set_seabed()` again. Quality values are in `data/quality/ocean_*.tres`
   (`OceanQuality`); changing cascade count or mesh density means re-creating the simulation and mesh.
5. **Make the overlay usable outside the prototype.** The plan's "toggled by a key, usable in any
   scene with an `Ocean`" is not done: the panel only appears as a tab in the water comparison scene.

## Open items that need eyes on a desktop GPU

- **Water-type presets** (clear ocean, coastal, murky) as `OceanLook` `.tres` files. Not written
  because the colours would be guesses.
- **Blended transitions between sea states.** The longest cascade's tile grows with the longest wave
  (233 m for a breeze, about 940 m for the storm preset), and a tile change rearranges every long
  wave at once. Blending the numbers alone would turn one jump into several. Doing it properly means
  running the old and the new longest cascade side by side and cross-fading them.
- **Auto values showing how far a manual value is from physical.** The Auto box exists; the
  deviation display from the original design does not.
- **The steepness and depth links** are still hard-coded in `ocean_tuner_links.gd`.

## How to verify (no desktop GPU needed)

Godot 4.7-stable, as in CI (`.github/scripts/install-godot.sh`). In a fresh container, install it
and the software Vulkan driver first (`apt-get update` is needed before the install works):

```
apt-get update && apt-get install -y --no-install-recommends mesa-vulkan-drivers libvulkan1
```

Then, from the project root:

```
godot --headless --import
for t in ocean_parameters ocean_rules ocean_height_field beach_profile river_flow_field; do
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
