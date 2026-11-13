# Frisquibo — Architecture & Engineering Strategy

Frisquibo is a story-driven, medieval open-world action game in the spirit of *Mafia*:
a living city and countryside, a linear narrative told through missions, crime and
factions, mounts and carts instead of cars, and a strong focus on atmosphere.

**Pillar: visible beauty and realism.** Graphical quality is one of the game's top priorities, and
a feature isn't done until it looks right. Section 7 says what that means in practice.

## 1. Platform & technology decisions

| Decision | Choice | Consequence |
|---|---|---|
| Engine | Godot 4.x | — |
| Language | **GDScript** (statically typed) | Keeps the web export. C# is not an option. C++ via GDExtension only where profiling demands it. |
| Workflow | **AI-first** (see section 12 and [ADR 0001](decisions/0001-engine-choice.md)) | Everything is text, scriptable and verifiable from the command line. |
| Targets | **Desktop is leading.** Web is a secondary, reduced build. | The web build never blocks a feature. |
| Renderers | Forward+ (desktop), `gl_compatibility` (web) | Desktop uses everything Forward+ offers (SDFGI, volumetric fog, compute shaders, etc.). |

### Desktop first, web as a scaled-down build: the rules
- **Desktop is never held back by the web.** "It wouldn't work on the web" is not a valid
  reason to drop, simplify or postpone a desktop feature.
- **The web build is allowed to be a lesser experience.** Web-only work means deciding
  what to scale down, swap for something simpler or turn off. It never sets the bar for desktop.
- **How web support is isolated:** desktop-only features sit behind feature checks
  (`OS.has_feature("web")`, the renderer, the quality tier) at clearly marked spots, with a
  cheaper fallback or no-op on the web. Gameplay logic itself is shared.
- **If a feature is essential to gameplay and can't run on the web**, the web build may
  leave out that content, or the web build may be dropped entirely. That decision is made
  on the web side, not by limiting desktop.
- **Quality tiers** (`data/quality/*.tres`: Low / Medium / High / Ultra / Web) hold every
  scalable number: foliage density, shadow size, draw distance, LOD bias, particle counts.
  Code never hardcodes these values. Desktop defaults to High, and the web uses its own `Web` tier.
- **Web download size:** web builds stream content in packs (`.pck` per region). Desktop
  assets are never downscaled for this; the web export pipeline handles compression and reduction.

## 2. Clean Code rules

1. **Static typing everywhere.** `project.godot` treats the `untyped_declaration` and `unsafe_*`
   warnings as errors, so untyped code doesn't compile.
2. **One responsibility per script/scene.** If a script needs a section-header comment
   to separate its concerns, split it.
3. **Composition over inheritance.** Behaviour comes from small component nodes
   (`Health`, `Hitbox`, `Interactable`, `Wanted`, `Inventory`), not deep class trees.
4. **Call down, signal up.** Parents call children, and children emit signals. No
   `get_parent()` chains and no absolute `/root/...` paths outside of `core/`.
5. **Data in Resources, logic in code.** Items, weapons, NPC archetypes, factions,
   missions and dialogue are `.tres`/custom `Resource` classes.
6. **No magic numbers.** Use named constants, exported properties, or quality-tier values.
7. **Names explain *what*, comments explain *why*.**
8. **Small, testable units.** Pure logic (economy, wanted level, mission state) lives
   in `RefCounted` classes with no scene dependencies and is covered by unit tests (GUT).
9. **Boy-scout rule.** Leave every file cleaner than you found it, and refactor before you extend.

### Naming conventions
- Files & folders: `snake_case` (`horse_controller.gd`, `market_stall.tscn`)
- Classes: `PascalCase` via `class_name`
- Signals: past tense (`died`, `mission_completed`, `wanted_level_changed`)
- Private members: leading underscore (`_velocity`)
- Constants: `SCREAMING_SNAKE_CASE`

## 3. Layered architecture

```
┌──────────────────────────────────────────────────────────────┐
│ Presentation   UI · HUD · Camera · VFX · Post · Audio mixing │
├──────────────────────────────────────────────────────────────┤
│ Gameplay       Missions · Combat · Wanted/Law · Factions ·   │
│                Economy · Inventory · Dialogue · Mounts · AI  │
├──────────────────────────────────────────────────────────────┤
│ World          Streaming · Terrain · Foliage · Weather ·     │
│                Time of day · Crowds/Traffic · Navigation     │
├──────────────────────────────────────────────────────────────┤
│ Core           EventBus · GameState · SaveSystem · Settings ·│
│                SceneLoader · Log                             │
└──────────────────────────────────────────────────────────────┘
          Content (data only): Resources, scenes, assets
```

**Dependency rule:** a layer may only depend on layers *below* it. Gameplay never touches
UI. The UI observes gameplay through signals and the EventBus.

### Core (autoloads: keep this list short)
| Autoload | Responsibility |
|---|---|
| `EventBus` | Global, game-wide signals only (`mission_completed`, `day_started`, `player_died`). Local communication uses plain signals. |
| `GameState` | Current chapter, flags, player profile. Exists so it can be serialised. |
| `SaveSystem` | Collects `Saveable` nodes and writes/reads versioned save data. |
| `Settings` | Quality tier, input bindings, audio, accessibility. |
| `SceneLoader` | Threaded loading, loading screens, region pack mounting. |

## 4. Systems designed around the Mafia-like genre

### Missions (the backbone)
A Mafia-like game is a **linear story inside an open world**, so missions are the main system.
- `MissionData` (Resource): ordered list of `ObjectiveData` resources plus triggers, rewards
  and fail conditions.
- `MissionRunner`: a state machine that runs one mission at a time and emits progress signals.
- Objectives are small, reusable types: `GoTo`, `Escort`, `Eliminate`, `Collect`,
  `Talk`, `Survive`, `Chase`, `Stealth`. Each one is a script on its own.
- Cutscenes and dialogue are driven by data (AnimationPlayer + `DialogueData`), never by
  hardcoding them in mission scripts.

### Law & notoriety ("wanted" system)
- A `Witness` component on NPCs reports crimes. `LawSystem` turns reports into a
  notoriety level per district, and city guards respond based on that level.
- The rules are pure logic (`RefCounted`) so they can be unit tested.

### Factions & economy
- `FactionData` resources (guilds, crime families, the crown, the church) with
  relationship values. Economy and protection rackets read from these.

### Mounts & carts (the "vehicles")
- One shared `Mount` abstraction (input → locomotion) with horse and cart implementations.
  The player and AI drivers use the same interface, so traffic NPCs reuse it.

### Living city
- **Crowds and traffic** are simulated cheaply, with level-of-detail for AI: full AI near
  the player, simplified AI at mid range, statistical simulation off-screen.
- NPC schedules follow the time of day (market by day, taverns at night).

### Combat
- Melee-first (swords, clubs) with ranged weapons (crossbows, bows). `WeaponData` resources,
  plus `Hitbox`/`Hurtbox` components and a cover system for ranged fights.

## 5. World structure & streaming
- The world is divided into **regions** (city districts, countryside), and each region is split into **chunks**.
- Chunks load and unload around the player with threaded loading. On the web, each region is its own
  `.pck` file that is downloaded when needed.
- Foliage uses MultiMesh with visibility ranges (generalised from the grass prototype).
- The city skyline uses merged low-detail meshes per block, swapped in for the detailed
  buildings at a distance via Godot's visibility ranges (Godot has no built-in HLOD system).
- Occlusion culling is used in dense city areas.

## 6. Folder layout (organised by feature)

```
res://
  addons/            third-party plugins (GUT, Terrain3D, ...)
  core/              autoloads, base classes, utilities
  systems/           missions/ combat/ law/ factions/ economy/ inventory/ dialogue/
  world/             streaming/ terrain/ foliage/ weather/ time_of_day/ crowds/
  actors/            player/ npcs/ mounts/ components/
  ui/                hud/ menus/ widgets/
  data/              quality/ items/ weapons/ factions/ missions/
  levels/            regions and test scenes
  assets/            models/ textures/ materials/ audio/ fonts/ (raw imports)
  tests/             unit/ (GUT), visual/ (shot lists; renders stay local)
  tools/             development tools (visual_check/)
  prototypes/        throwaway experiments; nothing here ships
  docs/
```

Rule: everything a feature needs (script, scene, data) lives in that feature's folder.
`assets/` holds only shared raw art.

## 7. Visual quality & art pipeline

### Principles
- **Realism is the target, grounded in reference.** Every environment, material and lighting setup
  starts from real-world reference (photos of medieval towns, castles, forests and weather; real
  material samples). "Looks plausible" is not the bar; "matches the reference" is.
- **Visual quality is a deciding factor, not a nice-to-have.** When a choice trades looks against
  convenience, looks win unless profiling proves the cost is unacceptable at the High tier.
- **Never lower the High/Ultra bar to hit performance.** Performance is solved through optimisation,
  LOD, streaming and the lower quality tiers, not by making the best version look worse.
- **Lighting is the biggest lever.** Physically based lighting with real-world units (lux, EV),
  a physical camera with auto-exposure, and consistent colour management.

### Rendering (desktop, Forward+)
- **Global illumination:** dynamic GI for the open world with the time of day, plus baked
  LightmapGI and reflection probes for interiors where quality matters most.
- **Atmosphere:** physically based sky, volumetric fog, and god rays through windows and forest canopies.
- **Screen-space effects:** SSAO/SSIL, screen-space reflections, contact shadows.
- **Shadows:** high-resolution cascaded sun shadows, soft shadows, and per-light shadows for torches and candles.
- **Anti-aliasing and upscaling:** temporal AA (TAA or FSR 2) as the default, so foliage and fine detail don't shimmer.
- **Post-processing:** filmic tone mapping (AgX/ACES), colour grading through LUTs, and subtle
  depth of field, motion blur, bloom and lens effects (each can be turned off in settings).
- **Custom rendering where Godot falls short:** compositor effects and custom shaders are expected,
  not exceptions. Wet surfaces, puddles, snow, mud, wind and interaction are shader-driven systems.

### Content quality
- **Materials:** fully PBR (albedo, normal, ORM, height where useful), calibrated against measured
  albedo ranges. Detail maps and layered materials (moss, dirt, wetness, wear) instead of unique
  textures everywhere.
- **Texel density:** 1024 px/m for props and characters (hero assets 2048 px/m), 512 px/m for buildings and terrain.
- **Geometry:** high-poly assets with automatic LODs (manual LODs for heroes and key buildings).
  Silhouettes must hold up close: no visibly faceted rounded shapes.
- **Characters:** realistic proportions, skin and hair shaders, facial animation for cutscenes.
- **Sources:** photogrammetry/scanned assets where the licence allows Godot use, plus custom sculpting.
  Every bought or scanned asset is checked for its licence before it goes into the repo.

### Pipeline
- Blender → glTF 2.0. Units are metres, +Y is up, and the scale is applied before export.
- Asset naming: `<type>_<name>_<variant>` (`prop_barrel_01`, `bld_tavern_a`).
- **Lookdev scene** (`levels/lookdev/`): a neutral, calibrated lighting setup (several times of day,
  interior and exterior) where every new asset and material is checked before use.

### What we build to get there
`docs/FEATURE_MAP.md` maps each Unreal capability to Godot's built-in features, libraries to evaluate,
and what we build ourselves, grouped into tracks that one person can own.

### Guarding the quality
- **Before/after shots:** a fixed set of camera shots per region (`tests/visual/`). Before a change,
  each developer renders a local baseline on their own machine; afterwards the tool shows exactly what
  changed, so quality can't erode unnoticed. Renders differ per GPU, so they're never committed.
- **Art direction document** (`docs/ART_DIRECTION.md`, to be written): palette, mood per region and time
  of day, reference boards.

## 8. Performance budgets (set early, measured regularly)
Desktop budgets are the ones that drive design decisions. Web budgets only decide how
far the web build is scaled down.

Desktop budgets assume a **recommended-spec GPU in the class of an RTX 4070 at 1440p**. This is a
proposal; the hardware target is still to be confirmed. Ultra may exceed the frame budget and rely
on upscaling.

| | Web (best effort) | Desktop (High, leading) |
|---|---|---|
| Frame time | 16.6 ms (60 fps) | 16.6 ms at 1440p (upscaling allowed) |
| Draw calls | < 1 000 | < 5 000 |
| Active full-AI NPCs | 20 | 60 |
| GPU memory | 512 MB | 8 GB |

## 9. Testing & CI
**In place today:** on every push and PR, CI imports the project (failing on any script or
resource error, including typing errors) and exports both the Windows and Web builds. The Windows
build is uploaded as an artifact, and PRs get a web preview deployment.

**Planned:**
- **GUT** (installed in `addons/`) unit tests for pure logic (missions, law, economy, save data), run in CI.
- Scene smoke tests: each region loads without errors.

## 10. Roadmap for the codebase
1. Refactor the grass prototype into `world/foliage`, `world/time_of_day`, `actors/player`
   and `core/settings` as the reference implementation of these rules.
2. ~~Visual check tool~~ Done: `tools/visual_check/` (section 12).
3. Core autoloads + quality tiers.
4. Player controller + camera rig + one mount.
5. Mission runner with 2–3 objective types + a vertical-slice mission.
6. First city district with streaming.

## 11. Open topics (decide before the related systems are built)
- **Localisation:** all player-facing text goes through translation keys (`tr()`) from day one.
- **Input:** only through Godot input actions (never raw keycodes in gameplay); controller support is a goal.
- **Accessibility:** subtitles, remappable controls, colour-blind-safe UI, camera-shake toggle.
- **Save versioning:** every save carries a format version, with a migration step per version bump.
- **Audio architecture:** bus layout (music, ambience, SFX, dialogue), reverb zones for interiors.

## 12. AI-first development
The game is built mostly by AI, without engine experts on the team (see
[ADR 0001](decisions/0001-engine-choice.md)). Every rule here exists so that an AI can build, change and check
everything on its own, and so a human can follow what it did.

- **Everything is text and in git.** Scenes (`.tscn`), resources (`.tres`), shaders, settings and scripts.
  Never use binary scene or resource formats (`.scn`, `.res`) for anything we author.
- **Prefer code and data over editor clicks.** When something can be set up by hand in the editor or
  described in a script or resource, describe it, so it can be reviewed, diffed and regenerated.
  Hand-placed level layout is fine, as long as it's saved as text.
- **Small, single-purpose files.** An AI works best on files it can read in full. This is the Clean
  Code rule from section 2, with an extra reason.
- **The AI must be able to see the result.** A visual check tool renders fixed camera shots (per scene
  and time of day) to PNG from the command line, so the AI can look at its own changes and compare them
  with a baseline rendered before the change (section 7, `tools/visual_check/`). Looking at images is expensive in
  tokens, so agents work from the tool's text output (PASS/FAIL, changed-pixel percentages) and open images
  only to investigate unexplained bugs or once to verify the final result.
- **The AI must be able to verify behaviour.** Headless import, headless runs and GUT tests all run from
  the command line, and CI runs them too. A change isn't done until the AI has run the checks itself.
- **Document decisions as they're made.** Architecture decisions go in `docs/decisions/` (one numbered
  file each), so future AI sessions know *why* things are the way they are and don't undo them.
