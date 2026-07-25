# Runtime Architecture

Status: current. Last reconciled with source: 2026-07-25.

## Runtime ownership

`BattleSimulator` is the canonical gameplay runtime. It owns the active
`BattleState`, turn manager, movement/combat/passive resolvers, entity brains,
event bus, and optional visual adapter.

```text
scene / tool
    -> BattleSimulator
        -> BattleState + TurnManager + resolvers + brains
        -> BattleEvents
            -> IBattleVisualAdapter implementations
```

The simulation remains usable without a scene tree. Presentation can request a
simulation operation and react to its events, but it cannot edit battle state
directly.

## Layer boundaries

| Layer | Locations | Responsibility |
|---|---|---|
| Simulation and data | `src/battle_sim/`, `src/algorithms/`, `src/board/`, `src/entities/`, `src/entity_ai/`, `src/factories/` | Deterministic rules, state, content construction, AI decisions |
| Presentation | `src/presentation/` | Cameras, meshes, cursor, UI helpers, console and Godot adapters |
| Scene orchestration | `src/systems/BattlePresentationController.gd` | Godot lifecycle, pacing, input, setup, screenshots, adapter wiring |
| Legacy rollback | `src/systems/BattleMaster.gd`, `src/systems/legacy/`, `scenes/main.tscn` | Frozen rollback path; no new gameplay features |

Godot value types such as `Vector2i`, `Dictionary`, and `RandomNumberGenerator`
are valid in the headless layer. Scene nodes, cameras, controls, and visual
resources are not.

## Authoritative state

`BattleState` owns:

- `board`, `heightBoard`, and `terrainBoard` as `Matrix` layers;
- monsters by deterministic ID, team rosters, and position lookup;
- round, turn, and current-monster counters;
- active effects and deterministic event/decision history;
- the battle seed, RNG state, and monotonic monster-ID allocator.

`BattleState.moveMonsterTo()` coordinates occupancy, `monsterPositions`, and the
monster’s mirrored position. Callers must not update one representation alone.
Base monster, map, spell, race, and passive definitions come from factory
references and are treated as read-only inputs.

## Battle construction

The current scene controller performs this sequence:

1. Create `BattleSimulator`.
2. Load a map with `loadMap()`.
3. Create and attach a presentation adapter with `setVisualAdapter()`.
4. Set the deterministic seed before gameplay decisions.
5. Spawn monsters through `spawnMonster()` at validated positions.
6. Call `startBattle()` and `turnManager.startNewRound()`.

`spawnMonster()` allocates the ID, builds the reference-backed monster, resolves
its CPU brain, validates the tile, registers it in state, and emits
`monster_spawned`.

The playable setup work will replace the controller’s hardcoded configuration
with `BattleSetupConfig` and map-owned deployment slots. See
[`PLAYABLE_BATTLE_PLAN.md`](./PLAYABLE_BATTLE_PLAN.md).

## Turn execution

For the current CPU runtime:

1. `TurnManager.startNewRound()` builds a living-unit queue sorted by speed and
   stable ID, then emits `round_started`.
2. `startNextTurn()` records the current unit and emits `turn_started`.
3. `BattleSimulator.executeTurn()` asks the registered brain for a decision,
   records it, executes movement, then attack/spell/wait behavior through the
   resolvers.
4. End-of-turn passive/status hooks run, then `TurnManager.endTurn()` completes
   the unit turn.
5. The caller checks victory after turns and advances or ends the round.

A decision currently contains `move_path`, `action`, `target_id`, and optional
spell indexes. Player control requires extracting validation/execution from AI
decision generation so CPU and player controllers submit the same command. That
change is planned, not yet part of the runtime contract.

## Event and presentation contract

`BattleEvents` describes lifecycle, movement intent/results, action targets,
combat, healing, effects, passives, and victory. `IBattleVisualAdapter` connects
a consumer to that bus.

The default Godot adapter owns visual instances and delegates cursor state to
`BattleCursorController`. Cursor events represent discrete tactical intent:
movement targets the destination tile, while attacks, spells, and healing
target the affected unit’s tile. Player cursor ownership must take priority over
AI events when interactive control is added.

Presentation animations may lag behind authoritative state. They must queue or
cancel visual work without delaying or rewriting simulation results.

## Determinism, history, and snapshots

- All gameplay randomness flows through `BattleState.rng`.
- Equal-speed turn ties use deterministic monster ID ordering.
- `BattleStateSerializer.serialize()` produces JSON-safe current state,
  including seed, RNG state, IDs, board layers, rosters, effects, history, and
  monsters.
- `BattleSimulator.createReplaySnapshot()` adds initial/current state, pending
  turn order, and brain class names.
- Snapshot deserialization, continuation, and replay playback are not yet
  implemented; they remain backlog work.
- Simulation never writes diagnostic files. Tools and presentation decide when
  to persist output.

## Safe extension rules

- Add content in reference data and teach a general resolver only when the
  existing effect vocabulary cannot express it.
- Add state fields together with serialization and deterministic verification.
- Add movement variants through `BattleState`/`MovementResolver` so all position
  mirrors stay synchronized.
- Add presentation behavior by subscribing to events or extending the adapter;
  never call into state mutation from an animation callback.
- Add a new controller/action only after authoritative command validation exists.
- Add or change events by updating `BattleEvents`, `IBattleVisualAdapter`, every
  active adapter, and focused event-contract checks together.

## Legacy boundary

`project.godot` launches `scenes/Battle25D.tscn`, which uses the canonical
presentation controller. `scenes/main.tscn` and the `BattleMaster` flow are a
frozen rollback path. A scene must never bind both runtimes to one battle.
Removing the legacy stack requires an explicitly approved cleanup after the
new runtime covers the needed behavior.
