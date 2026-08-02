# Backlog

Status: durable work outside the completed first-playable task. Last reviewed:
2026-07-29.

Items belong here only when they are actionable, still relevant, and not already
implemented by the playable battle flow.

## Simulation and architecture

- **Versioned command/event schema:** Stabilize explicit schema versions and
  migrations before replay files become a public compatibility promise or a
  network synchronization format.
- **AI brain registry:** Replace `_resolveBrainClass()` branches with a validated,
  data-driven registry.
- **General stat modifiers:** Expand active effects beyond special-case bonuses
  so buffs/debuffs target named stats without mutating reference data.
- **Additional passive triggers:** Consider damage-taken, spell-cast, and
  tile-entered triggers after the command/effect contracts stabilize.
- **Terrain and trajectory:** Add variable movement costs, specialized traversal,
  and explicitly designed lobbed/homing projectile clearance using `heightBoard`.
- **`ThreatMap` sits in the wrong directory:** Every other file in
  `src/algorithms/` depends only on `src/board/`, but `ThreatMap` takes
  `BattleState` and the movement/combat resolvers, and is consumed only by
  `src/entity_ai/`. There is no dependency cycle today, so this is a naming and
  discoverability problem rather than a correctness one. Consider moving it to
  `src/entity_ai/` so `algorithms/` can keep a single, enforceable dependency
  rule.

## Presentation

- **Authored model coverage:** Add registry mappings as authored monster scenes
  become available; preserve the procedural fallback for incomplete rosters.
- **Input and accessibility polish:** Add user-facing key remapping, explicit
  focus indicators, and keyboard/gamepad device QA beyond the current standard
  UI-action-compatible cursor API.
- **Screen-space tactical outline:** Investigate a secondary viewport or mask
  pipeline for silhouettes visible through terrain without drawing over a
  monster's front faces. Treat this as a performance-sensitive rendering change.

## Testing and maintenance

- **Build a fresh test suite:** The previous unit/integration/scene suite, the
  GUT addon, and their check runners were removed entirely to start clean.
  Design and add new unit, integration, and validator coverage (including
  monster-catalog validation, previously `CatalogValidator.gd`) as a
  deliberate decision, not a carryover of the old structure.
- **Factory path audit:** Verify explicit `preload()`/`load()` paths when scripts
  move; `class_name` does not repair an invalid resource path.

## Later gameplay

- Directional facing and backstab/cone rules.
- Inventory, consumable items, defend, and economy/shop systems.
- Manual deployment, local Player vs Player, and online PvP/co-op.
- Replay browsing, file import/export UX, and turn-by-turn playback controls.
- Roster, spell, passive, and AI-behavior expansion after player controls work.

## Research

- Deepen the stats reference only when a concrete design question requires it.
- Add missing games to relevant aspect studies rather than duplicating the full
  game roster across every module.