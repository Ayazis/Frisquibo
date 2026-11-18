# 0014 — Sea foam from photos and scans: one shared foam surface, hex-tiled, three textures per density

Date: 2026-11-16
Status: Built and checked: headless tests, GPU smoke tests, and renders against the user's reference photos
(storm, surf, beach, overcast). Frame cost is not measured yet.

## Context

The foam was a cellular "lace" texture thresholded into a hard white mask. It tiled visibly every 4 m and
looked cartoony next to the realistic water. Reference photos of real storms and surf showed what was
missing:
- open-sea foam is a sparse network of stretched, frayed veins;
- surf foam is nearly closed, with low-contrast holes stretched along the crests;
- foam has depth (bubbles glow turquoise just under it);
- in overcast light it is grey-blue, close to the water's own brightness.

Procedural noise alone (two attempts in `prototypes/foam/`) kept looking like marble or oil.

## Decisions

1. **One foam surface for all foam** (`world/water/foam_surface.gdshaderinc`). Open-sea whitecaps, the
   lace breakers leave (`foam_lace`, which now wraps it) and the swash foam on the beach all use it.
   - One `fill` value (0..1) runs from thin open-sea threads to a closed surf-zone sheet.
   - It returns a thickness, not a mask: thin foam lets the water through and takes the bubble colour,
     and only thick foam is fully white.
   - A blurred, wider copy of the pattern just under the surface glows with bubbles through the holes.
2. **The detail comes from real foam: three textures per density**, all in `world/water/foam_scans/`
   with their sources and licences in `SOURCE.txt`.
   - **Dense, middle and sparse.** Seven are top-down photos from Wikimedia Commons (CC0 / CC BY 2.0),
     two are ambientCG scans (CC0), and the specks are generated.
   - **Picked across the sea.** Broad noise picks which texture of a density is drawn where, and which
     density, around the `fill` value.
   - **Converted by our own tools.** `tools/foam_synth/foam_photo.gd` crops a photo, flattens its
     lighting, turns brightness into height, blends the seams one axis at a time, and derives normals.
     `tools/foam_scans/pack_foam_scans.gd` repacks the ambientCG scans. The packed layout is
     R, G = normal x, y (OpenGL), B = height, imported as BC7 with mipmaps.
   - **Sources stay local.** The 8K and original sources are in `build/foam_sources/` and not committed.
3. **No repeat on a grid: hex-tiling everywhere** (Heitz & Neyret 2018).
   - Every texture sample is cut into hexagonal cells. Each cell samples at a random offset and a small
     turn (up to 0.4 rad, so foam stretched along the crests stays stretched).
   - Neighbouring cells blend around the textures' typical height, keeping contrast.
4. **The large shapes come from the same textures drawn 5× bigger**, also hex-tiled, with 30% of the old
   vein network mixed in.
   - The fine layer fades out between 12 and 45 m.
   - The large layer stays to the horizon. Before, distant foam was only the vein network, which
     repeated every 22 m and drew contour rings.

## Consequences

- **Cost.** Up to about 24 texture samples per foam pixel:
  - two layers;
  - up to two densities per layer;
  - up to two textures per density;
  - three hex samples per texture.

  Lower tiers can drop the large layer or the hex-tiling, without lowering High.
- **Credits.** CC BY 2.0 textures ("Gischt" by Stiller Beobachter, the Pašman photo by Coralie Ferreira)
  need a credit in the game's credits.
- **Repository size.** About 90 MB of 2K PNGs, committed without Git LFS for now.
- **Generated foam kinds.** `tools/foam_synth/foam_synth.gd` makes five kinds of foam (surf sheet,
  streaks, spatter, old lace, churn) for testing. Only the spatter is used, for specks.
