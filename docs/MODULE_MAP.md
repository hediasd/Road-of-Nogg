# Module Map

Status: current. Last reconciled with source: 2026-08-02.

This is the **routing guide**: which directory owns what, what it may depend
on, and where to make a given change. It deliberately stays shallow.
[`ARCHITECTURE.md`](./ARCHITECTURE.md) remains the detailed source of truth for
runtime ownership, turn execution, and the event contract — when the two
disagree, ARCHITECTURE wins and this file is the one to correct.

## Directories

| Directory | Responsibility | Public entry points | May depend on | Must not depend on | Owning doc |
|---|---|---|---|---|---|
| `data/` | Authored JSON catalogs: monsters, spells, passives, archetypes, elements, status effects, taxonomy, maps | The JSON files themselves | nothing (inert data) | any code | [`REFERENCE_CATALOGS.md`](./REFERENCE_CATALOGS.md), [`SPELL_CATALOG_SCHEMA.md`](./SPELL_CATALOG_SCHEMA.md) |
| `src/factories/` | Load catalogs and build runtime entities; own the JSON→object boundary | `MonsterFactory`, `MapFactory`, `SpellFactory`, `PassiveSkillFactory`, `*References`, `BattleSetupPresets` | `data/`, `src/entities/` | presentation, scene tree | [`REFERENCE_CATALOGS.md`](./REFERENCE_CATALOGS.md) |
| `src/entities/` | Passive runtime content objects | `Monster`, `Map`, `Spell`, `PassiveSkill` | `src/board/` | presentation, scene tree | [`GAME_DESIGN.md`](./GAME_DESIGN.md) |
| `src/board/` | Grid containers and terrain storage | `BattleBoard`, `Matrix` | nothing | presentation, scene tree | [`ARCHITECTURE.md`](./ARCHITECTURE.md) |
| `src/algorithms/` | Spatial/tactical math. Five files are pure primitives; `ThreatMap` is the documented exception below | `AStarPathfinder`, `BFSFloodFill`, `LineOfSight`, `ParabolicArc`, `ShapeCaster`, `ThreatMap` | `src/board/`; `ThreatMap` additionally reads `BattleState` and the movement/combat resolvers | presentation, scene tree | [`ARCHITECTURE.md`](./ARCHITECTURE.md) |
| `src/entity_ai/` | CPU decision-making | `EntityBrain` and its `Tactical`/`Mage`/`Support`/`Berserk` subclasses, `CommandDeliberation`, `BattleCommandEvaluator` | `src/algorithms/`, `src/board/`, `src/entities/`, `src/battle_sim/` command types | presentation, scene tree | [`ARCHITECTURE.md`](./ARCHITECTURE.md) |
| `src/battle_sim/` | Canonical runtime: state, turn order, resolvers, setup, replay, event bus, adapter port | `BattleSimulator`, `BattleState`, `BattleSetupConfig`, `BattleSetupValidationResult`, `BattleSetupFactory`, `BattleCommand`, `BattleEvents`, `IBattleVisualAdapter`, `BattleStateSerializer`, `BattleReplayRunner` | every headless directory above | `src/presentation/`, `src/systems/`, scene tree | [`ARCHITECTURE.md`](./ARCHITECTURE.md) |
| `src/presentation/` | Observe simulation and draw it: camera, meshes, cursor, UI, effects, adapters | `GodotVisualAdapter`, `ConsoleVisualAdapter`, `BattleMeshFactory`, `BattleCameraController`, `BattleUIBuilder`, `BattleSetupUI`, `VisualActionQueue` | all simulation directories (read-only) | mutating `BattleState`; being imported by simulation | [`UI_DESIGN.md`](./UI_DESIGN.md), [`ARCHITECTURE.md`](./ARCHITECTURE.md) |
| `src/presentation/theme/` | Reusable HUD widgets and theme tokens | `NoggTheme`, `NoggWindow`, `MenuCursor`, `PagerArrow`, `ResonanceBar` | Godot `Control` API | simulation | [`UI_DESIGN.md`](./UI_DESIGN.md) |
| `src/presentation/effects/` | Transient visual effects | `SpellCastAura` | Godot 3D API | simulation | [`UI_DESIGN.md`](./UI_DESIGN.md) |
| `src/systems/` | Scene lifecycle and player-turn orchestration | `BattlePresentationController` (scene root), `PlayerTurnController` | simulation and presentation | being imported by either | [`ARCHITECTURE.md`](./ARCHITECTURE.md) |
| `scenes/` | Godot scenes | `Battle25D.tscn` (the entry scene), `Monster.tscn`, `map01.tscn` | `src/systems/`, `src/presentation/` | — | [`ARCHITECTURE.md`](./ARCHITECTURE.md) |
| `scripts/` | Headless tooling, run via `SceneTree` | `demo_battle.gd`, `update_gamerefs.gd` | simulation | being imported by runtime code | [`DEVELOPMENT.md`](./DEVELOPMENT.md) |

`data/` is loaded only through `src/factories/`. Nothing else reads the JSON
directly.

**The one asymmetry:** `AStarPathfinder`, `BFSFloodFill`, `LineOfSight`,
`ParabolicArc`, and `ShapeCaster` depend on nothing but `src/board/`.
`ThreatMap` is different — it takes `BattleState` and the movement/combat
resolvers, because an influence map is only accurate if it is built from the
same rules the simulation applies. It is consumed solely by `src/entity_ai/`;
`src/battle_sim/` never imports it, so there is no cycle. Treat it as AI
support that happens to live in `algorithms/`, and do not copy its dependency
breadth into the other five.

## Dependency direction

```text
data/  ──►  src/factories/  ──►  src/entities/
                                      │
              src/board/, src/algorithms/
                                      │
                                      ▼
                            src/battle_sim/  ◄── src/entity_ai/
                                      │
                            BattleEvents / IBattleVisualAdapter
                                      │  (one way: events out, commands in)
                                      ▼
                            src/presentation/
                                      ▲
                                      │
                             src/systems/  ──►  scenes/Battle25D.tscn
```

Authored data and setup feed the headless simulation; `src/systems/`
orchestrates the Godot lifecycle; presentation observes through events and
adapters and submits commands back. **No arrow points from simulation into
presentation.** Reading a `BattleState` constant or static helper (for example
`BattleState.TERRAIN_ABYSS` or `BattleState.isPermanentDuration`) from
presentation is a read, not a dependency inversion, and is allowed.

## Where to make a change

| Change | Go to |
|---|---|
| Catalog content — a new monster, spell, passive, element | `data/*.json`, then the matching `src/factories/*References.gd` if the schema changes |
| Combat rules, damage, status application | `src/battle_sim/CombatResolver.gd`, `DirectDamageRules.gd`, `SpellEffectResolver.gd`, `PassiveSkillResolver.gd` |
| Movement, reachability, line of sight | `src/battle_sim/MovementResolver.gd`, `src/algorithms/` |
| Turn order and round structure | `src/battle_sim/TurnManager.gd` |
| CPU behavior | `src/entity_ai/` — pick the brain, or `CommandDeliberation` for the search itself |
| Replay and serialization | `src/battle_sim/BattleStateSerializer.gd`, `BattleReplayRunner.gd` |
| Battle setup, modes, seeds, team construction | `src/battle_sim/BattleSetupConfig.gd`, `BattleSetupFactory.gd`, `src/factories/BattleSetupPresets.gd` |
| Battle HUD, menus, windows, fonts | `src/presentation/BattleUIBuilder.gd`, `PlayerCommandMenu.gd`, `src/presentation/theme/` |
| Setup screen | `src/presentation/BattleSetupUI.gd` |
| Monster/board meshes and materials | `src/presentation/BattleMeshFactory.gd` |
| Visual effects, animation pacing | `src/presentation/BattleVisualEffects.gd`, `VisualActionQueue.gd`, `src/presentation/effects/` |
| Camera | `src/presentation/BattleCameraController.gd` |
| Player-turn phases, cursor ownership, undo | `src/systems/PlayerTurnController.gd` |
| Scene lifecycle, pacing, adapter wiring | `src/systems/BattlePresentationController.gd` |
| Headless tooling and demos | `scripts/` |
