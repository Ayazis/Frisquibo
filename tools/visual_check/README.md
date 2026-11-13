# Visual check

Renders fixed camera shots of a scene to PNG and compares them with golden images. This is how changes to
the look of the game are checked, by people and by AI.

```bash
tools/visual_check/run.sh tests/visual/grass_demo.tres            # compare with golden images
tools/visual_check/run.sh tests/visual/grass_demo.tres capture    # only render
tools/visual_check/run.sh tests/visual/grass_demo.tres update     # accept the renders as the new golden images
```

Set `GODOT` to your Godot executable if it isn't on your `PATH` (on Windows, use the `_console.exe` build so
the output shows up in the terminal). A Godot window opens while it renders. The tool needs a real GPU, so it
can't run headless.

**Exit codes:** 0 = all shots match, 1 = differences or missing golden images, 2 = error.

## Output
Written to `build/visual_check/<list>/` (ignored by git):
- `<shot>.png`: the new render.
- `<shot>.compare.png`: golden | new render | diff, side by side. Changed pixels are red.

## Shot lists
A shot list is a text resource (`VisualShotList`) naming a scene, a resolution, comparison tolerances and a
list of `VisualShot`s (camera position, look-at target, FOV, and a `state` dictionary). Golden images live
next to it, in `golden/<list name>/<shot>.png`. See `tests/visual/grass_demo.tres`.

If the scene root has a method `apply_visual_check_state(state: Dictionary)`, it's called before each shot.
Use it to set the time of day or weather and to hide the HUD.

## Determinism
- Each shot builds the scene fresh, with a fixed random seed.
- `--fixed-fps 60` makes time advance by exactly one frame per frame, so shader animation and physics are
  identical on every run. On the same machine, renders match pixel for pixel.
- **Golden images are only comparable on the same GPU and driver.** Another machine or a driver update can
  shift pixels slightly. Raise `pixel_threshold`/`max_changed_ratio` in the shot list, or re-create the
  golden images with `update` and review them.

## Workflow for visual changes
Viewing images is expensive for an AI agent (tokens), while the text output is cheap. So:
1. Make the change, and keep iterating with text-based checks: import, logs, tests, and `compare`'s
   PASS/FAIL lines and changed-pixel percentages. An unexpected FAIL on a shot you didn't mean to touch
   is a signal, even without looking.
2. Open `*.compare.png` images only to investigate a bug the text can't explain, or once at the end to
   verify the final result. Open only the shots that matter.
3. If the change is intended and looks right, run `update` and commit the new golden images with the change.
   The golden image diff in the commit shows reviewers exactly what changed visually.
