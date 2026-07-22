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

Rules governing reference docs in `gamerefs/`:

1. **File Locations & Master Index**:
   - Keep aspect reference files directly in `gamerefs/` (`gamerefs/trpg_01_*.md` through `gamerefs/trpg_12_*.md`).
   - Maintain [tactical_rpg_turn_systems.md](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/gamerefs/tactical_rpg_turn_systems.md) as the master index containing links to all aspect files and the master comparison matrix.
2. **26-Game Full Coverage Rule**:
   - All 26 analyzed reference games (+ *Road of Nogg* baseline) **MUST** be explicitly accounted for in **every** aspect file.
   - If a concept/mechanic is absent in a game, it **MUST** be explicitly listed under a `### Not Applicable / Absent` subsection at the end of that topic section.
3. **Hierarchical Document Structure**:
   - Each aspect document must be structured with high-level conceptual topics (`## Topic Title`), approach subsections (`### Approach N.M: Approach Name`), explicit `* **Games Following This Approach:**` lists, and per-topic `### Not Applicable / Absent` subsections.
4. **Citation Validation Rule**:
   - Whenever we state that a certain game uses a specific algorithm, mathematical model, or similar mechanical architecture, the assertion **MUST** provide external HTTP links to valid references (interviews, wikis, decompilations) that prove this point.

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
2. **Git Push Discipline**:
   - When preparing to implement big changes (classified as Medium or Large), you must proactively suggest the user pushes the current stable state to Git first before executing the implementation plan.

3. **Always Log Learnings**:
   - When discovering new engine quirks, patterns, or UI solutions, record them concisely by topic in [LEARNINGS.md](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/ai/LEARNINGS.md). Do not treat it as a daily diary.

4. **Maintain the Backlog**:
   - Whenever you have an idea, suggestion, or observe technical debt / missing features in the game, immediately document it in [BACKLOG.md](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/ai/BACKLOG.md). Be proactive about proposing improvements.

5. **AI Folder Maintenance**:
   - Keep `ai/ARCHITECTURE.md`, `ai/POLICIES.md`, `ai/PROJECT_STRUCTURE.md`, `ai/GAME_DESIGN.md`, `ai/LEARNINGS.md`, and `ai/BACKLOG.md` up to date when engine systems or rules evolve.

6. **Document Specificity (Architecture vs Game Design vs Learnings)**:
   - For **architectural changes** (refactoring systems, changing data flow, introducing new core layers), you must proactively consult and update `ai/ARCHITECTURE.md`.
   - For **creative changes** (inventing new spells, naming monsters, balancing stats, new mechanics), you must proactively consult and update `ai/GAME_DESIGN.md`.
   - For **technical discoveries** (new engine quirks, GDScript patterns, structural tips, or tricks learned while coding and running), you must proactively consult and update `ai/LEARNINGS.md`.

7. **Strict Data-Driven Content Rule**:
   - All new game content (spells, monster base stats, items, status effects) **MUST** be created as pure data entries (e.g., in `SpellReferences.gd` or external data files) rather than hardcoded `if/else` logic branches inside the engine resolvers. Build generalized systems that process data.

8. **The "Scout Rule" (Progressive Refactoring)**:
   - If you edit a script and notice it exceeds 300 lines of code, or contains deeply nested logic (3+ levels deep), you must proactively pause and recommend a refactor/split of that file to prevent spaghetti code buildup.

9. **Visual Mockup Rule (Premium Aesthetics)**:
   - Before writing Godot `Control` node hierarchies for new complex UI menus (like a Shop or Inventory), you must first use the `generate_image` tool to create a premium, modern visual mockup and obtain user approval on the aesthetic direction.

10. **Signal Hygiene & Memory Leaks**:
   - Any time Godot signals are connected dynamically via code, they must either use `CONNECT_ONE_SHOT`, or you must ensure there is a guaranteed path for them to disconnect (e.g., `tree_exiting`). This is critical to prevent memory leaks as TRPG entities spawn and despawn.

11. **Immutable Base Data Rule**:
   - Any data dictionary fetched from our factory references (like `SpellReferences.gd`) must be treated as strictly read-only. We must never mutate base stats directly in memory; transient buffs or debuffs must be layered on top via the `BattleState`.

12. **Save/Load Determinism (No Instance IDs)**:
   - The simulation layer must never use Godot's `get_instance_id()` or memory addresses as keys for tracking combat entities. We must strictly use our own deterministic `uniqueID` integer system.

13. **Fail-Fast Error Handling**:
   - Instead of silently masking errors (e.g., `if target == null: return`), the engine must use Godot's `assert()` or `push_error()` to fail loudly if a critical internal state desync occurs.

14. **Concise & Professional Communication**:
   - Keep responses concise, structured, and focused on key technical summaries and decisions requiring user input.

15. **Deterministic Randomness (Seeded RNG)**:
   - The simulation layer must **NEVER** use global RNG functions like `randi()` or `randf()`. All random events (damage variance, dodge chance, critical hits) must use a controlled `RandomNumberGenerator` instance stored in the `BattleState` that is initialized with a shared seed.

16. **The "Clean Slate" Rule**:
   - Before writing any code for a new Medium or Large feature, you must verify that `git status` is clean. If there are uncommitted changes from a previous session, you must prompt the user to commit or stash them first.

17. **Always Ask — Never Decide Creatively Alone (CRITICAL)**:
   - You must **NEVER** make creative, lore, or naming decisions unilaterally. This includes: monster names, spell names, place names, character backstory, lore fragments, game world details, faction names, and any narrative flavor text.
   - If implementing a system requires a creative decision that is not explicitly specified by the user, you **MUST STOP** and ask before proceeding. Do not fill in placeholders, invent names, or infer intent for creative content.
   - This applies even to seemingly minor details (e.g., the name of a debuff, the flavor text of a spell, or whether a passive ability has a dramatic visual name). Always get explicit confirmation.
   - For **technical decisions** (architecture, patterns, algorithms), you may propose and proceed after presenting reasoning — but for **creative decisions**, you must always wait for user approval.


---

*Last updated: 2026-07-21*
