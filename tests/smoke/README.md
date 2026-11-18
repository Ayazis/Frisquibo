# Smoke tests

Scripts that run a real scene for a few hundred frames and fail on errors.

```
godot --headless --path . --script res://tests/smoke/ocean_smoke.gd
```

`--headless` has no RenderingDevice, so the ocean runs on its Gerstner fallback. To run the real FFT
path (compute shaders) without a GPU, use Mesa's software Vulkan driver (lavapipe) and a virtual
display. It is slow, but it runs the same shaders:

```
apt-get install -y mesa-vulkan-drivers libvulkan1 xvfb
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a \
  godot --path . --rendering-driver vulkan --resolution 320x180 --script res://tests/smoke/ocean_wave_height.gd
```

- `ocean_smoke.gd`: the water comparison scene with the custom ocean, preset changes and re-creation.
- `ocean_wave_height.gd`: FFT path only. Checks that the simulated significant wave height matches
  the sea state: the wind sea's spectrum, and swells of a given height. Skips without a RenderingDevice.
- `atmosphere_smoke.gd`: the water demo through every time of day, weather and sea state (as the demo
  keys and the visual check drive it) and a time lapse over a day; fails on non-finite light.
- `ocean_extremes.gd`: FFT path only. Every tunable at both ends of its range (open ranges pushed 4x
  past the slider) plus nasty combinations; fails on a non-finite surface, a wave height above 40 m,
  or a blacked-out picture. About 5 minutes. `ONLY=<name part>` runs a subset, `SHOTS=<dir>` saves
  the frames of failing cases.

Check the log as well as the exit code: Godot can exit successfully after reporting script errors.
