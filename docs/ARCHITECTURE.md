# Runtime Architecture

Status: current. Last reconciled with source: 2026-07-25.

## Runtime ownership

`BattleSimulator` is the canonical gameplay runtime. It owns the active
`BattleState`, turn manager, movement/combat/passive resolvers, entity brains,
event bus, setup snapshot, command ledger, and optional visual adapter.

```text
setup UI / replay tool / controller
    -> BattleSetupConfig
    -> BattleSetupFactory
        -> BattleSimulator
            -> BattleState + TurnManager + resolvers + brains
            -> BattleEvents
                -> IBattleVisualAdapter implementations
```

The simulation remains usable without a scene tree. Presentation submits
commands and reacts to events; it does not edit battle state directly.

## Layer boundaries

| Layer | Locations | Responsibility |
|---|---|---|
| Simulation and data | `src/battle_sim/`, `src/algorithms/`, `src/board/`, `src/entities/`, `src/entity_ai/`, `src/factories/` | Deterministic rules, state, setup construction, content, AI decisions |
| Presentation | `src/presentation/` | Cameras, meshes, cursor, setup/battle UI helpers, visual registry and adapters |
| Scene orchestration | `src/systems/BattlePresentationController.gd` | Godot lifecycle, pacing, input, player state machine, screenshots, adapter wiring |
| Legacy rollback | `src/systems/BattleMaster.gd`, `src/systems/legacy/`, `scenes/main.tscn` | Frozen rollback path; no new gameplay features |

Godot value types such as `Vector2i`, `Dictionary`, and
`RandomNumberGenerator` are valid in the headless layer. Scene nodes, cameras,
controls, and visual resources are not.

## Authoritative state

`BattleState` owns:

- `board`, `heightBoard`, and `terrainBoard` as `Matrix` layers;
- monsters by deterministic ID, team rosters, and position lookup;
- round, turn, and current-monster counters;
- active effects and deterministic event/command history;
- the battle seed, RNG state, and monotonic monster-ID allocator.

`BattleState.moveMonsterTo()` coordinates occupancy, `monsterPositions`, and the
monster's mirrored position. Callers must not update one representation alone.
Base monster, map, spell, race, and passive definitions are read-only inputs.

## Setup and battle construction

`Battle25D.tscn` creates the animated sky and setup overlay first. It does not
create a simulator, map, or monster visual before confirmation.

On Confirm:

1. `BattleSetupUI` produces a `BattleSetupConfig` containing mode, map, seed,
   controller ownership, and both four-monster rosters.
2. `BattleSetupConfig.validate()` checks catalogs, roster sizes, and every
   map-owned deployment slot.
3. `BattleSetupFactory` creates and seeds the simulator, loads the selected map,
   attaches the visual adapter, and deploys both teams.
4. `MonsterVisualRegistry` supplies an authored scene when registered;
   `GodotVisualAdapter` creates a procedural fallback otherwise.
5. The controller starts the battle and round, then dispatches CPU turns or
   pauses for a Team 1 player command according to the selected mode.

Returning to setup disposes the active visual adapter, clears the simulator and
player state, hides battle controls, and restores the setup overlay over the sky.

## Controller-neutral command contract

CPU brains and the player controller submit the same command fields:
`move_path`, `action`, `target_id`, `spell_set_index`, and `spell_index`.
`BattleSimulator.validateCommand()` checks the current actor, the complete move
path, the future destination, action type, spell availability, range, line of
sight, team rules, and target validity against authoritative state.

Command outcome has two distinct stages:

- A validation failure returns `success=false`, records `command_rejected`, and
  performs no movement or action.
- A validated command is recorded once and returns `success=true`. Movement and
  reactive effects then resolve. `resolved` and the nested `actionResult`
  describe whether the requested attack or spell completed.
- A reactive passive may defeat or invalidate an actor after acceptance. This
  is an accepted command with `resolved=false`, not a rejected command; the
  turn ends without generating a second fallback command.

`executeTurn()` only asks a CPU brain for its proposal and delegates to this
shared executor. The player controller waits for UI input and submits through
the same method.

## Player interaction and cursor

The first playable player state machine is:

```text
UNIT_SELECTED -> MOVE_PREVIEW -> ACTION_MENU -> TARGETING -> CONFIRM
```

Cancel walks back through the state machine. The presentation exposes reachable
tiles, the selected path, valid targets, spell range/cooldown information,
confirm, cancel, wait, and end-turn actions. Mouse ray-casting is the primary
input. Cursor movement and selection APIs also accept the standard Godot UI
directions and accept/cancel actions, keeping keyboard and gamepad support at
the same command boundary.

`BattleCursorController` owns discrete grid intent for AI turns, movement
destinations, player selection, and targeting. Player ownership blocks older AI
events from moving the cursor. Movement snaps to a destination cell; attacks,
spells, and heals snap to the affected target cell.

## Event and presentation contract

`BattleEvents` describes lifecycle, movement intent/results, action targets,
combat, healing, effects, passives, and victory. `IBattleVisualAdapter` connects
a consumer to that bus. Presentation animation may lag behind authoritative
state, but it must queue or cancel visual work without delaying or rewriting
simulation results.

## Determinism, replay, and restoration

- All gameplay randomness flows through `BattleState.rng`.
- Equal-speed turn ties use deterministic monster ID ordering.
- `BattleStateSerializer` produces and restores JSON-safe state, including RNG,
  IDs, board layers, rosters, effects, history, and monsters.
- `BattleSimulator.createReplaySnapshot()` includes setup, initial/current state,
  pending turn order, brain classes, and the controller-neutral command ledger.
- `BattleReplayRunner` reconstructs a battle from setup and replays recorded CPU
  and player commands through normal validation/execution.
- `restoreReplaySnapshot()` restores current state and rebuilds resolvers,
  brains, events, and the pending turn queue for continuation.
- Simulation never writes diagnostic files. Tools and presentation decide when
  to persist output.

## Safe extension rules

- Add content in reference data and teach a general resolver only when the
  existing effect vocabulary cannot express it.
- Add state fields together with JSON serialization, restoration, and
  deterministic verification.
- Add movement variants through `BattleState`/`MovementResolver` so all position
  mirrors stay synchronized.
- Add presentation behavior through events or the adapter; never mutate state
  from an animation callback.
- Preserve `success` versus `resolved` when adding reactions or action types.
- Add or change events by updating `BattleEvents`, `IBattleVisualAdapter`, every
  active adapter, and focused event-contract checks together.

## Legacy boundary

`project.godot` launches `scenes/Battle25D.tscn`, which uses the canonical
presentation controller. `scenes/main.tscn` and the `BattleMaster` flow are a
frozen rollback path. A scene must never bind both runtimes to one battle.
Removing the legacy stack requires an explicitly approved cleanup after the
new runtime covers the needed behavior.