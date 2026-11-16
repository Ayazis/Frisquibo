# Curling waves plan

Status: proposed. Nothing built yet. Follows decision 0010 (shore waves); the decision for this work
will be 0011.

## Goal

Breaking waves on the beach that look real up close: the crest pitches forward, a lip throws out and
falls, a tube of air forms under it, the lip plunges into the trough, white water bursts up, and the
wave goes on as a foaming bore. Sunlight glows green through the thin lip. Where the beach and the sea
call for it, waves spill instead (white water tumbling down the face without a tube) or surge up the
sand without breaking. Breaking runs along the crest (a wave "peels") instead of the whole crest
flipping at once.

## Why the current shore waves can't do it

- **The surface can't fold.** The shore waves move each point of the water forwards and up. A curl
  needs the surface to fold over itself, but the fold limiter (`min_jacobian`) holds every crest back
  before it does.
- **Normals come from a height map.** The fragment shader builds the normal from the slope over rest
  position. On an overhang the surface has two heights at one spot, and the underside of the lip needs a
  normal that points down.
- **The ocean mesh is too coarse.** It is radial and centred on the camera, with vertex spacing of
  about distance × 0.012: 0.25 m at 20 m, 0.5 m at 40 m. A lip about 1 m across needs at least 10
  vertices across it to read as a curve, which only the first 10 m or so would get. The grid also
  doesn't line up with the crests, so even a fine grid would leave a jagged lip edge.

## Approach (recommended): breaker ribbons along the crests

A narrow strip of mesh, a *ribbon*, follows each breaking crest near the camera. It is fine across
the crest (where the curl needs detail) and coarse along it. Its vertex shader traces the breaker's
cross-section, a 2D curve, from the same base wave the ocean draws, plus a fold that grows through
the breaker's life. Inside the ribbon's strip the ocean surface discards its pixels, and the ribbon
draws the full profile there. Outside it the ocean is unchanged.

### 1. Wave rays: coordinates that follow the crests

Bake rays from the `ShoreField`. Start them every 1 m along each waterline contour (marching squares
on depth 0) and trace them seaward along grad T. On each ray, record the world position every 0.25 s
of travel time, out to the edge of the shore zone. Store the result in a texture (`ShoreRays`): one
row per ray, one column per time step, holding world x and z. Alongshore position `a` (row) and
travel time `T` (column) then make a grid whose columns are the crests. A ribbon vertex at (a, T)
gets its world position from one filtered lookup.

The same bake gives these for free:
- **Refraction coefficient** Kr = sqrt(b0 / b), from the spacing of neighbouring rays (b) against
  their spacing offshore (b0). Waves gather energy on headlands and spread it out in bays. This
  replaces most of the `shore_lee_share` guess in the shore waves, which also gain from it.
- **Seabed slope** along each ray, which decides the breaker type (step 2).

On the demo island this is about 1,000 rays × 240 steps, a small RG float texture, baked once at load
after the shore field. Where rays cross at headlands, Kr is clamped and the positions smoothed.

### 2. Breaker type and life cycle: pure logic, tested

`BreakerProfile` (a `RefCounted` class, with a shader include as its twin, like ShoreWaves and
`ocean_shore_waves.gdshaderinc`):

- **Type from the surf similarity (Iribarren) number** ξ = tan β / sqrt(H_b / L0), using the seabed
  slope β at the break point, the breaking height H_b and the deep-water wavelength L0 = g T² / 2π
  (Battjes 1974):
  - spilling: ξ < 0.4
  - plunging: 0.4 to 2
  - surging: above 2

  On the demo island, a calm or moderate sea plunges (ξ ≈ 0.7) and a storm sea spills (ξ ≈ 0.35), as
  it should. A `curl_strength` tunable (1 = physical) can push this one way or the other.
- **Life cycle by distance past the break point**, in units of H_b:
  1. Steepening (already there).
  2. Lip throw: the lip tip follows a ballistic path, launched forward at the crest's speed and
     falling under gravity. That gives a plunge distance of about 2 to 3 H_b without any tuning.
  3. Plunge and splash-up.
  4. Bore: the existing sawtooth profile with foam.
- **Cross-section as one folded sheet**, in Lagrangian form like the rest of the ocean. Going from
  seaward to shoreward along the rest coordinate s, the curve runs up the back of the wave, over the
  crest, out to the lip tip, then back under the lip (the tube ceiling and the face), and on to the
  trough in front. It moves forward, then back, then forward again: an S-shaped fold. The lip gets
  its thickness from the gap between the outer and inner paths. Before breaking the fold has zero
  size, so the profile is exactly today's shore wave.
- **Normals from the curve's tangent** (dX/ds, dY/ds), worked out analytically. Under the lip they
  point down, which is right for its underside, and the outer and inner sides light correctly.
- **Peeling for free.** Each point on a crest breaks when its own size and depth say so. Size varies
  along the crest (the swash draw) and so does depth, so breaking starts at one end and runs along.
  Low-frequency noise along the crest on the lip's reach keeps it from looking like a perfect cylinder.

Headless tests:
- The curve is continuous in s and in time, with no jump between life stages.
- The lip tip follows the ballistic path.
- The water the profile encloses stays about the same through the fold.
- Normals point down under the lip.
- ξ picks the right type for worked examples.
- The rays start on the waterline, T rises along each ray, and Kr is 1 on a straight beach.

### 3. Shared ocean shading (refactor first)

`ocean.gdshader` is about 500 lines. Move its surface shading (refraction, absorption, caustics, foam,
reflection, the screen-space march) into `ocean_surface.gdshaderinc` so that the ocean and the
ribbons shade the same way. No visual change. Do this before step 4, as its own commit.

### 4. The ribbons

- **The mesh** is a static grid in (alongshore, across), one instance per breaking crest near the
  camera, drawn as a MultiMesh. Per-instance data holds which crest it is (its wave number) and its
  alongshore window. The vertex shader looks up world positions in the wave rays and places the
  cross-section from `BreakerProfile`. The AABB is widened so the engine doesn't cull the instances.
- **Window:** the crest region, from about 1.5 H in front of the lip tip to 3 H behind the crest,
  across, and ±75 m (High) of coast around the camera, along. Beyond that distance, curls fade back
  into today's shore waves and foam, so the cost stays bounded.
- **Seam with the ocean:** the ocean discards pixels inside the window, using the same analytic test
  on travel time and wave number. The ribbon reaches slightly past the window edge with a short skirt
  that dips under the surface, and draws after the ocean (higher render priority). Both surfaces
  draw at full opacity and test depth, so overlap is harmless where they agree.
- **Quality tiers (`OceanQuality`):**
  - Ribbon reach and segments across: High 64, Ultra 128.
  - Low turns the ribbons off (today's waves).
  - The web build has no FFT ocean and no shore waves, so the ribbons are off there.

Rough cost on High: 4 crests × 300 × 64 ≈ 80k vertices. Pixel cost is about the ocean's on the same
pixels. Budget: 1 ms on High at 1080p on the reference GPU, measured on a desktop.

### 5. What makes it beautiful

- **Glow through the lip.** The profile knows how thick the lip is along the view and sun
  directions. Light through it uses the crest light-scattering term (`water_scatter`) with real
  thickness, which gives the green backlit lip. Under the lip, the inside of the tube and the face
  are lit by what passes through the lip, not by the screen copy.
- **White water:**
  - The lip tip turns white as it aerates, and the white grows towards the plunge.
  - At the plunge, a burst of foam spreads into the existing trailing foam band.
  - The face fills with foam once the lip has hit.
  - A spilling breaker gets a white roller on the upper face instead of a lip.
- **Spray:** droplets peel off the lip tip, and splash-up and mist rise where it plunges. This is a
  GPU particle emitter (`BreakerSpray`) that samples the wave rays for its start points, the same way
  the wind spray reads the FFT maps. Its particle count is set per tier.
- **Shadow under the lip.** The trough and the face under the lip go darker. Whether transparent
  ribbons can cast shadows in Godot 4.7 is tested in the prototype first. If they can't, a darkening
  term from the profile does the job.
- **Hooks for sound:** a `breaker_plunged(position, size)` signal on the ocean, so audio can be added
  later without touching the water.

### 6. Gameplay heights (CPU twin)

Under a lip the water has two heights. `Ocean.height_at` keeps returning the uncurled base profile, so
floating objects ride the face and the bore and are never trapped in the tube. A new query,
`Ocean.breaker_at(xz) -> {inside_tube, foam, plunging}`, gives gameplay and effects what they need:
swimmers knocked down, boats swamped, splash sounds.

## Steps, in order

1. **Prototype** in `prototypes/breakers/`: a straight beach with a single hand-driven ribbon. It
   checks how the fold reads, the vertices needed across, the seam and draw order, the lip glow,
   and ribbon shadows. A person looks at it on a desktop GPU before any production code.
2. Wave rays (`ShoreRays`) and Kr in the shore waves, with tests. The shore waves change slightly
   (energy on headlands and in bays).
3. `BreakerProfile` and breaker type, with tests (pure logic, no rendering).
4. Shared ocean shading include (refactor, no visual change).
5. Breaker ribbons, the ocean discard, quality tiers.
6. Lip glow, white water, spray, shadow, the plunge signal.
7. The CPU `breaker_at` query.
8. Decision 0011, the desktop checks in `water_realism.md`, and the feature map entry.

Each step is committed on its own and verified with the headless import, the tests, and the Windows
and Web exports. How it looks is checked by a person on a desktop GPU after steps 1, 5 and 6.

## Risks and open questions

- **Refraction through the lip.** The screen copy is taken before any water is drawn, so a ray
  through the lip can't see the face behind it. The plan shades the lip and tube from the water's own
  colour and light instead of the screen copy. If that reads flat, the fallback is a second pass: draw
  the ribbon interior first and copy the screen again. That costs extra and needs a test in Godot.
- **The seam** between the ribbon and the ocean is the most likely place to flicker or leave a line.
  The prototype answers this.
- **Rays that cross** at sharp headlands pinch the ribbon. The fix is clamping and smoothing, and
  turning curls off where rays converge too hard.
- **Steep, short beaches** (cliffs, harbour walls) give surging or reflecting waves, not curls. That
  is correct, but a harbour wall may want its own splash effect later.
- **Alternatives considered:**
  - Folding the existing ocean mesh is simpler, but too coarse beyond about 10 m and jagged along the
    crests.
  - Ray-marching the breaker in a volume is too expensive, and hard to light with the rest of the
    water.
  - Pre-animated breaker meshes would loop visibly and wouldn't follow the coast.

## References

- Fournier & Reeves 1986, *A simple model of ocean waves*: overturning crests from orbits that tilt
  with depth.
- Battjes 1974, *Surf similarity*: breaker types from the Iribarren number.
- Thürey et al. 2007, *Real-time breaking waves for shallow water simulations*: breaking fronts as
  parametric meshes riding a coarser surface.
- Longuet-Higgins & Cokelet 1976: the shape of overturning waves, to check the profile against.
