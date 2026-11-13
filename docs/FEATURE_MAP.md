# Feature map: what Unreal ships, and how we get it in Godot

This is the starting list of what to build. For every capability Unreal Engine 5 gives you out of the box,
it shows what Godot 4.7 already has, which open-source libraries can cover part of it, and what we have to
build ourselves. Capabilities are grouped into **tracks**, so each person can own one track and go deep on it.

**Size:** S = days · M = weeks · L = 1–3 months · XL = research-level and open-ended.
**Library status:** *candidate* = found and looks right, but not yet tested against Godot 4.7 and our rules.

## Rules for third-party addons
- **Licence:** MIT, BSD, Apache or CC0 only, unless an ADR says otherwise.
- **Before adoption:** test it in `prototypes/` on our Godot version, check it's maintained, and record the
  decision in `docs/decisions/`.
- **Vendored and pinned:** addons live in `addons/` at a fixed version. Upgrades are deliberate commits.
- **AI-first fit:** prefer addons whose source we can read and whose configuration is text. Binary data that
  is binary by nature (heightmaps, textures, baked lightmaps) is fine.
- **Behind our own interfaces:** gameplay code talks to our wrapper, not to the addon directly, so an addon
  can be replaced later.

---

## Track 1: Lighting & atmosphere

| Unreal ships | Godot 4.7 built in | Libraries | We build | Size |
|---|---|---|---|---|
| **Lumen** dynamic GI and reflections | SDFGI, VoxelGI, LightmapGI, reflection probes, SSIL, SSR | — | A **GI strategy**: SDFGI tuned for outdoors with the time of day, baked LightmapGI and probes for interiors, and rules for which space uses what. Adopt hardware ray tracing for Ultra when Godot ships it (expected 4.8–4.9). | L |
| **MegaLights** (hundreds of shadowed lights) | Omni and spot lights with a shadow atlas; `AreaLight3D` (new in 4.7) | — | A **light budget manager**: prioritises which torches and candles cast shadows by distance and importance, with baked light for static ones. Essential for taverns and night streets. | M |
| **Sky, atmosphere and volumetric clouds** | Physical sky, volumetric fog | [Sky3D](https://github.com/TokisanGames/Sky3D) (MIT, day/night cycle, fog, clouds; *candidate*), [SunshineClouds2](https://github.com/Bonkahe/SunshineClouds2) (volumetric clouds; *candidate*) | The **time-of-day and weather director**: drives sun, sky, fog, exposure, wetness and wind together from one data asset per weather type. | M |
| **Auto-exposure and physical camera** | Camera attributes (physical), auto-exposure | — | Calibration of real-world light units per scene, as part of the lookdev scene. | S |
| **Post-processing** | AgX/ACES tone mapping, glow, depth of field, colour-correction LUTs, TAA/FSR 2 | — | **Motion blur** and **lens effects** as compositor effects. A **grading pipeline** with one LUT per region and time of day. | M |
| **HDR display output** | New in 4.7 (desktop) | — | Settings option and calibration screen. | S |

## Track 2: Geometry & surface detail

| Unreal ships | Godot 4.7 built in | Libraries | We build | Size |
|---|---|---|---|---|
| **Nanite** virtualised geometry | Automatic mesh LOD, visibility ranges, occlusion culling, MultiMesh instancing | — | No Nanite equivalent. Instead, **LOD discipline**: an asset import pipeline that checks LODs, impostors for distant objects, and merged far-distance meshes per city block. Real virtual geometry is XL research we should **not** start with. | L |
| **Material layering** (moss, dirt, wetness, wear) | Shader language, `StandardMaterial3D`, detail maps | — | A **master material library**: layered PBR shaders with world-space dirt, moss by slope and height, global wetness from the weather director, and vertex-paint blending. | L |
| **Displacement / tessellation** | Parallax occlusion mapping (heightmap in materials) | Terrain3D (real displacement teased for 1.1) | Use POM for cobblestones and walls. Revisit when Terrain3D displacement ships. | S |
| **Decals** | `Decal` node | — | A decal library (grime, blood, cracks, puddles) and a scatter tool for it. | S |
| **Mesh–terrain blending** (runtime virtual textures) | — | — | A shader that blends rocks and building bases into the terrain texture underneath. | M |
| **Content** (Megascans / Fab) | — | [Poly Haven](https://polyhaven.com) and [ambientCG](https://ambientcg.com) (CC0 scans, materials, HDRIs). Fab/Megascans: check licence terms for non-Unreal use. | Custom sculpting for medieval hero assets. | ongoing |

## Track 3: Terrain, vegetation & world building

| Unreal ships | Godot 4.7 built in | Libraries | We build | Size |
|---|---|---|---|---|
| **Landscape** | — | [Terrain3D](https://github.com/TokisanGames/Terrain3D) (MIT, clipmap terrain, sculpting, texture painting, foliage instancer with LODs; 1.0.x for Godot 4.4+; *strong candidate*) | Integration, terrain material layers, and a heightmap import pipeline. | M |
| **Foliage and PCG** (procedural placement) | MultiMesh | Terrain3D instancer; [ProtonScatter](https://github.com/HungryProton/scatter) (MIT, rule-based scattering; reported slow at large scale; *candidate*) | Generalise our **grass prototype** into a foliage system: wind, player interaction, LOD and density per quality tier. Add **rule-based scattering** (forest edges, undergrowth, rocks by slope). | L |
| **Splines and roads** | `Path3D`, `CSG` | [Godot Road Generator](https://github.com/TheDuckCow/godot-road-generator) (roads and intersections, Godot 4.4+; *candidate*) | Medieval roads, walls, fences and rivers along splines. Dirt roads need terrain blending and decals rather than modern road meshes. | M |
| **Water** | — | [GodotOceanWaves](https://github.com/2Retr0/GodotOceanWaves) (MIT, FFT; *candidate*), OceanPro and Swell (new, 4.7+; *candidate*) | Mostly **rivers, moats, lakes and puddles**: flow-map river shader, shoreline foam, and wetness interaction. The ocean libraries are relevant only for a harbour. | M |
| **World Partition** (open-world streaming) | Threaded resource loading, double-precision engine builds for large coordinates | None found that's maintained | **World streaming**: chunked regions, threaded loading/unloading, LOD proxies for unloaded chunks, and a `.pck` per region on the web. Core infrastructure. | L |
| **Procedural buildings** | — | — | A modular **building kit**: medieval houses assembled from parts by rules (data-driven), so a city can be dressed quickly and variation is cheap. | L |

## Track 4: Characters & animation

| Unreal ships | Godot 4.7 built in | Libraries | We build | Size |
|---|---|---|---|---|
| **MetaHuman** (realistic humans) | — | MPFB / MakeHuman (Blender, CC0 output; *candidate*) | **Character pipeline**: MPFB base → Blender customisation → Godot. Skin shader (subsurface scattering, which Godot has), eye and hair-card shaders. Many NPC variants from parts plus material variation. | XL |
| **Motion matching** | `AnimationTree`, state machines, blend spaces | [godot-motion-matching](https://github.com/GuilhermeGSousa/godot-motion-matching) (MIT GDExtension, 4.4+; early, rough edges reported; *candidate*) | Start with classic `AnimationTree` locomotion and evaluate motion matching once there's a motion-capture library. | L |
| **Control Rig / IK** | `SkeletonModifier3D`, built-in IK modifiers, `SpringBoneSimulator3D` (secondary motion) | — | Foot placement on uneven cobblestones, look-at, hand IK for weapons and reins. | M |
| **Animation content** | — | Mixamo (free; check terms), motion-capture packs | Medieval-specific animations: sword fighting, mounting, carrying. | ongoing |
| **Cloth and hair simulation** | `SoftBody3D` (limited) | — | Start with **bone-driven** capes and skirts (spring bones), not real cloth simulation. | M |
| **Facial animation** | Blend shapes | — | Lip-sync from dialogue audio, facial poses for cutscenes. | L |
| **Horses** | — | — | **Mount system**: quadruped locomotion, IK, rider sync. No library exists; one of the biggest custom jobs. | XL |

## Track 5: Gameplay infrastructure

| Unreal ships | Godot 4.7 built in | Libraries | We build | Size |
|---|---|---|---|---|
| **Behaviour trees and State Trees** | — | [LimboAI](https://github.com/limbonaut/limboai) (MIT, C++, behaviour trees and state machines, visual debugger, 1.8.x for 4.6+; *strong candidate*) | NPC behaviours: guards, merchants, witnesses, schedules. | M |
| **Mass** (crowds) | Navigation server with avoidance | — | **Crowd simulation** with AI LOD (full, simplified, statistical), plus traffic of carts and riders. | L |
| **Physics (Chaos)** | Jolt physics (built in) | — | Destruction (crates, fences, market stalls) through pre-fractured meshes. | M |
| **Dialogue** | — | Dialogue Manager, Dialogic 2 (*candidates*) | Integration with missions, factions and voice-over. | S |
| **Cameras** | `Camera3D` | Phantom Camera (*candidate*) | Third-person rig, mount camera, cutscene cameras. | M |
| **Audio** (MetaSounds, occlusion) | Audio buses, reverb, 3D audio | — | Ambience system per district and time of day, simple occlusion through walls. | M |
| **Testing** | — | GUT, gdUnit4 | — | S |

## Track 6: Tooling (makes every other track possible)

| Need | We build | Size |
|---|---|---|
| **Visual check tool** | **Done** (`tools/visual_check/`): renders fixed camera shots to PNG and compares them with a local, per-machine baseline made before a change. Still to add: a quality-tier option once tiers exist. | M |
| **Lookdev scene** | Calibrated neutral lighting setups for judging assets and materials. | S |
| **Asset import checks** | Automatic validation on import: naming, scale, LODs, texel density, material slots. | M |
| **Performance capture** | A fixed fly-through per region that logs frame time, draw calls and memory, so CI can catch performance regressions. | M |

---

## Suggested order
1. **Track 6: visual check tool and lookdev scene.** Every other track depends on being able to see results.
2. **Tracks 1 and 3 in parallel:** time of day and weather plus GI strategy, alongside Terrain3D and the
   foliage system (building on the grass prototype). Together these produce the first beautiful outdoor scene.
3. **Track 2: master material library**, then the building kit, for the first city block.
4. **Tracks 4 and 5:** characters, AI and crowds once there's a world to put them in.
