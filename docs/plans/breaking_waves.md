# Breaking waves plan

Status: phase A in progress; phases B and C not started. Follows decision 0010 (shore waves).

## Goal

Breaking waves that look real from the beach. Most real beaches show **spilling** breakers: white
water tumbling down the front of the crest, a foaming bore running in, and foam that ages into lace
and is left on the sand. Steeper beaches show **plunging** breakers: a lip thrown forward over a tube
of air. Both are wanted, in that order, because they differ a lot in risk.

## What is proven and what is not

- **Proven, and most likely to look good:** foam that lives on the water surface. Lace that opens up
  as it ages, white water riding the front of the crest, and foam left behind on the sand are what
  games with convincing shores rely on. Our foam system already draws on any surface with relief and
  bubble glow. The physics underneath (spilling breakers on gentle beaches, rays that bend towards the
  shore) is textbook.
- **Proven for one hand-made wave, unproven on any coast:** the curl. A curl shape swept along the
  crest is what surf games have used for twenty years, and it gives a recognisable curl. Making it
  form by itself along an arbitrary coastline is our own work.
- **The usual failure:** the white water of a plunge (burst, splash-up, mist). Real-time versions are
  usually soft round particles lit evenly, which read as cotton wool. Films use millions of simulated
  particles.
- **Scale:** on the demo island a typical breaker is about 0.5 m high, so a tube would be about 30 cm.
  From the beach, what people see is mostly the white water and the foam, not the curl. The ocean is
  meant mainly for a harbour (`docs/FEATURE_MAP.md`), where there is no surf to plunge.

So the order is:
- **Phase A:** the foam and spilling work.
- **Phase B:** two short test scenes with pass/fail bars, to settle the risky parts cheaply.
- **Phase C:** production curls, only if both test scenes pass.

## Phase A: spilling breakers and shore foam (proven)

1. [ ] **White water on the breaking front (the roller).** A band of dense, lumpy, bright foam rides
   the upper front face of each breaking crest. The pattern is tied to the crest, so it travels with
   the wave and slides slowly down the face, with a different pattern for each wave. A slight bulge in
   the surface gives the roller a rounded top in silhouette. It is foam on the surface, not particles.
2. [ ] **Foam that ages into lace.** Behind each breaker the foam starts as a solid sheet and opens
   into a network of cells whose holes grow, until thin threads are left and those fade too. The cells
   are cellular-noise edges (F2 - F1, two scales), so it looks like lace and never like scattered
   spots. Each wave leaves its own lace.
3. [ ] **Foam left on the sand.** As each wave's swash turns back, a lacy line of foam stays where the
   wave stopped, and a sheet of bubbles drains away behind it. Both fade during the backwash. This is
   drawn by the ground, with the same swash timing, so it lines up with the water's edge.
4. [ ] **Wave rays and the refraction coefficient.** Rays traced seaward from the waterline over the
   `ShoreField` give Kr = sqrt(b0 / b) from how far apart neighbouring rays are, against their spacing
   offshore. The shore waves get bigger on headlands and smaller in bays, which replaces most of the
   `shore_lee_share` guess. The rays are also the coordinates phase C would need.

Checks: headless import, tests and both exports for every step, and a person's look on a desktop
GPU (checks 19-22 in `water_realism.md`).

## Phase B: two test scenes with pass/fail bars (before any production curl)

Each one is a throwaway scene in `prototypes/breakers/`: a straight beach and one breaker driven by
hand. A person judges it on a desktop GPU, side by side with real surf footage at the same distance
and light. What counts as a pass is agreed before the scenes are built, and so is the stopping point:
if a scene fails twice, its part is dropped.

1. **Curl shape and lip.** One folded sheet swept along the crest, its lip following a ballistic path,
   normals from the curve's tangent, light through the lip worked out from its thickness. Passes if,
   at 15 m and at 40 m:
   - the silhouette and the motion read as a real plunging wave;
   - the lip glows green when the sun is behind it;
   - there is no visible seam with the surrounding sea;
   - the vertex count stays inside the budget.
2. **White water of a plunge, with no cotton balls.**
   - The burst where the lip lands is a thin sheet of water thrown up that breaks into foam on the
     water surface, not a cluster of puffs.
   - Spray is small, fast droplets stretched along their motion, mostly transparent, lit from behind
     and short-lived.
   - Mist is one faint, wide layer.

   Passes if nothing reads as soft round blobs from any distance, in sun and in overcast light.

## Phase C: production curls (only if both B scenes pass)

As in the earlier version of this plan:
1. **Breaker type.** Spill, plunge or surge is chosen from the surf similarity number
   ξ = tan β / sqrt(H_b / L0) (Battjes 1974), with a `curl_strength` tunable where 1 is physical.
2. **Breaker profile.** A `BreakerProfile` class with a shader twin: one folded sheet whose fold grows
   through the breaker's life. The lip follows a ballistic path, then plunges, splashes up and runs on
   as a bore.
3. **Ribbons.** Strips of mesh along the breaking crests near the camera, placed with the wave rays
   from A4. The ocean discards its pixels inside each strip, and the ribbon reaches slightly past the
   edge with a skirt that dips under the surface. Reach and resolution are set per quality tier. Off on
   Low and on the web.
4. **Shared shading.** The ocean's surface shading moves into one include that the ocean and the
   ribbons share. This refactor comes first and changes nothing visible.
5. **White water.** Built the way phase B's white water scene settled it. A `breaker_plunged` signal
   is added for sound.
6. **Gameplay heights.** `Ocean.height_at` keeps returning the uncurled height, and a new
   `Ocean.breaker_at(xz)` query reports whether a point is inside the tube, in foam, or being hit by a
   plunge.

Budget: about 80k vertices and 1 ms on High at 1080p.

Risks:
- **The seam** between ribbon and ocean.
- **Refraction through the lip.** The screen copy is taken before any water is drawn, so the lip and
  tube are shaded from the water's own light instead of the wave face behind them.
- **Rays that cross** at headlands pinch the ribbons.
- **Small tubes.** A tube is small at the demo's wave sizes.

### Alternatives considered for the curl

- **Folding the existing ocean mesh.** Too coarse beyond about 10 m from the camera, and jagged along
  the crests.
- **Ray-marching the breaker in a volume.** Too expensive, and hard to light with the rest of the
  water.
- **Pre-animated breaker meshes.** They loop visibly and don't follow the coast.

## References

- Battjes 1974, *Surf similarity*: breaker types from the Iribarren number.
- Fournier & Reeves 1986, *A simple model of ocean waves*: overturning crests.
- Thürey et al. 2007, *Real-time breaking waves for shallow water simulations*: breaking fronts as
  parametric meshes riding a coarser surface.
- Longuet-Higgins & Cokelet 1976: the shape of overturning waves.
