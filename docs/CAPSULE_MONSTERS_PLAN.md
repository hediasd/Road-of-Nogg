# Capsule Monsters Implementation Plan

Status: proposed for approval on 2026-07-25. This document supersedes the
original architectural draft. It is an implementation plan, not a promise that
all future meta-game ideas ship in the first playable release.

Implementation status: the optional PS1 rendering subsection of Phase 6 was
completed on 2026-07-25. Elevation, movement, combat, stat, AI, capsule visual,
and team-color work remains unstarted.

## Outcome

Build a deterministic, replayable tactical battle layer with meaningful
terrain elevation, height-aware movement and combat, stronger CPU decisions,
and an optional world-only PS1 presentation mode. Preserve the current
controller-neutral command pipeline and keep presentation code unable to alter
battle rules.

The work is complete only when CPU and player commands use the same elevation
rules, saved battles replay identically, every supported map remains playable,
and the visual mode can be disabled without changing simulation results.

## Decisions for the first slice

| Topic | Decision |
|---|---|
| Grid coordinates | Continue using `Vector2i(x, y)`; call the third dimension `height` or `elevation`. Godot presentation maps this to world Y. |
| Height storage | Use the existing `BattleState.heightBoard`; do not add another board or modify `Matrix` for this purpose. |
| Height unit | Integer elevation steps in the inclusive range 0 through 8. Existing maps default every tile to height 0. |
| Jump | Monsters receive `jump = 1` by default. Flying and water-walking are separate future movement capabilities. |
| LoS geometry | Unit eye/target height is 1.0 above the surface; obstacle terrain adds 2.0 height; comparisons use epsilon 0.001. |
| Movement cost | Every traversable cardinal step costs 1 in the first slice. Variable terrain cost is deferred. |
| Basic melee | Cardinal adjacency plus an absolute height difference no greater than 1. |
| Spell height reach | Add explicit `MAX_HEIGHT_DELTA`, defaulting to 1. `BYPASS_LOS` does not bypass height-range validation. |
| High ground | Direct damage receives +10% from higher ground and -10% from lower ground. Healing, status ticks, and reflected damage are unaffected. |
| Damage rounding | Apply elevation before target-side reduction using `floor((raw * percent + 50) / 100)`, where percent is 110, 100, or 90. |
| Obstacles | Trees, rocks, and walls may share the `TERRAIN_OBSTACLE` rule category, while visual/content identity remains separate. |
| Water and pits | Continue using the current unwalkable, non-LoS-blocking abyss rule. Specialized traversal is deferred. |
| Lethal AI choices | Use ordered outcome tiers, not a `+1000` magic constant. Winning and multi-kill outcomes outrank ordinary damage. |
| Team colors | Team 1 is blue and Team 2 is red, independent of whether either team is controlled by a player or CPU. |
| Retro rendering | Render the 3D world at low resolution, but keep UI at native resolution. The effect is optional and cannot affect picking or simulation. |
| Leveling | Level defaults to 1 and cannot change during a battle in the first slice. |
| Meta-game | Breeding, roulette, inventory, currencies, and individual stat modifiers are out of scope. |

Changing one of these decisions requires updating tests and this plan before
implementation continues.

## Architectural boundaries

The supported runtime is:

`BattleSetupConfig -> BattleSetupFactory -> BattleSimulator/BattleState`

`controller -> validated command -> resolver -> deterministic event history`

`battle events -> visual adapters/UI`

Rules belong in `src/battle_sim`, reusable searches belong in `src/algorithms`,
content defaults belong in `src/factories`, and visuals belong in
`src/presentation`. `src/board/BattleBoard.gd` is part of the legacy runtime and
must not become a second source of truth.

The following invariants apply throughout the project:

- `BattleState` remains headless and deterministic.
- One live entity per tile remains a hard invariant.
- Reachability previews, AI planning, command validation, and execution use the
  same movement and combat queries.
- AI estimates must be side-effect free and use the same arithmetic as actual
  resolution.
- Presentation may visualize height, trajectories, and teams but may not decide
  whether a command is legal.
- Every new state or command field has an explicit replay representation and
  backward-version policy.

## Data contracts

### Map elevation

Add an explicit `HEIGHTS` matrix and integer `REVISION` to each map reference.
The matrix must contain exactly `SIZE.y` rows and `SIZE.x` integer entries in the
supported 0-through-8 range. `MapFactory` validates and copies these values into
`BattleState.heightBoard`. Missing height data is accepted only for legacy map
definitions and means an all-zero matrix; a missing revision defaults to 1.

Keep `LAYOUT` responsible for terrain rule categories. Do not encode elevation
inside terrain characters: terrain and surface height are independent facts.
Deployment slots must be walkable, unoccupied, within bounds, and reachable
under the default jump rules unless a map deliberately declares isolated
starting areas.

### Monster and spell data

Add these monster fields:

- `level`, default 1;
- `jump`, default 1;
- immutable level-1 base values for HP, ATK, and DEF;
- nonnegative integer growth values for HP, ATK, and DEF, stored in hundredths
  per level.

Derived stat formula:

`stat = base + floor(growth_hundredths * (level - 1) / 100)`

SPD, MOVE, and JUMP do not scale in this slice. Current HP is initialized from
derived maximum HP at deployment. Because levels do not change during battle,
there is no mid-battle HP rescaling policy yet.

Add `MAX_HEIGHT_DELTA` to spell references. Later trajectory types such as
lobbed, beam, or homing attacks require a separate design; they must not be
inferred from `BYPASS_LOS`.

### Replay and restoration

Bump the state and replay schema when the new monster fields become persistent.
Snapshots record at least:

- rules/schema version;
- map name and map revision;
- height board;
- level and jump for each monster;
- derived and current combat stats;
- all command fields already required for deterministic replay.

Unsupported versions fail with a clear reason rather than silently interpreting
missing fields. During development, the one supported migration is version 2 to
the new version using height 0, level 1, and jump 1. Replay restoration validates
board occupancy, map dimensions, height values, and monster fields before
resuming.

## Phase 1: Elevation data and presentation

### Implementation

1. Extend `Map`, `MapReferences`, and `MapFactory` with validated height data.
2. Add `BattleState.getHeight(pos)` and a bounds-safe height-difference query.
3. Render each tile at world Y equal to its simulation height. Place monsters,
   cursors, tactical overlays, and selection bodies relative to the same surface.
4. Update camera framing so the highest supported tile does not clip.
5. Add a simple height indicator to movement/target inspection without exposing
   raw internal coordinates as the primary UI.

### Acceptance

- Existing maps are unchanged when all heights are zero.
- A test map containing at least three elevations renders tiles, models,
  cursors, overlays, and picking at matching heights.
- State serialization and JSON round trips preserve the complete height board.
- Camera reset and upper-model selection work from elevated tiles.

## Phase 2: Height-aware movement

### Implementation

1. Change BFS and A* adjacency callbacks to receive both the current and next
   position. Do not hide height logic in `Matrix`.
2. Centralize step legality in `MovementResolver.canTraverse(monsterID, from,
   to)`: cardinal adjacency, bounds, terrain, occupancy, and jump delta.
3. Make reachable-tile generation, pathfinding, `validateMovePath`, player
   previews, and AI paths call that same rule.
4. Keep step cost uniform. If variable costs are introduced later, replace BFS
   with a weighted search deliberately rather than layering costs onto BFS.
5. Animate vertical movement along a deterministic presentation arc while the
   simulator continues to record only grid coordinates.

### Acceptance

- A jump-1 monster can traverse height deltas 0 and 1 but not 2.
- Ascending and descending obey the same absolute-delta rule.
- A multi-step path is rejected if any intermediate edge exceeds jump.
- CPU reachability, player highlights, validation, and execution agree on every
  tested tile.
- An invalid height path cannot mutate state or enter command history.

## Phase 3: Height-aware combat and line of sight

### Implementation

1. Add shared range/height queries used by target previews, command validation,
   AI estimation, and execution.
2. Basic melee remains cardinal and receives the fixed height-delta limit.
3. Direct-damage spells validate their explicit height delta before LoS.
4. Replace the flat blocker callback with a height-aware supercover traversal
   that preserves the existing diagonal corner rule.
5. Define ray endpoints at tile surface plus the fixed 1.0 eye/target height.
   Clear terrain blocks when its surface exceeds the ray by epsilon 0.001.
   Obstacle terrain adds 2.0 blocker height. Source and target cells are excluded
   from intermediate blocking.
6. Centralize direct-damage calculation so basic attacks, spell damage lines,
   actual resolution, and AI estimates apply elevation and rounding identically.
7. Log the elevation modifier so players can understand the result.

### Acceptance

- Tests cover equal height, valid high ground, valid low ground, excessive
  vertical range, intervening ridge, obstacle top, diagonal corners, and
  `BYPASS_LOS` behavior.
- Multi-line spells apply the modifier exactly once per damage line.
- Healing, damage-over-time, and reflected damage receive no elevation modifier.
- Simulation estimates equal resolved damage when no reactive effect intervenes.
- Replay results remain byte-for-byte deterministic for a fixed rules version.

## Phase 4: Deterministic stat scaling

### Implementation

1. Extend monster references with explicit base and growth fields while retaining
   compatibility defaults for existing content.
2. Put derived-stat calculation in one pure helper used by construction,
   restoration, UI previews, and tests.
3. Serialize level, current HP, and the resolved battle stats needed to restore
   an in-progress battle exactly.
4. Display level and derived stats in setup and selection UI.
5. Do not add battle XP, level-up events, breeding modifiers, or equipment in
   this phase.

### Acceptance

- Level 1 equals the reference base exactly.
- Boundary tests prove integer rounding for several positive growth rates.
- Two instances of the same reference and level have identical derived stats.
- Save/restore does not heal, damage, or recalculate a monster differently.
- Existing level-less content loads as level 1.

## Phase 5: CPU evaluation refactor

### Implementation

1. Build a per-turn evaluation context once, containing reachable destinations,
   legal targets, cooldowns, threat data, and pure damage estimates.
2. Enumerate controller-neutral command candidates: movement plus melee, spell,
   support, or wait. Validate candidates through shared authoritative queries.
3. Score candidates with ordered outcome tiers:
   - immediately wins the battle;
   - number and value of enemy defeats;
   - actor and ally survival;
   - role utility such as healing, control, or buffing;
   - expected damage and positional value;
   - stable deterministic tie-break key.
4. Let Berserk, Mage, Support, and Tactical brains provide weights and preferred
   utility, not duplicate legality or damage formulas.
5. Generate accurate threat maps once per turn. Threat must consider actual
   movement, height, LoS, available spells, and cooldowns.
6. Preserve `wait` as a valid fallback. Anti-stall behavior, if needed, is based
   on explicit no-progress rounds rather than pretending a legal action exists.
7. Validate the chosen command immediately before execution and record only the
   accepted command, preserving the existing `success` versus `resolved`
   contract for reactive fizzles.

### Acceptance

- A safe lethal action beats nonlethal damage without relying on a magic bonus.
- A battle-winning action beats an ordinary kill, and a multi-kill can beat a
  lower-value single kill.
- Support units can heal or protect instead of taking a trivial available attack.
- Reactive passives do not mutate state during planning.
- Equal-score ties resolve by a documented stable key and replay identically.
- On the project reference machine, the 95th percentile CPU decision time stays
  below 50 ms for an eight-unit 16x16 headless fixture; record hardware and raw
  benchmark results instead of describing the AI as merely "chess-like."

## Phase 6: Capsule presentation and optional PS1 mode

### Capsule visuals

- Team 1 capsule bases are blue; Team 2 bases are red.
- Element affinity appears as a non-destructive tint or accent. Dual-element
  monsters retain a defined split treatment; authored textures are not replaced.
- On defeat, disable selection collision immediately, shrink the monster into
  the capsule, shatter the base with a bounded particle effect, then release the
  visual.
- Animation cancellation, fast replay, return-to-setup, and disposal must leave
  no stale tweens, colliders, or particles.

### Retro rendering

1. Render only the 3D battle world through a low-resolution SubViewport, with a
   default 320x240 reference mode and aspect-preserving nearest-neighbor upscale.
2. Render setup, HUD, text, and accessibility affordances at native resolution.
3. Apply nearest filtering through world-asset import/material policy rather
   than disabling mipmaps globally.
4. Treat vertex snapping and affine-style texture distortion as separate shader
   features. Expose snapping independently. Keep affine mapping selectable by
   presets with a perspective-correct fallback, but do not expose a player-facing
   toggle until textured perspective content makes its result demonstrable.
5. Persist the retro setting locally. It may change presentation resources but
   cannot rebuild or mutate the simulator.
6. Convert mouse coordinates correctly between the native UI viewport and the
   low-resolution world viewport so whole-model picking remains accurate.

### Acceptance

- Retro on/off produces identical commands, state hashes, and replay results.
- UI remains readable and sharp in both modes and at non-4:3 window sizes.
- Mouse picking, player targeting, screenshots, camera controls, and tactical
  overlays align after viewport scaling.
- Unsupported rendering hardware falls back without preventing battle startup.

## Verification matrix

Use focused bounded Godot checks described in `LEARNINGS.md`; GUT remains
isolated until its recorded Windows crash is re-evaluated.

Required automated coverage:

- map schema and deployment validation for every map;
- elevation serialization and version-2 migration;
- BFS/A*/validation agreement across height edges;
- melee, spell, LoS, damage-order, and rounding boundaries;
- player command rejection without mutation;
- AI lethal, support, AoE, reaction, and deterministic tie cases;
- CPU-vs-CPU completion for every map and default roster;
- replay from JSON plus restored continuation;
- elevated cursor, overlay, full-model picking, and camera alignment;
- retro-mode input mapping and simulation equivalence;
- default-scene startup and return-to-setup lifecycle.

Each phase ends with `git diff --check`, the documentation audit, its focused
success marker, the playable core/UI checks, and the determinism check. A phase
is not complete merely because its visual demonstration works.

## Delivery order and commit boundaries

1. Map height schema, state queries, serialization migration, and flat-map tests.
2. Height rendering, camera, cursor, overlay, and picking alignment.
3. Shared traversal rule plus BFS/A*/validation integration.
4. Shared height/range/LoS queries and centralized direct damage.
5. Level/stat schema and deterministic derivation.
6. AI candidate generation, outcome tiers, personalities, and performance work.
7. Capsule defeat sequence and team/element presentation.
8. World-only retro SubViewport and independent shader toggles.
9. Full regression matrix, documentation truth pass, and backlog cleanup.

Keep each commit within one boundary where practical. If a phase reveals that a
recommended decision is wrong, stop at that boundary and revise this plan rather
than burying a rules change inside presentation or AI code.

## Explicitly deferred

- diagonal movement;
- variable terrain movement cost;
- flying, hovering, swimming, and water-walking;
- destructible or moving terrain;
- lobbed and homing projectile trajectories;
- manual deployment and facing;
- mid-battle leveling;
- equipment and items;
- breeding, gacha/roulette, currencies, and monster inventory;
- local Player-vs-Player and online play.
