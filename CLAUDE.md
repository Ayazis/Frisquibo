# Frisquibo

A medieval, story-driven open-world action game in the spirit of *Mafia*, built in Godot 4 with GDScript.
The full architecture and engineering strategy is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Read it before making structural changes.

## Non-negotiables
- **Visible beauty and realism are top priorities.** Choose the better-looking solution unless profiling
  proves it's too expensive at the High tier. Never lower the High/Ultra look to fix performance; use
  optimisation, LOD and lower tiers instead. See section 7 of the architecture doc.
- **Desktop is leading.** Never drop, simplify or postpone a desktop feature because it won't work on the web.
  Web support is added afterwards through clearly marked feature checks (`OS.has_feature("web")`, renderer, quality tier)
  with a cheaper fallback or a no-op. Shared gameplay logic is never forked per platform.
- **GDScript, statically typed.** Every variable, parameter and return value has a type. C++ through
  GDExtension only where profiling proves GDScript too slow, decided case by case and recorded in `docs/decisions/`.
  `project.godot` turns untyped and unsafe code into errors; fix the types, don't suppress the warnings.
- **Every change must import cleanly and export for both Windows and Web** (CI checks this on each PR).
- **No magic numbers.** Scalable values (density, distances, counts) go in quality-tier resources in `data/quality/`;
  other tunables become named constants or `@export` properties.

## AI-first workflow
This game is built mostly by AI, without engine experts on the team (see `docs/decisions/0001-engine-choice.md`).
- Keep everything as text: `.tscn`, `.tres`, `.gdshader`, `.gd`. Never save authored content as binary `.scn` or `.res`.
- Prefer describing setup in scripts or resources over steps a human must click through in the editor.
- Verify your own work: run the headless import and tests. Don't report a change as done without having checked it.
- **Looking at images is expensive in tokens, so do it rarely.** Push the work as far as possible with cheap,
  text-based checks first: headless import, game logs, tests, and the visual check's text output
  (`tools/visual_check/run.sh <shot-list.tres>` prints PASS/FAIL and changed-pixel percentages without you
  opening anything). Only open render images:
  1. to investigate a bug or error that the text checks can't explain, or
  2. once, at the very end of a visual task, to verify the final result.
  Don't look at images after each step or iteration. When you do look, open only the `*.compare.png` of the
  shots that matter (each one already shows golden | render | diff in a single image).
- Only run the visual check's `update` mode for an intended change you've verified at the end, and commit the
  new golden images with it. Give new scenes and visual features their own shot list in `tests/visual/`.
- Record architecture decisions in `docs/decisions/` as numbered files.
- `docs/FEATURE_MAP.md` lists what we build per track and which libraries to evaluate. Follow its
  third-party addon rules (permissive licence, tested in `prototypes/` first, pinned in `addons/`, wrapped behind our own interfaces).

## Clean Code rules
- One responsibility per script or scene. If a script needs a section-header comment to separate its concerns, split it.
- Composition over inheritance: small component nodes (`Health`, `Hitbox`, `Interactable`, ...).
- Call down, signal up. No `get_parent()` chains and no `/root/...` paths outside `core/`.
- Data in `Resource` files (`.tres`), logic in code.
- Pure logic (missions, law, economy, save data) lives in `RefCounted` classes and gets GUT unit tests in `tests/unit/`.
- Layers: Presentation → Gameplay → World → Core. Each layer may only depend on the layers to its right;
  Gameplay never references UI.
- Keep autoloads to what's listed in the architecture doc; use the `EventBus` only for game-wide events.

## Conventions
- Files and folders: `snake_case`. Classes: `PascalCase` via `class_name`. Constants: `SCREAMING_SNAKE_CASE`.
- Signals are named in the past tense (`died`, `mission_completed`). Private members start with `_`.
- Organise by feature: a feature's scripts, scenes and data live together (see the folder layout in the architecture doc).
- `prototypes/` is for throwaway experiments; nothing there ships, and nothing outside it depends on it.
- Asset names: `<type>_<name>_<variant>` (`prop_barrel_01`, `bld_tavern_a`).

## Current state
`main.gd` / `main.tscn` are the original grass prototype (everything in one script). Splitting them into
`world/foliage`, `world/time_of_day`, `actors/player` and `core/settings` is the first item on the roadmap.
Don't extend `main.gd` with new features.
