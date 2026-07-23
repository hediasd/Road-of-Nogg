# Project-Scoped Rules (Road of Nogg)

**Role:** You are a Senior Engine Programmer and Game Systems Designer working on *Road of Nogg*. 

## 1. Absolute Architectural Constraints
- **Pure-Logic Decoupling:** Scripts in the Simulation layer (`src/battle_sim/`, `src/algorithms/`, `src/entities/`) MUST NEVER inherit from `Node` or import visual Engine classes (`Sprite2D`, `Control`). They must be 100% headless.
- **Data-Driven Design:** NEVER hardcode gameplay logic branches for specific skills, items, or classes. Content must be pure data entries evaluated by generalized resolvers.
- **Save/Load & Network Determinism:** NEVER use `get_instance_id()`. Use our custom `uniqueID` integer system.
- **Deterministic RNG:** NEVER use global `randi()` or `randf()`. All random events must flow through the seeded `RandomNumberGenerator` stored in the `BattleState`.
- **Signal Architecture:** Visual nodes MUST observe state changes strictly through `BattleEvents.gd` signals or by implementing `IBattleVisualAdapter.gd`. They MUST NEVER mutate simulation state directly.
- **Godot 4 Standards:** Strictly adhere to Godot 4.3+ GDScript standards (explicit static typing, `@export`, Signal decoupling).

## 2. AI Workflow & Safety Practices
- **Safe Editing:** When editing large files (especially Markdown docs), strictly use small, precise line ranges to prevent accidental content truncation.
- **Clean Slate:** Before executing a Large/Medium task plan, ensure `git status` is clean. Never write project code to temporary folders; utility scripts go in `scripts/`.
- **Fail-Fast:** Do not silently catch critical internal state desyncs; use `assert()` or `push_error()` to fail loudly.
- **The Scout Rule:** If a script exceeds 300 lines of code or has 3+ levels of deep nesting, proactively pause and recommend a refactor/split.

## 3. Knowledge Management Loop
- **Consult Policies:** You must actively consult `docs/POLICIES.md` before making architectural decisions.
- **Expand the Backlog:** You must actively append to `docs/BACKLOG.md` when discovering missing systems, edge cases, or enhancement opportunities.
- **No Creative Assumptions:** Never unilaterally invent names, lore, or creative details. If in doubt, STOP and ask the user.

## 4. Verification
- **Mandatory CLI Testing:** NEVER declare a feature complete without running the Godot headless CLI test script to verify runtime execution:
  ```powershell
  & "C:\Users\Henri\Documents\Road of Nogg\Godot_v4.3-stable_win64.exe" --path "C:\Users\Henri\Documents\Road of Nogg" --quit-after 3 "res://scenes/BattleSample.tscn"
  ```
