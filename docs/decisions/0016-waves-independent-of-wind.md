# 0016 — Waves set by their own sliders; the tuner as numbered steps

Date: 2026-11-18
Status: Proposed. Checked headless (import, all headless tests, the panel built headless) and with the
GPU smoke tests (wave height measured against the new sliders, every tunable at its extremes). Not
rendered or tried by hand: the panel layout needs the user's judgement in the water demo.

## Context

After 0007 the wind still did too much. The surface waves (the JONSWAP wind sea) were built from wind
speed and fetch, so the wind slider changed their height, length and direction. Crest lean grew with
the wind, and Auto made crest sharpness follow it. The user wants to shape the waves with wave
sliders only. They also found the sliders hard to read, and want the tuner in the order a sea is built:
wave shape, then surface waves and wind, then foam, then coast and beach.

## Decisions

- **The surface waves have their own sliders**: `surface_height` (significant height, m),
  `surface_length` (dominant wave length, m), `surface_direction` and `surface_spread` (was
  `wind_spread`). The spectrum keeps its JONSWAP and Donelan-Banner shape. `OceanSpectrum` turns height
  and length into the JONSWAP constant and peak frequency (`jonswap_alpha()`, `peak_frequency()`), and
  the compute shader takes those in place of wind speed and fetch.
- **The wind no longer changes any wave.** `fetch` is gone. `crest_lean` is used as set (it was faded
  in between 7 and 18 m/s). The default is 0.1, about what the default 9 m/s breeze gave, and the storm
  preset keeps 1.2. Crest sharpness has no Auto any more. The waves lean along their own direction,
  not the wind's. Wind still drives what rides on the waves: ripples, gust patches, spray, breaker
  mist, foam drift and streaks, and Auto on the whitecap amount.
- **The artistic size overrides are gone** (`height_scale`, `wavelength_scale`, "Keep steepness"
  between them). With height and length on their own sliders they only duplicated them. "Keep
  steepness" now ties surface wave length to surface wave height.
- **Old sea states still load.** `OceanSpectrum._set()` turns `fetch` and the wind speed and direction
  stored before it into the height, length and direction those gave. It applies `wavelength_scale` and
  `height_scale` to them (and the height scale to the swell too), and renames `wind_spread`. Saves leave
  out default values, so a save that kept the default fetch keeps the default surface waves. The
  presets were rewritten with the values their wind and fetch gave.
- **A warning, not a rule, ties waves to wind**: the readouts warn when the surface waves are higher than
  the wind could build (Pierson-Moskowitz). That is fine for a sea after a storm, so it only warns.
- **The tuner is five numbered steps**, one open at a time (`FoldableGroup`): *1 Wave shape* (swell,
  crest shape), *2 Surface waves and wind*, *3 Foam*, *4 Coast and beach* (water depth, shore waves,
  beach), *5 Water look*. The sea state readouts stay on top, save and load below. Each step has a
  one-line hint and a folded *Fine-tuning* part for values few people need (`FINE_TUNING`). The export
  groups name the sections; `OceanTunerPanel.STEPS` puts them in steps, and a test fails when a group,
  colour or link has no step.
- **Sliders read better**: plain, unique labels; wide ranges (max at least 50 times min) move
  logarithmically; a value that differs from where it started is tinted; each link checkbox sits in the
  section of the values it ties.

## Consequences

- The wind slider can be moved freely to try ripples, spray and streaks on the same waves.
- A big storm sea needs its height and length set, not just more wind; "Keep steepness" (on in the
  water demo) makes the length follow the height.
- `surface_height` stops at 15 m with no open end: the extremes test pushes open ranges four times
  past the slider, and a 60 m sea is no longer a sea.
