# Road of Nogg — Engine Architecture & Control Flow Blueprint

A comprehensive technical blueprint documenting the architecture, state contracts, control flows, visual bridge systems, and extension playbooks for the **Road of Nogg** combat simulation engine.

## 0. Runtime Authority and Migration Boundary

This section is authoritative wherever older sections below use stale names or
contracts.

| Concern | Canonical owner | Legacy or temporary path |
| --- | --- | --- |
| Battle state, board occupancy, teams, effects, and history | `BattleState` | `BattleBoard` state inside the old scene stack |
| Turn order, movement, combat, passives, victory, and seeded RNG | `BattleSimulator` and its resolvers | `BattleMaster`, `GameBoardLogic`, and `GameBoardThinker` |
| Simulation-to-presentation communication | `BattleEvents` and `IBattleVisualAdapter` | Direct calls from `BattleMaster` to `GameBoardVisual` |
| Godot scene lifecycle, input, camera, animation, and pacing | Presentation code under `src/systems/` | Current `scenes/main.tscn` rollback path |

### Canonical runtime contract

- `BattleSimulator` is the only authoritative gameplay runtime for new work.
- Simulation mutations flow through its state and resolvers. Presentation code
  may request actions but must never mutate simulation state directly.
- `BattleState.rng` is the only gameplay random source, and deterministic
  `uniqueID` values are the only entity identity keys.
- Visuals observe `BattleEvents` or implement `IBattleVisualAdapter`.
- The canonical runtime must remain usable without a Godot scene tree.

### Legacy freeze boundary

- `src/systems/BattleMaster.gd` and its direct `GameBoardLogic`,
  `GameBoardThinker`, and `GameBoardVisual` flow are frozen. Bug fixes needed to
  preserve the rollback path are allowed; new gameplay behavior is not.
- `scenes/main.tscn` still launches the legacy runtime today. This is an explicit
  temporary rollback state, not architectural authority.
- The legacy stack is not deleted until the new presentation controller can
  load equivalent sample data, spawn all visuals, pace turns, and provide a
  recoverable launch path.
- No scene may connect both runtimes to the same battle at once.

### Migration gates

1. Add a presentation controller that constructs and configures
   `BattleSimulator` without moving gameplay logic into `Node` classes.
2. Bind visuals only through the event/adapter contracts.
3. Verify the new scene independently, then switch the default main scene.
4. Retain the old scene as a named rollback entry point until visual and startup
   parity are confirmed.
5. Remove the legacy stack only in a separate, explicitly approved cleanup.

---

## 1. Core Architectural Principles

1. **Pure-Logic Simulation Layer (`src/battle_sim/`)**:
   - The battle simulator is **100% headless and decoupled** from the Godot Engine Node hierarchy.
   - Scripts in `src/battle_sim/`, `src/board/`, `src/entities/`, `src/entity_ai/`, and `src/factories/` MUST NOT inherit from `Node` or reference visual nodes (e.g. `Sprite2D`, `Control`, `Node3D`).
   - All logic can be instantiated, simulated, and tested purely in memory or via command-line scripts without graphics.

2. **Signal-Driven Visual Bridge (`BattleEvents.gd` & `IBattleVisualAdapter.gd`)**:
   - The simulation layer emits events via the `BattleEvents` signal bus.
   - Presentation layers (`GameBoardVisual.gd`, `ConsoleVisualAdapter.gd`) subscribe to these signals or implement `IBattleVisualAdapter` to render animations or log output asynchronously without mutating the underlying simulation state.

---

## 2. Core Data Models & State Contracts

### `Monster.gd` (Entity Model)
* **Location:** `src/entities/Monster.gd`
* **Purpose:** Represents an individual entity on the grid.
* **Core Attributes:**
  - `id: String`: Unique entity identifier.
  - `name: String`: Display name.
  - `team: int`: Team index (e.g., `1` for Player, `2` for Enemy).
  - `hp: int`, `max_hp: int`: Current and maximum health points.
  - `atk: int`: Physical attack stat.
  - `def: int`: Physical defense stat.
  - `speed: int`: Turn initiative stat (higher speed acts earlier in rounds).
  - `move: int`: Tile movement range per turn.
  - `position: Vector2i`: Grid coordinates `(x, y)` on the `BattleBoard`.
  - `active_effects: Array`: List of active status effect dictionaries (`{ "name": String, "duration": int, ... }`).
  - `brain`: Instance of `EntityBrain` governing AI decisions.

### `BattleState.gd` (State Container)
* **Location:** `src/battle_sim/BattleState.gd`
* **Purpose:** Single source of truth containing the complete active battle state.
* **Core Attributes:**
  - `board: BattleBoard`: 2D multi-layer grid storing tile occupancy and pathability.
  - `monsters: Array[Monster]`: Complete list of active entities.
  - `turn_manager: TurnManager`: Manages round queueing and entity turn order.
  - `round_number: int`: Active battle round index.
  - `is_finished: bool`: Set to `true` when a team is completely eliminated.
  - `winning_team: int`: Index of victorious team (`-1` if ongoing).

### `BattleBoard.gd` & `Matrix.gd` (Grid Representation)
* **Location:** `src/board/BattleBoard.gd`, `src/board/Matrix.gd`
* **Purpose:** Data structure tracking grid dimensions, tile obstacles, and entity positions.
* **Operations:** `get_occupant(pos)`, `set_occupant(pos, monster)`, `is_walkable(pos)`, `clear_position(pos)`.

---

## 3. Game Execution & Control Flows

### Flow 1: Battle Initialization & Setup
```
[ BattleSimulator.initialize_battle(monsters, board) ]
                       │
                       ▼
          [ Create BattleState Instance ]
                       │
                       ▼
       [ Register Entities on BattleBoard ]
                       │
                       ▼
      [ Initialize TurnManager(monsters) ]
                       │
                       ▼
   [ Bind Visual Adapter (IBattleVisualAdapter) ]
                       │
                       ▼
     [ Emit BattleEvents.battle_started ]
```
1. Caller invokes `BattleSimulator.initialize_battle(monsters, board_width, board_height)`.
2. `BattleSimulator` instantiates `BattleState` and populates `BattleBoard`.
3. Entities are assigned grid positions and registered on `BattleBoard`.
4. `TurnManager` is initialized with the monster list.
5. Visual adapter is connected to `BattleEvents`.

---

### Flow 2: Turn Loop & Round Management
```
               [ BattleSimulator.step_turn() ]
                              │
                              ▼
           [ TurnManager.get_next_entity() ]
                              │
               ┌──────────────┴──────────────┐
               │                             │
    [ New Round Needed? ]          [ Turn In Queue ]
               │                             │
               ▼                             │
    [ Sort Queue by Speed ]                  │
    [ Process Status Decay ]                 │
               │                             │
               └──────────────┬──────────────┘
                              │
                              ▼
              [ Check Entity Active & Living ]
                              │
                              ▼
               [ Execute Entity Turn Action ]
```
1. `BattleSimulator.step_turn()` calls `TurnManager.get_next_entity()`.
2. **Round Transition**: If the queue is empty, a new round begins:
   - All living entities are re-sorted by `speed` descending.
   - Status effects on active entities decrement duration by 1 turn. Expired effects are removed.
   - `round_number` increments.
3. If entity is dead (`hp <= 0`), turn is skipped and `step_turn()` advances.
4. Active entity turn begins.

---

### Flow 3: AI Decision & Action Resolution
```
            [ EntityBrain.decide_action(entity, state) ]
                              │
                              ▼
                 [ Evaluate Target & Move ]
                              │
               ┌──────────────┴──────────────┐
               │                             │
       [ Movement Needed? ]          [ In Range to Act? ]
               │                             │
               ▼                             ▼
    [ MovementResolver ]             [ CombatResolver ]
    - Calculate A* Path              - Calculate Damage
    - Update BattleBoard             - Apply HP Reduction
    - Update Monster.position        - Emit BattleEvents
               │                             │
               └──────────────┬──────────────┘
                              │
                              ▼
             [ BattleSimulator.check_victory() ]
```
1. `BattleSimulator` invokes `entity.brain.decide_action(entity, state)`.
2. **AI Logic (`SimpleBrain.gd`)**:
   - Finds nearest living enemy entity on the grid.
   - Checks if target is within attack/spell range.
3. **Movement Phase (`MovementResolver.gd`)**:
   - If not in range, calculates A* path towards target using `BattleBoard` walkable tiles.
   - Truncates path to entity's `move` stat.
   - Clears old board tile, updates `Monster.position`, sets new board occupant.
   - Emits `BattleEvents.entity_moved(entity, old_pos, new_pos, path)`.
4. **Combat Phase (`CombatResolver.gd`)**:
   - If in range, calculates damage: `damage = max(1, attacker.atk + spell_power - target.def)`.
   - Decrements `target.hp -= damage`.
   - Emits `BattleEvents.entity_attacked(attacker, target, damage)`.
   - If `target.hp <= 0`, sets target dead, clears grid tile, emits `BattleEvents.entity_defeated(target)`.

---

### Flow 4: Event & Visual Bridge Dispatch
```
  [ CombatResolver / MovementResolver ]
                   │
                   ▼ (Emits Signal)
         [ BattleEvents Bus ]
                   │
    ┌──────────────┼──────────────┐
    ▼              ▼              ▼
[ ConsoleAdapter ] [ GameBoardVisual ] [ AudioSystem ]
(Print text log)   (Animate sprite)    (Play SFX)
```
- Simulation resolvers emit signals to `BattleEvents` without importing visual classes.
- Visual components (`GameBoardVisual.gd`) process emissions asynchronously.
- Visual rendering NEVER writes back into simulation logic or alters calculations.

---

## 4. Safe Extension Playbooks (How to Add Features Safely)

### Playbook A: Adding a New Stat (e.g. `MAG` and `RES`)
1. **`Monster.gd`**: Add `var mag: int = 10` and `var res: int = 5` to properties and `to_dict()`/`from_dict()` serialization.
2. **`Factories`**: Update `MonsterFactory.gd` and reference data to supply default `mag`/`res` values.
3. **`CombatResolver.gd`**: Update magic spell calculations to use `attacker.mag + spell.power - target.res`.
4. **`BattleSimTest.gd`**: Run test script to verify physical and magical attacks resolve correctly.

### Playbook B: Adding a New Action Type (e.g. Defend or Items)
1. **`EntityBrain.gd`**: Add action enum/type handling (`ACTION_DEFEND`, `ACTION_ITEM`).
2. **`BattleSimulator.gd`**: Add match statement branch for handling `ACTION_DEFEND` or `ACTION_ITEM`.
3. **`CombatResolver.gd`**: Add resolution function (e.g., `resolve_defend(entity)` applying a 1-turn defense buff).
4. **`BattleEvents.gd`**: Add signal (e.g., `signal entity_defended(entity)`).

### Playbook C: Refactoring Turn Paradigm (e.g. CT/WT Initiative Timeline)
1. Preserve `TurnManager.gd` class interface (`get_next_entity()`, `peek_next_entity()`).
2. Replace round queue logic internally with CT tick accumulation accumulator (`CT += speed`).
3. Ensure `BattleState` interface contracts remain unchanged so `BattleSimulator` requires zero rewrites.

---

*Last updated: 2026-07-21*
