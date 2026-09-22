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
| Scene orchestration | `src/systems/hex_battle/HexBattleController.gd` | Godot lifecycle, side-turn pacing, input routing, adapter wiring |
| Unit action | `src/systems/hex_battle/HexBattleMemberTurn.gd` | One selected unit's pending move, action, cursor, and undo submission |

Godot value types such as `Vector2i`, `Dictionary`, and
`RandomNumberGenerator` are valid in the headless layer. Scene nodes, cameras,
controls, and visual resources are not.

For the per-directory breakdown — public entry points, allowed and forbidden
dependencies, and a "where to make a change" table — see
[`MODULE_MAP.md`](./MODULE_MAP.md). This section stays the authority on what
the layers *mean*; the map is the routing detail.

## Hex battle ownership

The active code still implements the square baseline described below. The hex
migration keeps `BattleSimulator` as the only canonical runtime and
`BattleState` as its authoritative state; it changes their topology and
activation contracts rather than adding a parallel maintained simulator. The
approved player-facing rules are in [`GAME_DESIGN.md`](./GAME_DESIGN.md), under
"Approved initial hex battle target."

The planned ownership split is:

- Headless board code owns offset/axial conversion, six-neighbour ordering, hex
  distance, footprints, weighted traversal, zone-of-control termination, and
  symmetric supercover line of sight. Simulation and AI consume the same query
  surfaces. Neither imports editor or presentation code.
- Setup data owns the selected tactical map, deterministic party identities,
  each party's commander and members, controllers, and deployment. A map owns
  valid cells, terrain, height, and source identity. Presentation scenes are not
  gameplay map definitions.
- `BattleState` owns party membership and withdrawal state, the round's ordered
  side queue, the active side, unit eligibility/spent state, pending unit moves,
  board layers, occupancy, and every value needed for deterministic save and replay.
- `BattleSimulator` owns side-turn transitions and is the only writer of that
  state. It orders surviving teams by deterministic team ID; accepts free unit
  selection; consumes Wait and End turn; advances unit-owned timing once when
  that unit is spent; resolves forced party withdrawal; and checks victory
  between fully resolved unit actions.
- Player controllers and CPU brains select only from simulator-reported ready
  units and submit the same typed commands. They never maintain a competing
  side queue or advance status, cooldown, passive, withdrawal, or victory state.
- Presentation observes `BattleEvents` or `IBattleVisualAdapter`, submits intent,
  and renders authoritative eligibility, paths, footprints, side progress, and
  outcomes. Picking, overlays, cameras, animation callbacks, and UI controls do
  not mutate `BattleState`.
- Tactical authoring may produce both a visual scene and a headless map resource,
  tied by source identity and geometry metadata. Runtime simulation loads only
  the headless product through its factory boundary; it never reads the editor.

### Hex battle HUD contract

The HUD reads battle state and never writes it. Four owners keep that true:

- `HexBattleMemberInput` owns what a member may do and why not. Its command
  model gives every command `enabled`, a `hint`, and a `reason` that is empty
  exactly when the command is enabled. Spells arrive nested under a `magic`
  entry, which is a grouping for the rail, not a command; `chooseCommand` only
  ever sees the `spell:<set>:<index>` ids.
- `HexBattleController` owns input routing. The STATUS sheet takes input first
  while it is open, then the camera, then inspection (hover and click on units,
  in every phase), then the member turn. While a command is being aimed a left
  click stays that aim's confirm and never inspects.
- `HexBattleVisualAdapter` owns the unit cues drawn on the board -- the hover
  outline and the selection ring -- and picks units against where their models
  are drawn, since playback runs behind the simulation. It also builds models
  for units already deployed when the battle opens, because a hex state arrives
  populated and emits no spawn events for them.
- `HexBattleHud` owns which unit is selected (presentation state, by
  `uniqueID`) and composes the windows. Everything the inspection surfaces show
  comes through `HexUnitFacts`, the one presentation file that reads a unit out
  of `BattleState`. STATUS and the placeholder Item plate are HUD-local; neither
  is a battle command.

### Shared hex lattice

`src/board/HexGrid.gd` is the headless authority for odd-column offset/axial
conversion, the deterministic E/NE/NW/W/SW/SE neighbour order, hex distance,
and row-major hex discs. Its public coordinates remain `Vector2i` offset cells
so `Matrix` storage stays rectangular. Axial coordinates are an internal math
space; callers do not repeat column-parity arithmetic.

`WorldMapHexGrid` delegates those operations to `HexGrid` and retains only the
presentation geometry needed by authoring: cell centres, world picking and cube
rounding, lattice extents, and exact-square fitting. This wrapper preserves the
editor's established API and dimensions while allowing battle simulation, AI,
and future nonvisual tools to depend on the lattice without importing editor
code.

### Hex battle map and scenario boundary

`BattleMapDefinition` is the headless tactical map contract. Its rectangular
`boardSize` is storage capacity; `validCells()` and `containsCell()` define the
actual odd-column offset board, including holes. Terrain, elevation, movement
cost, and line-of-sight state are independent of both the valid-cell mask and
live occupancy. The board-view contract is `boardSize`, `visualScenePath`,
row-major `validCells()`, `containsCell()`, `heightAt()`, `cellWidth`,
`cellHeight`, and `heightStep`.

`BattleMapFactory` accepts version 1, `hex_flat`, `odd_q_offset`, single-surface
maps. Every map carries source ID, revision, fingerprint, and visual scene path.
Only explicitly headless technical fixtures may omit the visual scene. Stacked
standable surfaces fail at this boundary instead of being flattened into one
cell.

`BattleScenario` ties one exact map revision and source fingerprint to
deterministic commander-led parties. Each member has a unique gameplay ID,
monster reference, level, and valid non-overlapping deployment cell. Party and
member counts are data-driven; the square setup's four-member roster constant
does not apply to this path.

`BattleSetupFactory.createHexState()` materializes the validated scenario into
`BattleState`, including dense compatibility matrices, the valid-cell map,
party indexes, team-roster projection, and explicitly identified monsters.
`BattleSimulator.configureHexState()` installs that state in the canonical
runtime, rebuilds resolvers and brains, and captures the ruleset-scoped content
fingerprint. Authoritative hex spatial execution remains a separate resolver
boundary; it does not change activation ownership.

The current square battle is preserved as a frozen, independently runnable
reference with its own source snapshot, resources, manifest, and launch steps.
The active project does not load it and exposes no square/hex runtime toggle.

### Side turns and unit actions

The simulator opens a round by freezing surviving teams in ascending team-ID
order. `BattleState.sideOrder` records that complete round order while
`pendingSideIDs` contains sides not yet opened. `activeSideID` remains set while
`currentMonsterID` changes freely among ready units.

`selectUnit()` checks team membership, life, withdrawal, board presence, and
the side turn's spent set before changing `currentMonsterID`. A move-only phase
is stored under `pendingUnitTurns`; selecting another unit neither spends nor
locks it. The pending unit may be selected again and its move undone while its
origin remains free. Casting after moving and moving after acting are rejected.
A resolved attack, spell, item action, or Wait records its accepted and resolved
outcome, fires end-turn passives, advances only that unit's status and cooldown
clocks, and marks it spent. Exhausting readiness closes the side once.
`endSideTurn()` submits ordinary Wait commands for all remaining ready units in
unit-ID order, sharing the same timing and history path.

After every unit timing step, the simulator reconciles commander defeat.
Surviving members of that commander's party leave occupancy and become
withdrawn without losing hit points. Victory uses surviving commanders; loss of
every team's last commander in one fully resolved step records outcome `0` as a
draw. The next unit cannot be selected after an outcome is recorded.

Side-turn state may be captured at any operation boundary, including with a
selected unit or several moved-but-unspent units. Pending origins and paths are
serialized, and replay reproduces selection, movement, undo, and action events
in their original interleaving order.
Restoring a side turn replaces the simulator's event bus as well as its state,
so presentation is told through `timeline_restored` on the bus it is still
listening to, and rebuilds against the restored board rather than unwinding what
it had drawn. The simulator also retains one complete checkpoint after each side opens.
Its technical `restoreSideTurn()` replaces the canonical state between
operations, increments timeline generation, and leaves an immutable branch
entry in the simulator's outer operation ledger. Replay checks a semantic
fingerprint after each accepted operation. Detached one-command forecasts use
the same resolvers on cloned state with a bounded rules-history suffix; see
[Nogg AI architecture](./AI_ARCHITECTURE.md) for RNG modes and retention limits.
Hex battle is the sole maintained product path; fixes and upgrades do not flow
back into the reference. This archive boundary avoids a second runtime family
while keeping the old behaviour available for comparison.

Until the migration lands, every section below remains a description of the
current square implementation. Planned hex terminology must not be read as an
already available state or command field.

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

### Invariants between steps

`BattleInvariants.violations(state)` answers what must be true of a battle
between two resolved steps: one unit per cell with the board layer and the
position lookup agreeing in both directions, nobody standing on unwalkable
ground, hitpoints inside their own range, the living and present holding a cell
while the dead and the withdrawn hold none, one side open at a time in
ascending team order, a spent unit holding no unfinished turn, magic never
resolved after a move, a withdrawn party taking its whole membership with it,
effects belonging to registered units with a non-negative duration, and an
outcome that names a team that fought.

The rules come from `GAME_DESIGN.md`, so a violation is a bug in the simulator
or in that document — never a reason to relax the check. It returns every
violation it finds rather than stopping at the first, and it is a pure read:
no events, no RNG draw, no mutation. That is what lets a run with checks on
record exactly what a run with them off records.

`BattleSimulator.setInvariantChecks(true)` makes the simulator call it after
every step that can change state — a move, an undo, an action, a unit
finishing, a side opening or closing. It is **off by default**: the interactive
game would pay a board and roster walk per step for a report only a log would
read. The headless runners turn it on, because there a violation is the only
reader a battle has. Where each kind of run draws the line:

- `run_battle.gd` writes both its outputs, then fails the run and names every
  violation. The record stays on disk as the evidence.
- `run_championship.gd` stores the offending battle's line, flushes, and stops
  the run. Every finished battle before it keeps its place in the corpus; what
  it refuses to do is produce a thousand more records from a state the rules
  call impossible.

`BattleState.assertValidOccupancy()` predates this and stays: it guards the
occupancy family inside `moveMonsterTo()` itself with `assert()`, which the
release build strips and which stops at the first failure.
`scripts/battle/checks/probe_invariants.gd` proves the checker both ways — a
whole battle violating nothing, and each invariant family reported on a state
broken on purpose.

## Setup and battle construction

`HexBattle.tscn` creates the animated sky and setup overlay first. It does not
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
   `HexBattleVisualAdapter` creates a procedural fallback otherwise.
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

`order` is now always `move_first`. Acting spends a unit, so act-then-move is
not a legal command. A spell command with a non-empty move path is rejected as
`spell_after_move`; attacks may validate from the move destination.

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

A unit holds at most one pending movement phase before its spending action.
`executeMovePhase()`, `executeActionPhase()`, and `finishTurn()` resolve those
steps incrementally, while `executeCommand()` remains the atomic entry point
for CPU brains. Pending state is per unit, so several move-only units may be
interleaved during one side turn.

History records `unit_selected`, `move_phase`, `undo_move`, and `unit_action`
separately in event order. The `unit_action` result retains the aggregate
command for records, while replay drives the same operations in their original
interleaving. `finishTurn()` is the sole caller of
`PassiveSkillResolver.ON_TURN_END`, which fires exactly once when the action
spends that unit.

`undoMovePhase()` rewinds movement to the tile that unit's pending action began on. It is legal
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
surface, obstacle, and intervening-unit tops. Which cells that ray touches is
pure geometry, cached per axial displacement and translated; the heights,
blockers and occupants it is compared against are asked fresh on every query.
The touched set is symmetric under reversal and invariant under translation,
but its enumeration order is only deterministic, not symmetric. `DirectDamageRules` owns the
110/100/90-percent elevation arithmetic used by real attacks, spells, and pure
CPU estimates; healing, ticks, and reflected damage do not call it.

Legal actions are enumerated from these same resolvers, never restated in the
AI: a rules change reaches the CPU without anyone copying it across. What is
legal, what a policy narrows that to, and how it ranks what survives are three
separate interfaces. `BattleSimulator.beginSideDeliberation()` is the only way a
CPU side decision opens, so which named policy is playing is always recorded
rather than implied by whichever class a caller happened to construct.

CPU actor selection, candidate pruning, role evaluation, spatial query use and
interactive scheduling are documented in [Nogg AI architecture](./AI_ARCHITECTURE.md).
That reference separates current behavior from the intended rework contracts.
Simulation retains ownership of legality and resolution.

## Player interaction and cursor

`HexBattleMemberTurn` owns one player-controlled member turn — its phase, the command
menu model, and submission through the incremental turn API.
`HexBattleController` routes input to it and reacts to its
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
tile metadata. `HexBattleController` raycasts the combined tile/unit
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
`BattleMeshFactory.createModelBase()`. The base is deliberately darker and more
metallic than any creature body — a matte body defaults to roughness 1.0,
metallic 0.0, and the base is always polished and metallic in comparison, at
every team colour — so it never reads as part of the monster, and it is split
into
`ascensionTier + 1` stacked layers — one for a basic monster, one more per
ascension. `MonsterReferences.ascensionTier()` walks the catalog's
`ASCENDS_FROM` chain and is the single tier source, so setup, replay
reconstruction, and board refresh all build the same stack, placeholder visuals
included. The layers share a fixed `BASE_TOTAL_HEIGHT` budget and get thinner as
the stack grows, and each layer up the stack is also more metallic and less
rough than the one below it, so ascension changes what a base *reads* as
without changing model height, footprint, or origin.

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
  `HexBattleVisualAdapter` implements this one, and `HexBattleMemberTurn` holds it
  as its adapter type.

Implementations inherit `animation_queue_drained` and must not redeclare it: a
redeclared signal is a distinct signal, so a controller connected through the
port would never be notified. `HexBattleVisualAdapter` copies position-bearing event data into typed
`VisualAction` snapshots in a FIFO queue, so movement, targeting, attacks,
spells, heals, defeat, and victory play in event order without blocking the
simulation. The queue clones each snapshot at enqueue time, preventing later
producer mutations from changing delayed playback.
`spell_cast_started` carries the ordered target `uniqueID` values plus the
radius and area shape resolved from the live `Spell` instance. This is
intentionally event data, not a presentation catalog lookup: transient radius
modifiers affect targeting and VFX together even though immutable reference
data stays unchanged. The event contains no presentation types. At enqueue
time, `HexBattleVisualAdapter` converts its board coordinates and IDs into a typed
`VfxCastContext`: source and impact world positions, target world positions,
body-only target bounds, and an optional presentation-surface path sampled
between source and impact. The adapter snapshots that path from board terrain
at enqueue time; delayed effects never query a later scene-tree or physics
state to decide where ground-bound geometry belongs. Missing target visuals use
a standard authored body box at the event impact, keeping delayed target-bound
effects safe.
Playback never re-reads a later monster position to start a queued action.
Movement begins at the model's current rendered transform and animates every
horizontal and vertical step through a bounded jump arc. Each tween has a
bounded watchdog recovery, while disposal invalidates callbacks and clears the
queue. Presentation may lag behind authoritative state but cannot delay or
rewrite simulation results.

An attack, spell hit, or heal carries its numeric amount on the `VisualAction`
snapshot (`damage_number`/`is_heal_number`), and `DamageNumberBillboard.spawn()`
draws it above the affected unit at playback time — not at enqueue time, since
the queue can be several actions behind the simulation. Its full visible
lifetime (pop, hold, fade) is folded into that action's hold via the same
`_activateScaled()` mechanism `SpellCastAura` uses, so the queue does not
advance to the next action while a number is still on screen. Because the
queue plays exactly one action at a time, this also means two numbers from one
multi-target spell are never visible simultaneously — each fully completes
before the next target's action begins.

The damage number is a native screen-space Control in NoggTheme.WORLD_EFFECT_LAYER (9): above the world and default CRT pass, below both UI CanvasLayers. The camera projection is mapped through RetroRenderController's aspect-preserving display rectangle, so its menu-font-sized glyphs stay aligned with the affected model across letterboxing and low-resolution render presets. Each digit is composed from four one-pixel black offset copies and one white centre copy, then pumps once and disappears without moving across the screen.

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

Decision latency and frame pacing are separate budgets. The current controller
advances deterministic planning slices on the presentation thread and applies
completed commands through the simulator. Earlier worker-based descriptions and
historical inline-turn timings are not the current execution model.

[Nogg AI architecture](./AI_ARCHITECTURE.md) owns the scheduling, purity,
work-budget and stale-proposal contracts. Measure interactive frame gaps as well
as decision time; a bounded number of slices cannot hide an unbounded operation
inside one slice. Presentation observes ordered simulation events and never
reorders resolution to accommodate planning or playback.

## Determinism, replay, and restoration

- All gameplay randomness flows through `BattleState.rng`.
- Side order uses ascending deterministic team ID; unit selection order belongs
  to the player or CPU policy rather than SPD initiative.
- Legacy square schema version 5 records map revision, height, level, jump,
  base/growth fields, resolved stats, family, ascension parent, Resonance bars,
  and Luck; versions 2-5 remain readable only for internal square-state
  compatibility while that code is retired.
- Hex state schema version 8 records `hex_flat`, `odd_q_offset`,
  `hex_side_turn_v1`, exact map/scenario identity, a scoped content fingerprint,
  parties, frozen and pending side order, active side, selected unit, spent and
  withdrawn identities, pending per-unit moves, side-turn phase/count, battle
  outcome, movement costs and mutable spell/passive instance data. Version 7
  state remains readable with catalog-restored abilities; retired version 6
  party-activation state fails loudly.
- `BattleStateSerializer` produces and restores JSON-safe state, including RNG,
  IDs, board layers, rosters, effects, history and monsters. RNG state is decimal
  text; large integers use a tagged decimal encoding for lossless disk restore.
  Runtime ability/loadout changes are stored in version 8. See the mutation
  boundary and remaining limits in [Nogg AI architecture](./AI_ARCHITECTURE.md).
- `BattleSimulator.createReplaySnapshot()` includes setup, initial/current state,
  brain classes, and explicit side-start, unit-selection, movement, undo, and
  unit-action operations. Each action carries both acceptance and resolution.
- Active-project replay snapshots are hex version 8. They identify topology,
  coordinate convention, ruleset, scenario/map revisions, map-source
  fingerprint, and a canonical fingerprint of the authored map, party, monster,
  spell, and passive catalogs. Version 7 replay envelopes are unsupported;
  square replay versions 2-5 return
  `square_reference_required`; retired party-activation version 6 returns
  `party_activation_replay_unsupported`.
- `BattleReplayRunner` reconstructs current setup/catalog identity before it
  executes anything, replays side starts, selection, moves, undo, and actions
  through their normal operations, compares recorded command outcomes, then
  compares final state, RNG, ID allocation, lifecycle, and material event
  outcomes.
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

`project.godot` launches `scenes/battle/HexBattle.tscn`, which uses the canonical
presentation controller. This is the only battle runtime: the earlier
rollback scene and its board/camera/input scripts were removed once the
current runtime covered their behavior, and `git log` is their archive. A
scene must never bind a second battle runtime alongside this one.
