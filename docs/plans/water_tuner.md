# Plan — water tuner: tweak water behaviour with UI controls

Date: 2026-11-14
Status: In progress (step 1).

Goal: tweak every aspect of the water live through UI controls, with everything steering towards
water that is as realistic as possible.

## Starting point

- `prototypes/water_compare/ocean_control_panel.gd` has 13 hand-listed sliders and 4 hard-coded
  "links". It lives in `prototypes/`, so it can't ship or be reused.
- About 25 shader values (water colour and absorption, scattering, foam look, caustics, fold limiting)
  have no control at all.
- The wave model is one wind sea. "Swell" only narrows the spreading, and vertical / horizontal size
  are artistic multipliers with no physical meaning.
- A tuned sea can't be saved; it is lost when the preset changes.
- Decision 0004: the GPU path was never verified on a desktop machine.

## The experience

A water tuner overlay, toggled by a key, usable in any scene with an `Ocean`:

- Grouped, collapsible sections with units, per-row reset and a short explanation per control.
- Auto or manual per control. Auto is the physically derived value (for example foam coverage and
  choppiness from wind); manual overrides it and shows how far it is from physical. This replaces the
  hard-coded links.
- Live readouts: significant wave height, peak period, dominant wavelength, steepness, Beaufort
  number, with a warning when a setting is not physically possible (waves steeper than they can be
  without breaking, a surface that folds through itself).
- Presets: save, load, and A/B against a snapshot. They save as text `.tres`, so a sea can be committed.
- Debug views: per-cascade tint, foam and fold map, water depth, rule weights, plus pause and time scale.

## Build order

1. **Parameter catalogue.** One tested `RefCounted` class lists every tunable with range, unit, group
   and description, read from the `@export` hints. The panel and the rule editor both generate from
   it, so a new parameter appears in both automatically. The panel moves to `ui/`.
2. **Look resource.** Optics, foam and caustics move from loose shader uniforms into an `OceanLook`
   resource with water-type presets (clear ocean, coastal, murky): tunable, savable, rule-addressable.
3. **Realism in the model.**
   - A separate swell system with its own direction, height and period, on top of the local wind sea.
   - Auto values and readouts.
   - Blended transitions between sea states.
4. **Presets, A/B and debug views.**
5. **Shore and quality.** Beach profile (sand slope, bar, shelf) and quality-tier values (cascades,
   mesh density, reflection resolution) become live controls.

Each step gets a decision record where it changes structure, plus headless tests for the pure logic.
On Web the panel works, with FFT-only controls disabled behind a feature check.

## Verification

No visual checks: the work is done in a container without a desktop GPU. Each step is checked with
the headless import and the headless tests only. Whether the water looks right has to be judged on a
desktop machine.

## Assumptions

- The tuner is a developer tool, not a player-facing settings menu.
