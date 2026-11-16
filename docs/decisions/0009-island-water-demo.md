# 0009 — One water demo: the island, a second mirror plane, swash on the ocean surface

Date: 2026-11-16
Status: Accepted. Checked headless; needs a desktop run for the look (docs/plans/water_realism.md).

## Context

The water comparison prototype had five stations (lake, river, the GodotOceanWaves library, our FFT
ocean on a straight beach, the grass playground). The comparison is decided (0002): our ocean stays. A
single scene that shows all our water together is a better test of how it looks and fits: sea, beach,
fresh water above sea level, and a river that joins them.

## Decisions

1. **`prototypes/water_demo` is the only water demo** and the project's main scene: an island in the
   FFT ocean with a sandy beach all round, a pond above sea level and a river from the pond down to the
   east coast. The other stations and the vendored GodotOceanWaves copy are removed (still in git
   history). The grass playground stays as its own scene (`main.tscn`).
2. **A second planar mirror** (`PlanarReflection.slot` 1, `water_reflection_2`) for water at another
   level, such as the pond. Each water material picks its mirror with `reflection_slot` (-1: the sky
   only, for sloping water such as the river). Ground shaders tell the two mirror cameras apart by an
   otherwise empty layer (`SECOND_MIRROR_LAYER`, 19) the second one leaves out, so each clips at its own
   height. The second mirror renders only while its water is on screen.
3. **The swash moves the ocean surface**: near the waterline the sea rises to the swash edge of the
   shared `water_swash()` (swash.gdshaderinc), so the water itself runs up the sand and slides back. The
   ground uses the same function for damp sand and the glossy backwash film, so the two agree.
4. **The island's ground is one radial mesh** (fine rings across the coast, coarse far out) with a
   height-map collision over the island and its shallows: about 0.8 s to build headless.

## Consequences

- Two mirror planes at most; a third level of water would reflect the sky only.
- The CPU water height (`Ocean.height_at`, buoyancy) does not include the swash, so objects right at the
  waterline don't ride it.
- Water and its ground are tied by shape: the pond's square and the river's ribbon rely on the terrain
  covering them outside the water (checked by tests/headless/island_terrain_test.gd).
