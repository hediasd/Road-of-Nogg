# Road of Nogg — AI Collaboration & Coding Policies

An authoritative, single-source-of-truth document specifying all guardrails, restrictions, coding standards, testing protocols, and documentation rules for developing **Road of Nogg**.

---

## 1. Architectural Guardrails & Pure-Logic Restrictions

1. **Strict Pure-Logic Decoupling**:
   - Scripts in `src/battle_sim/`, `src/board/`, `src/entities/`, `src/entity_ai/`, and `src/factories/` **MUST NOT** inherit from `Node` or import Godot UI/Engine visual nodes (e.g. `Sprite2D`, `Control`, `Node3D`, `Camera3D`).
   - The simulation layer must remain 100% runnable and testable in headless memory.
2. **Signal-Driven Visual Communication**:
   - Visual nodes (`src/systems/`, `scenes/`) must observe battle state changes strictly through `BattleEvents.gd` signals or by implementing `IBattleVisualAdapter.gd`.
   - Visual components **MUST NEVER** mutate simulation state directly or alter combat calculation logic.
3. **State Mutation Discipline**:
   - Battle state mutations must flow through dedicated resolvers (`MovementResolver.gd`, `CombatResolver.gd`, `TurnManager.gd`).
   - Do not mutate private third-party state or global arrays directly; keep transient state localized.

---

## 2. GDScript Coding & Style Standards

1. **Language Version & Annotations**:
   - Target **Godot 4.4 GDScript**.
   - Use explicit static typing annotations where possible (e.g., `var hp: int = 100`, `func step_turn() -> void`).
2. **Naming Conventions**:
   - `PascalCase`: Classes (`Monster`, `BattleState`, `TurnManager`), Enums, and Node script names.
   - `camelCase`: Variables (`activeEffects`, `winningTeam`) and function names (`getOccupant()`, `stepTurn()`).
   - `UPPER_SNAKE_CASE`: Constants and Enum keys (`MAX_ROUNDS`, `TEAM_PLAYER`).
3. **Documentation & Preservation**:
   - Preserve all existing code comments, docstrings, and debug logs unless explicitly asked to modify or remove them.
   - Document new functions and classes with concise, professional docstrings.

---

## 3. Testing & CLI Verification Protocol

1. **Godot Executable Configuration**:
   - **Godot CLI Path:** `C:\Users\Henri\Documents\Road of Nogg\Godot_v4.3-stable_win64.exe` (or user specified `C:\Users\Henri\Downloads\Godot_v4.4-stable_win64.exe`).
2. **Mandatory CLI Verification**:
   - **Rule:** NEVER declare a feature complete, bug fixed, or refactoring successful without running the Godot CLI test execution command to verify clean runtime execution:
     ```powershell
     & "C:\Users\Henri\Documents\Road of Nogg\Godot_v4.3-stable_win64.exe" --path "C:\Users\Henri\Documents\Road of Nogg" --quit-after 3 "res://scenes/BattleSample.tscn"
     ```
   - Inspect terminal output and logs silently. Address any errors or stack trace failures before concluding the task.

---

## 4. Game Reference Documentation Rules

Rules governing reference docs in `docs/`:

1. **File Locations & Master Index**:
   - Keep aspect reference files directly in `docs/` (`docs/trpg_01_*.md` through `docs/trpg_12_*.md`).
   - Maintain [tactical_rpg_turn_systems.md](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/docs/tactical_rpg_turn_systems.md) as the master index containing links to all aspect files and the master comparison matrix.
2. **26-Game Full Coverage Rule**:
   - All 26 analyzed reference games (+ *Road of Nogg* baseline) **MUST** be explicitly accounted for in **every** aspect file.
   - If a concept/mechanic is absent in a game, it **MUST** be explicitly listed under a `### Not Applicable / Absent` subsection at the end of that topic section.
3. **Hierarchical Document Structure**:
   - Each aspect document must be structured with high-level conceptual topics (`## Topic Title`), approach subsections (`### Approach N.M: Approach Name`), explicit `* **Games Following This Approach:**` lists, and per-topic `### Not Applicable / Absent` subsections.

---

## 5. AI Collaboration & Workflow Policies

1. **Planning Mode Threshold — MANDATORY**:
   - Any change classified as **Medium** (touches 2+ files, new mechanic, or refactor) or **Large** (architectural change, new system, or cross-layer impact) **MUST** generate an `implementation_plan.md` artifact and wait for explicit user approval before executing any code.
   - Only **Small** changes (single-file tweak, typo fix, docstring update, minor formatting) may be executed immediately.
   - When in doubt, treat the change as Medium and plan first.
   - Size classification guide:
     - **Small**: 1 file, purely additive, no interface changes.
     - **Medium**: 2–5 files, new fields/methods, or logic changes inside 1 layer.
     - **Large**: Cross-layer (data model + resolver + signal + adapter), new system, or architectural refactor.

2. **Always Log Learnings**:
   - When discovering new engine quirks, patterns, or UI solutions, record them concisely by topic in [LEARNINGS.md](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/ai/LEARNINGS.md). Do not treat it as a daily diary.

3. **Maintain the Backlog**:
   - Whenever you have an idea, suggestion, or observe technical debt / missing features in the game, immediately document it in [BACKLOG.md](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/ai/BACKLOG.md). Be proactive about proposing improvements.

4. **AI Folder Maintenance**:
   - Keep `ai/ARCHITECTURE.md`, `ai/POLICIES.md`, `ai/PROJECT_STRUCTURE.md`, `ai/GAME_DESIGN.md`, `ai/LEARNINGS.md`, and `ai/BACKLOG.md` up to date when engine systems or rules evolve.

5. **Concise & Professional Communication**:
   - Keep responses concise, structured, and focused on key technical summaries and decisions requiring user input.


---

*Last updated: 2026-07-21*
