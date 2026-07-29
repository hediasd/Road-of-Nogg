# Runtime Architecture

Status: current. Last reconciled with source: 2026-07-26.

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
| Scene orchestration | `src/systems/BattlePresentationController.gd` | Godot lifecycle, pacing, input routing, screenshots, adapter wiring |
| Player turn | `src/systems/PlayerTurnController.gd` | Player-turn phases, command menu model, phase submission |
| Legacy rollback | `src/systems/BattleMaster.gd`, `src/systems/legacy/`, `scenes/main.tscn` | Frozen rollback path; no new gameplay features |

Godot value types such as `Vector2i`, `Dictionary`, and
`RandomNumberGenerator` are valid in the headless layer. Scene nodes, cameras,
controls, and visual resources are not.

## Authoritative state

`BattleState` owns:

- `board`, `heightBoard`, and `terrainBoard` as `Matrix` layers;
- the active map name/revision used by state and replay compatibility;
- monsters by deterministic ID, team rosters, position lookup, level, jump,
  immutable base/growth values, and resolved battle stats;
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
2. `BattleSetupConfig.validate()` checks catalogs, roster sizes, the versioned
   terrain/height schema, and every map-owned deployment slot.
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
`move_path`, `action`, `target_id`, `spell_set_index`, `spell_index`, and
`order`. `BattleSimulator.validateCommand()` checks the current actor, the
complete move path, the destination, action type, spell availability, range,
line of sight, team rules, and target validity against authoritative state.

`order` is `move_first` or `act_first` and says which phase resolved first. It
decides which position the action is validated from: a `move_first` action is
checked against the move destination, an `act_first` action against the tile
the actor started the turn on. Without it an act-then-move turn would replay
as move-then-act and re-validate against a tile the actor was never in
position to act from.

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
shared executor.

## Incremental turn execution

A turn holds at most one movement phase and at most one action phase, in
either order. `executeMovePhase()`, `executeActionPhase()`, and `finishTurn()`
resolve them one at a time, which is what lets the interactive path animate a
move to completion before the player chooses an action. `executeCommand()` is
the atomic entry point CPU brains and replay use; it validates the whole turn
up front and then drives the same phase calls in the order the command
records.

Both routes accumulate into one turn and produce exactly one `command` history
event, written by `finishTurn()`. `finishTurn()` is also the sole caller of
`PassiveSkillResolver.ON_TURN_END`, which must fire once per turn however many
phases ran. An action phase validates from authoritative state rather than a
projected destination, because by then the actor is already standing where it
will act from.

`undoMovePhase()` rewinds movement to the tile the turn began on. It is legal
only while the action phase is unspent: an action is validated from the tile
it was made from, so rewinding that tile afterwards would retroactively
falsify a resolution that has already dealt damage. Movement itself has no
side effects to unwind — no passive triggers on it — so the rewind is a
position restore plus a `monster_moved` emission along the reverse path, which
presentation animates as an ordinary move.

## Elevation, combat, and CPU planning

`MapFactory` validates map revisions plus an independent integer height matrix
and copies it into `BattleState.heightBoard`. `MovementResolver.canTraverse()`
is the shared cardinal, terrain, occupancy, and JUMP edge rule used by BFS, A*,
player previews, command validation, and CPU paths.

Combat target queries enforce melee/spell height reach before resolution.
Height-aware supercover LoS compares the interpolated eye-to-eye ray against
surface, obstacle, and intervening-unit tops. `DirectDamageRules` owns the
110/100/90-percent elevation arithmetic used by real attacks, spells, and pure
CPU estimates; healing, ticks, and reflected damage do not call it.

`BattleCommandEvaluator` builds one context per CPU decision, enumerates legal
controller-neutral movement/action candidates, and orders them by battle win,
defeats, survival/threat, role utility, damage, position, and a stable tie key.
Brain subclasses provide weights rather than separate legality formulas.
## Player interaction and cursor

`PlayerTurnController` owns one player-controlled turn — its phase, the command
menu model, and submission through the incremental turn API.
`BattlePresentationController` routes input to it and reacts to its
`menu_changed`, `status_changed`, and `turn_finished` signals; it does not
track phases itself.

```text
MENU -> MOVE_SELECT                     -> (resolve, animate) -> MENU
MENU -> TARGET_SELECT -> CONFIRM_ACTION -> (resolve, animate) -> MENU
MENU -> (Undo Move)                     -> (rewind, animate)  -> MENU
MENU -> (Pass)                                                -> turn end
```

Each phase resolves on its own and the menu reopens with that entry spent, in
either order; spending both ends the turn. Movement has no confirm phase —
selecting a reachable tile resolves it, and `Undo Move` is the safety net.
That undo window is exactly the gap between moving and acting: once an action
resolves, both phases are spent and the turn is over.

A resolved phase animates before the menu reopens. Choosing a target while the
model is still walking would mean aiming from a tile the unit has already left
on screen.

Cancel walks back one phase; the root menu is left only through Pass or by
spending both phases. The presentation exposes reachable tiles, the previewed
path, valid targets, and spell range/cooldown information. Mouse ray-casting is
the primary input. Cursor movement and selection APIs also accept the standard Godot UI
directions and accept/cancel actions, keeping keyboard and gamepad support at
the same command boundary.

`BattleCursorController` owns discrete grid intent for AI turns, movement
destinations, player selection, and targeting. Player ownership blocks older AI
events from moving the cursor. Movement snaps to a destination cell; attacks,
spells, and heals snap to the affected target cell. Camera orbit/pan gestures
acquire explicit ownership on mouse press and retain motion delivery until the
matching release, independent of moving models or controls under the pointer.

Each coordinate renders a contiguous column of `height + 1` exact
`1 x 0.5 x 1` terrain blocks. Logical elevation stays integer-based while its
world-space top surface is `height * 0.5 + 0.25` before terrain-specific visual
offsets. Monsters, overlays, queued movement arcs, and cursor anchors derive
world Y from the same presentation surface query.

## Event and presentation contract

`BattleEvents` describes lifecycle, movement intent/results, action targets,
combat, healing, effects, passives, and victory. `IBattleVisualAdapter` connects
a consumer to that bus. `GodotVisualAdapter` copies position-bearing event data
into a FIFO visual-action queue, so movement, targeting, attacks, spells, heals,
defeat, and victory play in event order without blocking the simulation.
Playback never re-reads a later monster position to start a queued action.
Movement begins at the model's current rendered transform and animates every
horizontal and vertical step through a bounded jump arc. Each tween has a
bounded watchdog recovery, while disposal invalidates callbacks and clears the
queue. Presentation may lag behind authoritative state but cannot delay or
rewrite simulation results.

## Determinism, replay, and restoration

- All gameplay randomness flows through `BattleState.rng`.
- Equal-speed turn ties use deterministic monster ID ordering.
- Schema version 5 records map revision, height, level, jump, base/growth fields, resolved stats, family, ascension parent, Resonance bars, and Luck; version 2 migrates to height 0, level 1, and jump 1.
- `BattleStateSerializer` produces and restores JSON-safe state, including RNG,
  IDs, board layers, rosters, effects, history, and monsters.
- `BattleSimulator.createReplaySnapshot()` includes setup, initial/current state,
  pending turn order, brain classes, and the controller-neutral command ledger.
- Replay snapshots are version 4, which added the command `order` field.
  Version 3 and 2 snapshots still load, defaulting `order` to `move_first` —
  they predate act-first turns, so every recorded turn was move-first anyway.
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
