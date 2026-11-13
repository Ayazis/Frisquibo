# Frisquibo — Architecture & Engineering Strategy

Frisquibo is a story-driven, medieval open-world action game in the spirit of *Mafia*:
a living city and countryside, a linear narrative told through missions, crime and
factions, mounts and carts instead of cars, and a strong focus on atmosphere.

## 1. Platform & technology decisions

| Decision | Choice | Consequence |
|---|---|---|
| Engine | Godot 4.x | — |
| Language | **GDScript** (statically typed) | Keeps the web export. C# is not an option. |
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

1. **Static typing everywhere.** Enable `untyped_declaration` and `unsafe_*` warnings as errors.
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
  Buildings use HLOD (merged far-distance meshes) for the city skyline.
- Occlusion culling is used in dense city areas.

## 6. Folder layout (organised by feature)

```
res://
  core/              autoloads, base classes, utilities
  systems/           missions/ combat/ law/ factions/ economy/ inventory/ dialogue/
  world/             streaming/ terrain/ foliage/ weather/ time_of_day/ crowds/
  actors/            player/ npcs/ mounts/ components/
  ui/                hud/ menus/ widgets/
  data/              quality/ items/ weapons/ factions/ missions/
  levels/            regions and test scenes
  assets/            models/ textures/ materials/ audio/ fonts/ (raw imports)
  tests/             unit/ (GUT)
  prototypes/        throwaway experiments; nothing here ships
  docs/
```

Rule: everything a feature needs (script, scene, data) lives in that feature's folder.
`assets/` holds only shared raw art.

## 7. Art pipeline
- Blender → glTF 2.0. Units are metres, +Y is up, and the scale is applied before export.
- PBR materials (ORM-packed textures). Texel density target: 512 px/m for props and 256 px/m for buildings.
- Every mesh gets LODs (generated automatically by Godot, with manual LODs for heroes and key buildings).
- Asset naming: `<type>_<name>_<variant>` (`prop_barrel_01`, `bld_tavern_a`).

## 8. Performance budgets (set early, measured regularly)
Desktop budgets are the ones that drive design decisions. Web budgets only decide how
far the web build is scaled down.

| | Web (best effort) | Desktop (High, leading) |
|---|---|---|
| Frame time | 16.6 ms (60 fps) | 16.6 ms |
| Draw calls | < 1 000 | < 3 000 |
| Active full-AI NPCs | 20 | 60 |
| Texture memory | 512 MB | 2 GB |

## 9. Testing & CI
- **GUT** unit tests for pure logic (missions, law, economy, save data).
- Scene smoke tests: each region loads without errors.
- CI (GitHub Actions) runs the tests and the web export on every PR. Preview deployments already exist.

## 10. Roadmap for the codebase
1. Refactor the grass prototype into `world/foliage`, `world/time_of_day`, `actors/player`
   and `core/settings` as the reference implementation of these rules.
2. Core autoloads + quality tiers.
3. Player controller + camera rig + one mount.
4. Mission runner with 2–3 objective types + a vertical-slice mission.
5. First city district with streaming.
