# Road of Nogg — AI Collaboration & Coding Policies

An authoritative, single-source-of-truth document specifying all guardrails, restrictions, coding standards, testing protocols, and documentation rules for developing **Road of Nogg**.

---

## 1. CRITICAL DIRECTIVES (Zero Tolerance)

These rules are absolute and must never be broken under any circumstances.

1. **Always Ask — Never Decide Creatively Alone & Ask When in Doubt**:
   - You must **NEVER** make creative, lore, or naming decisions unilaterally. This includes: monster names, spell names, place names, character backstory, lore fragments, game world details, faction names, and any narrative flavor text.
   - If implementing a system requires a creative decision that is not explicitly specified by the user, you **MUST STOP** and ask before proceeding. Do not fill in placeholders or invent names.
   - **General Doubt Rule:** If there is ever any ambiguity or doubt regarding an action you are about to take (whether technical, architectural, or creative), you must explicitly ask the user for clarification before proceeding.
2. **Strict Pure-Logic Decoupling**:
   - Scripts in `src/battle_sim/`, `src/board/`, `src/entities/`, `src/entity_ai/`, and `src/factories/` **MUST NOT** inherit from `Node` or import Godot UI/Engine visual nodes (e.g. `Sprite2D`, `Control`, `Node3D`, `Camera3D`).
   - The simulation layer must remain 100% runnable and testable in headless memory.
3. **Save/Load Determinism (No Instance IDs)**:
   - The simulation layer must never use Godot's `get_instance_id()` or memory addresses as keys for tracking combat entities. We must strictly use our own deterministic `uniqueID` integer system.
4. **Deterministic Randomness (Seeded RNG)**:
   - The simulation layer must **NEVER** use global RNG functions like `randi()` or `randf()`. All random events (damage variance, dodge chance, critical hits) must use a controlled `RandomNumberGenerator` instance stored in the `BattleState` initialized with a shared seed.
5. **The "Clean Slate" Rule**:
   - Before writing any code for a new Medium or Large feature, you must verify that `git status` is clean. If there are uncommitted changes from a previous session, you must prompt the user to commit or stash them first.

---

## 2. AI WORKFLOW & COMMUNICATION

1. **Planning Mode Threshold — MANDATORY**:
   - Any change classified as **Medium** (touches 2+ files, new mechanic, or refactor) or **Large** (architectural change, new system, or cross-layer impact) **MUST** generate an `implementation_plan.md` artifact and wait for explicit user approval before executing any code.
   - Only **Small** changes (single-file tweak, typo fix, minor formatting) may be executed immediately.
2. **Git Push Discipline**:
   - Proactively suggest the user pushes the current stable state to Git before executing an implementation plan for Medium/Large changes.
3. **Visual Mockup Rule (Premium Aesthetics)**:
   - Before writing Godot `Control` node hierarchies for new complex UI menus, you must use the `generate_image` tool to create a premium visual mockup and obtain user approval on the aesthetic direction.
4. **Concise & Professional Communication**:
   - Keep responses concise, structured, and focused on key technical summaries and decisions requiring user input.

---

## 3. ARCHITECTURE & CODING STANDARDS

1. **Generalize via Inheritance & Virtual Classes**:
   - Whenever we can generalize logic, create virtual and inheritable classes and methods rather than duplicating code or using hardcoded `if/elif` type checks. Let polymorphism do the work.
2. **Method Documentation & Decision Rationale Rule**:
   - Whenever you touch or create a Medium or Large method, you **MUST** add a few lines of documentation above it explaining the core logic so the user doesn't have to read the code every time.
   - If specific design decisions were made as part of coding that method, include a brief explanation of the rationale within the docstring.
3. **Signal-Driven Visual Communication**:
   - Visual nodes (`src/systems/`, `scenes/`) must observe battle state changes strictly through `BattleEvents.gd` signals or by implementing `IBattleVisualAdapter.gd`. They **MUST NEVER** mutate simulation state directly.
4. **State Mutation Discipline**:
   - Battle state mutations must flow through dedicated resolvers. Do not mutate private third-party state or global arrays directly.
5. **Strict Data-Driven Content Rule**:
   - All new game content (spells, monster base stats, items, status effects) **MUST** be created as pure data entries (e.g., in `SpellReferences.gd` or external data files) rather than hardcoded logic branches.
6. **Immutable Base Data Rule**:
   - Any data dictionary fetched from factory references must be treated as strictly read-only. We must never mutate base stats directly in memory; transient buffs/debuffs must be layered on top via the `BattleState`.
7. **Signal Hygiene & Memory Leaks**:
   - Any time Godot signals are connected dynamically via code, they must either use `CONNECT_ONE_SHOT`, or ensure there is a guaranteed path for them to disconnect (e.g., `tree_exiting`).
8. **Fail-Fast Error Handling**:
   - Instead of silently masking errors, the engine must use Godot's `assert()` or `push_error()` to fail loudly if a critical internal state desync occurs.
9. **The "Scout Rule" (Progressive Refactoring)**:
   - If a script exceeds 300 lines of code, or contains deeply nested logic (3+ levels deep), proactively pause and recommend a refactor/split.
10. **Language Version & Formatting**:
    - Target **Godot 4.4 GDScript**. Use explicit static typing annotations where possible.
    - Casing: `PascalCase` for Classes/Enums; `camelCase` for variables/functions; `UPPER_SNAKE_CASE` for constants.

---

## 4. KNOWLEDGE & DOCUMENTATION MANAGEMENT

1. **Document Specificity (Architecture vs Game Design vs Learnings)**:
   - For **architectural changes** (refactoring systems, changing data flow), proactively consult and update `docs/ARCHITECTURE.md`.
   - For **creative changes** (inventing new spells, naming monsters, balancing stats), proactively consult and update `docs/GAME_DESIGN.md`.
   - For **technical discoveries** (new engine quirks, GDScript patterns), concisely record them by topic in `docs/LEARNINGS.md`. Do not treat it as a daily diary.
2. **Maintain the Backlog**:
   - Whenever you have an idea, suggestion, or observe technical debt / missing features in the game, immediately document it in `docs/BACKLOG.md`. Be proactive about proposing improvements.
3. **Game Reference Documentation Rules**:
   - Keep aspect reference files directly in `gamerefs/` (`gamerefs/trpg_01_*.md` through `gamerefs/trpg_12_*.md`).
   - Maintain `tactical_rpg_turn_systems.md` as the master index.
   - All analyzed reference games (+ *Road of Nogg* baseline) **MUST** be explicitly accounted for in **every** aspect file.
   - **Mandatory Footer Sections**: Every aspect file must conclude with an `## Implementation Takeaways for Road of Nogg` section, followed by a `### Master List Checklist Validation` section that lists all 26 reference games to ensure complete coverage.
   - Assertions about a game using a specific technical algorithm (e.g., pathing, AI) **MUST** provide external HTTP links to websites or documents (like developer interviews, wikis, or decompilations) that exist outside this game folder.

---

## 5. TESTING & VERIFICATION

1. **Mandatory CLI Verification**:
   - **Rule:** NEVER declare a feature complete, bug fixed, or refactoring successful without running the Godot CLI test execution command to verify clean runtime execution:
     ```powershell
     & "C:\Users\Henri\Documents\Road of Nogg\Godot_v4.3-stable_win64.exe" --path "C:\Users\Henri\Documents\Road of Nogg" --quit-after 3 "res://scenes/BattleSample.tscn"
     ```
   - Inspect terminal output and logs silently. Address any errors or stack trace failures before concluding the task.

---

*Last updated: 2026-07-22*
