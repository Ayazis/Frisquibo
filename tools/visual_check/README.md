# Visual check

Renders fixed camera shots of a scene to PNG and compares them with a **local baseline**, so you can see
exactly what a change did to the look of the game.

Renders differ slightly between GPUs and drivers, and we work on several machines. So baselines are made on
your own machine right before you start a change, and are **never committed**.

```bash
tools/visual_check/run.sh tests/visual/grass_demo.tres baseline   # 1. before changing anything
tools/visual_check/run.sh tests/visual/grass_demo.tres            # 2. after (or during) the change: compare
tools/visual_check/run.sh tests/visual/grass_demo.tres capture    # only render, no comparison
```

Set `GODOT` to your Godot executable if it isn't on your `PATH` (on Windows, use the `_console.exe` build so
the output shows up in the terminal). A Godot window opens while it renders. The tool needs a real GPU, so it
can't run headless or in CI.

**Exit codes:** 0 = all shots match, 1 = differences or missing baseline, 2 = error.

## Output
Everything goes to `build/visual_check/<list>/` (ignored by git):
- `baseline/<shot>.png`: the reference renders from before your change.
- `<shot>.png`: the latest render.
- `<shot>.compare.png`: baseline | render | diff, side by side. Changed pixels are red.

## Workflow for a feature change
1. **Before you change anything**, on a clean working tree, run `baseline` for the shot lists your change
   could affect.
2. Make the change. Keep iterating with cheap, text-based checks: import, logs, tests, and `compare`'s
   PASS/FAIL lines and changed-pixel percentages. A FAIL on a shot you didn't mean to touch is a signal
   on its own, without looking at any image.
3. Viewing images is expensive for an AI agent (tokens). Open `*.compare.png` images only to investigate a
   bug the text can't explain, or once at the end to verify the final result. Open only the shots that matter.
4. When you start the next change, run `baseline` again so it compares against the new state.

## Shot lists
A shot list is a text resource (`VisualShotList`) in `tests/visual/` naming a scene, a resolution,
comparison tolerances and a list of `VisualShot`s (camera position, look-at target, FOV, and a `state`
dictionary). Shot lists are committed; only the renders are local. See `tests/visual/grass_demo.tres`.

If the scene root has a method `apply_visual_check_state(state: Dictionary)`, it's called before each shot.
Use it to set the time of day or weather and to hide the HUD.

## Determinism
- Each shot builds the scene fresh, with a fixed random seed.
- `--fixed-fps 60` makes time advance by exactly one frame per frame, so shader animation and physics are
  identical on every run. On the same machine, renders match pixel for pixel.
- After a GPU driver update, make a new baseline before comparing.
