# Durable Engineering Learnings

Purpose: retain verified findings that prevent repeated investigation. This is
not a session log, policy copy, or backlog.

## When to consult

| Before working on… | Read… |
|---|---|
| Determinism, replay, RNG, or identity | Deterministic state |
| Commands, action results, or reactive passives | Command acceptance and resolution |
| Turn order, movement, or pathfinding | Ordering and pathing |
| Godot classes, loads, or factory paths | GDScript loading |
| Console maps or diagnostic output | Text rendering |
| Godot/GUT execution on Windows | Test and process behavior |
| Cursor ownership or tile intent | Cursor event semantics |

When adding a learning, include the verified observation, the reusable rule,
and a review trigger. Move commands to [`DEVELOPMENT.md`](./DEVELOPMENT.md),
actionable future work to [`BACKLOG.md`](./BACKLOG.md), and architectural truth
to [`ARCHITECTURE.md`](./ARCHITECTURE.md).

## Deterministic state

### Stable identity and RNG

- **Verified observation:** Runtime entities use project-owned `uniqueID`
  values, and battle randomness is routed through `BattleState.rng`.
- **Reusable rule:** Never derive gameplay identity from `get_instance_id()` or
  use global RNG in simulation. Persist the seed and command/event inputs needed
  to reproduce a battle.
- **Review when:** adding an entity type, random outcome, snapshot field, or
  replay continuation path.

### Coordinated position mirrors

- **Verified observation:** `BattleState.moveMonsterTo()` updates the occupancy
  board, `monsterPositions`, and `Monster.position` together.
- **Reusable rule:** Move entities only through the state/resolver contract so
  all three representations stay synchronized; views react to emitted events.
- **Review when:** adding movement, forced displacement, teleportation, or load.

## Command acceptance and resolution

### A valid command can still fizzle during resolution

- **Verified observation:** A command can pass authoritative target/range
  validation, then a reactive passive can defeat or invalidate its actor before
  the requested action resolves.
- **Reusable rule:** Treat validation acceptance and action resolution as
  separate outcomes. Record an accepted command once with `success=true`; use
  `resolved` and `actionResult` for a later fizzle. Do not relabel it as rejected
  or generate a fallback command.
- **Review when:** adding reactions, interrupts, counterattacks, movement
  triggers, new action types, replay logic, or network command handling.

## Ordering and pathing

### Stable turn ties

- **Verified observation:** Speed-only sorting leaves equal-speed ordering
  dependent on insertion details.
- **Reusable rule:** Sort by speed first and deterministic `uniqueID` second so
  snapshots and replays agree across runs.
- **Review when:** changing initiative, haste/slow, summons, or queue rebuilds.

### Grid heuristics

- **Verified observation:** Current orthogonal grid pathing uses Manhattan
  distance and dictionary-backed open/closed membership.
- **Reusable rule:** Keep heuristic and movement topology aligned. Re-evaluate
  the heuristic before enabling diagonals, variable edge costs, or portals.
- **Review when:** changing allowed movement directions or terrain costs.

## GDScript loading

### Global names do not repair invalid paths

- **Verified observation:** `class_name` exposes a global type name, while
  `preload()` still resolves its explicit resource path independently.
- **Reusable rule:** Prefer one mechanism intentionally and keep every explicit
  resource path valid. Never assume a global class makes a bad preload safe.
- **Review when:** moving scripts, changing factory dependencies, or exporting.

### Pure classes can own custom signals

- **Verified observation:** A non-`Node` GDScript class can declare and emit
  custom signals in memory.
- **Reusable rule:** `BattleEvents` can stay headless; scene-tree lifecycle
  behavior belongs in presentation code.
- **Review when:** adding event ownership, connection lifetimes, or adapters.

## Text rendering

### Terminal width is not portable for emoji

- **Verified observation:** Emoji and box-drawing glyphs occupy inconsistent
  terminal widths across fonts and Windows hosts.
- **Reusable rule:** Use single-column ASCII symbols for alignment-sensitive
  tactical grids; put descriptive names in a separate legend.
- **Review when:** changing console board output or CI diagnostics.

## Test and process behavior

### GUT is an isolated failure boundary

- **Verified observation:** Godot 4.4 starts and imports a fresh-cache project,
  but GUT 9.4’s supported CLI reproducibly exits with Windows access violation
  `0xC0000005` before useful stdout/stderr, including compatibility rendering,
  dummy audio, isolated user data, and a populated global-class cache.
- **Reusable rule:** Do not run GUT routinely. Use focused headless checks; only
  re-evaluate through `run_headless_tests.ps1 -ForceGut` with the shadow project
  and watchdog described in [`DEVELOPMENT.md`](./DEVELOPMENT.md).
- **Review when:** Godot, GUT, Windows, or the runner configuration changes.

### Bound native diagnostics

- **Verified observation:** Direct PowerShell invocation of the bundled
  non-console Godot binary returned before its detached process completed, so a
  stale exit code hid parser errors and left the failed `SceneTree` alive.
- **Reusable rule:** Use `scripts/run_godot_check.ps1`, a bounded waited process,
  a fresh captured log, and an expected success marker. On timeout, terminate
  only the exact process object launched by the check.
- **Review when:** the execution host or sandbox tooling changes.

## Cursor event semantics

### Events communicate discrete tactical intent

- **Verified observation:** Following a moving model caused the cursor to land on
  transient or stale tiles when movement and action events overlapped.
- **Reusable rule:** Cursor events describe stable grid intent: movement points
  to the destination; attacks, spells, and heals point to the action target.
  Cursor ownership prevents older AI activity from overriding player intent.
- **Review when:** implementing player control, queued animations, cancellation,
  keyboard navigation, or replay playback.
