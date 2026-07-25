# Road of Nogg — Project Structure

## Engine
Godot 4.4 / 4.3 (GDScript)

## Folder Layout

```
Road of Nogg/
├── ai/                      # AI collaboration docs, architecture & policies
│   ├── ARCHITECTURE.md          # Technical blueprint, control flows & data models
│   ├── POLICIES.md              # AI guardrails, coding standards, CLI test rules
│   ├── GAME_DESIGN.md           # Confirmed game design decisions
│   ├── PROJECT_STRUCTURE.md     # This file — folder layout reference
│   └── LEARNINGS.md             # Ongoing codebase discoveries & debug notes
│
├── gamerefs/                    # TRPG & Turn-Based RPG Reference Docs
│   ├── tactical_rpg_turn_systems.md  # Master Index & 26-game comparison matrix
│   ├── trpg_01_turn_flow_and_initiative.md
│   ├── trpg_02_speed_and_turn_frequency.md
│   ├── trpg_03_action_economy_and_costs.md
│   ├── trpg_04_offensive_stats_and_damage.md
│   ├── trpg_05_luck_and_chance_mechanics.md
│   ├── trpg_06_interactivity_and_counters.md
│   ├── trpg_07_secondary_resources_and_mental_stats.md
│   ├── trpg_08_equipment_weight_and_mobility.md
│   ├── trpg_09_algorithms_and_math_models.md
│   ├── trpg_10_elemental_systems_and_affinities.md
│   ├── trpg_11_shop_and_economy_systems.md
│   └── trpg_12_forging_crafting_and_item_systems.md
│
├── src/                     # All GDScript source code
│   ├── battle_sim/              # Pure-logic battle simulation (no visuals)
│   │   ├── BattleEvents.gd          # Signal bus for decoupling
│   │   ├── BattleState.gd           # All battle state in one place
│   │   ├── BattleSimulator.gd       # Main orchestrator
│   │   ├── TurnManager.gd           # Turn order and round management
│   │   ├── MovementResolver.gd      # A* pathfinding + movement validation
│   │   ├── CombatResolver.gd        # Damage calculation and attack resolution
│   │   └── IBattleVisualAdapter.gd  # Interface for presentation observers
│   │
│   ├── presentation/            # Simulation observers and Godot presentation
│   │   ├── GodotVisualAdapter.gd   # 3D event adapter
│   │   ├── BattleCameraController.gd # Tactical camera controls
│   │   ├── ConsoleVisualAdapter.gd # Console/file event adapter
│   │   └── legacy/Grid.gd          # Archived visual grid mesh
│   │
│   ├── entity_ai/               # AI brain modules for entities
│   │   ├── EntityBrain.gd           # Base brain class (interface)
│   │   └── SimpleBrain.gd           # Simple AI: move toward nearest enemy, attack
│   │
│   ├── board/                   # Grid data structures
│   │   ├── BattleBoard.gd           # Multi-layer grid state
│   │   └── Matrix.gd                # 2D array helper
│   │
│   ├── entities/                # Data models
│   │   ├── Monster.gd               # Unit/entity data class
│   │   └── Spell.gd                 # Spell/ability data class
│   │
│   ├── factories/               # Creation patterns and static data
│   │   ├── Factory.gd, MonsterFactory.gd, SpellFactory.gd
│   │   ├── MonsterReferences.gd, SpellReferences.gd
│   │   └── Reference.gd
│   │
│   └── systems/                 # Godot-integrated systems (visuals, input, camera)
│       ├── BattlePresentationController.gd # Canonical scene/pacing controller
│       ├── BattleMaster.gd          # Legacy rollback scene orchestrator
│       ├── legacy/GameBoardLogic.gd # Legacy rollback board mutation Node
│       ├── legacy/GameBoardThinker.gd # Legacy rollback AI Node
│       ├── BattleSample.gd          # Hardcoded test scenario
│       ├── GameBoardVisual.gd       # Monster sprite management
│       └── Input.gd, MainCamera.gd, Spin.gd
│
├── scenes/                  # Godot .tscn scene files
├── assets/                  # Models, textures, fonts, UI
└── project.godot            # Godot project configuration
```

## Key Architecture Principle
The `battle_sim/` layer is **pure logic** — no Node dependencies, no visuals.
It emits signals via `BattleEvents`, which a visual adapter (or console adapter) consumes.
This makes it testable independently and keeps the graphics bridge pluggable.
See [ARCHITECTURE.md](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/ai/ARCHITECTURE.md) and [POLICIES.md](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/ai/POLICIES.md) for complete details.

---

*Last updated: 2026-07-21*
