# ADR 0001: Engine choice

- **Status:** Accepted: **Godot 4.7** (see "Decision" at the end)
- **Date:** 2026-11-13

## Context
Frisquibo is a Mafia-like, story-driven medieval open world. Visible beauty and realism are top
priorities (see the architecture doc, section 7). Desktop is the leading platform, and a web build is
optional. The codebase is still a single grass prototype, so switching engines now costs almost nothing.
Development is done by a small team working heavily with Claude Code.

## Options

### Godot 4.7 (current)
- **Rendering today:** Forward+ with SDFGI/VoxelGI/LightmapGI, volumetric fog, SSR/SSAO/SSIL, TAA/FSR 2.
  4.7 (June 2026) added HDR display output and `AreaLight3D`. There's no hardware ray tracing yet;
  it's expected in 4.8–4.9 at the earliest, and NVIDIA maintains a separate Godot RTX fork.
- **Geometry and world scale:** no virtualised geometry (nothing like Nanite). Large open worlds
  need our own streaming, plus plugins such as Terrain3D.
- **Realistic characters:** no built-in solution; skin, hair and facial animation are custom work.
- **Strengths:** free and MIT-licensed with no royalties, small and fast editor, web export, and
  scenes and scripts stored as text. That last point makes it excellent for git diffs, code review
  and working with Claude.
- **Realism ceiling:** high with strong art direction and custom rendering work, but reaching AAA
  realism means building yourself what other engines ship with.

### Unreal Engine 5.8 (UE6 announced)
- **Rendering today:** Lumen dynamic GI (plus a lighter mode in 5.8), Nanite virtualised geometry,
  MegaLights for many dynamic shadowed lights (torches, candles), hardware ray tracing, a physically
  based sky and atmosphere, and volumetric clouds and fog. This is the industry reference for realism.
- **Open world:** World Partition streaming, a procedural content framework for vegetation and set
  dressing, and Mesh Terrain (new in 5.8).
- **Characters:** MetaHuman for realistic humans, with mature animation tooling (Control Rig, Motion Matching).
- **Content:** the biggest library of scanned assets (Fab/Megascans). Check the licensing terms per asset.
- **Genre fit:** *Mafia: The Old Country* (2025), the closest reference game, was built on UE5.
- **Costs and risks:**
  - 5% royalty on lifetime gross revenue above $1M; sales through the Epic Games Store are royalty-free.
  - C++ and Blueprints instead of GDScript. Blueprints, levels and assets are binary `.uasset`
    files, which are harder to diff, review and edit with AI tools. UE 5.8 does add an MCP server for AI tooling.
  - There's no web build.
  - A heavy editor and long build times. GitHub's hosted CI runners can't realistically build it,
    so a self-hosted build machine is needed, and Git LFS (or Perforce) for assets.
  - 5.8 is the last major UE5 release. UE6 early access is expected around 2027, which means a
    migration during development.

### Unity 6
- Unity has announced no new features for HDRP, its high-end renderer; future work goes into URP.
  For a realism-first game, that makes Unity the weakest choice of the three right now. **Not recommended.**

### Others (CryEngine, O3DE, Stride, a custom engine)
These have smaller ecosystems and communities, or need an engine team. Not realistic for this project.

## Comparison

| Criterion (weighted for Frisquibo) | Godot 4.7 | Unreal 5.8 |
|---|---|---|
| Realism out of the box (highest weight) | ●●○○○ | ●●●●● |
| Open-world tooling | ●●○○○ | ●●●●● |
| Realistic characters | ●○○○○ | ●●●●● |
| Asset ecosystem | ●●○○○ | ●●●●● |
| Iteration speed and editor weight | ●●●●● | ●●○○○ |
| Text-based files / AI-assisted workflow | ●●●●● | ●●○○○ |
| Cost and licence | ●●●●● | ●●●○○ |
| Web build | ●●●●○ | ○○○○○ |
| Engine stability during development | ●●●○○ (frequent breaking releases) | ●●●○○ (UE6 migration) |

## Recommendation
**Unreal Engine 5.8, planning for UE6.** Realism is the top priority, and Unreal covers the hardest parts
(global illumination, geometry detail, open-world streaming, realistic humans, scanned content) out of the box.
In Godot, each of those would be a project of its own. The trade-offs (no web build, royalty, binary
assets, heavier tooling) are acceptable given that desktop leads and the web build was already optional.

**Choose Godot instead if** the team values open source, no royalties, a lightweight text-based workflow and
the web build more than reaching AAA realism, and accepts building the missing rendering and world features.

## Decision
**Godot 4.7.** The recommendation above weighted realism out of the box highest. It left out one deciding
constraint: **development will be done very heavily by AI, without engine expertise on the team.**

That changes the weighing:
- **Unreal's realism is reached through the editor.** Lighting, materials, levels, Blueprints, MetaHumans
  and World Partition are all set up in a GUI and stored in binary `.uasset`/`.umap` files. An AI can't
  read, diff or reliably edit those. That work would need exactly the Unreal expertise the team doesn't have.
- **In Godot, everything an AI needs to touch is text:** scripts, scenes (`.tscn`), resources (`.tres`),
  shaders and project settings. The AI can build, change, review and verify the whole game, and git
  shows every change.
- **The engine is small enough to understand.** Its source and documentation fit an AI's working knowledge,
  and problems can be solved by reading the engine itself.

## Consequences
- **Realism is our own engineering work.** We close the gap with Unreal through custom shaders, compositor
  effects, procedural generation and strong lighting design, all written as code. If GDScript becomes too
  slow for heavy rendering or simulation, C++ through GDExtension is the planned escape hatch (decided per
  case, not by default).
- **The AI needs to see what it builds.** An automated visual feedback loop (rendered screenshots from fixed
  camera shots, compared against golden images) is core tooling, not a nice-to-have. See the architecture
  doc, section 12.
- **Watch for hardware ray tracing** in Godot 4.8–4.9, and adopt it for the Ultra tier when it ships.
- **Revisit this decision** only if a concrete visual target proves impossible in Godot after real effort.
