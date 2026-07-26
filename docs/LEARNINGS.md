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
| Presentation event sequencing or animation cancellation | Visual action playback |
| SubViewports, render scaling, shaders, or picking | Render isolation |

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
  board, `monsterPositions`, and `Monster.position` together. Fast consecutive
  commands can reuse a vacated tile before its previous visual tween finishes.
- **Reusable rule:** One live entity per tile is a hard invariant. Assert the
  board/position bijection after mutations, restore, and replay. Views serialize
  event-time position snapshots; they must not synchronize a follow-up action
  from newer authoritative state while an older position animation is playing.
- **Review when:** adding movement, forced displacement, teleportation, load,
  replay playback, or animation timing changes.

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

### Height is a shared edge rule

- **Verified observation:** Passing only a destination into BFS/A* cannot decide
  jump legality because traversal depends on both the current and next heights.
- **Reusable rule:** Search callbacks receive `(current, next)` and delegate to
  `MovementResolver.canTraverse()`; previews, validation, and CPU planning must
  not reimplement height edges.
- **Review when:** adding terrain costs, special traversal, teleportation, or
  moving/destructible surfaces.
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

## Visual action playback

### Follow-up actions must not resynchronize active movement

- **Verified observation:** Starting the attack bump called the global visual
  occupancy synchronizer, which killed the active movement tween and snapped the
  attacker to its newer authoritative tile before the move animation completed.
- **Reusable rule:** Queue movement, targeting, action, and defeat presentation
  in event order using coordinates and text captured when the event is emitted.
  Simulation never waits for this queue. Bound every tween with an idempotent
  completion callback plus a watchdog, and invalidate both on adapter disposal.
- **Review when:** adding a visual event, changing action timing, accelerating
  simulation playback, replay visualization, or implementing skip/fast-forward.

## Render isolation

### Standalone SubViewports need explicit display and input mapping

- **Verified observation:** A standalone `SubViewport` does not display itself
  or automatically receive main-viewport input. Its isolated 3D world also owns
  the physics space used by picking.
- **Reusable rule:** Display its `ViewportTexture` explicitly, keep native UI
  outside the low-resolution viewport, and map coordinates through the actual
  aspect-preserving display rectangle. Forward camera input deliberately and
  query physics through the isolated world root. A shader that writes
  POSITION must assign a valid clip-space value on every path.
- **Verified observation:** Per-mesh vertex coordinates restart for every part
  of a procedural model, so a local-coordinate color split repeats separately
  across the head, stem, collar, and base.
- **Reusable rule:** Multi-part visual effects that represent one model must use
  a shared model-space transform and shared complete-model bounds. Per-instance
  shader transforms preserve that space while materials remain shared.
- **Verified observation:** Affine UV interpolation has no visible result on
  flat-colored geometry under an orthographic camera because there is neither
  textured UV detail nor perspective depth to distort.
- **Reusable rule:** Do not present an affine/perspective choice as a useful
  player-facing control until the active content visibly demonstrates it. Use
  directly observable controls such as upscale filtering for current content.
- **Verified observation:** Screen-space vertex snapping also ran during the
  directional-light shadow pass and produced broad diagonal bands across the
  battlefield.
- **Reusable rule:** Keep real-time shadow casting disabled for snapped world
  materials unless a separate shadow-safe pass is implemented and visually
  verified.
- **Verified observation:** Rendering preset values can be edited independently
  during battle, so the originating preset name no longer describes the active
  configuration after the first manual change.
- **Reusable rule:** Treat presets as complete recipes and immediately label any
  manual rendering change as `Custom`; persist the complete Custom state. Keep
  `None` as the neutral reset baseline and migrate legacy preset identifiers.
- **Verified observation:** A strict parity checker with one coordinated light
  tone and one dark tone makes terrain categories visibly tile-based; mottled
  multi-step variation read as accidental inconsistency instead.
- **Reusable rule:** Derive presentation-only terrain alternation from `(x+y)%2`
  and a terrain base color. Keep it outside simulation RNG so grass, water, and
  future sand/rock/lava palettes inherit the same deterministic two-tone rule.
- **Verified observation:** CPU estimates made from a candidate destination can
  disagree with resolution if elevation arithmetic reads the actor's current
  state position instead of the proposed command position.
- **Reusable rule:** Pure planning queries accept explicit source positions and
  share the same damage/height arithmetic as resolution; never mutate state to
  simulate a candidate.
- **Review when:** changing viewport resolution, letterboxing, camera controls,
  mouse picking, world shaders, shadows, or the UI/world composition.
