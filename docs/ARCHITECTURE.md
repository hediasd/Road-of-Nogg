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

Godot value types such as `Vector2i`, `Dictionary`, and
`RandomNumberGenerator` are valid in the headless layer. Scene nodes, cameras,
controls, and visual resources are not.

For the per-directory breakdown — public entry points, allowed and forbidden
dependencies, and a "where to make a change" table — see
[`MODULE_MAP.md`](./MODULE_MAP.md). This section stays the authority on what
the layers *mean*; the map is the routing detail.

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
   terrain/height schema, and every map-owned deployment slot. It returns a
   typed `BattleSetupValidationResult` (`success`, `errors`, `errorText()`),
   not a dictionary.
3. `BattleSetupFactory.createSimulator(config: BattleSetupConfig, adapterFactory)
   -> BattleSimulator` creates and seeds the simulator, loads the selected map,
   attaches the visual adapter, and deploys both teams. It asserts that a
   supplied `adapterFactory` returns an `IBattleVisualAdapter` before attaching
   it.
4. `MonsterVisualRegistry` supplies an authored scene when registered;
   `GodotVisualAdapter` creates a procedural fallback otherwise.
5. The controller starts the battle and round, then dispatches CPU turns or
   pauses for a Team 1 player command according to the selected mode.

Returning to setup disposes the active visual adapter, clears the simulator and
player state, hides battle controls, and restores the setup overlay over the sky.

The setup lifecycle is typed end to end — `BattleSetupConfig`,
`BattleSetupValidationResult`, `BattleSimulator`, `IBattleVisualAdapter`. The
deliberate exception is the serialization edge: `serialize()` and
`fromDictionary()` exchange a `Dictionary` because the setup snapshot is stored
in replay files, and the defaults in `fromDictionary()` keep older snapshots
loadable. Catalog payloads, event history, and variable-shape resolver results
likewise stay dictionaries.

## Controller-neutral command contract

CPU brains, replay, and the simulator exchange typed `BattleCommand` values;
validation and execution return `BattleCommandResult`. Commands expose
`move_path`, `action`, canonical `target_pos`, derived `target_id`,
`spell_set_index`, `spell_index`, and `order`. Explicit `to_dictionary()` / `from_dictionary()` adapters keep dynamic
keys at command-history and replay serialization edges rather than in the
public orchestration API. Resolver-specific action details remain a dictionary
inside the typed result because their shape legitimately varies by action.
`BattleSimulator.validateCommand()` checks the current actor, the complete move
path, the destination, action type, spell availability, range, line of sight,
team rules, and target validity against authoritative state.

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

`BattleCommandEvaluator` builds one context per CPU decision and enumerates
legal target positions from every reachable destination. Area spells score all
units affected around each center; centers with the same affected-unit outcome
are deduplicated. Empty attacks and casts with no useful affected-unit outcome
remain legal candidates but score one point below Wait at the same destination.
Destinations and centers are sorted by coordinate, and the final tie key includes
destination, action/spell identity, and center coordinate. Projected-occupancy
queries treat the actor as having vacated its origin and reached the candidate
destination, so validation, scoring, and later execution see the same board.
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

`PlayerCommandMenu` renders root commands and Spell as independent columns. It
keeps their selections separately, and Spell owns its visible `< Back` command;
the scene controller routes Escape and right-click through the same transition.
Status instructions and read-only action forecasts travel on separate signals.

Every rendered tile also owns a pick-only surface collider with authoritative
tile metadata. `BattlePresentationController` raycasts the combined tile/unit
pick layers, so a mouse selection resolves the visible terrain surface rather
than an artificial `y = 0` plane.

The simulation command contract identifies action centers with `target_pos`;
`target_id` is only the occupant derived when validation executes. Basic attacks
can therefore resolve against adjacent empty tiles, and every non-self spell can
query tile centers. `CAN_TARGET_EMPTY` controls confirmation on an empty center
without controlling whether presentation displays that center. The player
controller stores and cycles coordinates, displays all reachable empty spell
centers, and asks the resolver again before confirmation. Spell footprints and
aggregate forecasts use `CombatResolver` queries shared by resolution, AI, and
presentation.

`BattleCursorController` owns discrete grid intent for AI turns, movement
destinations, player selection, and targeting. Player ownership blocks older AI
events from moving the cursor. Movement snaps to a destination cell; attacks,
spells, and heals snap to the affected target cell. Camera orbit/pan gestures
acquire explicit ownership on mouse press and retain motion delivery until the
matching release, independent of moving models or controls under the pointer.

Every monster model stands on a base built by
`BattleMeshFactory.createModelBase()`. The base is deliberately darker than any
creature body so it never reads as part of the monster, and it is split into
`ascensionTier + 1` stacked layers — one for a basic monster, one more per
ascension. `MonsterReferences.ascensionTier()` walks the catalog's
`ASCENDS_FROM` chain and is the single tier source, so setup, replay
reconstruction, and board refresh all build the same stack, placeholder visuals
included. The layers share a fixed `BASE_TOTAL_HEIGHT` budget and get thinner as
the stack grows, so ascension changes what a base *reads* as without changing
model height, footprint, or origin.

Each coordinate renders a contiguous column of `height + 1` exact
`1 x 0.5 x 1` terrain blocks. Logical elevation stays integer-based while its
world-space top surface is `height * 0.5 + 0.25` before terrain-specific visual
offsets. Monsters, overlays, queued movement arcs, and cursor anchors derive
world Y from the same presentation surface query.

## Event and presentation contract

`BattleEvents` describes lifecycle, movement intent/results, action targets,
combat, healing, effects, passives, and victory. `IBattleVisualAdapter` connects
a consumer to that bus.

There are two adapter contracts, and the split matters:

- **`IBattleVisualAdapter`** (`src/battle_sim/`) is the general, *observational*
  surface — enough to watch a battle. `ConsoleVisualAdapter` implements exactly
  this and stays non-interactive.
- **`IPlayerTurnVisualAdapter`** (`src/presentation/`) extends it with the
  narrow *interactive* additions a player turn needs: busy state, the
  `animation_queue_drained` signal, player/target cursor, target status,
  movement and target overlays, cursor release, and overlay clearing.
  `GodotVisualAdapter` implements this one, and `PlayerTurnController` holds it
  as its adapter type.

Implementations inherit `animation_queue_drained` and must not redeclare it: a
redeclared signal is a distinct signal, so a controller connected through the
port would never be notified. `GodotVisualAdapter` copies position-bearing event data into typed
`VisualAction` snapshots in a FIFO queue, so movement, targeting, attacks,
spells, heals, defeat, and victory play in event order without blocking the
simulation. The queue clones each snapshot at enqueue time, preventing later
producer mutations from changing delayed playback.
Playback never re-reads a later monster position to start a queued action.
Movement begins at the model's current rendered transform and animates every
horizontal and vertical step through a bounded jump arc. Each tween has a
bounded watchdog recovery, while disposal invalidates callbacks and clears the
queue. Presentation may lag behind authoritative state but cannot delay or
rewrite simulation results.

## Playback pause and run-ahead

The play/pause toggle is a playback control over the visual queue, not a
simulation control. `VisualActionQueue.setPaused()` stops dequeuing and pauses
the tween in flight; the simulation keeps stepping.

Two rules make that safe:

- **Pause must not bump the queue's serial.** The active tween's `finished`
  connection is bound to the serial it was activated with, and that connection
  is the only one that fires — reconnecting under a new serial does not work.
  Invalidating it leaves every resumed action to be completed by watchdog
  recovery instead: three-quarters of a second late, with a spurious "stalled
  action" warning each time. Because the serial deliberately survives a pause,
  the `timedOut and _paused` guard in `_complete()` is what stops the
  pre-pause watchdog from finalizing a frame the player froze on purpose. On
  resume a fresh watchdog is armed under the same serial, so a tween that can
  never finish — one killed from outside, which still reports `is_valid()` —
  is still recovered rather than wedging the queue.
- **The simulation runs ahead under a bound.** `_advance_battle()` yields while
  the queue holds `RUN_AHEAD_LIMIT` actions, so a paused queue cannot run the
  battle to its end and overflow `MAX_QUEUED_ACTIONS`, whose `recover()` would
  discard precisely the animations the player paused to watch. The turn timer
  keeps ticking and re-checks rather than stopping, so playback resumes as soon
  as there is room instead of waiting for the queue to reach zero.

A player turn opens only on a caught-up, unpaused board. When the simulation
reaches a player-controlled unit while playback is behind, the turn is held in
`_pending_player_turn_id` and started from the queue's `drained` signal.

## Frame budget: deliberation must not block presentation

**A turn may take as long as it needs. A frame may not.** These are different
budgets and the distinction is the whole point of this section: a unit that
appears to think for a moment before acting is fine, and arguably good. A
renderer, camera, or animation that stutters while it thinks is not, and no
amount of AI quality buys it back.

The two are currently coupled. `_advance_battle()` runs on the turn timer, on
the main thread, and calls `sim.executeTurn()` — which calls
`brain.decideTurn()` inline. Deliberation therefore happens *inside* a frame,
and the frame is as long as the decision.

Measured on a real CPU vs CPU battle (`Battle25D`, seed 42, headless, so these
numbers exclude render cost and understate a real window):

| | idle frames | frames carrying a turn |
|---|---|---|
| median | 6.9 ms | 24 ms at 1 turn/s, 31 ms at 8 turns/s |
| max | — | 46 ms at 1 turn/s, 75 ms at 8 turns/s |

Every AI turn overruns the 16.7 ms budget for 60fps, by 1.5x to 4.5x. At the
higher playback speeds the speed slider offers, 4.1% of all frames miss 60fps
and 1.9% miss even 30fps. This scales directly with AI complexity: candidate
enumeration grew by roughly an order of magnitude when AI targeting became
positional, and the frame cost grew with it.

### The seam that makes this fixable

Deliberation and mutation are already separate operations, and deliberation is
already side-effect free:

- `brain.decideTurn(id)` is a pure query. It reads `BattleState` and returns a
  `BattleCommand`. Verified directly: six consecutive calls change nothing in
  `state.history`, monster HP, positions, cooldowns, Resonance bars, or active
  effects, consume no RNG (`state.rng.state` is untouched), emit no events, and
  return the same decision every time. The `is_simulation` flag that damage
  estimation threads through `PassiveSkillResolver` exists precisely to keep it
  that way.
- `sim.executeCommand(id, command, source)` is the mutating half, and is the
  only half that must run on the main thread.

So the work can move off the frame without touching determinism: the RNG is
never drawn during deliberation, so moving *when* a decision is computed cannot
change *what* it computes, and the replay ledger records the resulting command
either way.

### Rules for anything that makes the AI think harder

1. **Never add work to the frame that scales with AI complexity.** If a new
   heuristic, deeper search, or larger candidate set lands on the main thread
   inside `_advance_battle()`, it is a rendering regression regardless of how
   good the decisions get.
2. **Keep `decideTurn()` pure.** No state mutation, no RNG draws, no event
   emission, no history writes. This is not a style preference — it is the
   precondition for ever computing a decision off the main thread or across
   several frames, and it is cheap to verify (see the probe described above).
3. **Measure frames, not turns.** A profile that reports milliseconds per
   decision does not tell you whether the game stutters. Sample the wall-clock
   gap between consecutive frames during a real battle and correlate the spikes
   with turn starts.
4. **Deliberation may be deferred; resolution may not be reordered.** Whatever
   scheme computes a decision early or in the background, the command must
   still be applied through `executeCommand()` on the main thread, in turn
   order, so history and replay are unchanged.

### Intended direction, not yet built

Compute the decision for the next actor off the frame — a `WorkerThreadPool`
task or a time-sliced evaluator — and apply the returned `BattleCommand` on the
main thread when it is ready. The window between turns is safe for a reader,
because `_advance_battle()` is the only thing that mutates simulation state and
it is not running during that window; the visual queue in the meantime only
animates already-recorded events. This is recorded in `BACKLOG_CRITICAL.md`; it
is a real architectural change and should be planned, not slipped in.

## Determinism, replay, and restoration

- All gameplay randomness flows through `BattleState.rng`.
- Equal-speed turn ties use deterministic monster ID ordering.
- Schema version 5 records map revision, height, level, jump, base/growth fields, resolved stats, family, ascension parent, Resonance bars, and Luck; version 2 migrates to height 0, level 1, and jump 1.
- `BattleStateSerializer` produces and restores JSON-safe state, including RNG,
  IDs, board layers, rosters, effects, history, and monsters.
- `BattleSimulator.createReplaySnapshot()` includes setup, initial/current state,
  pending turn order, brain classes, and the controller-neutral command ledger.
- Replay snapshots are version 5, which makes command `target_pos` canonical.
  Versions 2-4 derive it from the recorded `target_id` immediately before each
  legacy command executes; version 4 introduced `order`, while versions 2-3
  still default it to `move_first`.
- `BattleReplayRunner` reconstructs a battle from setup and replays recorded CPU
  and player commands through normal validation/execution.
- `restoreReplaySnapshot()` restores current state and rebuilds resolvers,
  brains, events, and the pending turn queue for continuation.
- Simulation never writes diagnostic files. Tools and presentation decide when
  to persist output.

## Safe extension rules

- Add content in reference data and teach a general resolver only when the
  existing effect vocabulary cannot express it.
- Keep JSON file/parse/shape/index handling in JsonCatalogLoader; domain wrappers
  own schema coercion and commit catalog state only after full validation.
- Author monster combat and movement values only inside the STATS dictionary;
  runtime serialization remains a separate resolved-state contract.
- Add state fields together with JSON serialization, restoration, and
  deterministic verification.
- Add movement variants through `BattleState`/`MovementResolver` so all position
  mirrors stay synchronized.
- Add presentation behavior through events or the adapter; never mutate state
  from an animation callback.
- Keep CPU deliberation free of state mutation, RNG draws, and event emission,
  and keep work that scales with AI complexity off the frame — see "Frame
  budget: deliberation must not block presentation".
- Preserve `success` versus `resolved` when adding reactions or action types.
- Add or change events by updating `BattleEvents`, `IBattleVisualAdapter`, every
  active adapter, and focused event-contract checks together.

## Single runtime

`project.godot` launches `scenes/Battle25D.tscn`, which uses the canonical
presentation controller. This is the only battle runtime: the earlier
rollback scene and its board/camera/input scripts were removed once the
current runtime covered their behavior, and `git log` is their archive. A
scene must never bind a second battle runtime alongside this one.
